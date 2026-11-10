import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/administration/domain/services/service_archivage.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:logialvia_app/elevage/data/repositories/cycle_couveuse_repository_drift.dart';
import 'package:logialvia_app/elevage/data/sync/table_cycles_couveuse_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_machines_incubateur_poste.dart';
import 'package:logialvia_app/elevage/domain/entities/cycle_incubation.dart';

import '../core/sync/faux_serveur_sync.dart';

/// Palier 7b — lots de couveuse (avec leurs mirages) et incubateurs.
///
/// Le faux serveur REJOUE les règles de `CyclesCouveuseTable` et
/// `MachinesIncubateurTable` (valeurs permises, compteurs cohérents, incubateur connu,
/// code unique, dernier écrivain gagne, pierre tombale).
class _Poste {
  _Poste(this.serveur, this.code) : db = AppDatabase.enMemoire() {
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
      tables: [TableMachinesIncubateurPoste(db), TableCyclesCouveusePoste(db)],
      client: serveur.client,
    );
    repo = CycleCouveuseRepositoryDrift(db);
  }

  final FauxServeurSync serveur;
  final String? code;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final CycleCouveuseRepositoryDrift repo;

  Future<void> demarrer() async {
    await preferences.definirCatalogueAdopte();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: code ?? 'P0',
      compte: 'g',
      le: DateTime.now(),
    );
    if (code == null) {
      await (db.delete(
        db.preferencesPoste,
      )..where((p) => p.cle.equals('poste.code_attribue'))).go();
    }
    await depot.ecrire('1|jeton');
  }

  Future<MachineIncubateur> machine([
    String code = 'INC-01',
    int? capacite = 528,
  ]) => repo.creerMachine(
    code: code,
    libelle: 'Couveuse $code',
    capaciteOeufs: capacite,
  );

  Future<CycleIncubation> lot({
    String? machineId,
    int oeufs = 200,
    DateTime? date,
    EspeceCouvable espece = EspeceCouvable.goliath,
  }) => repo.creer(
    espece: espece,
    dateChargement: date ?? DateTime(2026, 8, 1),
    oeufsCharges: oeufs,
    machineId: machineId,
  );

  Future<List<CycleCouveuseRow>> lots() => (db.select(
    db.cycleCouveuse,
  )..orderBy([(c) => OrderingTerm.asc(c.codeIncubation)])).get();

  Future<CycleCouveuseRow> lire(String id) =>
      (db.select(db.cycleCouveuse)..where((c) => c.id.equals(id))).getSingle();

  Future<List<MachineIncubateurRow>> machines() =>
      db.select(db.machinesIncubateur).get();
}

void main() {
  late FauxServeurSync serveur;
  final postes = <_Poste>[];

  Future<_Poste> poste([String? code = 'P1']) async {
    final p = _Poste(serveur, code);
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

  const idMachine = 'aaaaaaaa-0000-4000-8000-000000000001';
  const idLot = 'bbbbbbbb-0000-4000-8000-000000000001';
  const idLot2 = 'bbbbbbbb-0000-4000-8000-000000000002';

  group('envoi', () {
    test(
      'le premier envoi porte les incubateurs puis les lots, au format du contrat',
      () async {
        final a = await poste();
        final m = await a.machine();
        final l = await a.lot(machineId: m.id);

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(r.refusees, 0);
        expect(serveur.machines.keys, [m.id]);
        expect(serveur.cycles.keys, [l.id]);
        final envoye = serveur.cycles[l.id]!;
        expect(envoye['code_incubation'], 'C-P1-2026-001');
        expect(
          envoye['date_incubation'],
          '2026-08-01',
          reason: 'date civile, sans fuseau',
        );
        expect(envoye['oeufs_couves'], 200);
        expect(envoye['machine_id'], m.id);
        expect(envoye['statut'], 'En Incubation');
        expect(envoye['oeufs_blancs_j7'], isNull);
        expect((await a.lire(l.id)).syncStatus, 'synced');
        expect(
          (await a.machines()).single.syncStatus,
          'synced',
          reason: 'l\'incubateur part AVANT le lot qui l\'occupe',
        );
      },
    );

    test('un second envoi n\'envoie rien : rejeu sans effet', () async {
      final a = await poste();
      await a.lot();
      await a.moteur.synchroniser();
      final avant = serveur.envois.length;

      final r = await a.moteur.synchroniser();

      expect(r.envoyees, 0);
      expect(
        serveur.envois.length,
        avant,
        reason: 'rien à envoyer, aucun POST /push',
      );
    });

    test(
      'une saisie de mirage est une modification du lot : elle repart, datée',
      () async {
        final a = await poste();
        final l = await a.lot();
        await a.moteur.synchroniser();
        final avant = (await a.lire(l.id)).updatedAt;
        await Future<void>.delayed(const Duration(milliseconds: 3));

        await a.repo.enregistrerMirage(
          cycleId: l.id,
          jour: 7,
          oeufsRetires: 22,
        );
        final apres = await a.lire(l.id);
        expect(apres.syncStatus, 'pending');
        expect(
          DateTime.parse(apres.updatedAt).isAfter(DateTime.parse(avant)),
          isTrue,
        );

        await a.moteur.synchroniser();

        expect(serveur.cycles[l.id]!['oeufs_blancs_j7'], 22);
        expect((await a.lire(l.id)).syncStatus, 'synced');
      },
    );

    test(
      'mirage 2, éclosion avec sous-lot, modification : tout repart',
      () async {
        final a = await poste();
        final l = await a.lot();
        await a.moteur.synchroniser();

        await a.repo.enregistrerMirage(
          cycleId: l.id,
          jour: 14,
          oeufsRetires: 11,
        );
        final r = await a.repo.enregistrerEclosion(
          cycleId: l.id,
          poussinsEclos: 150,
          oeufsPerdus: 10,
          oeufsRemplacement: 90,
          dateRemplacement: DateTime(2026, 8, 22),
        );
        await a.moteur.synchroniser();

        expect(serveur.cycles[l.id]!['oeufs_gates_j14'], 11);
        expect(serveur.cycles[l.id]!['poussins_nes'], 150);
        expect(serveur.cycles[l.id]!['statut'], 'Remplacé');
        final sousLot = serveur.cycles[r.sousLot!.id]!;
        expect(sousLot['lot_parent_id'], l.id);
        expect(sousLot['code_incubation'], 'C-P1-2026-002');

        await a.repo.modifier(
          cycleId: r.sousLot!.id,
          espece: EspeceCouvable.pintade,
          dateChargement: DateTime(2026, 8, 23),
          oeufsCharges: 95,
        );
        await a.moteur.synchroniser();
        expect(serveur.cycles[r.sousLot!.id]!['espece'], 'pintade');
        expect(serveur.cycles[r.sousLot!.id]!['oeufs_couves'], 95);
      },
    );

    test(
      'une saisie faite PENDANT l\'envoi n\'est jamais marquée synchronisée à tort',
      () async {
        final a = await poste();
        final l = await a.lot();
        serveur.pendantEnvoi = () async {
          await Future<void>.delayed(const Duration(milliseconds: 3));
          await a.repo.enregistrerMirage(
            cycleId: l.id,
            jour: 7,
            oeufsRetires: 5,
          );
        };

        await a.moteur.synchroniser();

        expect(
          (await a.lire(l.id)).syncStatus,
          'pending',
          reason: 'la saisie du mirage n\'était pas dans l\'envoi',
        );
        await a.moteur.synchroniser();
        expect((await a.lire(l.id)).syncStatus, 'synced');
        expect(serveur.cycles[l.id]!['oeufs_blancs_j7'], 5);
      },
    );
  });

  group('numérotation', () {
    test('un poste appairé préfixe ses codes de lot : C-P2-2026-001', () async {
      final a = await poste('P2');
      final l1 = await a.lot();
      final l2 = await a.lot();
      expect(l1.code, 'C-P2-2026-001');
      expect(l2.code, 'C-P2-2026-002');
    });

    test('un poste jamais appairé garde l\'ancien format', () async {
      final a = await poste(null);
      expect((await a.lot()).code, 'C-2026-001');
    });

    test(
      'deux postes qui créent « leur premier lot » ne se heurtent pas',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.lot();
        await b.lot();

        final ra = await a.moteur.synchroniser();
        final rb = await b.moteur.synchroniser();
        await a.moteur.synchroniser();

        expect(ra.refusees + rb.refusees, 0);
        expect(serveur.cycles.values.map((c) => c['code_incubation']).toSet(), {
          'C-P1-2026-001',
          'C-P2-2026-001',
        });
        expect((await a.lots()).map((c) => c.codeIncubation), [
          'C-P1-2026-001',
          'C-P2-2026-001',
        ]);
      },
    );
  });

  group('identité de l\'incubateur', () {
    test(
      'INC-01 a le même identifiant au poste et au web (vecteur partagé avec Laravel)',
      () async {
        // Le même littéral figure dans `CouveuseWebTest` côté serveur : si l'un des deux
        // algorithmes change, les deux postes — et le web — ne désigneraient plus le même
        // incubateur.
        const attendu = 'ef7bcd40-7c36-5786-992e-94f3a9b0dc0f';
        expect(uuidDeterministe('machine:inc-01'), attendu);
        final a = await poste('P1');

        expect((await a.machine('INC-01')).id, attendu);
        expect(
          (await a.machine('Inc-02')).id,
          uuidDeterministe('machine:inc-02'),
        );
      },
    );
  });

  group('deux postes', () {
    test(
      'B reçoit les lots et incubateurs de A, SANS aucun effet de bord',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final m = await a.machine();
        final l = await a.lot(machineId: m.id);
        await a.repo.enregistrerMirage(
          cycleId: l.id,
          jour: 7,
          oeufsRetires: 22,
        );
        await a.moteur.synchroniser();
        final fichesB = (await b.db.select(b.db.ficheJournee).get()).length;
        final ventesB = (await b.db.select(b.db.ficheVentesJour).get()).length;
        final ecrituresB =
            (await b.db.select(b.db.ecritureComptable).get()).length;
        final corbeilleB = (await b.db.select(b.db.corbeille).get()).length;
        final evenements = <Object>[];
        final abonnement = b.db
            .tableUpdates(
              TableUpdateQuery.onAllTables([
                b.db.ficheJournee,
                b.db.ficheVentesJour,
                b.db.ecritureComptable,
                b.db.intrants,
                b.db.produitsVendables,
              ]),
            )
            .listen(evenements.add);

        final r = await b.moteur.synchroniser();
        await Future<void>.delayed(Duration.zero);
        await abonnement.cancel();

        expect(r.refuseesALaReception, 0);
        final recu = await b.lire(l.id);
        expect(recu.codeIncubation, 'C-P1-2026-001');
        expect(recu.oeufsBlancsJ7, 22);
        expect(recu.machineId, m.id);
        expect(recu.syncStatus, 'synced');
        expect((await b.machines()).single.code, 'INC-01');
        expect(
          (await b.db.select(b.db.ficheJournee).get()).length,
          fichesB,
          reason: 'la couveuse alimente les naissances, pas à la réception',
        );
        expect((await b.db.select(b.db.ficheVentesJour).get()).length, ventesB);
        expect(
          (await b.db.select(b.db.ecritureComptable).get()).length,
          ecrituresB,
        );
        expect((await b.db.select(b.db.corbeille).get()).length, corbeilleB);
        expect(evenements, isEmpty, reason: 'aucune autre table n\'a bougé');
        expect(
          (await b.lire(l.id)).syncStatus,
          'synced',
          reason: 'et il ne repart pas',
        );
        expect((await b.moteur.synchroniser()).envoyees, 0);
      },
    );

    test(
      'les deux postes convergent : mirages saisis dans le désordre',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final l = await a.lot();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        // A saisit le mirage 1, B le mirage 2 (chacun hors ligne de l'autre).
        await a.repo.enregistrerMirage(
          cycleId: l.id,
          jour: 7,
          oeufsRetires: 20,
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await b.repo.enregistrerMirage(
          cycleId: l.id,
          jour: 14,
          oeufsRetires: 9,
        );
        await b.moteur.synchroniser();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        // Dernier écrivain gagne sur la ligne entière : B (plus récent) l'emporte.
        final chezA = await a.lire(l.id);
        final chezB = await b.lire(l.id);
        expect(chezA.oeufsGatesJ14, 9);
        expect(chezB.oeufsGatesJ14, 9);
        expect(chezA.oeufsBlancsJ7, chezB.oeufsBlancsJ7);
        expect(chezA.updatedAt, chezB.updatedAt);
        expect(serveur.cycles[l.id]!['oeufs_gates_j14'], 9);
      },
    );

    test(
      'une saisie ancienne arrivée en retard ne défait pas une plus récente',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final l = await a.lot();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await a.repo.enregistrerMirage(
          cycleId: l.id,
          jour: 7,
          oeufsRetires: 20,
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await b.repo.enregistrerMirage(
          cycleId: l.id,
          jour: 7,
          oeufsRetires: 30,
        );
        await b.moteur.synchroniser();

        await a.moteur
            .synchroniser(); // la saisie de A, plus ancienne, arrive après

        expect(serveur.cycles[l.id]!['oeufs_blancs_j7'], 30);
        expect((await a.lire(l.id)).oeufsBlancsJ7, 30);
      },
    );

    test(
      'deux postes qui déclarent « INC-01 » désignent le même incubateur',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final ma = await a.machine('INC-01', 528);
        final mb = await b.machine('INC-01', 528);
        expect(ma.id, mb.id);
        await a.moteur.synchroniser();
        final r = await b.moteur.synchroniser();

        expect(r.refusees, 0);
        expect(serveur.machines, hasLength(1));
        expect(await b.machines(), hasLength(1));
      },
    );

    test(
      'la lignée d\'un remplacement survit au passage par le serveur',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final l = await a.lot();
        final r = await a.repo.enregistrerEclosion(
          cycleId: l.id,
          poussinsEclos: 150,
          oeufsPerdus: 10,
          oeufsRemplacement: 90,
        );
        await a.moteur.synchroniser();

        await b.moteur.synchroniser();

        final enfant = await b.lire(r.sousLot!.id);
        expect(enfant.lotParentId, l.id);
        expect((await b.lire(l.id)).statut, StatutCycle.remplace);
      },
    );

    test(
      'un lot dont l\'origine n\'est pas encore arrivée est accepté (ordre libre)',
      () async {
        final b = await poste('P2');
        serveur.ajouterCycle(idLot2, 'C-P1-2026-002', parentId: idLot);

        final r = await b.moteur.synchroniser();

        expect(r.refuseesALaReception, 0);
        expect((await b.lire(idLot2)).lotParentId, idLot);
      },
    );
  });

  group('règle du plus récent à la réception', () {
    test(
      'une saisie locale non envoyée plus récente est conservée, puis envoyée',
      () async {
        final a = await poste('P1');
        final l = await a.lot(oeufs: 200);
        serveur.ajouterCycle(
          l.id,
          l.code,
          charges: 10,
          updatedAt: '2020-01-01T00:00:00.000000Z',
        );
        // On coupe l'envoi : on isole la réception.
        final r = await a.moteur.synchroniser();

        expect(r.conserveesLocalement, 1);
        expect((await a.lire(l.id)).oeufsCouves, 200);
        expect(
          serveur.cycles[l.id]!['oeufs_couves'],
          200,
          reason: 'la saisie locale est partie à l\'envoi',
        );
      },
    );

    test(
      'une version du serveur strictement plus récente remplace la saisie locale',
      () async {
        final a = await poste('P1');
        final l = await a.lot(oeufs: 200);
        serveur.ajouterCycle(
          l.id,
          l.code,
          charges: 120,
          updatedAt: DateTime.now()
              .add(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
        );

        final r = await a.moteur.synchroniser();

        expect(r.supplantees, 1, reason: 'le poste le dit');
        expect((await a.lire(l.id)).oeufsCouves, 120);
        expect((await a.lire(l.id)).syncStatus, 'synced');
      },
    );
  });

  group('absorbeur strict', () {
    /// Une ligne du serveur correcte, qu'on abîme d'un seul champ.
    Map<String, dynamic> saine([Map<String, dynamic>? surcharge]) => {
      'id': idLot,
      'code_incubation': 'C-P9-2026-001',
      'espece': 'goliath',
      'date_incubation': '2026-08-01',
      'oeufs_couves': 100,
      'poussins_nes': null,
      'oeufs_perdus': null,
      'statut': 'En Incubation',
      'machine_id': null,
      'oeufs_blancs_j7': null,
      'oeufs_gates_j14': null,
      'lot_parent_id': null,
      'supprime_le': null,
      'updated_at': '2026-11-09T09:00:00.000000Z',
      ...?surcharge,
    };

    final cas = <String, Map<String, dynamic>>{
      'identifiant qui n\'est pas un UUID': {'id': 'pas-un-uuid'},
      'code vide': {'code_incubation': '  '},
      'espèce inconnue': {'espece': 'autruche'},
      'statut inconnu': {'statut': 'Perdu'},
      'date absente': {'date_incubation': null},
      'date invalide': {'date_incubation': '31/12/2026'},
      'zéro œuf chargé': {'oeufs_couves': 0},
      'œufs chargés en texte': {'oeufs_couves': '100'},
      'œufs chargés fractionnaires': {'oeufs_couves': 10.5},
      'clairs négatifs': {'oeufs_blancs_j7': -1},
      'mirages qui retirent plus d\'œufs que le lot': {
        'oeufs_blancs_j7': 60,
        'oeufs_gates_j14': 50,
      },
      'éclos + perdus au-delà des œufs retenus': {
        'oeufs_blancs_j7': 20,
        'poussins_nes': 70,
        'oeufs_perdus': 20,
      },
      'lot qui se remplace lui-même': {'lot_parent_id': idLot},
      'origine qui n\'est pas un UUID': {'lot_parent_id': 'x'},
      'incubateur inconnu du poste': {'machine_id': idMachine},
      'instant de saisie absent': {'updated_at': null},
    };
    cas.forEach((nom, surcharge) {
      test('refusée et comptée, rien d\'écrit : $nom', () async {
        final b = await poste('P2');
        serveur.cycles[idLot] = {
          ...saine(surcharge),
          'device_id': 'autre-poste',
          'serveur_modifie_le': serveur.instantServeur(),
        };

        final r = await b.moteur.synchroniser();

        expect(r.refuseesALaReception, 1, reason: nom);
        expect(await b.lots(), isEmpty);
      });
    });

    test('un lot sain, lui, est absorbé', () async {
      final b = await poste('P2');
      serveur.cycles[idLot] = {
        ...saine(),
        'device_id': 'autre-poste',
        'serveur_modifie_le': serveur.instantServeur(),
      };

      final r = await b.moteur.synchroniser();

      expect(r.refuseesALaReception, 0);
      expect(await b.lots(), hasLength(1));
    });

    test(
      'un code déjà porté ici par un AUTRE lot est signalé, jamais écrasé',
      () async {
        final b = await poste(null);
        final local = await b.lot(); // C-2026-001
        serveur.ajouterCycle(idLot, local.code, charges: 77);

        final r = await b.moteur.synchroniser();

        expect(r.refuseesALaReception, 1);
        expect((await b.lire(local.id)).oeufsCouves, 200);
        expect(await b.lots(), hasLength(1));
      },
    );

    test('un incubateur incohérent est refusé', () async {
      final b = await poste('P2');
      final cas = <Map<String, dynamic>>[
        {'code': ' '},
        {'libelle': ''},
        {'capacite_oeufs': 0},
        {'capacite_oeufs': '500'},
        {'active': 1},
        {'id': 'x'},
      ];
      var i = 0;
      for (final surcharge in cas) {
        serveur.machines['m${i++}'] = {
          'id': idMachine,
          'device_id': 'autre-poste',
          'code': 'INC-09',
          'libelle': 'Couveuse',
          'capacite_oeufs': 100,
          'active': true,
          'updated_at': '2026-11-09T09:00:00.000000Z',
          'serveur_modifie_le': serveur.instantServeur(),
          'supprime_le': null,
          ...surcharge,
        };
      }

      final r = await b.moteur.synchroniser();

      expect(r.refuseesALaReception, cas.length);
      expect(await b.machines(), isEmpty);
    });

    test(
      'un incubateur du serveur qui usurpe le code d\'un incubateur local est refusé',
      () async {
        final b = await poste('P2');
        await b.machine('INC-01');
        serveur.ajouterMachine(idMachine, 'INC-01', libelle: 'Intrus');

        final r = await b.moteur.synchroniser();

        expect(r.refuseesALaReception, 1);
        expect((await b.machines()).single.libelle, 'Couveuse INC-01');
      },
    );
  });

  group('incubateurs : règle du plus récent', () {
    test(
      'une saisie locale non envoyée plus récente est conservée, puis envoyée',
      () async {
        final a = await poste('P1');
        final m = await a.machine('INC-01', 528);
        serveur.ajouterMachine(
          m.id,
          'INC-01',
          libelle: 'Libellé ancien du serveur',
          capacite: 10,
          updatedAt: '2020-01-01T00:00:00.000000Z',
        );

        final r = await a.moteur.synchroniser();

        expect(r.conserveesLocalement, 1);
        expect((await a.machines()).single.capaciteOeufs, 528);
        expect(serveur.machines[m.id]!['capacite_oeufs'], 528);
      },
    );

    test(
      'une version du serveur strictement plus récente remplace la saisie locale',
      () async {
        final a = await poste('P1');
        final m = await a.machine('INC-01', 528);
        serveur.ajouterMachine(
          m.id,
          'INC-01',
          libelle: 'Neuve',
          capacite: 700,
          active: false,
          updatedAt: DateTime.now()
              .add(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
        );

        final r = await a.moteur.synchroniser();

        expect(r.supplantees, 1);
        final ligne = (await a.machines()).single;
        expect(ligne.capaciteOeufs, 700);
        expect(ligne.libelle, 'Neuve');
        expect(ligne.active, isFalse);
        expect(ligne.syncStatus, 'synced');
      },
    );

    test(
      'une saisie faite PENDANT l\'envoi n\'est jamais marquée synchronisée à tort',
      () async {
        final a = await poste('P1');
        final m = await a.machine('INC-01', 528);
        serveur.pendantEnvoi = () async {
          await Future<void>.delayed(const Duration(milliseconds: 3));
          await (a.db.update(
            a.db.machinesIncubateur,
          )..where((x) => x.id.equals(m.id))).write(
            MachinesIncubateurCompanion(
              capaciteOeufs: const Value(600),
              syncStatus: const Value('pending'),
              updatedAt: Value(instantSaisie()),
            ),
          );
        };

        await a.moteur.synchroniser();

        expect((await a.machines()).single.syncStatus, 'pending');
        await a.moteur.synchroniser();
        expect((await a.machines()).single.syncStatus, 'synced');
        expect(serveur.machines[m.id]!['capacite_oeufs'], 600);
      },
    );
  });

  group('refus du serveur', () {
    test(
      'un code déjà pris : le lot devient conflict, avec le motif du serveur',
      () async {
        final a = await poste('P1');
        final l = await a.lot(); // C-P1-2026-001
        serveur.ajouterCycle(idLot, l.code, charges: 77);

        final r = await a.moteur.synchroniser();

        expect(r.refusees, 1);
        final ligne = await a.lire(l.id);
        expect(ligne.syncStatus, 'conflict');
        expect(ligne.syncMotif, 'Ce code est déjà utilisé par un autre lot.');
        expect(serveur.cycles.containsKey(l.id), isFalse);
        // Jamais renvoyé en boucle.
        expect((await a.moteur.synchroniser()).envoyees, 0);
      },
    );

    test(
      'un lot dont l\'incubateur est refusé est refusé avec son motif',
      () async {
        final a = await poste('P1');
        final m = await a.machine('INC-01');
        final l = await a.lot(machineId: m.id);
        serveur.ajouterMachine(idMachine, 'INC-01', libelle: 'Déjà là');

        final r = await a.moteur.synchroniser();

        expect(r.refusees, 2);
        expect(
          (await a.machines()).single.syncMotif,
          'Un incubateur porte déjà le code INC-01.',
        );
        expect(
          (await a.lire(l.id)).syncMotif,
          'Incubateur inconnu du serveur.',
        );
      },
    );
  });

  group('suppression', () {
    test(
      'supprimer un lot envoie une pierre tombale : les autres postes le retirent',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final l = await a.lot();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        expect(await b.lots(), hasLength(1));
        await Future<void>.delayed(const Duration(milliseconds: 3));

        await a.repo.supprimer(l.id);
        expect(await a.lots(), isEmpty, reason: 'rangé en corbeille');
        final r = await a.moteur.synchroniser();

        expect(r.refusees, 0);
        expect(serveur.cycles[l.id]!['supprime_le'], isNotNull);
        await b.moteur.synchroniser();
        expect(await b.lots(), isEmpty);
      },
    );

    test(
      'un lot supprimé n\'est pas ressuscité par l\'écho du serveur',
      () async {
        final a = await poste('P1');
        final l = await a.lot();
        await a.moteur.synchroniser();
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await a.repo.supprimer(l.id);

        // Le tirage rend à A son propre lot (modifié après son curseur), AVANT que la
        // pierre tombale soit partie.
        final r = await a.moteur.synchroniser();

        expect(await a.lots(), isEmpty);
        expect(r.conserveesLocalement, 1);
        expect(serveur.cycles[l.id]!['supprime_le'], isNotNull);
      },
    );

    test(
      'un autre poste qui modifie le lot APRÈS sa suppression le fait revenir',
      () async {
        final a = await poste('P1');
        final l = await a.lot();
        await a.moteur.synchroniser();
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await a.repo.supprimer(l.id);
        serveur.cycles[l.id]!['oeufs_couves'] = 150;
        serveur.cycles[l.id]!['updated_at'] = DateTime.now()
            .add(const Duration(hours: 1))
            .toUtc()
            .toIso8601String();
        serveur.cycles[l.id]!['serveur_modifie_le'] = serveur.instantServeur();

        final r = await a.moteur.synchroniser();

        expect(r.supplantees, 1);
        expect((await a.lire(l.id)).oeufsCouves, 150);
        expect(
          serveur.cycles[l.id]!['supprime_le'],
          isNull,
          reason: 'la pierre tombale est caduque : elle ne repart pas',
        );
      },
    );

    test('la pierre tombale n\'est envoyée qu\'une fois (accusé)', () async {
      final a = await poste('P1');
      final l = await a.lot();
      await a.moteur.synchroniser();
      await a.repo.supprimer(l.id);
      await a.moteur.synchroniser();
      final avant = serveur.envois.length;

      final r = await a.moteur.synchroniser();

      expect(r.envoyees, 0);
      expect(serveur.envois.length, avant);
    });

    test('un tirage complet ne ressuscite pas un lot supprimé', () async {
      final a = await poste('P1');
      final l = await a.lot();
      await a.moteur.synchroniser();
      await a.repo.supprimer(l.id);
      await a.moteur.synchroniser();

      await a.moteur.synchroniser(complet: true);

      expect(await a.lots(), isEmpty);
    });

    test(
      'les sous-lots d\'un lot supprimé deviennent des lots racines, aussi au serveur',
      () async {
        final a = await poste('P1');
        final l = await a.lot();
        final r = await a.repo.enregistrerEclosion(
          cycleId: l.id,
          poussinsEclos: 150,
          oeufsPerdus: 10,
          oeufsRemplacement: 90,
        );
        await a.moteur.synchroniser();
        await Future<void>.delayed(const Duration(milliseconds: 3));

        await a.repo.supprimer(l.id);
        await a.moteur.synchroniser();

        expect((await a.lire(r.sousLot!.id)).lotParentId, isNull);
        expect(serveur.cycles[r.sousLot!.id]!['lot_parent_id'], isNull);
        expect(serveur.cycles[l.id]!['supprime_le'], isNotNull);
      },
    );

    test(
      'restaurer le lot lève la pierre tombale : il revient partout',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final l = await a.lot();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await a.repo.supprimer(l.id);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        expect(await b.lots(), isEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 3));

        final service = ServiceArchivage(a.db);
        await service.restaurer(
          (await service.lister()).single.id,
          estAdmin: false,
        );
        expect((await a.lire(l.id)).syncStatus, 'pending');
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        expect(serveur.cycles[l.id]!['supprime_le'], isNull);
        expect(await b.lots(), hasLength(1));
      },
    );

    test(
      'une pierre tombale du serveur ne supprime pas une saisie locale plus récente',
      () async {
        final a = await poste('P1');
        final l = await a.lot();
        await a.moteur.synchroniser();
        serveur.cycles[l.id]!['supprime_le'] = '2020-01-01T00:00:00.000000Z';
        serveur.cycles[l.id]!['updated_at'] = '2020-01-01T00:00:00.000000Z';
        serveur.cycles[l.id]!['serveur_modifie_le'] = serveur.instantServeur();
        await a.repo.enregistrerMirage(cycleId: l.id, jour: 7, oeufsRetires: 4);

        final r = await a.moteur.synchroniser();

        expect(r.conserveesLocalement, 1);
        expect(await a.lots(), hasLength(1));
      },
    );

    test('une pierre tombale pour un lot inconnu ne fait rien', () async {
      final b = await poste('P2');
      serveur.ajouterCycle(
        idLot,
        'C-P1-2026-001',
        supprimeLe: '2026-11-09T09:00:00.000Z',
      );

      final r = await b.moteur.synchroniser();

      expect(r.refuseesALaReception, 0);
      expect(await b.lots(), isEmpty);
    });

    test(
      'la corbeille vidée avant l\'envoi : la pierre tombale n\'existe plus',
      () async {
        // Limite documentée : rien à envoyer, mais rien ne casse.
        final a = await poste('P1');
        final l = await a.lot();
        await a.moteur.synchroniser();
        await a.repo.supprimer(l.id);
        await ServiceArchivage(a.db).purgerTout(estAdmin: true);

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(serveur.cycles[l.id]!['supprime_le'], isNull);
      },
    );

    test(
      'l\'instantané de la corbeille porte l\'instant de la suppression',
      () async {
        final a = await poste('P1');
        final l = await a.lot();
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await a.repo.supprimer(l.id);

        final archive = (await a.db.select(a.db.corbeille).get()).single;
        final donnees = jsonDecode(archive.donneesJson) as Map<String, Object?>;

        expect(donnees['sync_status'], 'pending');
        expect(
          DateTime.parse(
            donnees['updated_at']! as String,
          ).isAfter(DateTime.parse(l.dateChargement.toUtc().toIso8601String())),
          isTrue,
        );
      },
    );
  });

  group('hors ligne et remise à zéro', () {
    test(
      'hors ligne : le lot reste en attente et part à la reconnexion',
      () async {
        final a = await poste('P1');
        final l = await a.lot();
        serveur.horsLigne = true;

        expect(
          (await a.moteur.synchroniser()).issue,
          IssueSynchronisation.horsLigne,
        );
        expect((await a.lire(l.id)).syncStatus, 'pending');

        serveur.horsLigne = false;
        await a.moteur.synchroniser();

        expect((await a.lire(l.id)).syncStatus, 'synced');
      },
    );

    test(
      'remise à zéro du serveur : lots avant incubateurs, saisies non envoyées comptées',
      () async {
        final a = await poste('P1');
        final m = await a.machine();
        await a.lot(machineId: m.id);
        await a.moteur.synchroniser();
        serveur.remettreAZero();
        // Une saisie faite hors ligne, jamais envoyée : elle sera comptée.
        final perdu = await a.lot(machineId: m.id);
        await a.repo.supprimer(
          (await a.lots()).firstWhere((c) => c.id != perdu.id).id,
        );

        final r = await a.moteur.synchroniser();

        expect(r.remiseAZero, isTrue, reason: r.message);
        expect(await a.lots(), isEmpty);
        expect(
          await a.machines(),
          isEmpty,
          reason:
              'lots purgés AVANT leur incubateur : la clé étrangère n\'a rien bloqué',
        );
        expect(r.saisiesPerdues, greaterThanOrEqualTo(1));
      },
    );

    test(
      'la remise à zéro ne touche ni les fiches d\'élevage ni la corbeille',
      () async {
        final a = await poste('P1');
        final l = await a.lot();
        await a.repo.supprimer(l.id);
        await a.lot();
        await a.moteur.synchroniser();
        final corbeille = (await a.db.select(a.db.corbeille).get()).length;

        serveur.remettreAZero();
        await a.moteur.synchroniser();

        expect((await a.db.select(a.db.corbeille).get()).length, corbeille);
        expect(await a.db.select(a.db.ficheJournee).get(), isEmpty);
      },
    );
  });

  group('écritures locales : tout geste remet le lot à envoyer', () {
    test('création, mirage, éclosion, modification, sous-lot', () async {
      final a = await poste('P1');
      final l = await a.lot();
      await a.moteur.synchroniser();
      Future<String> statut(String id) async => (await a.lire(id)).syncStatus;

      expect(await statut(l.id), 'synced');
      await a.repo.enregistrerMirage(cycleId: l.id, jour: 14, oeufsRetires: 3);
      expect(await statut(l.id), 'pending');
      await a.moteur.synchroniser();
      await a.repo.modifier(
        cycleId: l.id,
        espece: EspeceCouvable.goliath,
        dateChargement: DateTime(2026, 8, 2),
        oeufsCharges: 190,
      );
      expect(await statut(l.id), 'pending');
      await a.moteur.synchroniser();
      final r = await a.repo.enregistrerEclosion(
        cycleId: l.id,
        poussinsEclos: 100,
        oeufsPerdus: 5,
        oeufsRemplacement: 50,
      );
      expect(await statut(l.id), 'pending');
      expect(await statut(r.sousLot!.id), 'pending');
    });

    test(
      'la modification d\'un lot en conflit le remet à envoyer (motif effacé)',
      () async {
        final a = await poste('P1');
        final l = await a.lot();
        serveur.ajouterCycle(idLot, l.code);
        await a.moteur.synchroniser();
        expect((await a.lire(l.id)).syncStatus, 'conflict');

        await a.repo.enregistrerMirage(cycleId: l.id, jour: 7, oeufsRetires: 1);

        final ligne = await a.lire(l.id);
        expect(ligne.syncStatus, 'pending');
        expect(ligne.syncMotif, isNull);
      },
    );
  });

  group('le moteur ne connaît que ses deux tables', () {
    test('noms de table du contrat', () {
      final db = AppDatabase.enMemoire();
      addTearDown(db.close);
      expect(TableCyclesCouveusePoste(db).nom, 'cycle_couveuse');
      expect(TableMachinesIncubateurPoste(db).nom, 'machines_incubateur');
      expect(TableCyclesCouveusePoste(db).referentiel, isFalse);
      expect(TableMachinesIncubateurPoste(db).referentiel, isFalse);
    });

    test(
      'les compteurs se contredisent : règles identiques à celles de l\'écran',
      () {
        bool incoherent({
          required int charges,
          int? blancs,
          int? gates,
          int? eclos,
          int? perdus,
        }) => TableCyclesCouveusePoste.compteursIncoherents(
          charges: charges,
          blancs: blancs,
          gates: gates,
          eclos: eclos,
          perdus: perdus,
        );
        expect(
          incoherent(charges: 100, blancs: 10, gates: 5, eclos: 80, perdus: 5),
          isFalse,
        );
        expect(
          incoherent(charges: 100, blancs: 10, gates: 5, eclos: 86, perdus: 0),
          isTrue,
        );
        expect(incoherent(charges: 100, blancs: 60, gates: 41), isTrue);
        expect(incoherent(charges: 100, blancs: 60, gates: 40), isFalse);
        expect(incoherent(charges: 0), isTrue);
        expect(incoherent(charges: 100, perdus: -1), isTrue);
      },
    );
  });
}
