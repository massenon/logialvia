// Prix e-MECeF : TTC en montants entiers (le pilote documente « Prix avec TVA »),
// même règle que le constructeur AgriERP (`MecefFactureBuilder`). Aucun appel réseau.
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/commercial/domain/entities/facture_mecef.dart';
import 'package:logialvia_app/commercial/domain/services/transmission_mecef.dart';

LigneFacture _l(
  double q,
  double ht,
  double taux, {
  String nom = 'Article',
  String? unite,
}) => LigneFacture(
  designation: nom,
  quantite: q,
  prixUnitaireHt: ht,
  groupeTaxe: taux == 0 ? 'A' : 'B',
  tauxTaxe: taux,
  unite: unite,
);

void main() {
  group('ligne e-MECeF en TTC entier', () {
    test('18 % : le prix envoyé est TTC, jamais le hors taxe', () {
      final m = ClientMecefHttp.ligneTtc(_l(2, 10000, 18));
      expect(m['price'], 11800);
      expect(m['quantity'], 2);
      expect(m['taxGroup'], 'B');
    });

    test('0 % : TTC = HT', () {
      expect(ClientMecefHttp.ligneTtc(_l(3, 1000, 0))['price'], 1000);
    });

    test('prix × quantité = montant TTC arrondi de la ligne', () {
      final m = ClientMecefHttp.ligneTtc(_l(4, 1250, 18)); // 5900
      expect((m['price'] as num) * (m['quantity'] as num), 5900);
    });

    test('arrondi : moitié vers le haut (0,5 → 1)', () {
      expect(ClientMecefHttp.arrondi(2.5), 3);
      expect(ClientMecefHttp.arrondi(2.4), 2);
      expect(ClientMecefHttp.arrondi(1180.5), 1181);
    });

    test('division non entière : quantité 1, réelle dans le libellé', () {
      final m = ClientMecefHttp.ligneTtc(
        _l(1.5, 1001, 0, nom: 'Provende', unite: 'kg'),
      ); // 1501,5 → 1502 ; 1502000 % 1500 != 0
      expect(m['price'], 1502);
      expect(m['quantity'], 1);
      expect(m['name'], 'Provende (1,5 kg)');
    });

    test(
      'quantité décimale qui divise juste : prix entier, quantité décimale',
      () {
        final m = ClientMecefHttp.ligneTtc(_l(0.5, 2000, 0)); // 1000 / 0,5
        expect(m['price'], 2000);
        expect(m['quantity'], 0.5);
      },
    );

    test('libellé borné à 60 caractères, suffixe conservé', () {
      final m = ClientMecefHttp.ligneTtc(
        _l(1.5, 1001, 0, nom: 'X' * 80, unite: 'kg'),
      );
      expect((m['name'] as String).length, lessThanOrEqualTo(60));
      expect(m['name'], endsWith('(1,5 kg)'));
    });

    test('quantité nulle refusée', () {
      expect(
        () => ClientMecefHttp.ligneTtc(_l(0, 1000, 0)),
        throwsA(isA<EchecTransmission>()),
      );
    });

    test('tous les montants envoyés sont des entiers', () {
      for (final q in [1.0, 2.0, 3.0, 0.5, 1.5, 7.0]) {
        for (final ht in [999.0, 1001.0, 1250.0, 33333.0]) {
          final m = ClientMecefHttp.ligneTtc(_l(q, ht, 18));
          expect(m['price'], isA<int>(), reason: 'q=$q ht=$ht');
        }
      }
    });
  });
}
