import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/administration/domain/services/service_archivage.dart';
import 'package:logialvia_app/approvisionnement/data/repositories/approvisionnement_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_intrants_poste.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/approvisionnement.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import '../core/sync/faux_serveur_sync.dart';

/// `47h_` D4 — trouvé contre le VRAI serveur : supprimer un intrant au poste ne
/// supprimait rien ailleurs (pas de pierre tombale, contrairement aux produits) et un
/// tirage complet (« Renvoyer vers ce poste », réinstallation) le RESSUSCITAIT.
class _Poste {
  _Poste(this.serveur) : db = AppDatabase.enMemoire() {
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: serveur.client,
    );
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: appairage,
      demandes: DepotDemandesReferentiel(db),
      tables: [TableIntrantsPoste(db)],
      client: serveur.client,
    );
    repo = ApprovisionnementRepositoryDrift(db);
  }

  final FauxServeurSync serveur;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final ApprovisionnementRepositoryDrift repo;

  Future<void> demarrer() async {
    await SeedInitial(db).executer();
    await preferences.definirCatalogueAdopte();
    await preferences.definirParametresElevageAdoptes();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }

  Future<IntrantRow?> intrant(String code) => (db.select(
    db.intrants,
  )..where((i) => i.code.equals(code))).getSingleOrNull();

  Future<void> creerIntrant(String code) => repo.enregistrerIntrant(
    Intrant(
      code: code,
      nom: 'Intrant $code',
      categorie: Intrant.categories.first,
      stock: 0,
      unite: 'kg',
      seuil: 1,
      pmp: 0,
    ),
    creation: true,
  );
}

void main() {
  late FauxServeurSync serveur;
  final postes = <_Poste>[];

  Future<_Poste> poste() async {
    final p = _Poste(serveur);
    postes.add(p);
    await p.demarrer();
    return p;
  }

  setUp(() {
    serveur = FauxServeurSync();
    postes.clear();
  });
  tearDown(() async {
    for (final p in postes) {
      await p.db.close();
    }
  });

  Future<void> cycle(_Poste p, {bool complet = false}) async {
    final r = await p.moteur.synchroniser(complet: complet);
    expect(r.reussie, isTrue, reason: r.message);
  }

  const code = 'INT-900';

  test(
    'un intrant supprimé au poste A est marqué archivé au serveur (jamais effacé) et disparaît de B',
    () async {
      final a = await poste();
      final b = await poste();
      await a.creerIntrant(code);
      await cycle(a);
      await cycle(b);
      expect(await b.intrant(code), isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await a.repo.supprimerIntrant(code);
      await cycle(a);

      expect(serveur.intrants[code], isNotNull, reason: 'jamais effacé');
      expect(serveur.intrants[code]!['archive_le'], isNotNull);
      await cycle(b);
      expect(await b.intrant(code), isNull);
      final corbeille = await b.db.select(b.db.corbeille).get();
      expect(
        corbeille.any(
          (c) => c.nomTable == 'intrants' && c.designation.startsWith(code),
        ),
        isTrue,
        reason: 'archivé dans la corbeille de B, restaurable',
      );
    },
  );

  test(
    'un tirage complet ne ressuscite pas l\'intrant supprimé, un poste neuf ne le crée pas',
    () async {
      final a = await poste();
      await a.creerIntrant(code);
      await cycle(a);
      await a.repo.supprimerIntrant(code);
      await cycle(a);

      await cycle(a, complet: true);
      final c = await poste();
      await cycle(c);

      expect(await a.intrant(code), isNull);
      expect(await c.intrant(code), isNull);
    },
  );

  test(
    'un intrant déjà cité par un mouvement d\'ICI n\'est pas archivé par la suppression d\'un autre poste',
    () async {
      final a = await poste();
      final b = await poste();
      await a.creerIntrant(code);
      await cycle(a);
      await cycle(b);
      // B a un mouvement (ajustement) sur cet intrant : son historique l'exige.
      await b.db
          .into(b.db.intrants)
          .insertOnConflictUpdate(
            IntrantsCompanion.insert(
              code: code,
              name: 'Intrant $code',
              cat: Intrant.categories.first,
              stock: 5,
              unit: 'kg',
              threshold: 1,
              pmp: 0,
            ),
          );
      await b.repo.ajusterInventaire(
        code: code,
        stockPhysique: 9,
        motif: 'Comptage',
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await a.repo.supprimerIntrant(code);
      await cycle(a);
      await cycle(b);

      expect(await b.intrant(code), isNotNull, reason: 'historique conservé');
    },
  );

  test(
    'restaurer l\'intrant depuis la corbeille lève la pierre tombale : les autres postes le retrouvent',
    () async {
      final a = await poste();
      final b = await poste();
      await a.creerIntrant(code);
      await cycle(a);
      await cycle(b);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await a.repo.supprimerIntrant(code);
      await cycle(a);
      await cycle(b);
      expect(await b.intrant(code), isNull);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final archive = (await a.db.select(a.db.corbeille).get()).firstWhere(
        (c) => c.designation.startsWith(code),
      );
      await ServiceArchivage(a.db).restaurer(archive.id, estAdmin: true);
      await cycle(a);
      expect(serveur.intrants[code]!['archive_le'], isNull);
      await cycle(b);

      expect(await b.intrant(code), isNotNull);
    },
  );
}
