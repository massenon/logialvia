import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/saisie/formats_saisie.dart';
import 'package:logialvia_app/core/widgets/champ_saisie_nombre.dart';

/// Les champs numériques n'acceptent que des chiffres, et jamais de négatif.
///
/// ## Ce que ces tests protègent
///
/// 43 champs déclaraient `keyboardType: TextInputType.number` et **aucun** ne
/// portait d'`inputFormatters`. Sur un poste Windows, ce type n'est qu'une
/// indication destinée aux claviers virtuels : rien n'empêchait de taper des
/// lettres, un signe moins ou une phrase dans « Nombre d'Œufs ». La valeur
/// était ensuite lue par `int.tryParse(...) ?? 0` — une frappe erronée
/// devenait **zéro sans un mot**, et ce zéro partait dans les calculs.
void main() {
  TextEditingValue frapper(List<TextInputFormatter> filtres, String texte) {
    var valeur = TextEditingValue.empty;
    for (final f in filtres) {
      valeur = f.formatEditUpdate(
        valeur,
        TextEditingValue(
          text: texte,
          selection: TextSelection.collapsed(offset: texte.length),
        ),
      );
    }
    return valeur;
  }

  group('Entiers — chiffres seuls', () {
    const filtres = FormatteursSaisie.entierPositif;

    test('les lettres et les phrases ne rentrent pas', () {
      expect(frapper(filtres, 'abc').text, '');
      expect(frapper(filtres, 'douze oeufs').text, '');
      expect(frapper(filtres, '12 oeufs').text, '12');
    });

    test('le signe moins est refusé — pas de quantité négative', () {
      expect(frapper(filtres, '-5').text, '5');
    });

    test('la décimale est refusée : ce sont des entiers', () {
      expect(frapper(filtres, '12,5').text, '125');
      expect(frapper(filtres, '12.5').text, '125');
    });

    test('un nombre valide passe intact', () {
      expect(frapper(filtres, '2026').text, '2026');
    });

    test('le curseur reste où il doit être après un refus', () {
      final valeur = frapper(filtres, '12a');
      expect(valeur.text, '12');
      expect(valeur.selection.baseOffset, 2);
    });
  });

  group('Montants — chiffres et un seul séparateur', () {
    const filtres = FormatteursSaisie.montant;

    test('la décimale est acceptée : le modèle stocke des réels', () {
      expect(frapper(filtres, '1500,50').text, '1500,50');
      expect(frapper(filtres, '1500.50').text, '1500.50');
    });

    test('un second séparateur est ignoré', () {
      // « 12,5,3 » rendrait `double.tryParse` nul, donc zero en silence.
      expect(frapper(filtres, '12,5,3').text, '12,53');
    });

    test('les lettres et le signe moins restent refusés', () {
      expect(frapper(filtres, '-1 500 FCFA').text, '1500');
    });
  });

  group('Pas à pas de la saisie journalière', () {
    Future<void> monter(
      WidgetTester tester, {
      required int valeur,
      required ValueChanged<int>? onChange,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChampSaisieNombre(
            libelle: 'Achats',
            valeur: valeur,
            onChange: onChange,
          ),
        ),
      ),
    );

    testWidgets('« + » incrémente, « − » décrémente', (tester) async {
      var valeur = 3;
      await monter(tester, valeur: valeur, onChange: (v) => valeur = v);

      await tester.tap(find.text('+'));
      expect(valeur, 4);

      await monter(tester, valeur: valeur, onChange: (v) => valeur = v);
      await tester.tap(find.text('−'));
      expect(valeur, 3);
    });

    testWidgets('« − » s\'éteint à zéro : aucun négatif possible', (
      tester,
    ) async {
      var valeur = 0;
      await monter(tester, valeur: valeur, onChange: (v) => valeur = v);

      await tester.tap(find.text('−'));
      await tester.pump();

      expect(
        valeur,
        0,
        reason: 'BR-ELV-001 : un effectif ne descend jamais sous zéro.',
      );
    });

    testWidgets('un champ en lecture seule n\'affiche aucun bouton', (
      tester,
    ) async {
      // « Ventes (POS) » est alimentée par le point de vente : un pas à pas
      // inerte serait un bouton décoratif.
      await monter(tester, valeur: 7, onChange: null);

      expect(find.text('+'), findsNothing);
      expect(find.text('−'), findsNothing);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('la frappe reste possible, et filtrée', (tester) async {
      var valeur = 0;
      await monter(tester, valeur: valeur, onChange: (v) => valeur = v);

      // Charger 300 sujets au clic serait absurde : le champ reste saisissable.
      await tester.enterText(find.byType(TextFormField), '300');
      expect(valeur, 300);

      await tester.enterText(find.byType(TextFormField), '30a0');
      expect(valeur, 300);
    });
  });
}
