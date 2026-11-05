import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/administration/data/repositories/auth_repository_drift.dart';
import 'package:logialvia_app/administration/data/repositories/modules_actifs_repository_drift.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/seed/admin_seeder.dart';
import 'package:logialvia_app/administration/data/seed/seed_demonstration.dart';
import 'package:logialvia_app/administration/domain/services/service_sauvegarde.dart';
import 'package:logialvia_app/administration/domain/usecases/connecter_utilisateur_usecase.dart';
import 'package:logialvia_app/administration/presentation/screens/compte/pages_compte.dart';
import 'package:logialvia_app/administration/presentation/screens/auth/login_screen.dart';
import 'package:logialvia_app/administration/presentation/screens/parametres_generaux_screen.dart';
import 'package:logialvia_app/administration/presentation/viewmodels/auth_view_model.dart';
import 'package:logialvia_app/administration/presentation/viewmodels/modules_actifs_view_model.dart';
import 'package:logialvia_app/approvisionnement/presentation/screens/pages_approvisionnement.dart';
import 'package:logialvia_app/commercial/presentation/screens/catalogue_screen.dart';
import 'package:logialvia_app/commercial/presentation/screens/clients_screen.dart';
import 'package:logialvia_app/commercial/presentation/screens/factures_mecef_screen.dart';
import 'package:logialvia_app/commercial/presentation/screens/ventes_screen.dart';
import 'package:logialvia_app/comptabilite/presentation/screens/pages_comptabilite.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/presentation/screens/cycle_couveuse_screen.dart';
import 'package:logialvia_app/elevage/presentation/screens/page_fiche_espece.dart';
import 'package:logialvia_app/elevage/presentation/screens/page_poulets_pondeuses.dart';
import 'package:logialvia_app/elevage/presentation/screens/parametres_elevage_screen.dart';
import 'package:logialvia_app/elevage/presentation/screens/soins_calendrier_screen.dart';
import 'package:logialvia_app/elevage/presentation/screens/statistiques_mirages_screen.dart';
import 'package:logialvia_app/pilotage/data/repositories/tableau_bord_repository_drift.dart';
import 'package:logialvia_app/pilotage/presentation/screens/dashboard_elevage_screen.dart';
import 'package:logialvia_app/pilotage/presentation/screens/dashboard_screen.dart';
import 'package:logialvia_app/pilotage/presentation/viewmodels/alertes_view_model.dart';
import 'package:logialvia_app/pilotage/presentation/viewmodels/dashboard_elevage_view_model.dart';
import 'package:logialvia_app/pilotage/presentation/viewmodels/tableau_bord_view_model.dart';
import 'package:logialvia_app/rapports/presentation/screens/inventaire_screen.dart';
import 'package:logialvia_app/rapports/presentation/screens/rapports_exports_screen.dart';
import 'package:provider/provider.dart';

import 'inventaire_libelles.dart';

/// Produit une capture d'écran par écran, pour le manuel d'utilisation.
///
/// ## Pourquoi passer par un test
///
/// Une capture prise à la main est périmée à la première évolution de l'écran,
/// et personne ne s'en aperçoit avant que la Gérante ne compare le manuel à son
/// logiciel. Générées ici, elles se refont d'une commande, avec **un mois de
/// données réalistes** plutôt que des tableaux vides.
///
/// ⚠️ **Les polices d'icônes ne sont pas chargées dans un test.** Sans le
/// `FontLoader` ci-dessous, tous les pictogrammes Material Symbols sortiraient
/// en carrés vides — et le manuel montrerait une application que personne ne
/// reconnaîtrait.
///
/// Lancement : `flutter test test/manuel/captures_test.dart`
/// Sortie : `docs/manuel/captures/*.png`
/// Semer un mois de donnees passe par les vrais cas d'usage -- ventes,
/// journees d'elevage, couveuse -- et prend plusieurs minutes. Ce travail
/// tombe dans le budget du premier test, ou les 10 minutes par defaut ne
/// suffisent pas.
const Timeout _large = Timeout(Duration(minutes: 30));

void main() {
  const dossier = '../docs/manuel/captures';
  const dossierLibelles = '../docs/manuel/libelles';
  const dossierReperes = '../docs/manuel/reperes';
  // Les sauvegardes de demonstration ne doivent pas atterrir dans les
  // Documents de qui lance les tests.
  final dossierSauvegardes = Directory.systemTemp.createTempSync(
    'logialvia-manuel-',
  );

  setUpAll(() async {
    await initializeDateFormatting('fr_FR');

    // Les icones de l'application.
    //
    // Le fichier est retrouve via `.dart_tool/package_config.json` : les
    // polices d'un paquet tiers ne sont pas servies au bundle d'un test, et
    // `Isolate.resolvePackageUri` n'est pas supporte par `flutter_test`. Sans
    // elles, tous les pictogrammes sortiraient en carres vides et le manuel
    // montrerait une application que personne ne reconnaitrait.
    final config =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final paquet = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['name'] == 'material_symbols_icons');
    final racine = Uri.parse('${paquet['rootUri']}');
    final base = racine.isAbsolute
        ? File.fromUri(racine).path
        : File('.dart_tool/${racine.path}').absolute.path;
    final police = File('$base/lib/fonts/MaterialSymbolsOutlined.ttf');
    expect(
      police.existsSync(),
      isTrue,
      reason: "Police d’icones introuvable : ${police.path}",
    );
    final octets = police.readAsBytesSync();
    // La famille doit etre enregistree sous le nom **resolu** :
    // `IconData(fontPackage: 'material_symbols_icons')` fait chercher a Flutter
    // « packages/material_symbols_icons/MaterialSymbolsOutlined ». Enregistree
    // sous son nom court seulement, la police n'etait jamais trouvee et chaque
    // icone sortait en carre vide.
    for (final famille in const [
      'MaterialSymbolsOutlined',
      'packages/material_symbols_icons/MaterialSymbolsOutlined',
    ]) {
      await (FontLoader(
        famille,
      )..addFont(Future.value(ByteData.view(octets.buffer)))).load();
    }

    // Les icones Material « classiques » (`Icons.close`, le chevron d'une
    // liste deroulante) viennent d'une **autre** police que Material Symbols :
    // MaterialIcons, livree avec le SDK Flutter et pas davantage chargee dans
    // un test. Sans elle, la croix de fermeture des modales sortait en carre.
    // Le chemin est cherche en remontant depuis l'executable de test plutot
    // que reconstruit : la profondeur de `flutter_tester.exe` dans le cache a
    // deja change d'une version du SDK a l'autre.
    File? icones;
    var remontee = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 6 && icones == null; i++) {
      final candidat = Directory('${remontee.path}/material_fonts');
      if (candidat.existsSync()) {
        icones = candidat
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().contains('materialicons'))
            .where((f) => f.path.toLowerCase().endsWith('.otf'))
            .firstOrNull;
      }
      remontee = remontee.parent;
    }
    if (icones != null && icones.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.view(icones.readAsBytesSync().buffer)),
          ))
          .load();
    }

    // NB : le tableau de bord salue l'utilisatrice avec un emoji. Windows le
    // rend avec sa police systeme, l'environnement de test n'en a aucune --
    // d'ou le carre vide sur cette seule capture. Enregistrer seguiemj.ttf
    // dans la famille « Roboto » a ete essaye : Skia n'y recourt pas en
    // repli. L'ecran reel, lui, affiche bien la main.
    final roboto = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Variable.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Italic-Variable.ttf'));
    await roboto.load();

    Directory(dossier).createSync(recursive: true);
    dossierSauvegardes.createSync(recursive: true);
  });

  late AppDatabase db;
  late AuthViewModel auth;
  late ModulesActifsViewModel modules;
  late TableauBordRepositoryDrift tableauBord;
  late EventBus bus;

  // Une seule base, semee une seule fois : ces 33 tests ne font que **lire**
  // pour photographier l'ecran. Re-semer un mois complet avant chacun coutait
  // une trentaine de minutes pour un resultat identique.
  setUpAll(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    await AdminSeeder(db).executer();
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

  tearDownAll(() async {
    auth.dispose();
    modules.dispose();
    await db.close();
  });

  final cle = GlobalKey();
  final cleEcran = GlobalKey();

  Future<void> capturer(
    WidgetTester tester,
    Widget ecran,
    String fichier, {
    String? onglet,
    String? modale,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1382, 794));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      // Deux limites de rendu, et le choix se fait a la prise de vue.
      //
      // Une modale vit dans l'Overlay du Navigator, au-dessus du Scaffold :
      // pour la photographier il faut envelopper toute l'application. Mais
      // certains ecrans ouvrent un rappel d'eux-memes -- le Tableau de Bord et
      // ses deux popups -- et leur capture d'ecran doit rester nette. La limite
      // interieure les ignore.
      RepaintBoundary(
        key: cle,
        child: MaterialApp(
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MultiProvider(
            providers: [
              Provider<AppDatabase>.value(value: db),
              // L'onglet Sauvegardes lit le disque : sans ce fournisseur, son
              // ViewModel ne se construit pas et l'ecran ne s'affiche pas.
              Provider<DossierDocuments>.value(
                value: DossierDocuments(dossierSauvegardes),
              ),
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
            child: RepaintBoundary(
              key: cleEcran,
              child: Scaffold(body: ecran),
            ),
          ),
        ),
      ),
    );
    // Surtout pas `pumpAndSettle` : son premier argument est l'**intervalle**
    // entre deux frames, pas un delai maximal. Un ecran qui anime en continu
    // -- une barre de progression, un degrade qui pulse -- ne cesse jamais de
    // programmer des frames, et la methode tournait jusqu'a epuiser son budget
    // de dix minutes. Trente-trois ecrans faisaient cinq heures.
    //
    // Une douzaine de frames espacees suffisent : chacune rend la main a la
    // boucle d'evenements, ce qui laisse les lectures en base se resoudre.
    // Deux frames, puis une vraie pause, puis les frames de rendu.
    //
    // Certains chargements traversent le **vrai** temps et non celui, simule,
    // du test : le magasin securise du systeme, le disque. Sans cette pause,
    // leurs ecrans etaient photographies sur leur rond de chargement.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // Sept ecrans ont des onglets internes. Sans ce clic, le manuel ne
    // montrerait jamais que le premier -- ni les Sauvegardes, ni la Corbeille,
    // ni le Compte de Resultat.
    if (onglet != null) {
      final cible = find.text(onglet);
      expect(
        cible,
        findsWidgets,
        reason: 'Onglet « $onglet » introuvable sur la capture $fichier.',
      );
      await tester.tap(cible.first, warnIfMissed: false);
      // Deux frames d'abord : c'est en s'affichant que l'onglet construit son
      // ViewModel et lance son chargement.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      // Puis une vraie pause : l'onglet Sauvegardes lit le disque, et son
      // chargement se resout dans le **vrai** temps, pas dans celui, simule,
      // du test. Sans elle, sa capture montrait un rond de chargement sur un
      // ecran vide.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    // Les modales : le manuel doit les montrer, ce sont elles qui portent la
    // saisie. Le declencheur est designe par son libelle exact -- si le bouton
    // est renomme sans que le manuel suive, la capture echoue au lieu de
    // montrer un ecran sans rapport.
    if (modale != null) {
      final declencheur = find.text(modale);
      expect(
        declencheur,
        findsWidgets,
        reason: 'Declencheur « $modale » introuvable pour la capture $fichier.',
      );
      await tester.tap(declencheur.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    // L'ecran est monte, charge et l'onglet demande est ouvert : c'est le
    // moment ou son arbre porte exactement ce que l'utilisatrice voit.
    ecrireInventaire(relever(tester, fichier), dossierLibelles);
    // Les rectangles des cibles de visite guidee : ce sont eux qui placeront
    // les reperes numerotes sur la capture, au pixel pres.
    ecrireReperes(
      fichier,
      releverReperes(tester, const Size(1382, 794)),
      dossierReperes,
    );

    final limite =
        (modale == null ? cleEcran : cle).currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    // ×2 : le manuel est lu à l'écran comme imprimé, une capture à l'échelle 1
    // devient illisible dès qu'on l'agrandit.
    // `toImage` et `toByteData` passent par le moteur de rendu, hors du temps
    // simule du test. Appelees directement, leurs futures ne se resolvent qu'au
    // rythme ou la machinerie de timeout reveille la boucle : chaque capture
    // prenait plus de dix minutes pour un travail d'une fraction de seconde.
    // `runAsync` rend la main au vrai temps le temps de l'encodage.
    final octets = await tester.runAsync(() async {
      final image = await limite.toImage(pixelRatio: 2);
      final donnees = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return donnees!.buffer.asUint8List();
    });
    File('$dossier/$fichier.png').writeAsBytesSync(octets!);
  }

  // L'ecran de connexion : premier contact avec le logiciel, et seul ecran du
  // chapitre « Prise en main » a montrer avant la barre laterale.
  testWidgets(
    '00 connexion',
    (t) => capturer(t, const LoginScreen(), '00-connexion'),
    timeout: _large,
  );
  testWidgets(
    '01 tableau de bord',
    (t) => capturer(t, const DashboardScreen(), '01-tableau-de-bord'),
    timeout: _large,
  );
  testWidgets(
    '02 dashboard élevage',
    (t) => capturer(t, const DashboardElevageScreen(), '02-dashboard-elevage'),
    timeout: _large,
  );
  testWidgets(
    '03 cycle couveuse',
    (t) => capturer(t, const PageCycleCouveuse(), '03-cycle-couveuse'),
    timeout: _large,
  );
  testWidgets(
    '04 mirages',
    (t) =>
        capturer(t, const PageStatistiquesMirages(), '04-statistiques-mirages'),
    timeout: _large,
  );
  testWidgets(
    '05 fiche goliaths',
    (t) => capturer(
      t,
      const PageFicheEspece(configuration: ConfigurationsEspeces.goliaths),
      '05-fiche-goliaths',
    ),
    timeout: _large,
  );
  testWidgets(
    '06 fiche pintades',
    (t) => capturer(
      t,
      const PageFicheEspece(configuration: ConfigurationsEspeces.pintades),
      '06-fiche-pintades',
    ),
    timeout: _large,
  );
  testWidgets(
    '07 fiche lapins',
    (t) => capturer(
      t,
      const PageFicheEspece(configuration: ConfigurationsEspeces.lapins),
      '07-fiche-lapins',
    ),
    timeout: _large,
  );
  testWidgets(
    '08 fiche poissons-chats',
    (t) => capturer(
      t,
      const PageFicheEspece(configuration: ConfigurationsEspeces.poissonsChats),
      '08-fiche-poissons-chats',
    ),
    timeout: _large,
  );
  testWidgets(
    '09 fiche poulets pondeuses',
    (t) =>
        capturer(t, const PagePouletsPondeuses(), '09-fiche-poulets-pondeuses'),
    timeout: _large,
  );
  testWidgets(
    '10 soins',
    (t) => capturer(t, const PageSoinsCalendrier(), '10-soins-calendrier'),
    timeout: _large,
  );
  testWidgets(
    '11 paramètres élevage',
    (t) => capturer(t, const PageParametresElevage(), '11-parametres-elevage'),
    timeout: _large,
  );
  testWidgets(
    '12 ventes',
    (t) => capturer(t, const PageVentes(), '12-ventes'),
    timeout: _large,
  );
  testWidgets(
    '13 clients',
    (t) => capturer(t, const PageClients(), '13-clients'),
    timeout: _large,
  );
  testWidgets(
    '14b factures mecef',
    (t) => capturer(t, const PageFacturesMecef(), '14b-factures-mecef'),
    timeout: _large,
  );
  testWidgets(
    '14 inventaire',
    (t) => capturer(t, const PageInventaire(), '14-inventaire'),
    timeout: _large,
  );
  testWidgets(
    '15 achats',
    (t) => capturer(t, const PageAchats(), '15-achats'),
    timeout: _large,
  );
  testWidgets(
    '16 fournisseurs',
    (t) => capturer(t, const PageFournisseurs(), '16-fournisseurs'),
    timeout: _large,
  );
  testWidgets(
    '17 stocks',
    (t) => capturer(t, const PageGestionStocks(), '17-gestion-stocks'),
    timeout: _large,
  );
  testWidgets(
    '18 catalogue',
    (t) => capturer(t, const PageCatalogue(), '18-catalogue'),
    timeout: _large,
  );
  testWidgets(
    '19 comptabilité',
    (t) => capturer(t, const PageComptabiliteHub(), '19-comptabilite-hub'),
    timeout: _large,
  );
  testWidgets(
    '20 journal',
    (t) => capturer(t, const PageJournalComptable(), '20-journal-comptable'),
    timeout: _large,
  );
  testWidgets(
    '21 grand livre',
    (t) => capturer(t, const PageGrandLivre(), '21-grand-livre'),
    timeout: _large,
  );
  testWidgets(
    '22 balance',
    (t) => capturer(t, const PageBalanceGenerale(), '22-balance-generale'),
    timeout: _large,
  );
  testWidgets(
    '23 plan comptable',
    (t) => capturer(t, const PagePlanComptable(), '23-plan-comptable'),
    timeout: _large,
  );
  testWidgets(
    '24 dépenses',
    (t) => capturer(t, const PageSaisieDepenses(), '24-saisie-depenses'),
    timeout: _large,
  );
  testWidgets(
    '25 analytique',
    (t) => capturer(
      t,
      const PageComptabiliteAnalytique(),
      '25-comptabilite-analytique',
    ),
    timeout: _large,
  );
  testWidgets(
    '26 états financiers',
    (t) => capturer(t, const PageEtatsFinanciers(), '26-etats-financiers'),
    timeout: _large,
  );
  testWidgets(
    '27 bilan',
    (t) => capturer(t, const PageBilanEntreprise(), '27-bilan-entreprise'),
    timeout: _large,
  );
  testWidgets(
    '28 clôture',
    (t) => capturer(t, const PageClotureExercice(), '28-cloture-exercice'),
    timeout: _large,
  );
  testWidgets(
    '29 rapports',
    (t) => capturer(t, const PageRapports(), '29-rapports-exports'),
    timeout: _large,
  );
  testWidgets(
    '30 paramètres généraux',
    (t) =>
        capturer(t, const PageParametresGeneraux(), '30-parametres-generaux'),
    timeout: _large,
  );
  testWidgets(
    '31 mon profil',
    (t) => capturer(t, const PageMonProfil(), '31-mon-profil'),
    timeout: _large,
  );
  testWidgets(
    '32 aide',
    (t) => capturer(t, const PageAideAPropos(), '32-aide-a-propos'),
    timeout: _large,
  );
  testWidgets(
    '33 contact',
    (t) => capturer(t, const PageContactEditeur(), '33-contact-editeur'),
    timeout: _large,
  );

  // ------------------------------------------------------- les modales
  //
  // Ce sont elles qui portent la saisie : un manuel qui montre l ecran
  // sans montrer la modale ne montre pas le geste.
  testWidgets(
    'M01 couveuse - nouveau cycle',
    (t) => capturer(
      t,
      const PageCycleCouveuse(),
      'm01-couveuse-nouveau-cycle',
      modale: 'Déclarer un Nouveau Cycle',
    ),
    timeout: _large,
  );
  testWidgets(
    'M02 couveuse - ajouter incubateur',
    (t) => capturer(
      t,
      const PageCycleCouveuse(),
      'm02-couveuse-incubateur',
      modale: 'Ajouter un Incubateur',
    ),
    timeout: _large,
  );
  testWidgets(
    'M03 soins - nouveau soin',
    (t) => capturer(
      t,
      const PageSoinsCalendrier(),
      'm03-soins-nouveau',
      modale: 'Nouveau Soin',
    ),
    timeout: _large,
  );
  testWidgets(
    'M04 soins - planifier intervention',
    (t) => capturer(
      t,
      const PageSoinsCalendrier(),
      'm04-soins-planifier',
      onglet: 'Calendrier des Doses',
      modale: 'Planifier une Intervention',
    ),
    timeout: _large,
  );
  testWidgets(
    'M05 stocks - ajouter intrant',
    (t) => capturer(
      t,
      const PageGestionStocks(),
      'm05-stocks-intrant',
      modale: 'Ajouter un Intrant',
    ),
    timeout: _large,
  );
  testWidgets(
    'M06 stocks - fabrication provende',
    (t) => capturer(
      t,
      const PageGestionStocks(),
      'm06-stocks-provende',
      modale: 'Fabrication de Provende',
    ),
    timeout: _large,
  );
  testWidgets(
    'M07 catalogue - ajouter produit',
    (t) => capturer(
      t,
      const PageCatalogue(),
      'm07-catalogue-produit',
      modale: 'Ajouter un Produit',
    ),
    timeout: _large,
  );
  testWidgets(
    'M08 clients - ajouter client',
    (t) => capturer(
      t,
      const PageClients(),
      'm08-clients-ajouter',
      modale: 'Ajouter un Client',
    ),
    timeout: _large,
  );
  testWidgets(
    'M09 fournisseurs - ajouter',
    (t) => capturer(
      t,
      const PageFournisseurs(),
      'm09-fournisseurs-ajouter',
      modale: 'Ajouter un Fournisseur',
    ),
    timeout: _large,
  );
  testWidgets(
    'M10 mecef - emettre facture',
    (t) => capturer(
      t,
      const PageFacturesMecef(),
      'm10-mecef-emettre',
      modale: 'Émettre une Facture',
    ),
    timeout: _large,
  );

  // ------------------------------------------------ onglets internes
  //
  // Sept ecrans ont des onglets ; seul le premier de chacun etait
  // photographie. Les 23 suivants completent le manuel.
  testWidgets(
    '09b poulets/pondeuses - pondeuses',
    (t) => capturer(
      t,
      const PagePouletsPondeuses(),
      '09b-fiche-poulets-pondeuses-pondeuses',
      onglet: 'Pondeuses',
    ),
    timeout: _large,
  );
  testWidgets(
    '10b soins - calendrier des doses',
    (t) => capturer(
      t,
      const PageSoinsCalendrier(),
      '10b-soins-calendrier-doses',
      onglet: 'Calendrier des Doses',
    ),
    timeout: _large,
  );
  testWidgets(
    '10c soins - suivi infirmerie',
    (t) => capturer(
      t,
      const PageSoinsCalendrier(),
      '10c-soins-infirmerie',
      onglet: 'Suivi Infirmerie',
    ),
    timeout: _large,
  );
  testWidgets(
    '11b parametres elevage - prophylaxie',
    (t) => capturer(
      t,
      const PageParametresElevage(),
      '11b-parametres-elevage-prophylaxie',
      onglet: 'Calendriers Prophylaxie',
    ),
    timeout: _large,
  );
  testWidgets(
    '11c parametres elevage - intrants provende',
    (t) => capturer(
      t,
      const PageParametresElevage(),
      '11c-parametres-elevage-provende',
      onglet: 'Intrants de Provende',
    ),
    timeout: _large,
  );
  testWidgets(
    '11d parametres elevage - numerotation',
    (t) => capturer(
      t,
      const PageParametresElevage(),
      '11d-parametres-elevage-numerotation',
      onglet: 'Numérotation Bandes & Sujets',
    ),
    timeout: _large,
  );
  testWidgets(
    '12b ventes - devis',
    (t) => capturer(
      t,
      const PageVentes(),
      '12b-ventes-devis',
      onglet: 'Devis Prestations',
    ),
    timeout: _large,
  );
  testWidgets(
    '12c ventes - historique',
    (t) => capturer(
      t,
      const PageVentes(),
      '12c-ventes-historique',
      onglet: 'Historique des Ventes',
    ),
    timeout: _large,
  );
  testWidgets(
    '12d ventes - retours',
    (t) => capturer(
      t,
      const PageVentes(),
      '12d-ventes-retours',
      onglet: 'Retours et Avoirs',
    ),
    timeout: _large,
  );
  testWidgets(
    '26b etats financiers - compte de resultat',
    (t) => capturer(
      t,
      const PageEtatsFinanciers(),
      '26b-etats-financiers-resultat',
      onglet: 'Compte de Résultat',
    ),
    timeout: _large,
  );
  testWidgets(
    '26c etats financiers - tresorerie',
    (t) => capturer(
      t,
      const PageEtatsFinanciers(),
      '26c-etats-financiers-tresorerie',
      onglet: 'Flux de Trésorerie',
    ),
    timeout: _large,
  );
  testWidgets(
    '26d etats financiers - notes annexes',
    (t) => capturer(
      t,
      const PageEtatsFinanciers(),
      '26d-etats-financiers-notes',
      onglet: 'Notes Annexes',
    ),
    timeout: _large,
  );
  testWidgets(
    '29b rapports - tresorerie',
    (t) => capturer(
      t,
      const PageRapports(),
      '29b-rapports-tresorerie',
      onglet: 'État de Trésorerie',
    ),
    timeout: _large,
  );
  testWidgets(
    '29c rapports - creances',
    (t) => capturer(
      t,
      const PageRapports(),
      '29c-rapports-creances',
      onglet: 'Créances Clients',
    ),
    timeout: _large,
  );
  testWidgets(
    '29d rapports - dettes',
    (t) => capturer(
      t,
      const PageRapports(),
      '29d-rapports-dettes',
      onglet: 'Dettes Fournisseurs',
    ),
    timeout: _large,
  );
  testWidgets(
    '29e rapports - elevage',
    (t) => capturer(
      t,
      const PageRapports(),
      '29e-rapports-elevage',
      onglet: 'Rapport Élevage',
    ),
    timeout: _large,
  );
  testWidgets(
    '29f rapports - stocks',
    (t) => capturer(
      t,
      const PageRapports(),
      '29f-rapports-stocks',
      onglet: 'Rapport de Stocks',
    ),
    timeout: _large,
  );
  testWidgets(
    '30b parametres general - entreprise',
    (t) => capturer(
      t,
      const PageParametresGeneraux(),
      '30b-parametres-general-entreprise',
      onglet: 'Données de l\'Entreprise',
    ),
    timeout: _large,
  );
  testWidgets(
    '30c parametres general - utilisateurs',
    (t) => capturer(
      t,
      const PageParametresGeneraux(),
      '30c-parametres-general-utilisateurs',
      onglet: 'Gestion Utilisateurs',
    ),
    timeout: _large,
  );
  testWidgets(
    '30d parametres general - paiement',
    (t) => capturer(
      t,
      const PageParametresGeneraux(),
      '30d-parametres-general-paiement',
      onglet: 'Modes de Paiement',
    ),
    timeout: _large,
  );
  testWidgets(
    '30e parametres general - sauvegardes',
    (t) => capturer(
      t,
      const PageParametresGeneraux(),
      '30e-parametres-general-sauvegardes',
      onglet: 'Sauvegardes',
    ),
    timeout: _large,
  );
  testWidgets(
    '30f parametres general - corbeille',
    (t) => capturer(
      t,
      const PageParametresGeneraux(),
      '30f-parametres-general-corbeille',
      onglet: 'Corbeille',
    ),
    timeout: _large,
  );
  testWidgets(
    '30g parametres general - donnees de test',
    (t) => capturer(
      t,
      const PageParametresGeneraux(),
      '30g-parametres-general-donnees-test',
      onglet: 'Données de Test',
    ),
    timeout: _large,
  );
}
