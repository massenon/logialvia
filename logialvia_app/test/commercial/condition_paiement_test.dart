import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';

/// Arbitrage de la Gérante : « Avance » est une condition de paiement, pas un
/// mode de règlement. Point 3 de l'index maître, resté ouvert jusqu'ici.
void main() {
  group('Les deux questions sont séparées', () {
    test('le mode de règlement ne propose plus que 2 instruments', () {
      expect(ModeReglement.tous, [
        ModeReglement.especes,
        ModeReglement.mobileMoney,
      ]);
      expect(
        ModeReglement.tous,
        isNot(contains(ConditionPaiement.avance)),
        reason:
            'C\'etait la troisieme valeur historique de VENTES.mode : elle '
            'repondait a « combien », pas a « avec quoi ».',
      );
    });

    test('la condition de paiement en propose 2', () {
      expect(ConditionPaiement.toutes, [
        ConditionPaiement.comptant,
        ConditionPaiement.avance,
      ]);
    });

    test('une avance peut désormais être versée en Mobile Money', () {
      // Impossible avant : `mode` etait occupe par « Avance », l'instrument
      // reel disparaissait. Le rapprochement de caisse en dependait.
      const mode = ModeReglement.mobileMoney;
      const condition = ConditionPaiement.avance;

      expect(ModeReglement.tous, contains(mode));
      expect(ConditionPaiement.toutes, contains(condition));
    });
  });

  group('La condition se déduit du statut — aucune colonne ajoutée', () {
    test('une vente au statut Avance est une vente à crédit', () {
      expect(
        ConditionPaiement.depuisStatut(StatutVente.avance),
        ConditionPaiement.avance,
      );
    });

    test('une vente payée est comptant', () {
      expect(
        ConditionPaiement.depuisStatut(StatutVente.payee),
        ConditionPaiement.comptant,
      );
    });

    test('une vente annulée n\'est pas présentée comme une créance', () {
      expect(
        ConditionPaiement.depuisStatut(StatutVente.annulee),
        ConditionPaiement.comptant,
        reason:
            'Une vente annulee ne doit pas apparaitre en avance : son reste '
            'du est nul par construction (Vente.resteDu).',
      );
    });

    test('les deux informations coexistent sur une même vente', () {
      final vente = Vente(
        reference: 'V-2026-001',
        client: 'AGOSSOU Prudence',
        date: DateTime(2026, 8, 15),
        mode: ModeReglement.mobileMoney,
        statut: StatutVente.avance,
        total: 12000,
        paye: 5000,
      );

      expect(vente.mode, ModeReglement.mobileMoney);
      expect(
        ConditionPaiement.depuisStatut(vente.statut),
        ConditionPaiement.avance,
      );
      expect(vente.resteDu, 7000);
    });
  });

  group('Ventes antérieures à la migration v15', () {
    test('leur instrument est « Non précisé », pas « Espèces »', () {
      expect(ModeReglement.nonPrecise, 'Non précisé');
      expect(
        ModeReglement.tous,
        isNot(contains(ModeReglement.nonPrecise)),
        reason:
            'On ne peut pas le SAISIR : c\'est une trace du passe, pas un '
            'choix offert a la caissiere.',
      );
    });
  });
}
