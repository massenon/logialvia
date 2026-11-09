import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/comptabilite/data/seed/plan_comptable_seeder.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_clotures_poste.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_ecritures_poste.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_exercices_poste.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_notes_annexes_poste.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_plan_comptable_poste.dart';
import 'package:logialvia_app/comptabilite/domain/entities/comptabilite.dart';
import 'package:logialvia_app/comptabilite/presentation/viewmodels/comptabilite_view_model.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_produits_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_ventes_poste.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import '../core/sync/faux_serveur_sync.dart';

/// P8 — la comptabilité entre deux postes, contre un faux serveur qui rejoue les règles
/// du vrai (`EcrituresTable`, clôtures). Les écritures sont des FAITS IMMUABLES : ils
/// circulent avec leur origine, sans jamais engendrer d'écriture locale.
final int annee = DateTime.now().year;
DateTime jour([int mois = 6, int j = 15]) => DateTime(annee, mois, j, 10);

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
      socleDuPlan: {
        for (final c in PlanComptableSeeder.tous)
          c.numero: (libelle: c.libelle, classe: c.classe),
      },
      tables: [
        TableProduitsPoste(db),
        TableClientsPoste(db),
        TableVentesPoste(db),
        TablePlanComptablePoste(db),
        TableExercicesPoste(db),
        TableEcrituresPoste(db),
        TableNotesAnnexesPoste(db),
        TableCloturesPeriodiquesPoste(db),
        TableCloturesExercicePoste(db),
      ],
      client: serveur.client,
    );
    bus = EventBus();
    ventes = VentesRepositoryDrift(db, bus);
    compta = ComptabiliteRepositoryDrift(db);
    vm = ComptabiliteViewModel(compta);
  }

  final FauxServeurSync serveur;
  final String? code;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final EventBus bus;
  late final VentesRepositoryDrift ventes;
  late final ComptabiliteRepositoryDrift compta;
  late final ComptabiliteViewModel vm;

  Future<void> demarrer() async {
    await SeedInitial(db).executer();
    await preferences.definirAdresseServeur('http://serveur.test');
    if (code != null) {
      await preferences.memoriserAppairage(
        codePoste: code!,
        compte: 'g',
        le: DateTime.now(),
      );
    } else {
      // Poste jamais appairé : un jeton suffit pour synchroniser, mais pas de code.
      await preferences.memoriserAppairage(
        codePoste: 'P0',
        compte: 'g',
        le: DateTime.now(),
      );
      await (db.delete(
        db.preferencesPoste,
      )..where((p) => p.cle.equals('poste.code_attribue'))).go();
    }
    await depot.ecrire('1|jeton');
    await vm.charger();
  }

  Future<String> identifiant() => preferences.identifiantPoste();

  Future<void> depense(
    double montant, {
    DateTime? date,
    String compteCharge = '624',
    String tresorerie = '531',
    String? numero,
  }) async {
    final piece = numero ?? vm.prochainNumeroPiece('DEP');
    final r = await vm.enregistrerPiece(
      date: date ?? jour(),
      journalCode: 'CA',
      numeroPiece: piece,
      lignes: [
        LigneAEcrire(
          numeroCompte: compteCharge,
          debit: montant,
          credit: 0,
          libelle: 'Transport',
        ),
        LigneAEcrire(
          numeroCompte: tresorerie,
          debit: 0,
          credit: montant,
          libelle: 'Transport',
        ),
      ],
    );
    expect(r, isA<Succes<void>>(), reason: '$r');
    await vm.charger();
  }

  Future<List<EcritureRow>> lignes() => (db.select(
    db.ecritureComptable,
  )..orderBy([(e) => OrderingTerm.asc(e.updatedAt)])).get();

  Future<List<EcritureRow>> propres() =>
      (db.select(db.ecritureComptable)..where((e) => e.origine.isNull())).get();

  Future<String> vendre(String nomProduit, {double qte = 1}) async {
    final p = (await ventes.chargerCatalogue()).firstWhere(
      (p) => p.nom == nomProduit,
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

  /// Totaux de la balance, tous faits confondus (le grand livre du poste).
  Future<({double debit, double credit})> totaux() async {
    await vm.charger();
    return (debit: vm.balanceTotalDebit, credit: vm.balanceTotalCredit);
  }

  Future<ExerciceRow> exercice(int a) => (db.select(
    db.exerciceComptable,
  )..where((e) => e.annee.equals(a))).getSingle();

  Future<void> fermer() async {
    bus.dispose();
    await db.close();
  }
}

Map<String, dynamic> _ligne(
  String compte,
  double debit,
  double credit, {
  String? axe,
}) => {
  'id': nouvelUuid(),
  'numero_compte': compte,
  'debit': debit,
  'credit': credit,
  'libelle': 'Fait venu du serveur',
  'axe_analytique': axe,
};

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
    // Le serveur est semé à l'identique des postes (même programme).
    for (final c in PlanComptableSeeder.tous) {
      serveur.ajouterCompte(c.numero, c.libelle, c.classe);
    }
    serveur.ajouterExercice(annee);
    postes.clear();
  });

  tearDown(() async {
    for (final p in postes) {
      await p.fermer();
    }
  });

  // ------------------------------------------------------------------- plan
  group('plan comptable : référentiel, le serveur gagne, le poste propose', () {
    test(
      'un compte créé au poste est PROPOSÉ (jamais envoyé comme un fait) puis connu des autres',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.vm.creerCompte(
          numero: '635',
          libelle: 'Frais bancaires',
          classe: '6',
        );

        final r = await a.moteur.synchroniser();
        expect(r.reussie, isTrue, reason: r.message);
        expect(r.demandesAcceptees, greaterThanOrEqualTo(1));
        expect(serveur.comptes.containsKey('635'), isTrue);
        expect(
          serveur.envois.expand((e) => (e['tables'] as Map).keys),
          isNot(contains('plan_comptable')),
          reason: 'un référentiel ne part jamais comme un fait',
        );

        await b.moteur.synchroniser();
        await b.vm.charger();
        expect(b.vm.plan.map((c) => c.numero), contains('635'));
      },
    );

    test(
      'la valeur de semis du serveur n\'écrase pas le poste ; une décision du serveur, si',
      () async {
        final a = await poste('P1');
        await a.vm.modifierCompte(
          numero: '624',
          libelle: 'Transports (renommé)',
          classe: '6',
        );
        // Aucune demande n'est partie : le poste n'a pas encore synchronisé, et le
        // serveur n'a jamais décidé 624 (semis). L'adoption initiale n'est pas
        // l'objet de ce test : on la tient pour faite.
        await (a.db.delete(a.db.demandesReferentiel)).go();
        await a.preferences.definirPlanAdopte();
        await a.moteur.synchroniser(complet: true);
        await a.vm.charger();
        expect(
          a.vm.plan.firstWhere((c) => c.numero == '624').libelle,
          'Transports (renommé)',
        );

        // Le serveur DÉCIDE : cette fois le poste obéit.
        serveur.ajouterCompte(
          '624',
          'Transports et déplacements',
          '6',
          decide: true,
        );
        await a.moteur.synchroniser(complet: true);
        await a.vm.charger();
        expect(
          a.vm.plan.firstWhere((c) => c.numero == '624').libelle,
          'Transports et déplacements',
        );
      },
    );

    test(
      'une saisie locale plus récente que la décision du serveur est conservée et part',
      () async {
        final a = await poste('P1');
        serveur.ajouterCompte(
          '624',
          'Décision ancienne',
          '6',
          decide: true,
          saisiLe: DateTime.now()
              .subtract(const Duration(days: 2))
              .toUtc()
              .toIso8601String(),
        );
        await a.vm.modifierCompte(
          numero: '624',
          libelle: 'Ma saisie récente',
          classe: '6',
        );

        final r = await a.moteur.synchroniser(complet: true);

        expect(r.conserveesLocalement, 1);
        expect(serveur.comptes['624']!['libelle'], 'Ma saisie récente');
      },
    );

    test(
      'un compte incohérent venu du serveur est refusé et compté, jamais lissé',
      () async {
        final a = await poste('P1');
        serveur.comptes['999'] = {
          'numero_compte': '999',
          'libelle': 'Hors plan',
          'classe': '9',
          'archive': false,
          'saisi_le': null,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-02-01T00:00:00Z',
        };
        serveur.comptes['6x1'] = {
          'numero_compte': '6x1',
          'libelle': 'Lettre',
          'classe': '6',
          'archive': false,
          'saisi_le': null,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-02-01T00:00:00Z',
        };
        serveur.comptes['651'] = {
          'numero_compte': '651',
          'libelle': 'Mauvaise classe',
          'classe': '7',
          'archive': false,
          'saisi_le': null,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-02-01T00:00:00Z',
        };

        final r = await a.moteur.synchroniser();

        expect(r.refuseesALaReception, 3);
        await a.vm.charger();
        expect(a.vm.plan.map((c) => c.numero), isNot(contains('999')));
        expect(a.vm.plan.map((c) => c.numero), isNot(contains('651')));
      },
    );

    test(
      'le socle semé n\'est jamais reproposé ; seul ce que le poste a ajouté l\'est, une fois',
      () async {
        final a = await poste('P1');
        await a.vm.creerCompte(
          numero: '635',
          libelle: 'Frais bancaires',
          classe: '6',
        );
        await (a.db.delete(
          a.db.demandesReferentiel,
        )).go(); // l'adoption seule parle
        await a.moteur.synchroniser();
        final cles = serveur.demandesRecues
            .where((d) => d['type'] == 'compte_comptable')
            .map((d) => (d['donnees'] as Map)['numero_compte'])
            .toList();
        expect(cles, ['635']);

        serveur.demandesRecues.clear();
        await a.moteur.synchroniser();
        expect(
          serveur.demandesRecues.where((d) => d['type'] == 'compte_comptable'),
          isEmpty,
        );
      },
    );
  });

  // -------------------------------------------------------------- écritures
  group('écritures : faits immuables, une pièce voyage entière', () {
    test(
      'la pièce part avec ses lignes et son piece_id, puis devient synced',
      () async {
        final a = await poste('P1');
        await a.depense(3500);

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(serveur.pieces, hasLength(1));
        final piece = serveur.pieces.values.single;
        expect(piece['numero_piece'], 'DEP-P1-$annee-0001');
        expect(piece['journal_code'], 'CA');
        expect((piece['lignes'] as List), hasLength(2));
        final lignes = await a.lignes();
        expect(lignes.map((l) => l.pieceId).toSet(), {piece['id']});
        expect(lignes.every((l) => l.syncStatus == 'synced'), isTrue);
        expect(piece['device_id'], await a.identifiant());
      },
    );

    test(
      'la pièce d\'un poste arrive chez l\'autre avec son origine, sans rien générer',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.depense(3500);
        await a.moteur.synchroniser();

        final r = await b.moteur.synchroniser();

        expect(r.recues, greaterThanOrEqualTo(1));
        final chezB = await b.lignes();
        expect(
          chezB,
          hasLength(2),
          reason: 'exactement les 2 lignes de A, rien de plus',
        );
        for (final l in chezB) {
          expect(l.origine, await a.identifiant());
          expect(l.syncStatus, 'synced');
        }
        expect(await b.propres(), isEmpty);
        // Elle compte au grand livre de B.
        final t = await b.totaux();
        expect(t.debit, 3500);
        expect(t.credit, 3500);
      },
    );

    test(
      'une vente d\'un autre poste n\'engendre AUCUNE écriture locale : sa propre écriture arrive comme un fait',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.vendre('Goliath mature'); // génère l'écriture de A
        await a.moteur.synchroniser();

        await b.moteur.synchroniser();

        expect(
          (await b.db.select(b.db.ventes).get()).length,
          1,
          reason: 'B connaît la vente de A',
        );
        final chezB = await b.lignes();
        expect(chezB.every((l) => l.origine != null), isTrue);
        expect(
          chezB.length,
          (await a.lignes()).length,
          reason: 'ni trou ni doublon',
        );
      },
    );

    test(
      'grand livre de chaque poste = TOUS les faits : A et B vendent hors ligne, se synchronisent dans le désordre, mêmes totaux',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.vendre('Goliath mature');
        await b.vendre('Goliath mature', qte: 2);
        await b.depense(1000);

        await b.moteur.synchroniser();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await a.moteur.synchroniser();

        final ta = await a.totaux();
        final tb = await b.totaux();
        expect(ta.debit, tb.debit);
        expect(ta.credit, tb.credit);
        expect(ta.debit, ta.credit);
        expect((await a.lignes()).length, (await b.lignes()).length);
        expect(
          (await a.lignes()).map((l) => l.id).toSet(),
          (await b.lignes()).map((l) => l.id).toSet(),
        );
        // Le résultat net est le même des deux côtés (BR-CPT-005).
        expect(a.vm.resultatNet, b.vm.resultatNet);
        expect(serveur.pieces, hasLength(3));
      },
    );

    test('rejouer un tirage ne double rien (idempotent par UUID)', () async {
      final a = await poste('P1');
      final b = await poste('P2');
      await a.depense(700);
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();

      await b.moteur.synchroniser(complet: true);
      await b.moteur.synchroniser(complet: true);

      expect(await b.lignes(), hasLength(2));
    });

    test(
      'un renvoi du lot déjà reçu est accepté sans rien changer au serveur',
      () async {
        final a = await poste('P1');
        await a.depense(700);
        await a.moteur.synchroniser();
        final avant = Map<String, dynamic>.from(serveur.pieces.values.single);

        // Le poste croit n'avoir rien envoyé (accusé perdu).
        await (a.db.update(a.db.ecritureComptable)).write(
          const EcritureComptableCompanion(syncStatus: Value('pending')),
        );
        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue);
        expect(serveur.pieces, hasLength(1));
        expect(
          serveur.pieces.values.single['serveur_modifie_le'],
          avant['serveur_modifie_le'],
        );
        expect(
          (await a.lignes()).every((l) => l.syncStatus == 'synced'),
          isTrue,
        );
      },
    );

    test(
      'absorbeur strict : pièce déséquilibrée, compte ou exercice inconnu, ligne seule : refusées et comptées',
      () async {
        final a = await poste('P1');
        final base = {
          'device_id': 'autre-poste',
          'numero_piece': 'OD-P2-$annee-0001',
          'date_ecriture': jour().toUtc().toIso8601String(),
          'exercice_annee': annee,
          'journal_code': 'OD',
          'vente_ref': null,
          'achat_ref': null,
          'contrepasse_de': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'serveur_modifie_le': DateTime.now().toUtc().toIso8601String(),
        };
        void poser(String suffixe, Map<String, dynamic> surcharge) {
          final id = nouvelUuid();
          serveur.pieces[id] = {...base, 'id': id, ...surcharge};
        }

        poser('desequilibree', {
          'lignes': [_ligne('531', 100, 0), _ligne('701', 0, 90)],
        });
        poser('compte', {
          'lignes': [_ligne('531', 100, 0), _ligne('9999', 0, 100)],
        });
        poser('exercice', {
          'exercice_annee': annee - 5,
          'lignes': [_ligne('531', 100, 0), _ligne('701', 0, 100)],
        });
        poser('seule', {
          'lignes': [_ligne('531', 100, 0)],
        });
        poser('deux-sens', {
          'lignes': [_ligne('531', 100, 100), _ligne('701', 0, 0)],
        });
        poser('bonne', {
          'lignes': [_ligne('531', 100, 0), _ligne('701', 0, 100)],
        });

        final r = await a.moteur.synchroniser();

        expect(r.refuseesALaReception, 5);
        expect(
          await a.lignes(),
          hasLength(2),
          reason: 'seule la bonne pièce est entrée',
        );
      },
    );

    test(
      'un refus du serveur reste visible avec son motif, sans quitter les livres du poste',
      () async {
        final a = await poste('P1');
        await a.depense(400);
        serveur.exercices[annee]!['is_cloture'] =
            true; // clos entre-temps, côté serveur

        final r = await a.moteur.synchroniser();

        expect(r.refusees, 1);
        final lignes = await a.lignes();
        expect(lignes.every((l) => l.syncStatus == 'conflict'), isTrue);
        expect(lignes.first.syncMotif, contains('clôturé'));
        await a.vm.charger();
        expect(a.vm.ecrituresRefusees, hasLength(2));
        final t = await a.totaux();
        expect(
          t.debit,
          400,
          reason: 'la pièce refusée reste dans les livres de ce poste',
        );
        expect(serveur.pieces, isEmpty);
      },
    );

    test(
      'une pièce refusée se corrige : même identité, repart à envoyer, motif effacé',
      () async {
        final a = await poste('P1');
        await a.depense(400);
        final piece = (await a.lignes()).first;
        serveur.exercices[annee]!['is_cloture'] = true;
        await a.moteur.synchroniser();
        serveur.exercices[annee]!['is_cloture'] = false;
        await a.vm.charger();

        final r = await a.vm.remplacerPiece(
          numeroPiece: piece.numeroPiece!,
          date: jour(),
          journalCode: 'CA',
          lignes: const [
            LigneAEcrire(
              numeroCompte: '624',
              debit: 450,
              credit: 0,
              libelle: 'Transport corrigé',
            ),
            LigneAEcrire(
              numeroCompte: '531',
              debit: 0,
              credit: 450,
              libelle: 'Transport corrigé',
            ),
          ],
        );
        expect(r, isA<Succes<void>>(), reason: '$r');
        final apres = await a.lignes();
        expect(apres.map((l) => l.pieceId).toSet(), {piece.pieceId});
        expect(
          apres.every((l) => l.syncStatus == 'pending' && l.syncMotif == null),
          isTrue,
        );

        await a.moteur.synchroniser();
        expect(serveur.pieces[piece.pieceId], isNotNull);
      },
    );

    test(
      'numéro de pièce : préfixe de poste (DV-21), séquence continue, jamais renumérotée',
      () async {
        final a = await poste('P2');
        expect(a.vm.prochainNumeroPiece('OD'), 'OD-P2-$annee-0001');
        await a.depense(100);
        await a.depense(200);
        expect((await a.lignes()).map((l) => l.numeroPiece).toSet(), {
          'DEP-P2-$annee-0001',
          'DEP-P2-$annee-0002',
        });
        expect(a.vm.prochainNumeroPiece('DEP'), 'DEP-P2-$annee-0003');

        // Modifier une pièce non transmise garde son numéro.
        await a.vm.remplacerPiece(
          numeroPiece: 'DEP-P2-$annee-0001',
          date: jour(),
          journalCode: 'CA',
          lignes: const [
            LigneAEcrire(
              numeroCompte: '624',
              debit: 150,
              credit: 0,
              libelle: 'x',
            ),
            LigneAEcrire(
              numeroCompte: '531',
              debit: 0,
              credit: 150,
              libelle: 'x',
            ),
          ],
        );
        expect(
          (await a.lignes()).map((l) => l.numeroPiece),
          contains('DEP-P2-$annee-0001'),
        );
      },
    );

    test('un poste jamais appairé garde l\'ancien format sans code', () async {
      final seul = await poste(null);
      expect(seul.vm.prochainNumeroPiece('OD'), 'OD-$annee-0001');
    });

    test('les numéros de deux postes ne se rencontrent jamais', () async {
      final a = await poste('P1');
      final b = await poste('P2');
      await a.depense(10);
      await b.depense(10);
      expect({
        a.vm.prochainNumeroPiece('DEP'),
        b.vm.prochainNumeroPiece('DEP'),
      }, hasLength(2));
    });
  });

  // ------------------------------------------------------------ immutabilité
  group('un fait transmis ne se modifie ni ne se supprime : il s\'annule', () {
    test('modifier une pièce transmise est refusé avec un motif', () async {
      final a = await poste('P1');
      await a.depense(900);
      await a.moteur.synchroniser();
      await a.vm.charger();
      final numero = (await a.lignes()).first.numeroPiece!;

      final r = await a.vm.remplacerPiece(
        numeroPiece: numero,
        date: jour(),
        journalCode: 'CA',
        lignes: const [
          LigneAEcrire(numeroCompte: '624', debit: 1, credit: 0, libelle: 'x'),
          LigneAEcrire(numeroCompte: '531', debit: 0, credit: 1, libelle: 'x'),
        ],
      );

      expect(r, isA<Echec<void>>());
      expect((r as Echec<void>).message, contains('déjà été transmise'));
      expect(await a.lignes(), hasLength(2));
    });

    test(
      'supprimer une pièce transmise la CONTREPASSE : trace conservée, résultat annulé',
      () async {
        final a = await poste('P1');
        await a.depense(900);
        await a.moteur.synchroniser();
        await a.vm.charger();
        final originale = (await a.lignes()).first;
        expect(a.vm.depenses, hasLength(1));

        final r = await a.vm.supprimerPiece(originale.numeroPiece!);

        expect(r, isA<Succes<void>>(), reason: '$r');
        final toutes = await a.lignes();
        expect(toutes, hasLength(4), reason: 'rien n\'est effacé');
        final inverses = toutes.where(
          (l) => l.contrepasseDe == originale.pieceId,
        );
        expect(inverses, hasLength(2));
        expect(
          inverses.every(
            (l) => l.numeroPiece == 'ANN-${originale.numeroPiece}',
          ),
          isTrue,
        );
        expect(inverses.every((l) => l.journalCode == 'OD'), isTrue);
        final charge = inverses.firstWhere((l) => l.numeroCompte == '624');
        expect(charge.credit, 900);
        expect(charge.debit, 0);
        await a.vm.charger();
        expect(
          a.vm.depenses,
          isEmpty,
          reason: 'la dépense annulée sort de la liste',
        );
        expect(a.vm.resultatNet, 0);

        await a.moteur.synchroniser();
        expect(serveur.pieces, hasLength(2));
        expect(
          serveur.pieces.values.where(
            (p) => p['contrepasse_de'] == originale.pieceId,
          ),
          hasLength(1),
        );
      },
    );

    test('annuler deux fois, ou annuler une annulation, est refusé', () async {
      final a = await poste('P1');
      await a.depense(900);
      await a.moteur.synchroniser();
      await a.vm.charger();
      final numero = (await a.lignes()).first.numeroPiece!;
      await a.vm.supprimerPiece(numero);

      final deux = await a.vm.supprimerPiece(numero);
      expect(deux, isA<Echec<void>>());
      expect((deux as Echec<void>).message, contains('déjà annulée'));

      await a.moteur.synchroniser();
      await a.vm.charger();
      final annulation = await a.vm.supprimerPiece('ANN-$numero');
      expect(annulation, isA<Echec<void>>());
      expect((annulation as Echec<void>).message, contains('ne s\'annule pas'));
    });

    test('une pièce NON transmise se supprime vraiment', () async {
      final a = await poste('P1');
      await a.depense(900);
      await a.vm.charger();
      final numero = (await a.lignes()).first.numeroPiece!;

      expect(await a.vm.supprimerPiece(numero), isA<Succes<void>>());

      expect(await a.lignes(), isEmpty);
    });

    test(
      'la pièce d\'un autre poste ne se modifie ni ne se supprime ici',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.depense(900);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await b.vm.charger();
        final numero = (await b.lignes()).first.numeroPiece!;

        final suppr = await b.vm.supprimerPiece(numero);
        final modif = await b.vm.remplacerPiece(
          numeroPiece: numero,
          date: jour(),
          journalCode: 'CA',
          lignes: const [
            LigneAEcrire(
              numeroCompte: '624',
              debit: 1,
              credit: 0,
              libelle: 'x',
            ),
            LigneAEcrire(
              numeroCompte: '531',
              debit: 0,
              credit: 1,
              libelle: 'x',
            ),
          ],
        );

        expect(suppr, isA<Echec<void>>());
        expect(modif, isA<Echec<void>>());
        expect((suppr as Echec<void>).message, contains('autre poste'));
        expect(await b.lignes(), hasLength(2));
      },
    );

    test(
      'la contrepassation d\'un poste arrive chez l\'autre et annule la dépense des deux côtés',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.depense(900);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await a.vm.charger();
        await a.vm.supprimerPiece((await a.lignes()).first.numeroPiece!);
        await a.moteur.synchroniser();

        await b.moteur.synchroniser();
        await b.vm.charger();

        expect(await b.lignes(), hasLength(4));
        expect(b.vm.depenses, isEmpty);
        expect(b.vm.resultatNet, 0);
      },
    );
  });

  // ------------------------------------------------------------ clôtures
  group('clôture mensuelle : dernier écrivain gagne, verrou partout', () {
    test(
      'un mois clôturé au poste A verrouille l\'écriture sur B après synchronisation',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.vm.cloturerMois(3);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await b.vm.charger();

        final r = await b.vm.enregistrerPiece(
          date: jour(3, 10),
          journalCode: 'OD',
          numeroPiece: 'OD-P2-$annee-0001',
          lignes: const [
            LigneAEcrire(
              numeroCompte: '624',
              debit: 5,
              credit: 0,
              libelle: 'x',
            ),
            LigneAEcrire(
              numeroCompte: '531',
              debit: 0,
              credit: 5,
              libelle: 'x',
            ),
          ],
        );

        expect(r, isA<Echec<void>>());
        expect((r as Echec<void>).message, contains('clôturé'));
      },
    );

    test('la déclôture (la plus récente) l\'emporte partout', () async {
      final a = await poste('P1');
      final b = await poste('P2');
      await a.vm.cloturerMois(3);
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b.vm.charger();
      final de = await b.vm.decloturerMois(
        mois: 3,
        roleId: 'admin',
        utilisateurId: 'u1',
      );
      expect(de, isA<Succes<void>>());
      await b.moteur.synchroniser();

      await a.moteur.synchroniser();
      await a.vm.charger();

      expect(a.vm.cloturesMois[3], isFalse);
    });

    test(
      'une clôture locale plus récente que celle du serveur est conservée et part ; une plus ancienne est supplantée',
      () async {
        final a = await poste('P1');
        // Le serveur a une DÉCLÔTURE ancienne de mars (il y a 2 jours).
        final id = TableCloturesPeriodiquesPoste.idDuMois(annee, 3);
        serveur.cloturesMois[id] = {
          'id': id,
          'annee': annee,
          'mois': 3,
          'is_cloture': false,
          'date_cloture': null,
          'decloture_par': 'u1',
          'updated_at': DateTime.now()
              .subtract(const Duration(days: 2))
              .toUtc()
              .toIso8601String(),
          'serveur_modifie_le': DateTime.now().toUtc().toIso8601String(),
        };
        await a.vm.cloturerMois(3); // saisie locale plus récente

        final r = await a.moteur.synchroniser();

        expect(r.conserveesLocalement, 1);
        expect(
          serveur.cloturesMois[id]!['is_cloture'],
          isTrue,
          reason: 'la saisie récente part et gagne',
        );

        // Inversement : une décision plus RÉCENTE du serveur supplante la saisie non envoyée.
        await a.vm.decloturerMois(
          mois: 3,
          roleId: 'admin',
          utilisateurId: 'u1',
        );
        serveur.cloturesMois[id]!
          ..['is_cloture'] = true
          ..['date_cloture'] = DateTime.now().toUtc().toIso8601String()
          ..['updated_at'] = DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .toIso8601String()
          ..['serveur_modifie_le'] = DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .toIso8601String();
        final r2 = await a.moteur.synchroniser(complet: true);
        expect(r2.supplantees, 1);
        await a.vm.charger();
        expect(a.vm.cloturesMois[3], isTrue);
      },
    );

    test(
      'une pièce écrite hors ligne dans un mois clôturé entre-temps est refusée AVEC son motif',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        // B, hors ligne, écrit en mars ; A clôture mars et synchronise.
        await b.depense(80, date: jour(3, 12));
        await a.vm.cloturerMois(3);
        await a.moteur.synchroniser();

        // B se reconnecte : il reçoit la clôture, puis envoie sa pièce (trop tard).
        final r = await b.moteur.synchroniser();

        expect(r.refusees, 1);
        final lignes = await b.lignes();
        expect(lignes.every((l) => l.syncStatus == 'conflict'), isTrue);
        expect(lignes.first.syncMotif, contains('3/$annee'));
        expect(serveur.pieces, isEmpty);
      },
    );
  });

  group('clôture d\'exercice : un fait lourd', () {
    test('seule l\'administratrice clôture', () async {
      final a = await poste('P1');
      final r = await a.vm.cloturerExercice(roleId: 'caissier');
      expect(r, isA<Echec<void>>());
      expect((r as Echec<void>).message, contains('administratrice'));
      expect(a.vm.exerciceEstCloture, isFalse);
    });

    test(
      'un poste appairé qui a des pièces non transmises ne clôture pas',
      () async {
        final a = await poste('P1');
        await a.depense(100);

        final r = await a.vm.cloturerExercice(roleId: 'admin');

        expect(r, isA<Echec<void>>());
        expect((r as Echec<void>).message, contains('Synchronisez'));
        expect(a.vm.exerciceEstCloture, isFalse);
        expect((await a.exercice(annee)).isCloture, isFalse);
      },
    );

    test(
      'pièces refusées : la clôture est aussi refusée (le serveur verrouillerait un exercice incomplet)',
      () async {
        final a = await poste('P1');
        await a.depense(100);
        serveur.exercices[annee]!['is_cloture'] = true;
        await a.moteur.synchroniser();
        serveur.exercices[annee]!['is_cloture'] = false;
        await a.vm.charger();

        final r = await a.vm.cloturerExercice(roleId: 'admin');

        expect((r as Echec<void>).message, contains('refusée'));
      },
    );

    test('un poste jamais appairé clôture seul', () async {
      final seul = await poste(null);
      await seul.depense(100);
      final r = await seul.vm.cloturerExercice(roleId: 'admin');
      expect(r, isA<Succes<void>>(), reason: '$r');
      expect(seul.vm.exerciceEstCloture, isTrue);
    });

    test(
      'la clôture part APRÈS les pièces et verrouille l\'exercice pour tous les postes',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.depense(100);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await a.vm.charger();

        expect(
          await a.vm.cloturerExercice(roleId: 'admin'),
          isA<Succes<void>>(),
        );
        expect((await a.exercice(annee)).syncStatus, 'pending');
        serveur.envois.clear();
        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(serveur.exercices[annee]!['is_cloture'], isTrue);
        expect(
          serveur.exercices.containsKey(annee + 1),
          isTrue,
          reason: 'l\'exercice suivant est ouvert',
        );
        expect((await a.exercice(annee)).syncStatus, 'synced');

        // Sur B : l'exercice est clos, ses écritures verrouillées, plus d'écriture possible.
        await b.moteur.synchroniser();
        await b.vm.charger();
        expect(b.vm.exerciceEstCloture, isTrue);
        expect(b.vm.ecritures.every((e) => e.isLocked), isTrue);
        final refus = await b.vm.enregistrerPiece(
          date: jour(7, 1),
          journalCode: 'OD',
          numeroPiece: 'OD-P2-$annee-0001',
          lignes: const [
            LigneAEcrire(
              numeroCompte: '624',
              debit: 5,
              credit: 0,
              libelle: 'x',
            ),
            LigneAEcrire(
              numeroCompte: '531',
              debit: 0,
              credit: 5,
              libelle: 'x',
            ),
          ],
        );
        expect(refus, isA<Echec<void>>());
      },
    );

    test(
      'un poste neuf qui reçoit un exercice clos reçoit ses pièces VERROUILLÉES',
      () async {
        serveur.ajouterExercice(annee - 1, clos: true);
        serveur.ajouterPiece(
          nouvelUuid(),
          annee: annee - 1,
          date: DateTime(annee - 1, 11, 20, 10),
          numeroPiece: 'OD-P2-${annee - 1}-0001',
          lignes: [_ligne('531', 700, 0), _ligne('701', 0, 700)],
        );
        final b = await poste('P3');

        await b.moteur.synchroniser();
        await b.vm.charger();

        final anciennes = b.vm.ecritures;
        await b.vm.changerExercice(annee - 1);
        expect(b.vm.exerciceEstCloture, isTrue);
        expect(b.vm.ecritures, hasLength(2));
        expect(b.vm.ecritures.every((e) => e.isLocked), isTrue);
        expect(
          anciennes,
          isEmpty,
          reason: 'l\'exercice courant n\'a rien reçu',
        );
      },
    );

    test(
      'ordre d\'un cycle : la clôture annuelle est envoyée en DERNIER',
      () async {
        final a = await poste(null);
        await a.depense(100);
        await a.vm.cloturerExercice(roleId: 'admin');
        // Le poste devient appairé après coup : tout est à envoyer, dans le bon ordre.
        await a.preferences.memoriserAppairage(
          codePoste: 'P1',
          compte: 'g',
          le: DateTime.now(),
        );
        serveur.envois.clear();

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        final ordre = [
          for (final e in serveur.envois) ...(e['tables'] as Map).keys,
        ];
        expect(ordre.indexOf('ecriture_comptable'), greaterThanOrEqualTo(0));
        expect(
          ordre.indexOf('clotures_exercice'),
          greaterThan(ordre.indexOf('ecriture_comptable')),
        );
        expect(serveur.exercices[annee]!['is_cloture'], isTrue);
        expect(serveur.pieces, hasLength(1));
      },
    );

    test(
      'clôture refusée par le serveur : l\'exercice est rouvert ici, le motif est dit, on peut recommencer',
      () async {
        final a = await poste('P1');
        await a.depense(100);
        await a.moteur.synchroniser();
        await a.vm.charger();
        serveur.clotureExerciceAutorisee = false;
        await a.vm.cloturerExercice(roleId: 'admin');
        expect(a.vm.exerciceEstCloture, isTrue);

        final r = await a.moteur.synchroniser();

        expect(r.refusees, 1);
        await a.vm.charger();
        expect(
          a.vm.exerciceEstCloture,
          isFalse,
          reason: 'le serveur n\'a pas clos',
        );
        expect(a.vm.motifRefusCloture, contains('Droit insuffisant'));
        expect(a.vm.ecritures.every((e) => !e.isLocked), isTrue);
        expect(serveur.exercices[annee]!['is_cloture'], isFalse);

        serveur.clotureExerciceAutorisee = true;
        expect(
          await a.vm.cloturerExercice(roleId: 'admin'),
          isA<Succes<void>>(),
        );
        await a.moteur.synchroniser();
        expect(serveur.exercices[annee]!['is_cloture'], isTrue);
        await a.vm.charger();
        expect(a.vm.motifRefusCloture, isNull);
      },
    );

    test(
      'jamais de déclôture venue du serveur : un serveur « ouvert » ne rouvre pas un exercice clos ici',
      () async {
        final a = await poste(null);
        await a.vm.cloturerExercice(roleId: 'admin');
        await a.preferences.memoriserAppairage(
          codePoste: 'P1',
          compte: 'g',
          le: DateTime.now(),
        );
        await a.moteur.synchroniser();
        serveur.exercices[annee]!
          ..['is_cloture'] = false
          ..['date_cloture'] = null
          ..['updated_at'] = DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 5))
              .toIso8601String();

        await a.moteur.synchroniser(complet: true);

        expect((await a.exercice(annee)).isCloture, isTrue);
      },
    );
  });

  group('absorbeur strict : exercices et clôtures incohérents', () {
    test(
      'année absurde, clôture sans date, mois hors 1-12, identifiant qui ne désigne pas le mois : refusés et comptés',
      () async {
        final a = await poste('P1');
        final maintenant = DateTime.now().toUtc().toIso8601String();
        serveur.exercices[1999] = {
          'annee': 1999,
          'is_cloture': false,
          'date_cloture': null,
          'updated_at': maintenant,
        };
        serveur.exercices[annee + 3] = {
          'annee': annee + 3,
          'is_cloture': true,
          'date_cloture': null, // clôture sans date
          'updated_at': maintenant,
        };
        serveur.cloturesMois['mauvais-id'] = {
          'id': nouvelUuid(),
          'annee': annee,
          'mois': 3,
          'is_cloture': true,
          'date_cloture': maintenant,
          'decloture_par': null,
          'updated_at': maintenant,
          'serveur_modifie_le': maintenant,
        };
        serveur.cloturesMois['mois-13'] = {
          'id': TableCloturesPeriodiquesPoste.idDuMois(annee, 13),
          'annee': annee,
          'mois': 13,
          'is_cloture': true,
          'date_cloture': maintenant,
          'decloture_par': null,
          'updated_at': maintenant,
          'serveur_modifie_le': maintenant,
        };

        serveur.notes['$annee-6'] = {
          'id': uuidDeterministe('note:$annee-6'),
          'exercice_annee': annee,
          'numero_note': 6, // les notes obligatoires vont de 1 à 5
          'titre': 'Note inventée',
          'contenu': 'x',
          'device_id': 'autre-poste',
          'updated_at': maintenant,
          'serveur_modifie_le': maintenant,
        };

        final r = await a.moteur.synchroniser();

        expect(r.refuseesALaReception, 5);
        expect(await a.db.select(a.db.notesAnnexes).get(), isEmpty);
        expect(await a.db.select(a.db.cloturesPeriodiques).get(), isEmpty);
        expect(
          (await a.db.select(a.db.exerciceComptable).get()).map((e) => e.annee),
          isNot(contains(1999)),
        );
      },
    );

    test(
      'une pièce de B ne repart jamais de A (rien à renvoyer après un tirage)',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.depense(10);
        await a.moteur.synchroniser();
        serveur.envois.clear();

        await b.moteur.synchroniser();

        expect(
          serveur.envois.expand((e) => (e['tables'] as Map).keys),
          isNot(contains('ecriture_comptable')),
        );
        expect(await b.moteur.aDesSaisiesAEnvoyer(), isFalse);
      },
    );
  });

  // ------------------------------------------------------------------ notes
  group('notes annexes : dernier écrivain gagne par (exercice, numéro)', () {
    test(
      'une note de A arrive chez B ; la plus récente gagne des deux côtés',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.vm.enregistrerNote(
          const NoteAnnexe(
            numero: 1,
            titre: 'Méthodes Comptables',
            contenu: 'Version A',
          ),
        );
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await b.vm.charger();
        expect(b.vm.contenuNote(1), 'Version A');

        await Future<void>.delayed(const Duration(milliseconds: 5));
        await b.vm.enregistrerNote(
          const NoteAnnexe(
            numero: 1,
            titre: 'Méthodes Comptables',
            contenu: 'Version B',
          ),
        );
        await b.moteur.synchroniser();
        await a.moteur.synchroniser();
        await a.vm.charger();

        expect(a.vm.contenuNote(1), 'Version B');
        expect(serveur.notes, hasLength(1));
      },
    );

    test(
      'une saisie locale plus récente est conservée, la plus ancienne du serveur ignorée',
      () async {
        final a = await poste('P1');
        final ancien = DateTime.now().subtract(const Duration(days: 3)).toUtc();
        serveur.notes['$annee-2'] = {
          'id': uuidDeterministe('note:$annee-2'),
          'exercice_annee': annee,
          'numero_note': 2,
          'titre': 'Immobilisations',
          'contenu': 'Ancienne',
          'device_id': 'autre-poste',
          'updated_at': ancien.toIso8601String(),
          'serveur_modifie_le': DateTime.now().toUtc().toIso8601String(),
        };
        await a.vm.enregistrerNote(
          const NoteAnnexe(
            numero: 2,
            titre: 'Immobilisations',
            contenu: 'Récente locale',
          ),
        );

        final r = await a.moteur.synchroniser();

        expect(r.conserveesLocalement, 1);
        expect(serveur.notes['$annee-2']!['contenu'], 'Récente locale');
      },
    );

    test(
      'l\'identifiant d\'une note est déterministe (même note, même UUID sur tous les postes)',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.vm.enregistrerNote(
          const NoteAnnexe(numero: 3, titre: 'Stocks', contenu: 'CMUP'),
        );
        await b.vm.enregistrerNote(
          const NoteAnnexe(numero: 3, titre: 'Stocks', contenu: 'CMUP'),
        );
        final ia = (await a.db.select(a.db.notesAnnexes).getSingle()).id;
        final ib = (await b.db.select(b.db.notesAnnexes).getSingle()).id;
        expect(ia, ib);
      },
    );
  });

  // -------------------------------------------------------- remise à zéro
  group('remise à zéro du serveur', () {
    test(
      'les écritures, notes et clôtures sont purgées, les exercices rouverts, le plan préservé ; les saisies perdues sont comptées',
      () async {
        final a = await poste('P1');
        await a.depense(100);
        await a.moteur.synchroniser();
        await a.vm.cloturerMois(2);
        await a.vm.enregistrerNote(
          const NoteAnnexe(
            numero: 1,
            titre: 'Méthodes Comptables',
            contenu: 'x',
          ),
        );
        await a.moteur.synchroniser();
        await a.depense(55, date: jour(8, 1)); // jamais envoyée
        serveur.remettreAZero();

        final r = await a.moteur.synchroniser();

        expect(r.remiseAZero, isTrue);
        expect(
          r.saisiesPerdues,
          1,
          reason: 'la pièce non envoyée est perdue, et dite',
        );
        expect(await a.lignes(), isEmpty);
        expect(await a.db.select(a.db.notesAnnexes).get(), isEmpty);
        expect(await a.db.select(a.db.cloturesPeriodiques).get(), isEmpty);
        expect((await a.exercice(annee)).isCloture, isFalse);
        await a.vm.charger();
        expect(a.vm.plan, isNotEmpty);
      },
    );
  });
}
