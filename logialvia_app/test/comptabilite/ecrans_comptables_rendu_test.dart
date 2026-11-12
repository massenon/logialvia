import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/administration/data/repositories/auth_repository_drift.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/seed/admin_seeder.dart';
import 'package:logialvia_app/administration/domain/usecases/connecter_utilisateur_usecase.dart';
import 'package:logialvia_app/administration/presentation/viewmodels/auth_view_model.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/comptabilite/domain/entities/comptabilite.dart';
import 'package:logialvia_app/comptabilite/presentation/screens/balance_generale_screen.dart';
import 'package:logialvia_app/comptabilite/presentation/screens/bilan_entreprise_screen.dart';
import 'package:logialvia_app/comptabilite/presentation/screens/cloture_exercice_screen.dart';
import 'package:logialvia_app/comptabilite/presentation/screens/grand_livre_screen.dart';
import 'package:logialvia_app/comptabilite/presentation/screens/journal_comptable_screen.dart';
import 'package:logialvia_app/comptabilite/presentation/viewmodels/comptabilite_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/widgets/carte_kpi_lisere.dart';
import 'package:provider/provider.dart';

/// Rendu réel des écrans comptables.
///
/// ⚠️ Quatre d'entre eux levaient `BoxConstraints forces an infinite height` à
/// **chaque** affichage : leurs cartes KPI dessinaient le liseré d'accent avec
/// un `Container(width: 4)` dans un `Row(crossAxisAlignment: stretch)`. Dans
/// une colonne défilante, la hauteur disponible est infinie.
///
/// Le motif avait été recopié six fois. Ces tests montent chaque écran pour de
/// bon : une exception de rendu fait échouer le test, elle ne se contente plus
/// d'un carré rouge que personne ne regarde.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late AppDatabase db;
  late ComptabiliteViewModel vm;
  late AuthViewModel auth;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    await AdminSeeder(db).executer();
    vm = ComptabiliteViewModel(ComptabiliteRepositoryDrift(db));
    await vm.charger();

    // La Cloture d'Exercice lit la session : la decloture est reservee a
    // l'administratrice (BR-CPT-006).
    final depot = AuthRepositoryDrift(db);
    auth = AuthViewModel(
      ConnecterUtilisateurUseCase(depot),
      depot,
      PreferencesPosteRepository(db),
    );
    await auth.seConnecter(identifiant: 'admin', motDePasse: 'ALLMANY2026');
  });

  tearDown(() async {
    vm.dispose();
    auth.dispose();
    await db.close();
  });

  Future<void> afficher(WidgetTester tester, Widget ecran) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<ComptabiliteViewModel>.value(value: vm),
            ChangeNotifierProvider<AuthViewModel>.value(value: auth),
          ],
          child: Scaffold(body: ecran),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Enregistre une dépense, pour que les écrans aient de la matière : un
  /// écran vide ne prouverait pas grand-chose.
  Future<void> saisirUneDepense() async {
    final piece = vm.prochainNumeroPiece('DEP');
    await vm.enregistrerPiece(
      date: DateTime(vm.exercice, 6, 12),
      journalCode: CodeJournal.caisse,
      numeroPiece: piece,
      lignes: const [
        LigneAEcrire(
          numeroCompte: '618',
          debit: 12000,
          credit: 0,
          libelle: 'Transport livraison',
        ),
        LigneAEcrire(
          numeroCompte: '571',
          debit: 0,
          credit: 12000,
          libelle: 'Transport livraison',
        ),
      ],
    );
  }

  group('Les écrans s\'affichent sans lever d\'exception', () {
    testWidgets('Journal Comptable', (tester) async {
      await saisirUneDepense();
      await afficher(tester, const JournalComptableScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('Journal Comptable'), findsOneWidget);
    });

    testWidgets('Journal Comptable — vide aussi', (tester) async {
      await afficher(tester, const JournalComptableScreen());
      expect(tester.takeException(), isNull);
    });

    testWidgets('Balance Générale', (tester) async {
      await saisirUneDepense();
      await afficher(tester, const BalanceGeneraleScreen());
      expect(tester.takeException(), isNull);
    });

    testWidgets('Grand Livre', (tester) async {
      await saisirUneDepense();
      await afficher(tester, const GrandLivreScreen());
      expect(tester.takeException(), isNull);
    });

    testWidgets('Clôture d\'Exercice', (tester) async {
      await saisirUneDepense();
      await afficher(tester, const ClotureExerciceScreen());
      expect(tester.takeException(), isNull);
    });

    testWidgets('Bilan de l\'Entreprise', (tester) async {
      await saisirUneDepense();
      await afficher(tester, const BilanEntrepriseScreen());
      expect(tester.takeException(), isNull);
    });
  });

  group('Les cartes KPI passent par le widget partagé', () {
    testWidgets('le Journal en affiche', (tester) async {
      await saisirUneDepense();
      await afficher(tester, const JournalComptableScreen());

      expect(
        find.byType(CarteKpiLisere),
        findsWidgets,
        reason:
            'Six copies du meme motif existaient, toutes fautives. Un widget '
            'partage est la seule facon que la correction ne se perde pas au '
            'prochain ecran.',
      );
    });

    testWidgets('le liseré ne réclame pas de hauteur infinie', (tester) async {
      await saisirUneDepense();
      await afficher(tester, const BalanceGeneraleScreen());

      // La carte doit avoir une hauteur FINIE, imposee par son contenu.
      final taille = tester.getSize(find.byType(CarteKpiLisere).first);
      expect(taille.height, greaterThan(0));
      expect(taille.height.isFinite, isTrue);
      expect(taille.height, lessThan(300));
    });
  });
}
