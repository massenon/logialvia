import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/parametres_repository_drift.dart';
import 'package:logialvia_app/administration/domain/entities/parametres_entreprise.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/commercial/presentation/viewmodels/ventes_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';

/// Échéance de paiement — migration v17.
///
/// Avant elle, `CreanceClient.echeance` retournait `dateVente` : toute créance
/// née la veille était affichée « En Retard », et la **lettre de relance**
/// imprimée depuis ce tableau réclamait un paiement non échu.
void main() {
  late AppDatabase db;
  late VentesViewModel vm;

  Future<void> definirDelai(int? jours) =>
      ParametresRepositoryDrift(db).enregistrer(
        ParametresEntrepriseModele(
          raisonSociale: 'ALLMANY ET COMPAGNIE',
          telephone: '+229 97 00 00 00',
          delaiPaiementJours: jours,
        ),
      );

  ProduitVendable produit(String nom) =>
      vm.produitsFiltres.firstWhere((p) => p.nom == nom);

  Future<void> panierACredit({double montant = 12000}) async {
    vm.ajouterAuPanier(
      produit('Goliath mature'),
      quantite: 2,
      montantGlobal: montant,
    );
    vm.condition = ConditionPaiement.avance;
    vm.montantRecu = 5000;
  }

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    vm = VentesViewModel(VentesRepositoryDrift(db, EventBus()), db);
    await vm.charger();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  group('Le délai par défaut pré-remplit, sans jamais s\'imposer', () {
    test('passer en Avance propose la date par défaut', () async {
      await definirDelai(30);
      await vm.charger();

      vm.condition = ConditionPaiement.avance;

      final attendu = DateTime.now().add(const Duration(days: 30));
      expect(vm.echeance, isNotNull);
      expect(vm.echeance!.difference(attendu).inHours.abs(), lessThan(2));
    });

    test('la caissière peut l\'écraser', () async {
      await definirDelai(30);
      await vm.charger();
      vm.condition = ConditionPaiement.avance;

      final negociee = DateTime.now().add(const Duration(days: 7));
      vm.echeance = negociee;

      expect(vm.echeance, negociee);
    });

    test('sans délai configuré, aucune échéance n\'est proposée', () {
      vm.condition = ConditionPaiement.avance;

      expect(
        vm.echeance,
        isNull,
        reason:
            'Inventer « 30 jours » produirait des retards fictifs et des '
            'lettres de relance injustifiees.',
      );
      expect(vm.delaiPaiementParDefaut, isNull);
      expect(vm.echeanceNonFixee, isTrue);
    });

    test('un délai nul ou négatif compte comme non fixé', () async {
      await definirDelai(0);
      await vm.charger();
      expect(vm.delaiPaiementParDefaut, isNull);
    });
  });

  group('L\'échéance ne concerne que les ventes à crédit', () {
    test('une vente comptant n\'a pas d\'échéance', () async {
      await definirDelai(30);
      await vm.charger();

      vm.condition = ConditionPaiement.comptant;
      expect(vm.echeance, isNull);
      expect(vm.echeanceNonFixee, isFalse);
    });

    test('revenir en comptant efface l\'échéance saisie', () async {
      await definirDelai(30);
      await vm.charger();
      vm.condition = ConditionPaiement.avance;
      expect(vm.echeance, isNotNull);

      vm.condition = ConditionPaiement.comptant;

      expect(vm.echeance, isNull);
    });
  });

  group('L\'échéance est réellement persistée', () {
    test('elle survit à l\'encaissement et se relit', () async {
      await definirDelai(15);
      await vm.charger();
      await panierACredit();

      final convenue = vm.echeance;
      await vm.encaisser();
      await vm.charger();

      final vente = vm.ventes.first;
      expect(vente.statut, StatutVente.avance);
      expect(vente.echeance, isNotNull);
      expect(vente.echeance!.difference(convenue!).inHours.abs(), lessThan(2));
    });

    test('une vente comptant est enregistrée sans échéance', () async {
      await definirDelai(15);
      await vm.charger();

      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      vm.montantRecu = 6000;
      await vm.encaisser();
      await vm.charger();

      expect(vm.ventes.first.echeance, isNull);
    });

    test(
      'une vente à crédit sans délai configuré reste sans échéance',
      () async {
        await panierACredit();
        await vm.encaisser();
        await vm.charger();

        final vente = vm.ventes.first;
        expect(vente.statut, StatutVente.avance);
        expect(
          vente.echeance,
          isNull,
          reason:
              'La creance existe et le solde reste du — mais rien ne permet de '
              'dire qu\'elle est en retard.',
        );
        expect(vente.resteDu, 7000);
      },
    );

    test('vider le panier remet l\'échéance à zéro', () async {
      await definirDelai(15);
      await vm.charger();
      await panierACredit();
      expect(vm.echeance, isNotNull);

      vm.viderPanier();

      expect(vm.echeance, isNull);
      expect(vm.condition, ConditionPaiement.comptant);
    });
  });

  group('Migration v17', () {
    test('les ventes antérieures restent sans échéance', () async {
      await db.customStatement(
        'INSERT INTO ventes (id, updated_at, ref, client, date_vente, mode, status, total, '
        'paye) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          '2026-01-01T00:00:00.000Z',
          'V-2025-001',
          'AGOSSOU Prudence',
          DateTime(2025, 5, 1).millisecondsSinceEpoch ~/ 1000,
          ModeReglement.especes,
          StatutVente.avance,
          12000.0,
          5000.0,
        ],
      );
      await vm.charger();

      final ancienne = vm.ventes.firstWhere((v) => v.reference == 'V-2025-001');
      expect(
        ancienne.echeance,
        isNull,
        reason:
            'Leur delai n\'a jamais ete convenu : ecrire une date a leur place '
            'inventerait la dette de quelqu\'un.',
      );
    });

    test('la v17 est bien franchie sur une base neuve', () {
      // `schemaVersion` a continue de monter (v18 : cout de revient).
      expect(db.schemaVersion, greaterThanOrEqualTo(17));
    });
  });
}
