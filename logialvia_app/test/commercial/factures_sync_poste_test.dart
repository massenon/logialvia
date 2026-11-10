import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/commercial/data/repositories/factures_mecef_repository_drift.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_factures_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_groupes_taxe_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_produits_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_ventes_poste.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/commercial/presentation/viewmodels/factures_mecef_view_model.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:logialvia_app/core/sync/table_poste.dart';

import '../core/sync/faux_serveur_sync.dart';

/// P9 — factures e-MECeF et grille de taxation entre postes, contre un faux
/// serveur qui rejoue la LOGIQUE du vrai (`FacturesTable`).
///
/// Ce qui est éprouvé ici : lot facture + lignes, numérotation à préfixe de poste
/// (DV-21), statut qui ne régresse jamais (le rang l'emporte sur l'horloge),
/// normalisation immuable (la double normalisation n'est jamais départagée en
/// silence), absence totale d'effet de bord à l'absorption, un seul poste qui
/// transmet, aucun secret sur le fil.
class _Poste {
  _Poste(this.serveur, this.code) : db = AppDatabase.enMemoire() {
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: serveur.client,
    );
    tableFactures = TableFacturesPoste(db);
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: appairage,
      demandes: DepotDemandesReferentiel(db),
      tables: [
        TableProduitsPoste(db),
        TableClientsPoste(db),
        TableVentesPoste(db),
        TableGroupesTaxePoste(db),
        tableFactures,
      ],
      client: serveur.client,
    );
    bus = EventBus();
    ventes = VentesRepositoryDrift(db, bus);
    factures = FacturesMecefRepositoryDrift(db);
  }

  final FauxServeurSync serveur;
  final String? code;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final TableFacturesPoste tableFactures;
  late final EventBus bus;
  late final VentesRepositoryDrift ventes;
  late final FacturesMecefRepositoryDrift factures;

  Future<void> demarrer() async {
    await SeedInitial(db).executer();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: code ?? 'P0',
      compte: 'g',
      le: DateTime.now(),
    );
    if (code == null) {
      // Poste « avant appairage » : références sans code de poste.
      await (db.delete(
        db.preferencesPoste,
      )..where((p) => p.cle.equals('poste.code_attribue'))).go();
    }
    await depot.ecrire('1|jeton');
  }

  Future<String> vendre({double qte = 1}) async {
    final p = (await ventes.chargerCatalogue()).firstWhere(
      (p) => p.nom == 'Goliath mature',
    );
    final r = await ventes.enregistrerVente(
      client: 'Client Comptant',
      mode: ModeReglement.especes,
      statut: StatutVente.payee,
      montantPaye: p.prix * qte,
      panier: [
        LignePanier(
          produitId: p.id,
          nom: p.nom,
          montantGlobal: p.prix * qte,
          quantite: qte,
          stockDisponible: p.stock,
          prixIndicatif: p.prix,
          prixIndicatifMax: p.prixMax,
          espece: p.espece,
          unite: p.unite,
        ),
      ],
    );
    return r.vente.reference;
  }

  /// Vend puis facture : renvoie la référence de la facture.
  Future<String> facturer() async {
    final vente = await vendre();
    return (await factures.emettrePourVente(venteRef: vente)).reference;
  }

  Future<FactureRow> facture(String ref) =>
      (db.select(db.factures)..where((f) => f.ref.equals(ref))).getSingle();

  Future<List<FactureRow>> lesFactures() =>
      (db.select(db.factures)..orderBy([(f) => OrderingTerm.asc(f.ref)])).get();

  Future<void> fermer() async {
    bus.dispose();
    await db.close();
  }
}

/// Une facture telle que le serveur la sert (ou la reçoit).
Map<String, dynamic> uneFacture({
  required String ref,
  String? id,
  String type = 'FV',
  String statut = 'a_transmettre',
  String? updatedAt,
  String? venteRef,
  String? origineRef,
  String? code,
  String? nim,
  String? erreur,
  double ht = 10000,
  double taux = 18,
  List<Map<String, dynamic>>? lignes,
}) {
  final taxe = ht * taux / 100;
  final normalisee = statut == 'normalisee';
  return {
    'id': id ?? uuidDeterministe('facture-test:$ref'),
    'reference': ref,
    'type': type,
    'vente_ref': venteRef,
    'origine_ref': origineRef ?? (type == 'FA' ? 'FV-P9-2026-001' : null),
    'date_facture': '2026-11-01T08:00:00.000Z',
    'client': 'DOSSOU Félicité',
    'client_ifu': null,
    'client_adresse': null,
    'total_ht': ht,
    'total_taxe': taxe,
    'total_ttc': ht + taxe,
    'motif': type == 'FA' ? 'Erreur de facturation' : null,
    'statut': statut,
    'code_mecef': normalisee ? (code ?? 'CODE-A') : null,
    'nim': normalisee ? (nim ?? 'NIM-1') : null,
    'compteur': normalisee ? '12/50' : null,
    'lien_verification': normalisee ? 'https://dgi.example/v/1' : null,
    'date_normalisation': normalisee ? '2026-11-02T09:00:00.000Z' : null,
    'erreur_transmission': erreur,
    'updated_at': updatedAt ?? '2026-11-02T09:00:00.000000Z',
    'lignes':
        lignes ??
        [
          {
            'id': uuidDeterministe('ligne-test:$ref'),
            'designation': 'Goliath mature',
            'quantite': 1,
            'unite': 'u',
            'prix_unitaire_ht': ht,
            'groupe_taxe': 'B',
            'taux_taxe': taux,
            'montant_ht': ht,
            'montant_taxe': taxe,
          },
        ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
      await p.fermer();
    }
  });

  final annee = DateTime.now().year;

  group('numérotation à préfixe de poste (DV-21)', () {
    test(
      'poste appairé : FV-P2-AAAA-001, puis 002 ; l\'avoir a sa séquence',
      () async {
        final a = await poste('P2');
        final f1 = await a.facturer();
        final f2 = await a.facturer();
        final avoir = await a.factures.emettreAvoir(
          factureOrigine: f1,
          motif: 'Retour',
        );

        expect(f1, 'FV-P2-$annee-001');
        expect(f2, 'FV-P2-$annee-002');
        expect(avoir.reference, 'FA-P2-$annee-001');
      },
    );

    test('poste jamais appairé : ancien format FV-AAAA-001', () async {
      final a = await poste(null);
      expect(await a.facturer(), 'FV-$annee-001');
    });

    test('après 999 : le maximum est NUMÉRIQUE (1000 suit 999)', () async {
      final a = await poste('P2');
      await a.facturer();
      await a.db.customStatement(
        "UPDATE factures SET ref = 'FV-P2-$annee-999'",
      );
      expect(await a.facturer(), 'FV-P2-$annee-1000');
    });

    test(
      '999 et 1000 coexistent : le suivant est 1001, jamais un doublon',
      () async {
        final a = await poste('P2');
        await a.facturer();
        await a.facturer();
        await a.db.customStatement(
          "UPDATE factures SET ref = 'FV-P2-$annee-999' WHERE ref LIKE '%001'",
        );
        await a.db.customStatement(
          "UPDATE factures SET ref = 'FV-P2-$annee-1000' WHERE ref LIKE '%002'",
        );
        expect(await a.facturer(), 'FV-P2-$annee-1001');
      },
    );

    test('P1 et P12 ne se mélangent pas', () async {
      final a = await poste('P1');
      await a.facturer();
      await a.db.customStatement(
        "UPDATE factures SET ref = 'FV-P12-$annee-007'",
      );
      expect(await a.facturer(), 'FV-P1-$annee-001');
    });

    test(
      'une facture n\'est jamais renumérotée par la synchronisation',
      () async {
        final a = await poste('P2');
        final ref = await a.facturer();
        await a.moteur.synchroniser();
        expect((await a.lesFactures()).single.ref, ref);
        expect(serveur.factures.values.single['reference'], ref);
      },
    );
  });

  group('envoi', () {
    test('la facture part avec ses lignes imbriquées, à transmettre', () async {
      final a = await poste('P1');
      final ref = await a.facturer();

      final r = await a.moteur.synchroniser();

      expect(r.reussie, isTrue, reason: r.message);
      final f = serveur.factures.values.single;
      expect(f['reference'], ref);
      expect(f['statut'], 'a_transmettre');
      expect(f['lignes'] as List, hasLength(1));
      expect((await a.facture(ref)).syncStatus, 'synced');
    });

    test('AUCUN secret sur le fil : ni jeton, ni URL du service', () async {
      final a = await poste('P1');
      await a.db
          .update(a.db.parametresEntreprise)
          .write(
            const ParametresEntrepriseCompanion(
              mecefUrl: Value('https://mecef.dgi.example/secret-url'),
            ),
          );
      await a.depot.ecrire('1|jeton-secret');
      final ref = await a.facturer();
      await a.factures.normaliser(
        reference: ref,
        codeMecef: 'CODE-1',
        nim: 'NIM-1',
      );
      await a.moteur.synchroniser();

      final fil = jsonEncode(serveur.envois);
      expect(fil, isNot(contains('jeton-secret')));
      expect(fil, isNot(contains('secret-url')));
      for (final cle in ['jeton', 'token', 'mecef_url', 'url']) {
        expect((serveur.factures.values.single).keys, isNot(contains(cle)));
      }
      // Ce que la DGI a rendu, en revanche, voyage.
      expect(serveur.factures.values.single['code_mecef'], 'CODE-1');
    });

    test('la grille de taxation n\'est jamais envoyée (référentiel)', () async {
      final a = await poste('P1');
      await a.facturer();
      await a.moteur.synchroniser();
      for (final e in serveur.envois) {
        expect((e['tables'] as Map).keys, isNot(contains('groupes_taxe')));
      }
    });

    test(
      'normaliser remet la facture à envoyer ; le serveur la reçoit normalisée',
      () async {
        final a = await poste('P1');
        final ref = await a.facturer();
        await a.moteur.synchroniser();
        await a.factures.normaliser(
          reference: ref,
          codeMecef: 'CODE-1',
          nim: 'NIM-1',
          compteur: '1/9',
        );
        expect((await a.facture(ref)).syncStatus, 'pending');

        await a.moteur.synchroniser();

        final f = serveur.factures.values.single;
        expect(f['statut'], 'normalisee');
        expect(f['nim'], 'NIM-1');
        expect((await a.facture(ref)).syncStatus, 'synced');
      },
    );

    test(
      'un avoir part APRÈS sa facture, même si la facture est normalisée plus tard',
      () async {
        final a = await poste('P1');
        final ref = await a.facturer();
        await a.factures.emettreAvoir(factureOrigine: ref, motif: 'Retour');
        // La facture est normalisée APRÈS l'avoir : son instant de saisie est plus
        // récent. Triés par date, l'avoir partirait avant elle et serait refusé.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await a.factures.normaliser(
          reference: ref,
          codeMecef: 'CODE-1',
          nim: 'NIM-1',
        );

        final envoi = await a.tableFactures.aEnvoyer();
        expect(envoi.map((e) => e.corps['type']), ['FV', 'FA']);

        final r = await a.moteur.synchroniser();
        expect(r.refusees, 0, reason: r.message);
        expect(serveur.factures, hasLength(2));
      },
    );

    test(
      'rejeter puis normaliser : le serveur suit, sans jamais régresser',
      () async {
        final a = await poste('P1');
        final ref = await a.facturer();
        await a.factures.marquerRejetee(reference: ref, erreur: 'Réseau coupé');
        await a.moteur.synchroniser();
        expect(serveur.factures.values.single['statut'], 'rejetee');
        expect(
          serveur.factures.values.single['erreur_transmission'],
          'Réseau coupé',
        );

        await a.factures.normaliser(
          reference: ref,
          codeMecef: 'CODE-1',
          nim: 'NIM-1',
        );
        await a.moteur.synchroniser();
        expect(serveur.factures.values.single['statut'], 'normalisee');
        expect(
          serveur.factures.values.single['erreur_transmission'],
          isNull,
          reason: 'une facture normalisée n\'a plus d\'erreur de transmission',
        );
      },
    );

    test('rejouer l\'envoi ne duplique ni facture ni lignes', () async {
      final a = await poste('P1');
      final ref = await a.facturer();
      await a.moteur.synchroniser();
      await a.db
          .update(a.db.factures)
          .write(const FacturesCompanion(syncStatus: Value('pending')));

      final r = await a.moteur.synchroniser();

      expect(r.refusees, 0, reason: r.message);
      expect(serveur.factures, hasLength(1));
      expect((await a.facture(ref)).syncStatus, 'synced');
    });

    test(
      'refus du serveur : la facture devient conflit, avec le motif',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        // Les deux postes facturent la MÊME vente (la vente de A, absorbée par B).
        final vente = await a.vendre();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await a.factures.emettrePourVente(venteRef: vente);
        await b.factures.emettrePourVente(venteRef: vente);
        await a.moteur.synchroniser();

        final r = await b.moteur.synchroniser();

        expect(r.refusees, 1, reason: r.message);
        final f = (await b.lesFactures()).firstWhere((f) => f.origine == null);
        expect(f.syncStatus, 'conflict');
        expect(f.syncMotif, startsWith('Cette vente porte déjà la facture'));
      },
    );
  });

  group('deux postes', () {
    test(
      'B reçoit la facture de A avec ses lignes, SANS aucun effet de bord',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final ecrituresB =
            (await b.db.select(b.db.ecritureComptable).get()).length;
        final stockB = (await b.ventes.chargerCatalogue())
            .firstWhere((p) => p.nom == 'Goliath mature')
            .stock;
        final ref = await a.facturer();
        await a.moteur.synchroniser();

        final r = await b.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        final f = await b.facture(ref);
        expect(f.syncStatus, 'synced');
        expect(
          f.origine,
          isNotNull,
          reason: 'facture émise sur un autre poste',
        );
        expect(f.totalTtc, (await a.facture(ref)).totalTtc);
        expect(
          await (b.db.select(
            b.db.lignesFacture,
          )..where((l) => l.factureRef.equals(ref))).get(),
          hasLength(1),
        );
        expect(
          (await b.db.select(b.db.ecritureComptable).get()).length,
          ecrituresB,
          reason: 'aucune écriture comptable',
        );
        expect(
          (await b.ventes.chargerCatalogue())
              .firstWhere((p) => p.nom == 'Goliath mature')
              .stock,
          stockB,
          reason: 'le stock de B ne bouge pas',
        );
        // Rien n'est parti de B : la facture reste à son émetteur.
        expect(
          serveur.factures.values.single['device_id'],
          isNot(b.preferences.hashCode),
        );
        expect(await b.tableFactures.aEnvoyer(), isEmpty);
      },
    );

    test(
      'une facture normalisée est immuable : un second code est refusé',
      () async {
        final a = await poste('P1');
        final ref = await a.facturer();
        await a.factures.normaliser(
          reference: ref,
          codeMecef: 'CODE-1',
          nim: 'NIM-1',
        );

        await expectLater(
          a.factures.normaliser(
            reference: ref,
            codeMecef: 'CODE-2',
            nim: 'NIM-2',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('déjà normalisée'),
            ),
          ),
        );
        // Un rejet tardif ne la fait pas régresser non plus.
        await a.factures.marquerRejetee(reference: ref, erreur: 'Réseau coupé');
        final f = await a.facture(ref);
        expect(f.statut, 'normalisee');
        expect(f.codeMecef, 'CODE-1');
        expect(f.erreurTransmission, isNull);
      },
    );

    test(
      'la facture d\'un autre poste n\'est ni transmise ni normalisée ici',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final ref = await a.facturer();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        await expectLater(
          b.factures.normaliser(reference: ref, codeMecef: 'X', nim: 'Y'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('émise sur un autre poste'),
            ),
          ),
        );
        await expectLater(
          b.factures.marquerRejetee(reference: ref, erreur: 'x'),
          throwsA(isA<StateError>()),
        );
        expect((await b.facture(ref)).statut, 'a_transmettre');
      },
    );

    test(
      'l\'écran refuse de transmettre la facture d\'un autre poste',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final ref = await a.facturer();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        final vm = FacturesMecefViewModel(b.factures, b.db);
        await vm.charger();

        final r = await vm.transmettre(ref);

        expect(r, isA<Echec<void>>());
        expect(
          (r as Echec<void>).message,
          FacturesMecefViewModel.messageAutrePoste,
        );
        expect((await b.facture(ref)).statut, 'a_transmettre');
        final manuel = await vm.normaliserManuellement(
          reference: ref,
          codeMecef: 'X',
          nim: 'Y',
        );
        expect(manuel, isA<Echec<void>>());
      },
    );

    test(
      'la facture d\'un autre poste ne repart jamais, même marquée à envoyer',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.facturer();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await b.db
            .update(b.db.factures)
            .write(const FacturesCompanion(syncStatus: Value('pending')));

        expect(await b.tableFactures.aEnvoyer(), isEmpty);
      },
    );

    test(
      'A normalise : B reçoit la normalisation (le rang l\'emporte)',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final ref = await a.facturer();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await a.factures.normaliser(
          reference: ref,
          codeMecef: 'CODE-1',
          nim: 'NIM-1',
          compteur: '3/9',
          lienVerification: 'https://dgi.example/v/1',
        );
        await a.moteur.synchroniser();

        await b.moteur.synchroniser();

        final f = await b.facture(ref);
        expect(f.statut, 'normalisee');
        expect(f.codeMecef, 'CODE-1');
        expect(f.nim, 'NIM-1');
        expect(f.compteur, '3/9');
        expect(f.syncStatus, 'synced');
      },
    );

    test(
      'double normalisation : jamais départagée en silence, le serveur garde la première',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final ref = await a.facturer();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        // A normalise et envoie. B, hors ligne, a normalisé la même facture avec un
        // AUTRE code (base modifiée à la main : l'application le refuse).
        await a.factures.normaliser(
          reference: ref,
          codeMecef: 'CODE-A',
          nim: 'NIM-A',
        );
        await a.moteur.synchroniser();
        await b.db
            .update(b.db.factures)
            .write(
              FacturesCompanion(
                statut: const Value('normalisee'),
                codeMecef: const Value('CODE-B'),
                nim: const Value('NIM-B'),
                dateNormalisation: Value(DateTime.now()),
                syncStatus: const Value('pending'),
                updatedAt: Value(instantSaisie()),
                origine: const Value(null),
              ),
            );

        final r = await b.moteur.synchroniser();

        expect(r.refuseesALaReception, 1, reason: r.message);
        final f = await b.facture(ref);
        expect(f.codeMecef, 'CODE-B', reason: 'rien n\'est écrasé localement');
        expect(f.syncStatus, 'conflict');
        expect(f.syncMotif, contains('normalisée deux fois'));
        expect(
          serveur.factures.values.single['code_mecef'],
          'CODE-A',
          reason: 'le serveur garde la première normalisation reçue',
        );
      },
    );

    test(
      'le même conflit, quand c\'est le serveur qui refuse à l\'envoi',
      () async {
        final a = await poste('P1');
        final ref = await a.facturer();
        await a.moteur.synchroniser();
        // Le serveur a reçu entre-temps (d'un autre poste) une autre normalisation,
        // que ce poste n'a pas encore tirée.
        serveur.factures.values.single
          ..['statut'] = 'normalisee'
          ..['code_mecef'] = 'CODE-AUTRE'
          ..['nim'] = 'NIM-AUTRE';
        await a.factures.normaliser(
          reference: ref,
          codeMecef: 'CODE-A',
          nim: 'NIM-A',
        );

        final r = await a.moteur.synchroniser();

        expect(r.refusees, 1, reason: r.message);
        final f = await a.facture(ref);
        expect(f.syncStatus, 'conflict');
        expect(f.syncMotif, contains('déjà normalisée sous un autre code'));
        expect(f.codeMecef, 'CODE-A', reason: 'rien n\'est écrasé localement');
        expect(serveur.factures.values.single['code_mecef'], 'CODE-AUTRE');
      },
    );

    test(
      'règle du rang : normalisée du serveur contre rejet local non envoyé',
      () async {
        final a = await poste('P1');
        final ref = await a.facturer();
        await a.moteur.synchroniser();
        await a.factures.marquerRejetee(reference: ref, erreur: 'Réseau coupé');
        final locale = await a.facture(ref);

        final res = await a.tableFactures.absorber([
          // Le serveur est PLUS ANCIEN que la saisie locale : l'horloge perdrait.
          _depuis(
            locale,
            statut: 'normalisee',
            updatedAt: '2000-01-01T00:00:00.000000Z',
          ),
        ]);

        expect(res.absorbees, 1);
        expect(
          res.supplantees,
          1,
          reason: 'une saisie locale non envoyée remplacée',
        );
        final f = await a.facture(ref);
        expect(f.statut, 'normalisee');
        expect(f.codeMecef, 'X');
        expect(f.syncStatus, 'synced');
        expect(f.erreurTransmission, isNull);
      },
    );

    test(
      'règle du rang : normalisée locale non envoyée contre rejet du serveur',
      () async {
        final a = await poste('P1');
        final ref = await a.facturer();
        await a.moteur.synchroniser();
        await a.factures.normaliser(
          reference: ref,
          codeMecef: 'CODE-1',
          nim: 'NIM-1',
        );
        final locale = await a.facture(ref);

        final res = await a.tableFactures.absorber([
          _depuis(
            locale,
            statut: 'rejetee',
            updatedAt: '2999-01-01T00:00:00.000000Z',
          ),
        ]);

        expect(res.absorbees, 0);
        expect(
          res.conservees,
          1,
          reason: 'la saisie locale, plus avancée, partira',
        );
        final f = await a.facture(ref);
        expect(f.statut, 'normalisee', reason: 'un statut ne régresse jamais');
        expect(f.syncStatus, 'pending');
      },
    );

    test(
      'deux rejets : le plus récent gagne ; un rejet plus ancien est conservé',
      () async {
        final a = await poste('P1');
        final ref = await a.facturer();
        await a.moteur.synchroniser();
        await a.factures.marquerRejetee(reference: ref, erreur: 'Local');
        final locale = await a.facture(ref);

        var res = await a.tableFactures.absorber([
          _depuis(
            locale,
            statut: 'rejetee',
            erreur: 'Serveur ancien',
            updatedAt: '2000-01-01T00:00:00.000000Z',
          ),
        ]);
        expect(res.conservees, 1);
        expect((await a.facture(ref)).erreurTransmission, 'Local');

        res = await a.tableFactures.absorber([
          _depuis(
            locale,
            statut: 'rejetee',
            erreur: 'Serveur récent',
            updatedAt: '2999-01-01T00:00:00.000000Z',
          ),
        ]);
        expect(res.absorbees, 1);
        expect(res.supplantees, 1);
        expect((await a.facture(ref)).erreurTransmission, 'Serveur récent');
      },
    );

    test(
      'le contenu d\'une facture connue ne change jamais (statut seul repris)',
      () async {
        final a = await poste('P1');
        final ref = await a.facturer();
        await a.moteur.synchroniser();
        final locale = await a.facture(ref);

        final altere = _depuis(locale, statut: 'normalisee');
        altere['client'] = 'Quelqu\'un d\'autre'; // le contenu ne change pas
        altere['code_mecef'] = 'C';
        altere['nim'] = 'N';
        altere['date_normalisation'] = '2026-11-02T09:00:00.000Z';
        await a.tableFactures.absorber([altere]);

        final f = await a.facture(ref);
        expect(f.client, locale.client, reason: 'le contenu est immuable');
        expect(f.statut, 'normalisee');
      },
    );
  });

  group('absorbeur strict', () {
    Future<ResultatAbsorption> absorber(
      _Poste p,
      Map<String, dynamic> facture,
    ) => p.tableFactures.absorber([facture]);

    test(
      'une facture cohérente d\'un autre poste est absorbée, marquée de son origine',
      () async {
        final a = await poste('P1');
        final res = await absorber(
          a,
          uneFacture(ref: 'FV-P9-2026-001')..['device_id'] = 'poste-9',
        );
        expect(res.absorbees, 1);
        final f = await a.facture('FV-P9-2026-001');
        expect(f.origine, 'poste-9');
        expect(f.syncStatus, 'synced');
      },
    );

    for (final (nom, mutation)
        in <(String, void Function(Map<String, dynamic>))>[
          ('UUID invalide', (f) => f['id'] = 'pas-un-uuid'),
          ('référence invalide', (f) => f['reference'] = 'XX-1'),
          ('type et référence incohérents', (f) => f['type'] = 'FA'),
          ('client vide', (f) => f['client'] = ' '),
          ('statut inconnu', (f) => f['statut'] = 'payee'),
          ('total TTC faux', (f) => f['total_ttc'] = 1.0),
          ('lignes vides', (f) => f['lignes'] = <Object>[]),
          (
            'totaux qui ne sont pas ceux des lignes',
            (f) {
              f['total_ht'] = 12345.0;
              f['total_taxe'] = 0.0;
              f['total_ttc'] =
                  12345.0; // cohérent entre eux, faux vis-à-vis des lignes
            },
          ),
          (
            'normalisée sans code',
            (f) {
              f['statut'] = 'normalisee';
              f['nim'] = 'N';
              f['date_normalisation'] = '2026-11-02T09:00:00.000Z';
            },
          ),
          ('code sans normalisation', (f) => f['code_mecef'] = 'C'),
          (
            'avoir sans facture d\'origine',
            (f) {
              f['type'] = 'FA';
              f['reference'] = 'FA-P9-2026-001';
              f['motif'] = 'x';
              f['origine_ref'] = null;
            },
          ),
          (
            'avoir sans motif',
            (f) {
              f['type'] = 'FA';
              f['reference'] = 'FA-P9-2026-001';
              f['origine_ref'] = 'FV-P9-2026-001';
              f['motif'] = null;
            },
          ),
          (
            'facture de vente qui désigne une origine',
            (f) => f['origine_ref'] = 'FV-1-2026-001',
          ),
          (
            'groupe de taxe invalide',
            (f) => ((f['lignes'] as List).first as Map)['groupe_taxe'] = 'ab',
          ),
          (
            'quantité nulle',
            (f) => ((f['lignes'] as List).first as Map)['quantite'] = 0,
          ),
          (
            'taux hors limites',
            (f) => ((f['lignes'] as List).first as Map)['taux_taxe'] = 150,
          ),
        ]) {
      test('refusée : $nom', () async {
        final a = await poste('P1');
        final f = uneFacture(ref: 'FV-P9-2026-001');
        mutation(f);
        final res = await absorber(a, f);
        expect(res.refusees, 1);
        expect(res.absorbees, 0);
        expect(await a.lesFactures(), isEmpty);
      });
    }

    test(
      'une référence déjà prise par une AUTRE facture locale n\'est jamais écrasée',
      () async {
        final a = await poste('P1');
        final ref = await a.facturer();
        final res = await absorber(
          a,
          uneFacture(ref: ref, id: uuidDeterministe('autre')),
        );
        expect(res.refusees, 1);
        expect((await a.facture(ref)).origine, isNull);
      },
    );
  });

  group('remise à zéro du serveur', () {
    test(
      'les factures non normalisées partent ; la normalisée est conservée et repart',
      () async {
        final a = await poste('P1');
        final f1 = await a.facturer();
        final f2 = await a.facturer();
        await a.factures.normaliser(
          reference: f1,
          codeMecef: 'CODE-1',
          nim: 'NIM-1',
        );
        await a.moteur.synchroniser();
        // Une facture non envoyée.
        await a.facturer();
        serveur.remettreAZero();

        final r = await a.moteur.synchroniser();

        expect(r.remiseAZero, isTrue);
        expect(r.saisiesPerdues, greaterThanOrEqualTo(1));
        final restantes = await a.lesFactures();
        expect(restantes.map((f) => f.ref), [
          f1,
        ], reason: 'pièce fiscale conservée');
        expect(f2, isNotEmpty);
        expect(
          await a.db.select(a.db.lignesFacture).get(),
          hasLength(1),
          reason: 'les lignes des factures purgées partent avec elles',
        );
        expect(serveur.factures.values.map((f) => f['reference']), [
          f1,
        ], reason: 'et le serveur remis à zéro la reçoit de nouveau');
      },
    );
  });

  group('groupes de taxe (référentiel)', () {
    test('créé s\'il manque ; le poste ne l\'envoie jamais', () async {
      final a = await poste('P1');
      final res = await a.moteur.tables
          .whereType<TableGroupesTaxePoste>()
          .single
          .absorber([
            {
              'id': uuidDeterministe('groupe_taxe:C'),
              'code': 'C',
              'libelle': 'Taux réduit',
              'taux': 9,
              'ordre': 3,
              'created_at': '2026-11-01T00:00:00.000000Z',
              'updated_at': '2026-11-01T00:00:00.000000Z',
            },
          ]);
      expect(res.absorbees, 1);
      expect((await a.factures.groupesTaxe()).map((g) => g.code), [
        'A',
        'B',
        'C',
      ]);
    });

    test(
      'valeur de semis : n\'écrase jamais une grille corrigée à la main',
      () async {
        final a = await poste('P1');
        await (a.db.update(a.db.groupesTaxe)..where((g) => g.code.equals('B')))
            .write(const GroupesTaxeCompanion(taux: Value(19)));
        final table = TableGroupesTaxePoste(a.db);

        await table.absorber([
          _groupe('B', 'Taux normal 18 %', 18, decide: false),
        ]);

        final b = (await a.factures.groupesTaxe()).firstWhere(
          (g) => g.code == 'B',
        );
        expect(
          b.taux,
          19,
          reason: 'le semis du serveur n\'est pas une décision',
        );
      },
    );

    test('décidé par le serveur : le serveur gagne', () async {
      final a = await poste('P1');
      final table = TableGroupesTaxePoste(a.db);

      final res = await table.absorber([
        _groupe('B', 'Taux normal 18 %', 18.5, decide: true),
      ]);

      expect(res.absorbees, 1);
      final b = (await a.factures.groupesTaxe()).firstWhere(
        (g) => g.code == 'B',
      );
      expect(b.taux, 18.5);
    });

    test(
      'jamais supprimé, jamais lissé : une ligne incohérente est refusée',
      () async {
        final a = await poste('P1');
        final table = TableGroupesTaxePoste(a.db);
        for (final l in [
          _groupe('b', 'Minuscule', 5),
          _groupe('Z', ' ', 5),
          _groupe('Z', 'Taux négatif', -1),
          _groupe('Z', 'Taux énorme', 101),
          _groupe('Z', 'Mauvais id', 5, id: uuidDeterministe('autre')),
        ]) {
          final res = await table.absorber([l]);
          expect(res.refusees, 1, reason: '${l['libelle']}');
        }
        expect((await a.factures.groupesTaxe()).map((g) => g.code), ['A', 'B']);
        expect(await table.purger(), 0);
      },
    );

    test('l\'UUID déterministe du groupe est celui que calcule le serveur', () {
      // Valeurs figées : le test PHP vérifie les mêmes (`GroupesTaxeTest`).
      expect(uuidDeterministe('groupe_taxe:A'), _idGroupeA);
      expect(uuidDeterministe('groupe_taxe:B'), _idGroupeB);
    });

    test('de bout en bout : le tirage reçoit la grille du serveur', () async {
      final a = await poste('P1');
      serveur.ajouterGroupeTaxe(
        'C',
        'Taux réduit',
        9,
        ordre: 3,
        id: uuidDeterministe('groupe_taxe:C'),
      );
      final r = await a.moteur.synchroniser();
      expect(r.reussie, isTrue, reason: r.message);
      expect(
        (await a.factures.groupesTaxe()).map((g) => g.code),
        contains('C'),
      );
    });
  });

  group('tirage des factures d\'un autre poste', () {
    test(
      'le tirage complet apporte factures et lignes, normalisées ou non',
      () async {
        final a = await poste('P1');
        serveur.ajouterFacture(uneFacture(ref: 'FV-P9-2026-001'));
        serveur.ajouterFacture(
          uneFacture(ref: 'FV-P9-2026-002', statut: 'normalisee'),
        );

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(await a.lesFactures(), hasLength(2));
        expect(await a.db.select(a.db.lignesFacture).get(), hasLength(2));
        final n = await a.facture('FV-P9-2026-002');
        expect(n.statut, 'normalisee');
        expect(n.codeMecef, 'CODE-A');
        expect(n.origine, 'autre-poste');
      },
    );

    test('un tirage rejoué n\'ajoute ni facture ni ligne', () async {
      final a = await poste('P1');
      serveur.ajouterFacture(uneFacture(ref: 'FV-P9-2026-001'));
      await a.moteur.synchroniser();
      await a.preferences.definirCurseurTirage(null);

      await a.moteur.synchroniser();

      expect(await a.lesFactures(), hasLength(1));
      expect(await a.db.select(a.db.lignesFacture).get(), hasLength(1));
    });
  });
}

const _idGroupeA = 'cc7f16d2-cdc8-5c30-8f4b-d53be458e98c';
const _idGroupeB = 'fd27a3e2-e56c-50d9-8212-1525b58e06cf';

Map<String, dynamic> _groupe(
  String code,
  String libelle,
  double taux, {
  bool decide = true,
  String? id,
}) => {
  'id': id ?? uuidDeterministe('groupe_taxe:$code'),
  'code': code,
  'libelle': libelle,
  'taux': taux,
  'ordre': 2,
  'created_at': '2026-11-01T00:00:00.000000Z',
  'updated_at': decide
      ? '2026-11-05T00:00:00.000000Z'
      : '2026-11-01T00:00:00.000000Z',
};

/// La facture locale telle que le serveur la renverrait, avec un autre statut.
Map<String, dynamic> _depuis(
  FactureRow l, {
  required String statut,
  String? erreur,
  String updatedAt = '2999-01-01T00:00:00.000000Z',
}) {
  final normalisee = statut == 'normalisee';
  return {
    'id': l.id,
    'reference': l.ref,
    'type': l.type,
    'vente_ref': l.venteRef,
    'origine_ref': l.origineRef,
    'date_facture': l.dateFacture.toUtc().toIso8601String(),
    'client': l.client,
    'total_ht': l.totalHt,
    'total_taxe': l.totalTaxe,
    'total_ttc': l.totalTtc,
    'statut': statut,
    'code_mecef': normalisee ? 'X' : null,
    'nim': normalisee ? 'Y' : null,
    'date_normalisation': normalisee ? '2026-11-02T09:00:00.000Z' : null,
    'erreur_transmission': erreur,
    'updated_at': updatedAt,
    'lignes': [
      {
        'id': uuidDeterministe('ligne-${l.ref}'),
        'designation': 'x',
        'quantite': 1,
        'prix_unitaire_ht': l.totalHt,
        'groupe_taxe': 'A',
        'taux_taxe': 0,
        'montant_ht': l.totalHt,
        'montant_taxe': l.totalTaxe,
      },
    ],
  };
}
