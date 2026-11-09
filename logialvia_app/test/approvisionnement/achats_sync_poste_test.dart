import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/approvisionnement/data/repositories/approvisionnement_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_achats_poste.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_fournisseurs_poste.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/approvisionnement.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import '../core/sync/faux_serveur_sync.dart';

/// Palier 4 — fournisseurs (fait plat) et achats (lot achat + lignes) entre deux
/// postes, contre un faux serveur qui rejoue la LOGIQUE du vrai.
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
      tables: [TableFournisseursPoste(db), TableAchatsPoste(db)],
      client: serveur.client,
    );
    appro = ApprovisionnementRepositoryDrift(db);
  }

  final FauxServeurSync serveur;
  final String? code;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final ApprovisionnementRepositoryDrift appro;

  Future<void> demarrer() async {
    await SeedInitial(db).executer();
    await preferences.definirAdresseServeur('http://serveur.test');
    if (code != null) {
      await preferences.memoriserAppairage(
        codePoste: code!,
        compte: 'g',
        le: DateTime.now(),
      );
    }
    // Un poste non appairé a quand même un jeton ici : on teste la synchro, pas l'appairage.
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

  Future<String> fournisseur([String nom = 'Maïs Local']) async =>
      (await appro.creerFournisseur(nom: nom, telephone: '97000001')).id;

  Future<String> acheter(
    String fournisseurId, {
    bool livree = false,
    double? paye,
    double qte = 100,
  }) async {
    final r = await appro.enregistrerAchat(
      fournisseurId: fournisseurId,
      mode: ModeReglement.especes,
      montantPaye: paye ?? 0,
      livree: livree,
      panier: [
        LignePanierAchat(
          intrantCode: 'INT-001',
          nom: 'Maïs',
          quantite: qte,
          prixUnitaire: 300,
          unite: 'kg',
        ),
      ],
    );
    return r.reference;
  }

  Future<List<AchatRow>> achats() =>
      (db.select(db.achats)..orderBy([(a) => OrderingTerm.asc(a.ref)])).get();
  Future<AchatRow> achat(String ref) =>
      (db.select(db.achats)..where((a) => a.ref.equals(ref))).getSingle();
  Future<int> stockMais() async => (await (db.select(
    db.intrants,
  )..where((i) => i.code.equals('INT-001'))).getSingle()).stock;
}

void main() {
  late FauxServeurSync serveur;
  final postes = <_Poste>[];

  Future<_Poste> poste(String? code) async {
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

  final annee = DateTime.now().year;

  group('références', () {
    test(
      'poste appairé : ACH-P2-AAAA-NNN ; jamais appairé : ACH-AAAA-NNN',
      () async {
        final a = await poste('P2');
        final f = await a.fournisseur();
        expect(await a.acheter(f), 'ACH-P2-$annee-001');
        expect(await a.acheter(f), 'ACH-P2-$annee-002');

        final sans = await poste(null);
        final fs = await sans.fournisseur();
        expect(await sans.acheter(fs), 'ACH-$annee-001');
      },
    );

    test(
      'le code survit à la déconnexion ; P1 et P12 ne se mélangent pas',
      () async {
        final a = await poste('P12');
        final f = await a.fournisseur();
        await a.acheter(f);
        await a.preferences.oublierAppairage();
        expect(await a.acheter(f), 'ACH-P12-$annee-002');
        await a.preferences.memoriserAppairage(
          codePoste: 'P1',
          compte: 'g',
          le: DateTime.now(),
        );
        expect(await a.acheter(f), 'ACH-P1-$annee-001');
      },
    );
  });

  group('envoi', () {
    test(
      'un achat part avec ses lignes, son fournisseur d\'abord, puis est marqué synchronisé',
      () async {
        final a = await poste('P1');
        final f = await a.fournisseur();
        final ref = await a.acheter(f, paye: 10000);

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(r.refusees, 0, reason: r.message);
        expect(serveur.fournisseurs, hasLength(1));
        final x = serveur.achats.values.single;
        expect(x['reference'], ref);
        expect(x['fournisseur_id'], f);
        expect((x['lignes'] as List), hasLength(1));
        expect((await a.achat(ref)).syncStatus, 'synced');
      },
    );

    test(
      'réceptionner ou régler un achat le remet à envoyer, avec un instant plus récent',
      () async {
        final a = await poste('P1');
        final f = await a.fournisseur();
        final ref = await a.acheter(f);
        await a.moteur.synchroniser();
        final avant = (await a.achat(ref)).updatedAt;
        await Future<void>.delayed(const Duration(milliseconds: 3));

        await a.appro.receptionnerAchat(ref);
        var x = await a.achat(ref);
        expect(x.syncStatus, 'pending');
        expect(
          DateTime.parse(x.updatedAt).isAfter(DateTime.parse(avant)),
          isTrue,
        );

        await a.moteur.synchroniser();
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await a.appro.reglerAchat(reference: ref, montant: 5000);
        x = await a.achat(ref);
        expect(x.syncStatus, 'pending');
        expect(x.paye, 5000);
      },
    );

    test(
      'fournisseur refusé : l\'achat qui le porte devient conflit, avec le motif',
      () async {
        final a = await poste('P1');
        final f = await a.fournisseur();
        final ref = await a.acheter(f);
        // Le fournisseur est refusé par le serveur (nom vidé après coup).
        await (a.db.update(a.db.fournisseurs)..where((x) => x.id.equals(f)))
            .write(const FournisseursCompanion(nom: Value('  ')));

        final r = await a.moteur.synchroniser();

        expect(r.refusees, greaterThanOrEqualTo(1));
        final x = await a.achat(ref);
        expect(x.syncStatus, 'conflict');
        expect(x.syncMotif, 'Fournisseur inconnu du serveur.');
      },
    );

    test('rejouer l\'envoi ne duplique ni achat ni lignes', () async {
      final a = await poste('P1');
      final f = await a.fournisseur();
      await a.acheter(f);
      await a.moteur.synchroniser();
      await a.db
          .update(a.db.achats)
          .write(const AchatsCompanion(syncStatus: Value('pending')));

      await a.moteur.synchroniser();

      expect(serveur.achats, hasLength(1));
    });

    test('un achat modifié PENDANT l\'envoi repart au prochain envoi', () async {
      final a = await poste('P1');
      final f = await a.fournisseur();
      final ref = await a.acheter(f);
      // Le moteur envoie d'abord les fournisseurs, PUIS les achats : la
      // modification doit tomber pendant l'envoi de l'achat.
      late Future<void> Function() pendant;
      pendant = () async {
        if (serveur.achats.isEmpty && serveur.fournisseurs.isNotEmpty) {
          // Premier envoi de l'achat en cours : on modifie l'achat maintenant.
        } else if (serveur.fournisseurs.isEmpty) {
          serveur.pendantEnvoi =
              pendant; // requête des fournisseurs : on attend la suivante
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await a.appro.reglerAchat(reference: ref, montant: 7000);
      };
      serveur.pendantEnvoi = pendant;

      await a.moteur.synchroniser();

      expect(
        (await a.achat(ref)).syncStatus,
        'pending',
        reason: 'jamais « synchronisé » à tort',
      );
      await a.moteur.synchroniser();
      expect((await a.achat(ref)).syncStatus, 'synced');
      expect(serveur.achats.values.single['paye'], 7000);
    });
  });

  group('deux postes', () {
    test(
      'B reçoit l\'achat de A avec ses lignes, SANS stock, SANS PMP, SANS mouvement, SANS écriture',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final stockB = await b.stockMais();
        final mouvementsB =
            (await b.db.select(b.db.mouvementsIntrant).get()).length;
        final ecrituresB =
            (await b.db.select(b.db.ecritureComptable).get()).length;
        final f = await a.fournisseur();
        final ref = await a.acheter(f, livree: true, qte: 50);
        await a.moteur.synchroniser();

        final r = await b.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        final x = await b.achat(ref);
        expect(x.syncStatus, 'synced');
        expect(x.statut, StatutAchat.livre);
        expect(
          await (b.db.select(
            b.db.lignesAchat,
          )..where((l) => l.achatRef.equals(ref))).get(),
          hasLength(1),
        );
        expect(
          await b.stockMais(),
          stockB,
          reason: 'la réception appartient au poste qui a reçu la marchandise',
        );
        expect(
          (await b.db.select(b.db.mouvementsIntrant).get()).length,
          mouvementsB,
        );
        expect(
          (await b.db.select(b.db.ecritureComptable).get()).length,
          ecrituresB,
        );
        expect(
          await (b.db.select(
            b.db.fournisseurs,
          )..where((x) => x.id.equals(f))).getSingle(),
          isNotNull,
        );
      },
    );

    test(
      'la séquence de références de B n\'est pas perturbée par les achats de A',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.acheter(await a.fournisseur());
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        expect(await b.acheter(await b.fournisseur()), 'ACH-P2-$annee-001');
      },
    );

    test(
      'la livraison enregistrée par A arrive chez B (entête), les lignes ne bougent pas',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final ref = await a.acheter(await a.fournisseur());
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await Future<void>.delayed(const Duration(milliseconds: 3));

        await a.appro.receptionnerAchat(ref);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        expect((await b.achat(ref)).statut, StatutAchat.livre);
        expect(await b.db.select(b.db.lignesAchat).get(), hasLength(1));
      },
    );

    test(
      'deux fournisseurs homonymes créés chacun de leur côté restent deux fournisseurs',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.fournisseur('Soja Bénin');
        await b.fournisseur('Soja Bénin');
        for (final p in [a, b, a, b]) {
          await p.moteur.synchroniser();
        }

        expect(serveur.fournisseurs, hasLength(2));
        expect(await a.db.select(a.db.fournisseurs).get(), hasLength(2));
        expect(await b.db.select(b.db.fournisseurs).get(), hasLength(2));
      },
    );

    test(
      'même ancienne référence sans code sur deux postes : le serveur accepte les deux, chacun garde la sienne',
      () async {
        final a = await poste(null);
        final b = await poste(null);
        expect(await a.acheter(await a.fournisseur()), 'ACH-$annee-001');
        expect(await b.acheter(await b.fournisseur()), 'ACH-$annee-001');

        await a.moteur.synchroniser();
        final rb = await b.moteur.synchroniser();
        final ra = await a.moteur.synchroniser();

        expect(serveur.achats, hasLength(2));
        expect(rb.refuseesALaReception, 1);
        expect(ra.refuseesALaReception, 1);
        expect(await a.achats(), hasLength(1));
        expect(await b.achats(), hasLength(1));
      },
    );
  });

  group('absorbeur strict et règle du plus récent', () {
    Map<String, dynamic> achatServeur(
      String fournisseurId, {
      Map<String, dynamic> surcharge = const {},
    }) => {
      'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'device_id': 'autre',
      'reference': 'ACH-P9-2026-001',
      'fournisseur_id': fournisseurId,
      'date_achat': '2026-11-01T10:00:00.000000Z',
      'statut': StatutAchat.commande,
      'total': 30000,
      'paye': 10000,
      'mode': ModeReglement.especes,
      'echeance': null,
      'updated_at': '2026-11-01T10:00:00.000000Z',
      'serveur_modifie_le': '2026-11-09T10:00:00.000001Z',
      'lignes': [
        {
          'id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
          'intrant_code': 'INT-001',
          'nom': 'Maïs',
          'qte': 100,
          'pu_achat': 300,
        },
      ],
      ...surcharge,
    };

    Future<String> avecFournisseurServeur(_Poste p) async {
      const id = 'abababab-abab-4bab-8bab-abababababab';
      serveur.fournisseurs[id] = {
        'id': id,
        'device_id': 'autre',
        'nom': 'Fournisseur distant',
        'telephone': null,
        'adresse': null,
        'fournit': null,
        'updated_at': '2026-11-01T09:00:00.000000Z',
        'serveur_modifie_le': '2026-11-09T10:00:00.000000Z',
        'supprime_le': null,
      };
      return id;
    }

    test(
      'un achat cohérent est absorbé avec ses lignes et son fournisseur',
      () async {
        final b = await poste('P2');
        final f = await avecFournisseurServeur(b);
        serveur.achats['x'] = achatServeur(f);

        final r = await b.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(await b.achats(), hasLength(1));
        expect(await b.db.select(b.db.lignesAchat).get(), hasLength(1));
      },
    );

    final cas = <String, Map<String, dynamic> Function(String)>{
      'référence invalide': (f) =>
          achatServeur(f, surcharge: {'reference': 'V-2026-001'}),
      'sans ligne': (f) => achatServeur(f, surcharge: {'lignes': <Object>[]}),
      'payé au-delà du total': (f) =>
          achatServeur(f, surcharge: {'paye': 99999}),
      'statut inconnu': (f) => achatServeur(f, surcharge: {'statut': 'Perdu'}),
      'mode inconnu': (f) => achatServeur(f, surcharge: {'mode': 'Troc'}),
      'fournisseur inconnu du poste': (f) =>
          achatServeur('00000000-0000-4000-8000-000000000000'),
      'intrant inconnu du poste': (f) => achatServeur(
        f,
        surcharge: {
          'lignes': [
            {
              'id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
              'intrant_code': 'INT-INCONNU',
              'nom': 'X',
              'qte': 1,
              'pu_achat': 1,
            },
          ],
        },
      ),
    };
    cas.forEach((nom, fabrique) {
      test('refusé, sans rien écrire : $nom', () async {
        final b = await poste('P2');
        final f = await avecFournisseurServeur(b);
        serveur.achats['x'] = fabrique(f);

        final r = await b.moteur.synchroniser();

        expect(r.refuseesALaReception, 1);
        expect(await b.achats(), isEmpty);
        expect(
          await b.db.select(b.db.lignesAchat).get(),
          isEmpty,
          reason: 'jamais de ligne sans son achat',
        );
      });
    });

    test(
      'une saisie locale plus récente n\'est pas écrasée ; une plus ancienne est remplacée, et c\'est dit',
      () async {
        final a = await poste('P1');
        final ref = await a.acheter(await a.fournisseur());
        await a.moteur.synchroniser();
        final id = (await a.achat(ref)).id;

        // Local ANCIEN (non envoyé), serveur plus récent : le serveur l'emporte.
        await (a.db.update(a.db.achats)..where((x) => x.id.equals(id))).write(
          const AchatsCompanion(
            paye: Value(1000),
            syncStatus: Value('pending'),
            updatedAt: Value('2020-01-01T00:00:00.000000Z'),
          ),
        );
        serveur.achats[id]!['statut'] = StatutAchat.livre;
        serveur.achats[id]!['updated_at'] = '2026-11-09T12:00:00.000000Z';
        serveur.achats[id]!['serveur_modifie_le'] = serveur.instantServeur();

        final r = await a.moteur.synchroniser();

        expect(r.supplantees, 1);
        expect((await a.achat(ref)).statut, StatutAchat.livre);
      },
    );

    test('les lignes d\'un achat connu ne changent jamais', () async {
      final b = await poste('P2');
      final f = await avecFournisseurServeur(b);
      serveur.achats['x'] = achatServeur(f);
      await b.moteur.synchroniser();

      serveur.achats['x']!['lignes'] = [
        {
          'id': 'abababab-abab-4bab-8bab-abababababab',
          'intrant_code': 'INT-001',
          'nom': 'Autre',
          'qte': 9,
          'pu_achat': 1,
        },
      ];
      serveur.achats['x']!['statut'] = StatutAchat.livre;
      serveur.achats['x']!['updated_at'] = '2026-11-09T13:00:00.000000Z';
      serveur.achats['x']!['serveur_modifie_le'] = serveur.instantServeur();
      await b.moteur.synchroniser();

      final lignes = await b.db.select(b.db.lignesAchat).get();
      expect(lignes, hasLength(1));
      expect(lignes.single.qte, 100);
      expect((await b.achats()).single.statut, StatutAchat.livre);
    });
  });

  group('fournisseurs : absorbeur strict', () {
    Map<String, dynamic> f([Map<String, dynamic> s = const {}]) => {
      'id': '12121212-1212-4121-8121-121212121212',
      'device_id': 'autre',
      'nom': 'Fournisseur distant',
      'telephone': null,
      'adresse': null,
      'fournit': null,
      'updated_at': '2026-11-01T09:00:00.000000Z',
      'serveur_modifie_le': '2026-11-09T10:00:00.000001Z',
      'supprime_le': null,
      ...s,
    };

    test(
      'cohérent : absorbé ; incohérent (UUID, nom, instant) : refusé',
      () async {
        final b = await poste('P2');
        serveur.fournisseurs['ok'] = f();
        serveur.fournisseurs['x1'] = f({'id': 'pas-un-uuid'});
        serveur.fournisseurs['x2'] = f({
          'id': '13131313-1313-4131-8131-131313131313',
          'nom': '  ',
        });
        serveur.fournisseurs['x3'] = f({
          'id': '14141414-1414-4141-8141-141414141414',
          'updated_at': 'hier',
        });

        final r = await b.moteur.synchroniser();

        expect(r.recues, 1);
        expect(r.refuseesALaReception, 3);
        expect((await b.db.select(b.db.fournisseurs).get()).map((x) => x.nom), [
          'Fournisseur distant',
        ]);
      },
    );

    test(
      'une pierre tombale ne supprime jamais un fournisseur (un achat peut s\'y rattacher)',
      () async {
        final b = await poste('P2');
        final id = await b.fournisseur('Garde-moi');
        await b.moteur.synchroniser();
        serveur.fournisseurs[id]!['supprime_le'] = '2026-11-09T12:00:00.000Z';
        serveur.fournisseurs[id]!['updated_at'] = '2026-11-09T12:00:00.000000Z';
        serveur.fournisseurs[id]!['serveur_modifie_le'] = serveur
            .instantServeur();

        final r = await b.moteur.synchroniser();

        expect(await b.db.select(b.db.fournisseurs).get(), hasLength(1));
        expect(
          r.conserveesLocalement,
          1,
          reason: 'la pierre tombale est ignorée, et comptée',
        );
      },
    );
  });

  test(
    'remise à zéro du serveur : achats et fournisseurs partent (achats d\'abord), le reste demeure',
    () async {
      final a = await poste('P1');
      final f = await a.fournisseur();
      await a.acheter(f);
      await a.moteur.synchroniser();

      serveur.remettreAZero();
      final r = await a.moteur.synchroniser();

      expect(r.remiseAZero, isTrue, reason: r.message);
      expect(await a.achats(), isEmpty);
      expect(await a.db.select(a.db.lignesAchat).get(), isEmpty);
      expect(
        await a.db.select(a.db.fournisseurs).get(),
        isEmpty,
        reason:
            'achats purgés AVANT leur fournisseur : la clé étrangère n\'a rien bloqué',
      );
      expect(
        (await a.db.select(a.db.intrants).get()),
        isNotEmpty,
        reason: 'les intrants (référentiel) restent',
      );
    },
  );

  test(
    'hors ligne : l\'achat reste en attente et part à la reconnexion',
    () async {
      final a = await poste('P1');
      final ref = await a.acheter(await a.fournisseur());
      serveur.horsLigne = true;
      expect(
        (await a.moteur.synchroniser()).issue,
        IssueSynchronisation.horsLigne,
      );
      expect((await a.achat(ref)).syncStatus, 'pending');

      serveur.horsLigne = false;
      await a.moteur.synchroniser();

      expect((await a.achat(ref)).syncStatus, 'synced');
    },
  );
}
