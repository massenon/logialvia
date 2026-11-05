import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/administration/data/repositories/auth_repository_drift.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/seed/admin_seeder.dart';
import 'package:logialvia_app/administration/data/seed/seed_demonstration.dart';
import 'package:logialvia_app/administration/domain/usecases/connecter_utilisateur_usecase.dart';
import 'package:logialvia_app/administration/presentation/viewmodels/auth_view_model.dart';
import 'package:logialvia_app/administration/presentation/viewmodels/modules_actifs_view_model.dart';
import 'package:logialvia_app/administration/data/repositories/modules_actifs_repository_drift.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/pilotage/data/repositories/tableau_bord_repository_drift.dart';
import 'package:logialvia_app/pilotage/presentation/viewmodels/alertes_view_model.dart';
import 'package:logialvia_app/pilotage/presentation/viewmodels/dashboard_elevage_view_model.dart';
import 'package:logialvia_app/pilotage/presentation/viewmodels/tableau_bord_view_model.dart';
import 'package:provider/provider.dart';

// Les 31 ecrans, dans l'ordre de la barre laterale.
import 'package:logialvia_app/administration/presentation/screens/compte/pages_compte.dart';
import 'package:logialvia_app/administration/presentation/screens/parametres_generaux_screen.dart';
import 'package:logialvia_app/approvisionnement/presentation/screens/pages_approvisionnement.dart';
import 'package:logialvia_app/commercial/presentation/screens/catalogue_screen.dart';
import 'package:logialvia_app/commercial/presentation/screens/clients_screen.dart';
import 'package:logialvia_app/commercial/presentation/screens/ventes_screen.dart';
import 'package:logialvia_app/comptabilite/presentation/screens/pages_comptabilite.dart';
import 'package:logialvia_app/elevage/presentation/screens/cycle_couveuse_screen.dart';
import 'package:logialvia_app/elevage/presentation/screens/page_fiche_espece.dart';
import 'package:logialvia_app/elevage/presentation/screens/page_poulets_pondeuses.dart';
import 'package:logialvia_app/elevage/presentation/screens/parametres_elevage_screen.dart';
import 'package:logialvia_app/elevage/presentation/screens/soins_calendrier_screen.dart';
import 'package:logialvia_app/elevage/presentation/screens/statistiques_mirages_screen.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/pilotage/presentation/screens/dashboard_elevage_screen.dart';
import 'package:logialvia_app/pilotage/presentation/screens/dashboard_screen.dart';
import 'package:logialvia_app/rapports/presentation/screens/inventaire_screen.dart';
import 'package:logialvia_app/rapports/presentation/screens/rapports_exports_screen.dart';

/// Le parcours réel : **tous les écrans, avec un mois de données**.
///
/// ## Pourquoi ce fichier existe
///
/// Jusqu'ici, les écrans étaient montés sur une base quasi vide. Or un tableau
/// vide ne déborde jamais, un KPI sans données affiche « — » et ne révèle ni un
/// format cassé ni une somme fausse. Les trois vrais défauts trouvés sur ce
/// projet — un `RenderFlex overflowed` de 4,2 px dans une colonne d'actions, une
/// base qui ne démarrait plus, un descripteur de fichier laissé ouvert — sont
/// **tous** venus de l'exécution, aucun d'une relecture.
///
/// Ces tests peuplent donc un mois d'activité par les **vrais chemins
/// d'écriture**, puis montent chaque écran à une taille de fenêtre réaliste et
/// vérifient qu'aucune exception n'est levée. Une exception de rendu fait
/// échouer le test ; elle ne se contente plus d'un carré rouge que personne ne
/// regarde en développement.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late AppDatabase db;
  late AuthViewModel auth;
  late ModulesActifsViewModel modules;
  late TableauBordRepositoryDrift tableauBord;
  late EventBus bus;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    await AdminSeeder(db).executer();

    // Un mois d'activite, ecrit comme l'application l'ecrirait.
    await SeedDemonstration(db).executer(jusqua: DateTime(2026, 8, 20));

    final depot = AuthRepositoryDrift(db);
    auth = AuthViewModel(
      ConnecterUtilisateurUseCase(depot),
      depot,
      PreferencesPosteRepository(db),
    );
    await auth.seConnecter(identifiant: 'admin', motDePasse: 'ALLMANY2026');

    modules = ModulesActifsViewModel(ModulesActifsRepositoryDrift(db));
    await modules.charger();

    tableauBord = TableauBordRepositoryDrift(db);
    bus = EventBus();
  });

  tearDown(() async {
    auth.dispose();
    modules.dispose();
    await db.close();
  });

  /// Monte un écran dans une fenêtre de la taille réelle du poste.
  ///
  /// 1382 × 794 est le viewport logique mesuré sur l'écran de la Gérante
  /// (Doc E8) : c'est là que les débordements se produisent, pas dans une
  /// fenêtre de test complaisante.
  Future<void> afficher(WidgetTester tester, Widget ecran) async {
    await tester.binding.setSurfaceSize(const Size(1382, 794));
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
        home: MultiProvider(
          // Les memes fournisseurs globaux que `main.dart` : un ecran qui a
          // besoin d'un ViewModel partage doit le trouver ici comme dans
          // l'application, sinon on testerait un montage qui n'existe pas.
          providers: [
            Provider<AppDatabase>.value(value: db),
            Provider<EventBus>.value(value: bus),
            ChangeNotifierProvider<AuthViewModel>.value(value: auth),
            ChangeNotifierProvider<ModulesActifsViewModel>.value(
              value: modules,
            ),
            ChangeNotifierProvider<AlertesViewModel>(
              create: (_) => AlertesViewModel(tableauBord),
            ),
            ChangeNotifierProvider<TableauBordViewModel>(
              create: (_) => TableauBordViewModel(tableauBord),
            ),
            ChangeNotifierProvider<DashboardElevageViewModel>(
              create: (_) => DashboardElevageViewModel(tableauBord),
            ),
          ],
          child: Scaffold(body: ecran),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Monte l'écran et exige qu'aucune exception n'ait été levée.
  Future<void> verifier(WidgetTester tester, Widget ecran, String nom) async {
    await afficher(tester, ecran);
    final exception = tester.takeException();
    expect(
      exception,
      isNull,
      reason:
          'L\'écran « $nom » lève $exception avec un mois de données. '
          'Il se comportait bien sur une base vide.',
    );
  }

  group('Pilotage', () {
    testWidgets(
      'Tableau de Bord',
      (t) => verifier(t, const DashboardScreen(), 'Tableau de Bord'),
    );
    testWidgets(
      'Dashboard Élevage',
      (t) => verifier(t, const DashboardElevageScreen(), 'Dashboard Élevage'),
    );
  });

  group('Élevage', () {
    testWidgets(
      'Cycle Couveuse',
      (t) => verifier(t, const PageCycleCouveuse(), 'Cycle Couveuse'),
    );
    testWidgets(
      'Statistiques Mirages',
      (t) =>
          verifier(t, const PageStatistiquesMirages(), 'Statistiques Mirages'),
    );
    testWidgets(
      'Soins & Calendrier',
      (t) => verifier(t, const PageSoinsCalendrier(), 'Soins & Calendrier'),
    );
    testWidgets(
      'Paramètres Élevage',
      (t) => verifier(t, const PageParametresElevage(), 'Paramètres Élevage'),
    );

    testWidgets(
      'Fiche Goliaths',
      (t) => verifier(
        t,
        const PageFicheEspece(configuration: ConfigurationsEspeces.goliaths),
        'Fiche Goliaths',
      ),
    );
    testWidgets(
      'Fiche Pintades',
      (t) => verifier(
        t,
        const PageFicheEspece(configuration: ConfigurationsEspeces.pintades),
        'Fiche Pintades',
      ),
    );
    testWidgets(
      'Fiche Lapins',
      (t) => verifier(
        t,
        const PageFicheEspece(configuration: ConfigurationsEspeces.lapins),
        'Fiche Lapins',
      ),
    );
    testWidgets(
      'Fiche Poissons-Chats',
      (t) => verifier(
        t,
        const PageFicheEspece(
          configuration: ConfigurationsEspeces.poissonsChats,
        ),
        'Fiche Poissons-Chats',
      ),
    );
    testWidgets(
      'Fiche Poulets/Pondeuses',
      (t) =>
          verifier(t, const PagePouletsPondeuses(), 'Fiche Poulets/Pondeuses'),
    );
  });

  group('Commercial', () {
    testWidgets('Ventes', (t) => verifier(t, const PageVentes(), 'Ventes'));
    testWidgets(
      'Clients et Créances',
      (t) => verifier(t, const PageClients(), 'Clients'),
    );
    testWidgets(
      'Catalogue',
      (t) => verifier(t, const PageCatalogue(), 'Catalogue'),
    );
  });

  group('Approvisionnement', () {
    testWidgets(
      'Achats & Commandes',
      (t) => verifier(t, const PageAchats(), 'Achats'),
    );
    testWidgets(
      'Fournisseurs',
      (t) => verifier(t, const PageFournisseurs(), 'Fournisseurs'),
    );
    testWidgets(
      'Gestion des Stocks',
      (t) => verifier(t, const PageGestionStocks(), 'Stocks'),
    );
  });

  group('Comptabilité', () {
    testWidgets(
      'Hub',
      (t) => verifier(t, const PageComptabiliteHub(), 'Hub Comptabilité'),
    );
    testWidgets(
      'Journal',
      (t) => verifier(t, const PageJournalComptable(), 'Journal'),
    );
    testWidgets(
      'Grand Livre',
      (t) => verifier(t, const PageGrandLivre(), 'Grand Livre'),
    );
    testWidgets(
      'Balance',
      (t) => verifier(t, const PageBalanceGenerale(), 'Balance'),
    );
    testWidgets(
      'Plan Comptable',
      (t) => verifier(t, const PagePlanComptable(), 'Plan Comptable'),
    );
    testWidgets(
      'Saisie Dépenses',
      (t) => verifier(t, const PageSaisieDepenses(), 'Saisie Dépenses'),
    );
    testWidgets(
      'Analytique',
      (t) => verifier(t, const PageComptabiliteAnalytique(), 'Analytique'),
    );
    testWidgets(
      'États Financiers',
      (t) => verifier(t, const PageEtatsFinanciers(), 'États Financiers'),
    );
    testWidgets(
      'Bilan',
      (t) => verifier(t, const PageBilanEntreprise(), 'Bilan'),
    );
    testWidgets(
      'Clôture',
      (t) => verifier(t, const PageClotureExercice(), 'Clôture'),
    );
  });

  group('Rapports', () {
    testWidgets(
      'Rapports & Exports',
      (t) => verifier(t, const PageRapports(), 'Rapports'),
    );
    testWidgets(
      'Inventaire',
      (t) => verifier(t, const PageInventaire(), 'Inventaire'),
    );
  });

  group('Compte et paramètres', () {
    testWidgets(
      'Paramètres Généraux',
      (t) => verifier(t, const PageParametresGeneraux(), 'Paramètres Généraux'),
    );
    testWidgets(
      'Mon Profil',
      (t) => verifier(t, const PageMonProfil(), 'Mon Profil'),
    );
    testWidgets(
      'Aide & À Propos',
      (t) => verifier(t, const PageAideAPropos(), 'Aide'),
    );
    testWidgets(
      'Contact Éditeur',
      (t) => verifier(t, const PageContactEditeur(), 'Contact'),
    );
  });
}
