import 'package:drift/drift.dart' show Variable;
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

/// `#modal-account-select` de `ventes.html` : une modale bloquante qui fait
/// choisir parmi **une seule** ligne codée en dur, et dont `validateSale()` ne
/// conserve rien. Doc K2 §B.
void main() {
  late AppDatabase db;
  late VentesViewModel vm;

  /// Enregistre reellement les parametres, comme le ferait l'ecran Parametres
  /// Generaux. Tant qu'aucune ligne n'existe, le repository sert ses valeurs
  /// par defaut — dont le numero de `parametres-generaux.html`.
  Future<void> definirTelephone(String? numero) =>
      ParametresRepositoryDrift(db).enregistrer(
        ParametresEntrepriseModele(
          raisonSociale: 'ALLMANY ET COMPAGNIE',
          telephone: numero,
        ),
      );

  ProduitVendable produit(String nom) =>
      vm.produitsFiltres.firstWhere((p) => p.nom == nom);

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

  group('La ligne vient de Paramètres Généraux, pas d\'une constante', () {
    test('elle reprend le Téléphone Principal de l\'entreprise', () async {
      await definirTelephone('+229 97 00 00 00');
      await vm.charger();

      vm.mode = ModeReglement.mobileMoney;
      expect(vm.ligneMobileMoney, '+229 97 00 00 00');
      expect(vm.ligneMobileMoneyManquante, isFalse);
    });

    test('elle est nulle en espèces — il n\'y a pas de ligne à créditer', () {
      vm.mode = ModeReglement.especes;
      expect(vm.ligneMobileMoney, isNull);
      expect(vm.ligneMobileMoneyManquante, isFalse);
    });
  });

  group('Sans numéro configuré, l\'encaissement Mobile Money est refusé', () {
    setUp(() async {
      await definirTelephone(null);
      await vm.charger();
    });

    test('le refus nomme l\'écran où corriger', () {
      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      vm.mode = ModeReglement.mobileMoney;
      vm.montantRecu = 6000;

      final erreur = vm.validerAvantEncaissement();
      expect(erreur, isNotNull);
      expect(
        erreur,
        contains('Paramètres Généraux'),
        reason:
            'Le prototype impose un numero code en dur ; ici on refuse, mais '
            'on dit ou le renseigner.',
      );
    });

    test('la même vente en espèces passe', () {
      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      vm.mode = ModeReglement.especes;
      vm.montantRecu = 6000;

      expect(vm.validerAvantEncaissement(), isNull);
    });

    test('un numéro vide compte comme absent', () async {
      await definirTelephone('   ');
      await vm.charger();
      vm.mode = ModeReglement.mobileMoney;

      expect(vm.ligneMobileMoneyManquante, isTrue);
    });
  });

  group('La ligne est réellement persistée sur la vente', () {
    test('elle survit à l\'encaissement et se relit', () async {
      await definirTelephone('+229 97 00 00 00');
      await vm.charger();

      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      vm.mode = ModeReglement.mobileMoney;
      vm.montantRecu = 6000;
      await vm.encaisser();

      final ligne = await db
          .customSelect('SELECT ligne_mobile_money FROM ventes LIMIT 1')
          .getSingle();
      expect(
        ligne.read<String?>('ligne_mobile_money'),
        '+229 97 00 00 00',
        reason: 'validateSale() ne conservait rien de ce choix pourtant exige.',
      );

      await vm.charger();
      expect(vm.ventes.first.ligneMobileMoney, '+229 97 00 00 00');
    });

    test('une vente en espèces ne porte aucune ligne', () async {
      await definirTelephone('+229 97 00 00 00');
      await vm.charger();

      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      vm.mode = ModeReglement.especes;
      vm.montantRecu = 6000;
      await vm.encaisser();
      await vm.charger();

      expect(vm.ventes.first.ligneMobileMoney, isNull);
    });

    test(
      'changer de numéro plus tard ne réécrit pas les ventes passées',
      () async {
        await definirTelephone('+229 97 00 00 00');
        await vm.charger();
        vm.ajouterAuPanier(
          produit('Goliath mature'),
          quantite: 1,
          montantGlobal: 6000,
        );
        vm.mode = ModeReglement.mobileMoney;
        vm.montantRecu = 6000;
        await vm.encaisser();

        // La Gerante change de ligne.
        await definirTelephone('+229 96 11 22 33');
        await vm.charger();

        expect(
          vm.ventes.first.ligneMobileMoney,
          '+229 97 00 00 00',
          reason:
              'La denormalisation existe pour ca : le rapprochement du compte '
              '512 doit continuer de nommer la ligne qui a recu l\'argent.',
        );
        expect(
          vm.ligneMobileMoney,
          isNull,
          reason: 'Le mode est revenu a especes.',
        );
      },
    );
  });

  group('Migration v16', () {
    test('les ventes antérieures restent à NULL — c\'est exact', () async {
      await db.customStatement(
        'INSERT INTO ventes (id, updated_at, ref, client, date_vente, mode, status, total, '
        'paye) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          '2026-01-01T00:00:00.000Z',
          'V-2025-001',
          'Client Comptant',
          DateTime(2025, 5, 1).millisecondsSinceEpoch ~/ 1000,
          ModeReglement.mobileMoney,
          StatutVente.payee,
          5000.0,
          5000.0,
        ],
      );

      final ligne = await db
          .customSelect(
            'SELECT ligne_mobile_money FROM ventes WHERE ref = ?',
            variables: [Variable.withString('V-2025-001')],
          )
          .getSingle();

      expect(
        ligne.read<String?>('ligne_mobile_money'),
        isNull,
        reason:
            'Leur ligne creditee n\'a jamais ete enregistree : la laisser vide '
            'est la seule reponse honnete.',
      );
    });

    test('la v16 est bien franchie sur une base neuve', () {
      // `schemaVersion` a continue de monter (v17 : echeances de paiement).
      // Ce qui compte est que le palier v16 soit derriere nous.
      expect(db.schemaVersion, greaterThanOrEqualTo(16));
    });
  });
}
