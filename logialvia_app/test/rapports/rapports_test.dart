import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/comptabilite/presentation/viewmodels/comptabilite_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/rapports/data/repositories/rapports_repository_drift.dart';
import 'package:logialvia_app/rapports/domain/entities/rapports.dart';
import 'package:logialvia_app/rapports/presentation/viewmodels/rapports_view_model.dart';

void main() {
  late AppDatabase db;
  late RapportsRepositoryDrift repository;
  late RapportsViewModel vm;

  /// Date de référence figée : les retards et la période par défaut ne doivent
  /// pas dépendre de l'horloge de la machine de test.
  final aujourdhui = DateTime(2026, 8, 20);
  final annee = aujourdhui.year;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    repository = RapportsRepositoryDrift(db);
    vm = RapportsViewModel(repository, aujourdhui: aujourdhui);
    await vm.charger();
  });

  tearDown(() async => db.close());

  Future<void> ecrirePiece({
    required String piece,
    required DateTime date,
    required List<LigneAEcrire> lignes,
    String journal = 'OD',
    String? venteRef,
    String? achatRef,
  }) => ComptabiliteRepositoryDrift(db).enregistrerPiece(
    date: date,
    journalCode: journal,
    numeroPiece: piece,
    lignes: lignes,
    venteRef: venteRef,
    achatRef: achatRef,
  );

  group('Période par défaut', () {
    test('le mois civil en cours, pas la date figée du prototype', () {
      expect(vm.debut, DateTime(annee, 8, 1));
      expect(vm.fin, aujourdhui);
    });

    test('une période inversée est remise d\'aplomb', () async {
      await vm.changerPeriode(debut: DateTime(annee, 8, 20));
      await vm.changerPeriode(fin: DateTime(annee, 8, 1));
      expect(vm.debut, DateTime(annee, 8, 1));
      expect(vm.fin, DateTime(annee, 8, 20));
    });
  });

  group('Onglet 1 — Recettes et Dépenses', () {
    setUp(() async {
      await ecrirePiece(
        piece: 'V-001',
        date: DateTime(annee, 8, 5),
        journal: 'VT',
        venteRef: 'V-2026-001',
        lignes: const [
          LigneAEcrire(
            numeroCompte: '531',
            debit: 10000,
            credit: 0,
            libelle: 'Vente comptant',
          ),
          LigneAEcrire(
            numeroCompte: '701',
            debit: 0,
            credit: 6000,
            libelle: 'Vente avicole',
          ),
          LigneAEcrire(
            numeroCompte: '707',
            debit: 0,
            credit: 4000,
            libelle: 'Vente marchandises',
          ),
        ],
      );
      await ecrirePiece(
        piece: 'DEP-001',
        date: DateTime(annee, 8, 6),
        journal: 'CA',
        lignes: const [
          LigneAEcrire(
            numeroCompte: '628',
            debit: 1500,
            credit: 0,
            libelle: 'Entretien groupe électrogène',
          ),
          LigneAEcrire(
            numeroCompte: '531',
            debit: 0,
            credit: 1500,
            libelle: 'Entretien groupe électrogène',
          ),
        ],
      );
      await vm.charger();
    });

    test(
      'seules les classes 6 et 7 comptent — pas les contreparties',
      () async {
        // 531 est mouvemente de 10 000 puis 1 500 : le compter doublerait tout.
        expect(vm.totalRecettes, 10000);
        expect(vm.totalDepenses, 1500);
        expect(vm.resultatNet, 8500);
        expect(vm.donnees.recettesDepenses, hasLength(3)); // 628, 701, 707
      },
    );

    test('le Résultat Net est le même que celui du Compte de Résultat — '
        'BR-CPT-005 vaut aussi entre modules', () async {
      final compta = ComptabiliteViewModel(ComptabiliteRepositoryDrift(db));
      await compta.charger();
      expect(vm.resultatNet, compta.resultatNet);
      expect(vm.totalRecettes, compta.totalProduits);
      expect(vm.totalDepenses, compta.totalCharges);
    });

    test('les centres de profit sont déduits du numéro de compte', () {
      final parCentre = {
        for (final l in vm.donnees.recettesDepenses)
          l.categorie.split(' ').first: l.centre,
      };
      expect(parCentre['701'], CentresProfit.aviculture);
      expect(parCentre['707'], CentresProfit.commerceAnnexe);
      expect(parCentre['628'], CentresProfit.chargeGenerale);
    });

    test('le filtre par centre restreint la table et le solde cumulé', () {
      vm.definirFiltreCentre(CentresProfit.aviculture);
      expect(vm.recettesDepensesFiltrees, hasLength(1));
      expect(vm.soldesCumules, [6000]);

      vm.definirFiltreCentre(null);
      expect(vm.recettesDepensesFiltrees, hasLength(3));
      expect(vm.soldesCumules.last, 8500);
    });

    test('le taux de marge brute est indéfini sans recette', () async {
      final vide = RapportsViewModel(repository, aujourdhui: aujourdhui);
      await vide.changerPeriode(
        debut: DateTime(annee, 1, 1),
        fin: DateTime(annee, 1, 31),
      );
      expect(vide.totalRecettes, 0);
      expect(vide.tauxMargeBrute, isNull);
    });

    test('une écriture hors période est exclue', () async {
      await ecrirePiece(
        piece: 'V-002',
        date: DateTime(annee, 7, 15),
        journal: 'VT',
        lignes: const [
          LigneAEcrire(
            numeroCompte: '531',
            debit: 50000,
            credit: 0,
            libelle: 'Vente de juillet',
          ),
          LigneAEcrire(
            numeroCompte: '701',
            debit: 0,
            credit: 50000,
            libelle: 'Vente de juillet',
          ),
        ],
      );
      await vm.charger();
      expect(vm.totalRecettes, 10000, reason: 'Juillet est hors période.');
    });
  });

  group('Onglet 2 — État de Trésorerie', () {
    setUp(() async {
      // Solde d'ouverture : une ecriture ANTERIEURE a la periode.
      await ecrirePiece(
        piece: 'OD-000',
        date: DateTime(annee, 7, 1),
        lignes: const [
          LigneAEcrire(
            numeroCompte: '531',
            debit: 20000,
            credit: 0,
            libelle: 'Apport initial',
          ),
          LigneAEcrire(
            numeroCompte: '101',
            debit: 0,
            credit: 20000,
            libelle: 'Apport initial',
          ),
        ],
      );
      await ecrirePiece(
        piece: 'V-001',
        date: DateTime(annee, 8, 5),
        journal: 'VT',
        venteRef: 'V-2026-001',
        lignes: const [
          LigneAEcrire(
            numeroCompte: '531',
            debit: 4500,
            credit: 0,
            libelle: 'Vente comptant',
          ),
          LigneAEcrire(
            numeroCompte: '701',
            debit: 0,
            credit: 4500,
            libelle: 'Vente comptant',
          ),
        ],
      );
      await ecrirePiece(
        piece: 'A-001',
        date: DateTime(annee, 8, 6),
        journal: 'AC',
        achatRef: 'ACH-2026-001',
        lignes: const [
          LigneAEcrire(
            numeroCompte: '601',
            debit: 6000,
            credit: 0,
            libelle: 'Achat maïs',
          ),
          LigneAEcrire(
            numeroCompte: '512',
            debit: 0,
            credit: 6000,
            libelle: 'Achat maïs',
          ),
        ],
      );
      await vm.charger();
    });

    test('le solde d\'ouverture ne compte que les écritures antérieures', () {
      expect(vm.soldeOuverture('Caisse'), 20000);
      expect(vm.soldeOuverture('Mobile Money'), 0);
    });

    test('le solde de clôture ajoute les mouvements de la période', () {
      expect(vm.soldeCloture('Caisse'), 24500);
      expect(vm.soldeCloture('Mobile Money'), -6000);
      expect(vm.tresorerieNetteGlobale, 18500);
    });

    test('le solde progressif est tenu PAR COMPTE, jamais en cumul mêlé', () {
      // Ligne 1 = Caisse (20 000 + 4 500), ligne 2 = Mobile Money (0 − 6 000).
      expect(vm.soldesProgressifsTresorerie, [24500, -6000]);
    });

    test('le type d\'opération est déduit de l\'origine réelle', () {
      final types = {
        for (final m in vm.donnees.mouvementsTresorerie)
          m.libelle: m.typeOperation,
      };
      expect(types['Vente comptant'], 'Vente POS');
      expect(types['Achat maïs'], 'Décaissement Achat');
    });

    test('le filtre par compte n\'altère pas le solde de l\'autre', () {
      vm.definirFiltreCompte('Caisse');
      expect(vm.mouvementsFiltres, hasLength(1));
      expect(vm.soldesProgressifsTresorerie, [24500]);
      expect(
        vm.soldeCloture('Mobile Money'),
        -6000,
        reason: 'Le filtre est un filtre d\'affichage, pas de calcul.',
      );
    });
  });

  group('Onglet 3 — Créances Clients', () {
    setUp(() async {
      await db
          .into(db.ventes)
          .insert(
            VentesCompanion.insert(
              ref: 'V-2026-100',
              client: 'AGOSSOU Prudence',
              dateVente: DateTime(annee, 8, 1),
              mode: 'Avance',
              status: 'Payée partiellement',
              total: 9500,
              paye: 2500,
              // Echeance convenue au 05/08 : la creance est exigible depuis
              // 15 jours a la date de reference du test (20/08).
              echeance: Value(DateTime(annee, 8, 5)),
            ),
          );
      await db
          .into(db.ventes)
          .insert(
            VentesCompanion.insert(
              ref: 'V-2026-101',
              client: 'Client Comptant',
              dateVente: aujourdhui,
              mode: 'Espèces',
              status: 'Payée',
              total: 4000,
              paye: 4000,
            ),
          );
      await vm.charger();
    });

    test('seules les ventes non soldées sont des créances', () {
      expect(vm.donnees.creances, hasLength(1));
      expect(vm.donnees.creances.single.numeroFacture, 'V-2026-100');
      expect(vm.donnees.creances.single.soldeDu, 7000);
      expect(vm.creancesEnCours, 7000);
    });

    test('le retard se calcule depuis l\'échéance, pas depuis la vente', () {
      final creance = vm.donnees.creances.single;
      expect(
        creance.joursDeRetard,
        15, // du 05/08 (echeance) au 20/08
        reason:
            'Avant la v17 le retard partait de la date de VENTE (01/08), soit '
            '19 jours : toute creance nee la veille etait deja « En Retard ».',
      );
      expect(creance.statut, 'En Retard');
      expect(vm.creancesEnRetard, 7000);
    });

    test('l\'échéance est celle convenue, pas la date de vente', () {
      final creance = vm.donnees.creances.single;
      expect(creance.echeance, DateTime(annee, 8, 5));
      expect(
        creance.echeance,
        isNot(creance.dateVente),
        reason:
            'C\'etait le defaut : la colonne « Echeance » recopiait la date de '
            'vente, donc ne portait aucune information.',
      );
    });

    test('sans échéance convenue, une créance n\'est JAMAIS en retard', () async {
      await (db.update(db.ventes)..where((v) => v.ref.equals('V-2026-100')))
          .write(const VentesCompanion(echeance: Value(null)));
      await vm.charger();

      final creance = vm.donnees.creances.single;
      expect(creance.sansEcheance, isTrue);
      expect(creance.joursDeRetard, 0);
      expect(creance.enRetard, isFalse);
      expect(
        creance.statut,
        'Sans échéance',
        reason:
            '« Sans echeance » n\'est pas « A echoir » : la premiere dit '
            'qu\'aucune date n\'a ete fixee, la seconde qu\'une date existe et '
            'n\'est pas atteinte.',
      );
      expect(
        vm.creancesEnRetard,
        0,
        reason:
            'La lettre de relance s\'imprime depuis ce tableau : reclamer un '
            'paiement non echu engage la Gerante aupres d\'un client.',
      );
    });

    test('le taux de recouvrement est Acomptes / Montant Initial', () {
      expect(vm.tauxRecouvrement, closeTo(2500 / 9500 * 100, 0.001));
    });

    test('une vente annulée n\'est plus une créance', () async {
      await (db.update(db.ventes)..where((v) => v.ref.equals('V-2026-100')))
          .write(const VentesCompanion(status: Value('Annulée')));
      await vm.charger();
      expect(vm.donnees.creances, isEmpty);
      expect(vm.creancesEnCours, 0);
      expect(vm.tauxRecouvrement, isNull);
    });

    test('un client à 2 factures impayées reste UN débiteur', () async {
      await db
          .into(db.ventes)
          .insert(
            VentesCompanion.insert(
              ref: 'V-2026-102',
              client: 'AGOSSOU Prudence',
              dateVente: DateTime(annee, 8, 10),
              mode: 'Avance',
              status: 'Payée partiellement',
              total: 3000,
              paye: 0,
            ),
          );
      await vm.charger();
      expect(vm.donnees.creances, hasLength(2));
      expect(vm.clientsDebiteurs, 1);
    });
  });

  group('Onglet 4 — Dettes Fournisseurs', () {
    setUp(() async {
      final id = await db
          .into(db.fournisseurs)
          .insert(FournisseursCompanion.insert(nom: 'Fournisseur Maïs Local'));
      await db
          .into(db.achats)
          .insert(
            AchatsCompanion.insert(
              ref: 'ACH-2026-041',
              fournisseurId: id,
              dateAchat: DateTime(annee, 8, 6),
              statut: 'Réceptionnée',
              total: 25000,
              paye: const Value(13000),
              echeance: Value(DateTime(annee, 8, 10)),
            ),
          );
      await vm.charger();
    });

    test('le solde restant et le statut sont dérivés, jamais stockés', () {
      final dette = vm.donnees.dettes.single;
      expect(dette.soldeRestant, 12000);
      expect(dette.fournisseur, 'Fournisseur Maïs Local');
      expect(dette.urgente, isTrue);
      expect(dette.statut, 'Urgent');
      expect(vm.totalDettes, 12000);
      expect(vm.dettesUrgentes, 12000);
      expect(vm.fournisseursCrediteurs, 1);
    });

    test(
      'l\'échéance est celle convenue — jamais antérieure à l\'engagement',
      () {
        final dette = vm.donnees.dettes.single;
        expect(dette.echeance, DateTime(annee, 8, 10));
        expect(
          dette.echeance!.isBefore(dette.dateAchat),
          isFalse,
          reason:
              'Le prototype date sa seule dette du 06/08 avec une echeance au '
              '05/08 : exigible la veille de son propre engagement.',
        );
      },
    );

    test('sans échéance convenue, une dette n\'est jamais urgente', () async {
      await (db.update(db.achats)..where((a) => a.ref.equals('ACH-2026-041')))
          .write(const AchatsCompanion(echeance: Value(null)));
      await vm.charger();

      final dette = vm.donnees.dettes.single;
      expect(dette.sansEcheance, isTrue);
      expect(dette.urgente, isFalse);
      expect(dette.statut, 'Sans échéance');
      expect(vm.dettesUrgentes, 0);
    });

    test('un achat soldé disparaît des dettes', () async {
      await (db.update(db.achats)..where((a) => a.ref.equals('ACH-2026-041')))
          .write(const AchatsCompanion(paye: Value(25000)));
      await vm.charger();
      expect(vm.donnees.dettes, isEmpty);
      expect(vm.totalDettes, 0);
    });
  });

  group('Onglet 5 — Rapport Élevage', () {
    setUp(() async {
      await db
          .into(db.ficheJournee)
          .insert(
            FicheJourneeCompanion.insert(
              espece: 'goliaths',
              date: DateTime(annee, 8, 5),
              mortCat1: const Value(2),
              donCat2: const Value(1),
              effectif: const Value(94),
              effCat1Day: const Value(30),
              effCat2Day: const Value(33),
              effCat3Day: const Value(31),
              isRecorded: const Value(true),
            ),
          );
      await db
          .into(db.cycleCouveuse)
          .insert(
            CycleCouveuseCompanion.insert(
              codeIncubation: 'C-2026-012',
              espece: const Value('goliath'),
              dateIncubation: DateTime(annee, 7, 12),
              oeufsCouves: 200,
              poussinsNes: const Value(168),
              statut: 'Éclos',
            ),
          );
      await db
          .into(db.cycleCouveuse)
          .insert(
            CycleCouveuseCompanion.insert(
              codeIncubation: 'C-2026-014',
              espece: const Value('pintade'),
              dateIncubation: DateTime(annee, 8, 1),
              oeufsCouves: 140,
              statut: 'En cours',
            ),
          );
      await vm.charger();
    });

    test('le recensement lit la dernière journée saisie de la période', () {
      final ligne = vm.donnees.recensement.single;
      expect(ligne.lot, 'Goliaths');
      expect(ligne.effectifTotal, 94);
      expect(ligne.effectifMatures, 31); // derniere categorie
      expect(ligne.effectifJeunes, 63); // 30 + 33
      expect(ligne.mortsPeriode, 2);
      expect(ligne.donsPeriode, 1);
    });

    test('la provende servie applique les barèmes configurés', () {
      final mouvement = vm.donnees.mouvementsElevage.single;
      // 30 × 30 + 33 × 60 + 31 × 110 = 900 + 1980 + 3410
      expect(mouvement.provendeServieGrammes, 6290);
    });

    test(
      'l\'éclosion attendue dépend de l\'espèce — 21 j goliath, 27 j pintade',
      () {
        final parCode = {for (final c in vm.donnees.couvoir) c.codeLot: c};
        expect(
          parCode['C-2026-012']!.eclosionAttendue,
          DateTime(annee, 7, 12).add(const Duration(days: 21)),
        );
        expect(
          parCode['C-2026-014']!.eclosionAttendue,
          DateTime(annee, 8, 1).add(const Duration(days: 27)),
        );
      },
    );

    test('le taux d\'éclosion est null tant que le cycle n\'a pas éclos', () {
      final parCode = {for (final c in vm.donnees.couvoir) c.codeLot: c};
      expect(parCode['C-2026-014']!.tauxEclosion, isNull);
      expect(parCode['C-2026-012']!.tauxEclosion, closeTo(84.0, 0.001));
      expect(parCode['C-2026-012']!.mortsAuDemarrage, 32);
    });

    test('les KPI zootechniques sont calculés, jamais recopiés', () {
      expect(vm.donnees.effectifTotal, 94);
      expect(vm.donnees.cyclesEnCours, 1);
      expect(vm.donnees.tauxEclosionMoyen, closeTo(84.0, 0.001));
      expect(vm.donnees.sujetsMalades, 0);
    });

    test('sans aucun soin ni cas d\'infirmerie, les colonnes le disent', () {
      final mouvement = vm.donnees.mouvementsElevage.single;
      expect(mouvement.traitementAdministre, 'Aucun traitement administré');
      expect(mouvement.signesObserves, 'Aucun signe observé');
    });
  });

  group('Onglet 6 — Rapport de Stocks', () {
    test('intrants et produits finis sont réunis, valorisés séparément', () {
      final intrants = vm.donnees.stocks
          .where((s) => s.categorie == LigneStock.categorieIntrant)
          .toList();
      final produits = vm.donnees.stocks
          .where((s) => s.categorie == LigneStock.categorieProduitFini)
          .toList();

      expect(intrants, hasLength(6));
      expect(produits, hasLength(14));

      final mais = intrants.firstWhere((s) => s.designation == 'Maïs');
      expect(mais.cmup, 600);
      expect(mais.valeurTotale, 18 * 600);
      expect(mais.critique, isTrue);
      expect(mais.statut, 'Critique');
    });

    test('les KPI décrivent tout le stock, la table en montre une partie', () {
      final total = vm.valeurTotaleStock;
      final references = vm.referencesActives;

      vm.definirFiltreCategorieStock(LigneStock.categorieIntrant);
      expect(vm.stocksFiltres, hasLength(6));
      expect(
        vm.valeurTotaleStock,
        total,
        reason: 'Le prototype cumule avant d\'appliquer le filtre.',
      );
      expect(vm.referencesActives, references);
    });

    test(
      'aucun SKU n\'est vide, même quand le catalogue n\'en fournit pas',
      () {
        expect(vm.donnees.stocks.every((s) => s.sku.isNotEmpty), isTrue);
      },
    );
  });

  group('Base vierge — aucun chiffre inventé', () {
    test(
      'les 6 onglets renvoient des états vides, pas des valeurs de démo',
      () async {
        final neuf = AppDatabase.enMemoire();
        await SeedInitial(neuf).executer();
        final vmVierge = RapportsViewModel(
          RapportsRepositoryDrift(neuf),
          aujourdhui: aujourdhui,
        );
        await vmVierge.charger();

        expect(vmVierge.totalRecettes, 0);
        expect(vmVierge.totalDepenses, 0);
        expect(vmVierge.resultatNet, 0);
        expect(vmVierge.tauxMargeBrute, isNull);
        expect(vmVierge.tresorerieNetteGlobale, 0);
        expect(vmVierge.donnees.creances, isEmpty);
        expect(vmVierge.donnees.dettes, isEmpty);
        expect(vmVierge.donnees.recensement, isEmpty);
        expect(vmVierge.donnees.couvoir, isEmpty);
        expect(vmVierge.donnees.effectifTotal, 0);
        expect(
          vmVierge.donnees.tauxEclosionMoyen,
          isNull,
          reason: 'Jamais 0 %, qui se lirait comme un échec total.',
        );
        // Le catalogue et les intrants sont semes : le stock, lui, n'est pas vide.
        expect(vmVierge.donnees.stocks, isNotEmpty);

        await neuf.close();
      },
    );
  });
}
