import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/comptabilite/presentation/screens/saisie_depenses_screen.dart';
import 'package:logialvia_app/comptabilite/presentation/viewmodels/comptabilite_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/widgets/champ_saisie_nombre.dart';
import 'package:provider/provider.dart';

/// Structure de l'écran Saisie des Dépenses — `saisie-depenses.html`.
///
/// Le formulaire y est **posé sur la page**, pas dans une modale. C'était le
/// défaut structurel signalé par la Gérante.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late AppDatabase db;
  late ComptabiliteViewModel vm;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    vm = ComptabiliteViewModel(ComptabiliteRepositoryDrift(db));
    await vm.charger();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  Future<void> afficher(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ChangeNotifierProvider<ComptabiliteViewModel>.value(
          value: vm,
          child: const Scaffold(body: SaisieDepensesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Le formulaire est sur la page, pas dans une modale', () {
    testWidgets('les 6 champs sont visibles sans aucun clic', (tester) async {
      await afficher(tester);

      for (final libelle in const [
        'DATE DE LA TRANSACTION *',
        'LIBELLÉ DE LA DÉPENSE *',
        'CATÉGORIE DE CHARGES (SYSCOHADA) *',
        'MONTANT DÉCAISSÉ (FCFA) *',
        'COMPTE DE TRÉSORERIE CRÉDITÉ *',
        'REÇU / FACTURE (PHOTO)',
      ]) {
        expect(
          find.text(libelle),
          findsOneWidget,
          reason:
              '« $libelle » doit etre visible d\'emblee : le prototype pose ce '
              'formulaire entre les KPI et la barre de filtres.',
        );
      }
    });

    testWidgets('aucun bouton n\'ouvre une modale de saisie', (tester) async {
      await afficher(tester);

      expect(
        find.widgetWithText(ElevatedButton, 'Nouvelle Dépense'),
        findsNothing,
        reason:
            'Le titre « Nouvelle Depense » est celui de la carte, pas d\'un '
            'bouton d\'ouverture.',
      );
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('le bouton de soumission porte le libellé du prototype', (
      tester,
    ) async {
      await afficher(tester);
      expect(find.text('Enregistrer la Dépense'), findsOneWidget);
    });

    testWidgets('le titre de la carte reprend celui du prototype', (
      tester,
    ) async {
      await afficher(tester);
      expect(find.text('Nouvelle Dépense'), findsOneWidget);
    });
  });

  group('Ordre des blocs — KPI, formulaire, filtres, tableau', () {
    testWidgets('le formulaire est au-dessus de la barre de filtres', (
      tester,
    ) async {
      await afficher(tester);

      final formulaire = tester.getTopLeft(find.text('Nouvelle Dépense')).dy;
      final filtres = tester.getTopLeft(find.text('Réinitialiser')).dy;
      final tableau = tester.getTopLeft(find.text('Dépenses enregistrées')).dy;

      expect(formulaire, lessThan(filtres));
      expect(filtres, lessThan(tableau));
    });

    testWidgets('les 3 KPI sont au-dessus du formulaire', (tester) async {
      await afficher(tester);

      final kpi = tester.getTopLeft(find.text('DÉPENSES DU MOIS')).dy;
      final formulaire = tester.getTopLeft(find.text('Nouvelle Dépense')).dy;

      expect(kpi, lessThan(formulaire));
      expect(find.text('CHARGES FIXES'), findsOneWidget);
      expect(find.text('CHARGES VARIABLES'), findsOneWidget);
    });

    testWidgets('l\'export PDF est dans la barre de filtres', (tester) async {
      await afficher(tester);

      final filtres = tester.getTopLeft(find.text('Réinitialiser')).dy;
      final export = tester.getTopLeft(find.text('Exporter PDF')).dy;

      expect(
        (export - filtres).abs(),
        lessThan(40),
        reason: '`ml-auto` le pousse a droite de la MEME barre.',
      );
    });
  });

  group('Hauteur des champs', () {
    test('le champ de saisie journalière suit le `h-11` du prototype', () {
      expect(
        ChampSaisieNombre.hauteurStandard,
        44,
        reason:
            'Les champs etaient en h-10 (40 px), la taille des barres de '
            'filtres. 44 px est la hauteur que le prototype donne a ses '
            'champs de formulaire.',
      );
    });
  });
}
