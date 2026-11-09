import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'administration/data/repositories/auth_repository_drift.dart';
import 'administration/domain/services/service_restauration.dart';
import 'core/database/reprise_dossier_precedent.dart';
import 'administration/domain/services/service_sauvegarde.dart';
import 'administration/data/repositories/preferences_poste_repository.dart';
import 'administration/data/sync/depot_demandes_referentiel.dart';
import 'administration/data/repositories/modules_actifs_repository_drift.dart';
import 'administration/domain/repositories/auth_repository.dart';
import 'administration/domain/usecases/connecter_utilisateur_usecase.dart';
import 'administration/presentation/viewmodels/auth_view_model.dart';
import 'administration/presentation/viewmodels/modules_actifs_view_model.dart';
import 'core/database/app_database.dart';
import 'core/database/seed/seed_initial.dart';
import 'core/events/domain_event.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'pilotage/data/repositories/tableau_bord_repository_drift.dart';
import 'pilotage/domain/repositories/tableau_bord_repository.dart';
import 'pilotage/presentation/viewmodels/alertes_view_model.dart';
import 'pilotage/presentation/viewmodels/dashboard_elevage_view_model.dart';
import 'pilotage/presentation/viewmodels/tableau_bord_view_model.dart';
import 'administration/presentation/viewmodels/splash_view_model.dart';
import 'administration/data/sync/table_modules_actifs_poste.dart';
import 'administration/data/sync/table_parametres_entreprise_poste.dart';
import 'approvisionnement/data/sync/table_achats_poste.dart';
import 'approvisionnement/data/sync/table_fournisseurs_poste.dart';
import 'commercial/data/sync/table_clients_poste.dart';
import 'commercial/data/sync/table_produits_poste.dart';
import 'commercial/data/sync/table_ventes_poste.dart';
import 'core/sync/depot_jeton_sync.dart';
import 'core/sync/moteur_synchronisation.dart';
import 'core/sync/planificateur_synchronisation.dart';
import 'core/sync/service_appairage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Doc K3 §5 : aucun appel d'initialisation SQLite specifique n'est requis ici.
  await windowManager.ensureInitialized();
  const optionsFenetre = WindowOptions(
    size: Size(1440, 900), // breakpoint xl du prototype
    minimumSize: Size(1024, 700), // breakpoint lg
    center: true,
    title: 'LogiALVIA — ALLMANY ET COMPAGNIE',
  );
  await windowManager.waitUntilReadyToShow(optionsFenetre, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // MESURE REELLE (ecran 3456x2160 a 250 %, devicePixelRatio 2,5) :
  // le viewport logique obtenu est 1382 x 794 px. La taille demandee de
  // 1440 x 900 ne tient donc pas — le bureau ne fait que 1382 x 864 px
  // logiques — et Windows la ramene a la taille de l'ecran. C'est sans
  // consequence : `xl` (1280) reste franchi, les breakpoints de Doc E8 se
  // comportent comme sur le web.
  //
  // ATTENTION en revanche a la largeur du CONTENU : 1382 − 288 (barre
  // laterale) − 48 (marges) = 1046 px. Tout code qui deciderait d'une
  // disposition sur `constraints.maxWidth` verrait 1046 et retomberait sous
  // `xl` — c'est exactement le bug corrige sur le bandeau KPI. Utiliser
  // `AppBreakpoints`, qui lit `MediaQuery` (Doc E8 §1).

  // Resolu une seule fois : `getApplicationDocumentsDirectory()` est
  // asynchrone, et l'onglet Sauvegardes ne doit pas attendre pour s'afficher.
  final documents = DossierDocuments(await getApplicationDocumentsDirectory());

  // ⚠️ AVANT toute ouverture de la base, et avant meme la restauration :
  // reprendre la base d'une installation anterieure si le dossier de donnees
  // a change de nom. Sur Windows ce dossier depend des champs CompanyName et
  // ProductName de l'executable ; les corriger deplace la base, et
  // l'application repartirait sur un fichier vide.
  final dossierBase = await getApplicationSupportDirectory();
  final repris = RepriseDossierPrecedent(
    dossierActuel: dossierBase,
    dossiersPrecedents: RepriseDossierPrecedent.emplacementsConnus(dossierBase),
  ).executer();
  if (repris != null) {
    debugPrint('Base reprise depuis ${repris.path}');
  }

  // ⚠️ AVANT toute ouverture de la base.
  //
  // Une restauration remplace le fichier de base. La faire pendant que
  // l'application le tient ouvert produirait au mieux une erreur, au pire une
  // base a moitie ecrite — sur la comptabilite d'une exploitation. Le fichier
  // choisi a donc ete mis en attente, et c'est ici qu'il est applique : avant
  // que `AppDatabase()` n'ouvre quoi que ce soit.
  final restauration = ServiceRestauration(
    dossierBase: dossierBase,
    dossierSauvegardes: ServiceSauvegarde.dossierDepuis(documents.dossier),
    versionLogiciel: AppDatabase.versionSchema,
  );
  final rapport = await restauration.appliquerSiDemandee();

  final database = AppDatabase();

  // Pas de `const` devant le widget racine : il recoit `database`, une valeur
  // determinee a l'execution (Doc K4 §1, bug "Not a constant expression"
  // reellement rencontre sur AgriERP).
  runApp(
    LogiALVIAApp(
      database: database,
      documents: documents,
      restauration: restauration,
      rapportRestauration: rapport,
    ),
  );
}

class LogiALVIAApp extends StatefulWidget {
  const LogiALVIAApp({
    super.key,
    required this.database,
    required this.documents,
    required this.restauration,
    this.rapportRestauration,
  });

  final AppDatabase database;

  /// Dossier Documents de l'utilisateur — destination des sauvegardes.
  final DossierDocuments documents;

  /// Fourni a l'onglet Sauvegardes, qui met une restauration en attente.
  final ServiceRestauration restauration;

  /// Non nul quand le demarrage vient d'appliquer une restauration : l'ecran
  /// doit le dire, sans quoi la Gerante ne saurait pas si elle a reussi.
  final RapportRestauration? rapportRestauration;

  @override
  State<LogiALVIAApp> createState() => _LogiALVIAAppState();
}

class _LogiALVIAAppState extends State<LogiALVIAApp> with WindowListener {
  late final AuthRepository _authRepository = AuthRepositoryDrift(
    widget.database,
  );
  late final TableauBordRepository _tableauBordRepository =
      TableauBordRepositoryDrift(widget.database);

  late final AuthViewModel _authViewModel = AuthViewModel(
    ConnecterUtilisateurUseCase(_authRepository),
    _authRepository,
    PreferencesPosteRepository(widget.database),
  );
  late final ModulesActifsViewModel _modulesActifsViewModel =
      ModulesActifsViewModel(ModulesActifsRepositoryDrift(widget.database));

  // --- Appairage et synchronisation (un seul moteur pour toute l'application :
  // deux tirages entrelaces se disputeraient le curseur) ---
  late final PreferencesPosteRepository _preferencesPoste =
      PreferencesPosteRepository(widget.database);
  late final ServiceAppairage _appairage = ServiceAppairage(
    preferences: _preferencesPoste,
    depot: const DepotJetonSyncSecurise(),
  );
  late final MoteurSynchronisationPoste
  _moteurSynchro = MoteurSynchronisationPoste(
    preferences: _preferencesPoste,
    depot: const DepotJetonSyncSecurise(),
    appairage: _appairage,
    // Les modifications de referentiel faites ici sont PROPOSEES au serveur.
    demandes: DepotDemandesReferentiel(widget.database),
    // Referentiels d'abord (le serveur gagne), puis les faits saisis au poste.
    // Paliers 1 a 4 de la migration UUID (DV-19) : modules, parametres, produits,
    // clients, fournisseurs, ventes, achats. Devis, factures, ecritures… suivront.
    tables: [
      TableModulesActifsPoste(widget.database),
      TableParametresEntreprisePoste(widget.database),
      TableProduitsPoste(widget.database),
      TableClientsPoste(widget.database),
      TableFournisseursPoste(widget.database),
      TableVentesPoste(widget.database),
      TableAchatsPoste(widget.database),
    ],
  );
  late final PlanificateurSynchronisation
  _planificateur = PlanificateurSynchronisation(
    moteur: _moteurSynchro,
    // La navigation depend des modules actifs : si le serveur les a changes,
    // la barre laterale doit suivre sans redemarrage.
    apresSynchronisation: (rapport) {
      if (rapport.referentielsMisAJour > 0) {
        _modulesActifsViewModel.charger();
      }
    },
  );

  /// Bus d'evenements de domaine (Doc C1 §4) — instance unique pour toute
  /// l'application.
  final EventBus _bus = EventBus();

  late final GoRouter _routeur = AppRouter.creer(
    _authViewModel,
    _modulesActifsViewModel,
  );

  @override
  void initState() {
    super.initState();
    // Sans effet (aucun minuteur) tant que le poste n'est pas appaire.
    _planificateur.demarrer();
    // La fermeture passe par nous : une derniere synchronisation, bornee a 4 s.
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true));
  }

  @override
  Future<void> onWindowClose() async {
    try {
      await _planificateur.synchroniserALaFermeture();
    } finally {
      // Quoi qu'il arrive, la fenetre se ferme : un echec de synchronisation ne
      // doit jamais empecher de quitter l'application.
      await windowManager.destroy();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    // Avant la fermeture de la base : un geste tardif ne doit pas l'ecrire.
    _planificateur.dispose();
    _authViewModel.dispose();
    _modulesActifsViewModel.dispose();
    _bus.dispose();
    widget.database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Doc K4 §5 : TOUT ViewModel utilise par plusieurs ecrans ou par une modale
    // partagee est enregistre ici, globalement — jamais localement dans un seul
    // ecran parent ("ecran rouge de la mort" a l'ouverture d'une modale).
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: widget.database),
        Provider<DossierDocuments>.value(value: widget.documents),
        Provider<ServiceRestauration>.value(value: widget.restauration),
        // `null` a tous les demarrages ordinaires. Non nul une seule fois,
        // juste apres une restauration : le Splash l'annonce, sinon la
        // Gerante n'aurait aucun moyen de savoir si elle a reussi.
        Provider<RapportRestauration?>.value(value: widget.rapportRestauration),
        Provider<EventBus>.value(value: _bus),
        Provider<ServiceAppairage>.value(value: _appairage),
        ChangeNotifierProvider<PlanificateurSynchronisation>.value(
          value: _planificateur,
        ),
        ChangeNotifierProvider<AuthViewModel>.value(value: _authViewModel),
        ChangeNotifierProvider<ModulesActifsViewModel>.value(
          value: _modulesActifsViewModel,
        ),
        ChangeNotifierProvider<SplashViewModel>(
          create: (_) => SplashViewModel(
            widget.database,
            SeedInitial(widget.database),
            _modulesActifsViewModel,
          ),
        ),
        ChangeNotifierProvider<AlertesViewModel>(
          create: (_) => AlertesViewModel(_tableauBordRepository),
        ),
        ChangeNotifierProvider<TableauBordViewModel>(
          create: (_) => TableauBordViewModel(_tableauBordRepository),
        ),
        ChangeNotifierProvider<DashboardElevageViewModel>(
          create: (_) => DashboardElevageViewModel(_tableauBordRepository),
        ),
      ],
      child: MaterialApp.router(
        title: 'LogiALVIA',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _routeur,
        // Interface integralement en francais (Doc A1 §5) : les composants
        // Material (selecteur de date, menus) doivent l'etre aussi.
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
