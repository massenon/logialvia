import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/approvisionnement/data/repositories/approvisionnement_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_intrants_poste.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/approvisionnement.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_produits_poste.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:logialvia_app/elevage/data/repositories/parametres_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/sync/identifiants_parametres_elevage.dart';
import 'package:logialvia_app/elevage/data/sync/table_parametres_elevage_poste.dart';

import 'faux_serveur_sync.dart';

/// `47h_` D1 — trouvé en rejouant les essais contre le VRAI serveur : l'adoption initiale
/// (premier cycle d'un poste : « voici tout mon semis ») datait chaque ligne de
/// l'instant présent. Le premier cycle d'un SECOND poste écrasait donc, avec son semis
/// intact, la correction qu'un premier poste avait faite entre-temps (le serveur
/// applique « dernier écrivain gagne »), et la renvoyait au premier poste.
///
/// Le faux serveur applique la même règle que le vrai (`DemandesReferentiel.php`) :
/// identique accepté, plus ancien ou égal refusé, plus récent appliqué.
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
      tables: [
        TableProduitsPoste(db),
        TableIntrantsPoste(db),
        TableBaremesRationPoste(db),
      ],
      client: serveur.client,
    );
  }

  final FauxServeurSync serveur;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;

  Future<void> demarrer() async {
    await SeedInitial(db).executer();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }
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

  Future<void> cycle(_Poste p) async {
    final r = await p.moteur.synchroniser();
    expect(r.reussie, isTrue, reason: r.message);
  }

  test(
    'barème : la correction du premier poste survit au premier cycle d\'un second poste neuf',
    () async {
      final a = await poste();
      final b = await poste();
      final id = IdentifiantsParametresElevage.bareme('goliaths', 'Mature');
      await cycle(a);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await ParametresElevageRepositoryDrift(
        a.db,
      ).modifierRation(id: id, rationGrammesParJour: 140, confirme: true);
      await cycle(a);
      expect(serveur.baremes[id]!['ration_grammes_par_jour'], 140);

      await cycle(b); // premier cycle de B : adoption de SON semis (110 g)

      expect(
        serveur.baremes[id]!['ration_grammes_par_jour'],
        140,
        reason: 'le semis de B n\'écrase pas la décision de A',
      );
      final chezB = await (b.db.select(
        b.db.baremesRation,
      )..where((x) => x.id.equals(id))).getSingle();
      expect(
        chezB.rationGrammesParJour,
        140,
        reason: 'B reçoit la décision de A',
      );
      await cycle(a);
      final chezA = await (a.db.select(
        a.db.baremesRation,
      )..where((x) => x.id.equals(id))).getSingle();
      expect(
        chezA.rationGrammesParJour,
        140,
        reason: 'A n\'est pas écrasé non plus',
      );
    },
  );

  test(
    'produit : le nouveau prix du premier poste survit au premier cycle d\'un second poste neuf',
    () async {
      final a = await poste();
      final b = await poste();
      await cycle(a);
      final repo = VentesRepositoryDrift(a.db, EventBus());
      final p = (await repo.chargerCatalogue()).firstWhere(
        (x) => x.nom == 'Goliath mature',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await repo.mettreAJourProduit(
        ProduitVendable(
          id: p.id,
          sku: p.sku,
          nom: p.nom,
          categorie: p.categorie,
          prix: p.prix + 500,
          prixMax: p.prixMax,
          unite: p.unite,
          icone: p.icone,
          stock: p.stock,
          seuil: p.seuil,
          espece: p.espece,
          coutRevient: p.coutRevient,
        ),
      );
      await cycle(a);
      expect(serveur.produits[p.id]!['price'], p.prix + 500);

      await cycle(b);

      expect(serveur.produits[p.id]!['price'], p.prix + 500);
      final chezB = await (b.db.select(
        b.db.produitsVendables,
      )..where((x) => x.id.equals(p.id))).getSingle();
      expect(chezB.price, p.prix + 500);
    },
  );

  test(
    'intrant : le seuil corrigé par le premier poste survit au premier cycle d\'un second poste neuf',
    () async {
      final a = await poste();
      final b = await poste();
      await cycle(a);
      final repo = ApprovisionnementRepositoryDrift(a.db);
      final i = (await a.db.select(a.db.intrants).get()).first;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await repo.enregistrerIntrant(
        Intrant(
          code: i.code,
          nom: i.name,
          categorie: i.cat,
          stock: i.stock,
          unite: i.unit,
          seuil: i.threshold + 9,
          pmp: i.pmp,
        ),
        creation: false,
      );
      await cycle(a);
      expect(serveur.intrants[i.code]!['threshold'], i.threshold + 9);

      await cycle(b);

      expect(serveur.intrants[i.code]!['threshold'], i.threshold + 9);
      final chezB = await (b.db.select(
        b.db.intrants,
      )..where((x) => x.code.equals(i.code))).getSingle();
      expect(chezB.threshold, i.threshold + 9);
    },
  );

  test(
    'une modification faite AVANT le premier cycle n\'est pas remplacée par l\'adoption : elle part avec son propre instant',
    () async {
      final a = await poste();
      final id = IdentifiantsParametresElevage.bareme('goliaths', 'Poussins');
      await ParametresElevageRepositoryDrift(
        a.db,
      ).modifierRation(id: id, rationGrammesParJour: 33, confirme: true);

      await cycle(a);

      expect(serveur.baremes[id]!['ration_grammes_par_jour'], 33);
      final demandes = serveur.demandesRecues
          .where((d) => (d['donnees'] as Map)['id'] == id)
          .toList();
      expect(
        demandes,
        hasLength(1),
        reason: 'une seule demande pour cette clé',
      );
      expect(
        demandes.single['saisi_le'],
        isNot(DepotDemandesReferentiel.instantAdoption),
        reason: 'une décision garde son instant de saisie',
      );
    },
  );

  test(
    'les lignes jamais touchées partent datées de l\'adoption (instant ancien), pas de l\'instant présent',
    () async {
      final a = await poste();

      await cycle(a);

      final id = IdentifiantsParametresElevage.bareme('goliaths', 'Mature');
      final d = serveur.demandesRecues.firstWhere(
        (d) => (d['donnees'] as Map)['id'] == id,
      );
      expect(d['saisi_le'], DepotDemandesReferentiel.instantAdoption);
    },
  );
}
