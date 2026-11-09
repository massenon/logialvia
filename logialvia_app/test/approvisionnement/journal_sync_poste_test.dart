import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/approvisionnement/data/repositories/approvisionnement_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_intrants_poste.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_mouvements_intrant_poste.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/approvisionnement.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:logialvia_app/rapports/data/repositories/inventaire_repository_drift.dart';

import '../core/sync/faux_serveur_sync.dart';

/// Palier 5 — décision du client : **stock propre à chaque poste + journal partagé**.
/// Le journal des mouvements circule ; il n'est appliqué à aucun stock.
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
      tables: [TableIntrantsPoste(db), TableMouvementsIntrantPoste(db)],
      client: serveur.client,
    );
    appro = ApprovisionnementRepositoryDrift(db);
  }

  final FauxServeurSync serveur;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final ApprovisionnementRepositoryDrift appro;

  Future<void> demarrer() async {
    await SeedInitial(db).executer();
    // Le catalogue a son propre test : on isole ici les intrants et le journal.
    await preferences.definirCatalogueAdopte();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }

  Future<IntrantRow> intrant(String code) =>
      (db.select(db.intrants)..where((i) => i.code.equals(code))).getSingle();
  Future<List<MouvementIntrantRow>> mouvements() => (db.select(
    db.mouvementsIntrant,
  )..orderBy([(m) => OrderingTerm.asc(m.horodatage)])).get();
  Future<List<MouvementIntrantRow>> locaux() =>
      (db.select(db.mouvementsIntrant)..where((m) => m.origine.isNull())).get();
  Future<void> ajuster(String code, int physique) => appro.ajusterInventaire(
    code: code,
    stockPhysique: physique,
    motif: 'Inventaire',
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

  group('intrants : référentiel sans stock ni PMP', () {
    test(
      'la première synchronisation propose les intrants, jamais leur stock ni leur PMP',
      () async {
        final a = await poste();

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(serveur.intrants, hasLength(6));
        for (final i in serveur.intrants.values) {
          expect(i.keys, isNot(contains('stock')));
          expect(i.keys, isNot(contains('pmp')));
        }
      },
    );

    test(
      'adoption unique : rien n\'est reproposé aux synchronisations suivantes',
      () async {
        final a = await poste();
        await a.moteur.synchroniser();
        serveur.demandesRecues.clear();

        await a.moteur.synchroniser();

        expect(serveur.demandesRecues, isEmpty);
      },
    );

    test(
      'un intrant créé au poste A arrive chez B avec un stock et un PMP de 0',
      () async {
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await a.appro.enregistrerIntrant(
          const Intrant(
            code: 'INT-099',
            nom: 'Sel minéral',
            categorie: 'Complément',
            stock: 40,
            unite: 'kg',
            seuil: 5,
            pmp: 800,
          ),
          creation: true,
        );
        await a.moteur.synchroniser();

        await b.moteur.synchroniser();

        final i = await b.intrant('INT-099');
        expect(i.name, 'Sel minéral');
        expect(i.stock, 0, reason: 'le stock de A n\'est pas celui de B');
        expect(i.pmp, 0);
        expect((await a.intrant('INT-099')).stock, 40);
      },
    );

    test(
      'un intrant connu garde SON stock et SON PMP quand le serveur change son nom',
      () async {
        final b = await poste();
        await b.moteur.synchroniser();
        final avant = await b.intrant('INT-001');
        serveur.intrants['INT-001'] = {
          'code': 'INT-001',
          'name': 'Maïs grain',
          'cat': avant.cat,
          'unit': avant.unit,
          'threshold': 40,
          'stock': 999,
          'pmp': 999,
          'saisi_le': '2026-11-09T09:00:00.000000Z',
          'created_at': '2026-11-01T00:00:00.000Z',
          'updated_at': serveur.instantServeur(),
        };

        await b.moteur.synchroniser();

        final apres = await b.intrant('INT-001');
        expect(apres.name, 'Maïs grain');
        expect(apres.threshold, 40);
        expect(
          apres.stock,
          avant.stock,
          reason: 'le stock annoncé par le serveur est ignoré',
        );
        expect(apres.pmp, avant.pmp);
      },
    );

    test(
      'une modification locale d\'un intrant est proposée, sans stock ni PMP',
      () async {
        final a = await poste();
        await a.moteur.synchroniser();
        final i = await a.intrant('INT-001');
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await a.appro.enregistrerIntrant(
          Intrant(
            code: i.code,
            nom: 'Maïs jaune',
            categorie: i.cat,
            stock: 7,
            unite: i.unit,
            seuil: 30,
            pmp: 1,
          ),
          creation: false,
        );

        await a.moteur.synchroniser();

        expect(serveur.intrants['INT-001']!['name'], 'Maïs jaune');
        expect(serveur.intrants['INT-001']!.keys, isNot(contains('stock')));
      },
    );

    test(
      'une demande locale plus récente n\'est pas défaite par le tirage',
      () async {
        final a = await poste();
        await a.moteur.synchroniser();
        final i = await a.intrant('INT-001');
        serveur.intrants['INT-001']!['name'] = 'Ancien nom du serveur';
        serveur.intrants['INT-001']!['saisi_le'] =
            '2020-01-01T00:00:00.000000Z';
        serveur.intrants['INT-001']!['updated_at'] = serveur.instantServeur();
        await a.appro.enregistrerIntrant(
          Intrant(
            code: i.code,
            nom: 'Mon nom plus récent',
            categorie: i.cat,
            stock: i.stock,
            unite: i.unit,
            seuil: i.threshold,
            pmp: i.pmp,
          ),
          creation: false,
        );

        await a.moteur.synchroniser();

        expect((await a.intrant('INT-001')).name, 'Mon nom plus récent');
      },
    );

    final cas = <String, Map<String, dynamic>>{
      'sans désignation': {'name': '  '},
      'sans unité': {'unit': ''},
      'seuil négatif': {'threshold': -1},
      'code trop long': {'code': 'X' * 41},
    };
    cas.forEach((nom, surcharge) {
      test(
        'ligne du serveur incohérente refusée, rien d\'écrit : $nom',
        () async {
          final b = await poste();
          serveur.intrants['x'] = {
            'code': 'INT-777',
            'name': 'Intrus',
            'cat': 'Divers',
            'unit': 'kg',
            'threshold': 1,
            'saisi_le': '2026-11-01T10:00:00.000000Z',
            'updated_at': serveur.instantServeur(),
            ...surcharge,
          };

          final r = await b.moteur.synchroniser();

          expect(r.refuseesALaReception, 1);
          expect(
            (await b.db.select(b.db.intrants).get()).map((i) => i.name),
            isNot(contains('Intrus')),
          );
        },
      );
    });
  });

  group('journal : un historique partagé, jamais un stock', () {
    test(
      'un mouvement part avec les intrants adoptés d\'abord, puis est marqué synchronisé',
      () async {
        final a = await poste();
        await a.ajuster('INT-001', 10);

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(r.refusees, 0, reason: r.message);
        expect(serveur.mouvements, hasLength(1));
        final m = (await a.mouvements()).single;
        expect(m.syncStatus, 'synced');
        expect(m.origine, isNull, reason: 'il est de CE poste');
        final i = serveur.journal.indexOf('POST /api/sync/demandes');
        final j = serveur.journal.indexOf('POST /api/sync/push');
        expect(
          j,
          greaterThan(i),
          reason: 'les intrants (demandes) partent AVANT leurs mouvements',
        );
      },
    );

    test(
      'B reçoit le mouvement de A SANS que son stock ni son PMP bougent',
      () async {
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        final avantB = await b.intrant('INT-001');
        await a.ajuster('INT-001', 3);
        await a.moteur.synchroniser();

        final r = await b.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        final m = (await b.mouvements()).single;
        expect(m.syncStatus, 'synced');
        expect(
          m.origine,
          isNotNull,
          reason: 'D\'où vient le mouvement : d\'un autre poste',
        );
        expect(m.type, TypeMouvement.ajustement);
        final apres = await b.intrant('INT-001');
        expect(
          apres.stock,
          avantB.stock,
          reason: 'stock propre à chaque poste',
        );
        expect(apres.pmp, avantB.pmp);
        expect((await a.intrant('INT-001')).stock, 3);
      },
    );

    test(
      'le rapport d\'inventaire de B ignore les mouvements des autres postes',
      () async {
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        final debut = DateTime.now().subtract(const Duration(days: 1));
        final fin = DateTime.now();
        final avant = (await InventaireRepositoryDrift(b.db).construire(
          debut: debut,
          fin: fin,
        )).intrants.firstWhere((l) => l.code == 'INT-001');

        await a.ajuster('INT-001', 3);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        expect(await b.mouvements(), hasLength(1));

        final apres = (await InventaireRepositoryDrift(b.db).construire(
          debut: debut,
          fin: fin,
        )).intrants.firstWhere((l) => l.code == 'INT-001');
        expect(
          apres.stockFinal,
          avant.stockFinal,
          reason: 'un mouvement d\'ailleurs ne change pas l\'inventaire d\'ici',
        );
        expect(apres.entrees, avant.entrees);
        expect(apres.sorties, avant.sorties);
        expect(apres.stockFinal, (await b.intrant('INT-001')).stock.toDouble());
      },
    );

    test(
      'mon propre mouvement qui revient au tirage n\'est ni dupliqué ni pris pour un mouvement d\'ailleurs',
      () async {
        final a = await poste();
        await a.ajuster('INT-001', 10);
        await a.moteur.synchroniser();
        await a.preferences.definirCurseurTirage(null);

        await a.moteur.synchroniser();

        final m = await a.mouvements();
        expect(m, hasLength(1));
        expect(m.single.origine, isNull);
      },
    );

    test(
      'plusieurs postes : chacun a l\'historique de tous, et son propre stock',
      () async {
        final a = await poste();
        final b = await poste();
        await a.ajuster('INT-001', 5);
        await b.ajuster('INT-001', 50);
        for (final p in [a, b, a, b]) {
          await p.moteur.synchroniser();
        }

        expect(serveur.mouvements, hasLength(2));
        expect(await a.mouvements(), hasLength(2));
        expect(await b.mouvements(), hasLength(2));
        expect((await a.intrant('INT-001')).stock, 5);
        expect((await b.intrant('INT-001')).stock, 50);
        expect(await a.locaux(), hasLength(1));
        expect(await b.locaux(), hasLength(1));
      },
    );

    test(
      'un mouvement ne se modifie jamais : une version différente venue du serveur est ignorée',
      () async {
        final a = await poste();
        final b = await poste();
        await a.ajuster('INT-001', 3);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        final id = (await b.mouvements()).single.id;
        serveur.mouvements[id]!['quantite'] = 9999.0;
        serveur.mouvements[id]!['motif'] = 'Falsifié';
        serveur.mouvements[id]!['serveur_modifie_le'] = serveur
            .instantServeur();

        await b.moteur.synchroniser();

        final m = (await b.mouvements()).single;
        expect(m.quantite, isNot(9999.0));
        expect(m.motif, isNot('Falsifié'));
      },
    );

    final cas = <String, Map<String, dynamic>>{
      'UUID invalide': {'id': 'pas-un-uuid'},
      'type inconnu': {'type': 'Vol'},
      'quantité nulle': {'quantite': 0},
      'motif vide': {'motif': ' '},
      'date invalide': {'horodatage': 'hier'},
      'intrant inconnu de ce poste': {'intrant_code': 'INT-INCONNU'},
    };
    cas.forEach((nom, surcharge) {
      test('refusé, rien d\'écrit : $nom', () async {
        final b = await poste();
        serveur.mouvements['x'] = {
          'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'device_id': 'autre',
          'horodatage': '2026-11-01T10:00:00.000000Z',
          'intrant_code': 'INT-001',
          'article': 'Maïs',
          'type': TypeMouvement.entree,
          'motif': 'Réception',
          'quantite': 10,
          'reference': null,
          'serveur_modifie_le': serveur.instantServeur(),
          ...surcharge,
        };

        final r = await b.moteur.synchroniser();

        expect(r.refuseesALaReception, 1);
        expect(await b.mouvements(), isEmpty);
      });
    });

    test(
      'hors ligne : le mouvement reste en attente et part à la reconnexion',
      () async {
        final a = await poste();
        await a.ajuster('INT-001', 10);
        serveur.horsLigne = true;
        expect(
          (await a.moteur.synchroniser()).issue,
          IssueSynchronisation.horsLigne,
        );
        expect((await a.mouvements()).single.syncStatus, 'pending');

        serveur.horsLigne = false;
        await a.moteur.synchroniser();

        expect((await a.mouvements()).single.syncStatus, 'synced');
      },
    );

    test(
      'remise à zéro du serveur : le journal part (celui des autres aussi), les intrants et le stock restent',
      () async {
        final a = await poste();
        final b = await poste();
        await a.ajuster('INT-001', 5);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        final stockB = (await b.intrant('INT-001')).stock;

        serveur.remettreAZero();
        final r = await b.moteur.synchroniser();

        expect(r.remiseAZero, isTrue, reason: r.message);
        expect(await b.mouvements(), isEmpty);
        expect(
          await b.db.select(b.db.intrants).get(),
          hasLength(6),
          reason: 'les intrants (référentiel) restent',
        );
        expect(
          (await b.intrant('INT-001')).stock,
          stockB,
          reason: 'le stock est propre à ce poste',
        );
      },
    );

    test(
      'un mouvement d\'un autre poste n\'est jamais renvoyé au serveur',
      () async {
        final a = await poste();
        final b = await poste();
        await a.ajuster('INT-001', 3);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        serveur.envois.clear();

        await b.moteur.synchroniser();

        for (final e in serveur.envois) {
          final t = (e['tables'] as Map);
          expect(
            t.containsKey('mouvements_intrant')
                ? (t['mouvements_intrant'] as List)
                : const [],
            isEmpty,
          );
        }
      },
    );
  });
}
