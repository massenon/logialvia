import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/seed/seed_initial.dart';
import 'modules_actifs_view_model.dart';

/// Ecran de demarrage — Doc F1 Ecran 1.
///
/// Verifie l'etat de l'application (base accessible, migrations a jour, compte
/// administrateur present) avant de rediriger.
class SplashViewModel extends ChangeNotifier {
  SplashViewModel(this._database, this._seed, this._modulesActifs);

  final AppDatabase _database;
  final SeedInitial _seed;
  final ModulesActifsViewModel _modulesActifs;

  /// Duree totale de l'ecran de demarrage — `setTimeout(..., 3000)` du
  /// prototype (index.html l.77).
  static const Duration dureeAffichage = Duration(seconds: 3);

  /// Cadence de rotation des messages d'etat (index.html l.66).
  static const Duration cadenceEtapes = Duration(milliseconds: 600);

  /// Messages d'etat, repris mot pour mot du prototype (index.html l.51-57).
  ///
  /// Ils defilent sur une cadence fixe, exactement comme cote web. Les etapes 3
  /// et 5 designent des chargements (couveuse, catalogue/vaccins) dont les
  /// modules n'existent pas encore — elles seront branchees sur le travail reel
  /// correspondant quand Doc F3 et Doc F5 seront implementes.
  static const List<String> etapes = [
    'Vérification de la base de données locale…',
    'Initialisation du moteur de synchronisation…',
    'Chargement des cycles de couveuse en cours…',
    'Sécurisation de l\'espace de stockage…',
    'Chargement du catalogue de stocks et de vaccins…',
  ];

  int _indexEtape = 0;
  String get etapeCourante => etapes[_indexEtape];

  String? _erreurInitialisation;
  String? get erreurInitialisation => _erreurInitialisation;

  String? _routeCible;

  /// Route a atteindre une fois l'initialisation terminee, `null` tant qu'elle
  /// est en cours ou en erreur.
  String? get routeCible => _routeCible;

  Timer? _minuteurEtapes;

  /// Initialise l'application, puis determine la route de destination.
  ///
  /// ECART_DELIBERE : Doc K4 §8 place l'appel du seeder avant `runApp()`, tandis
  /// que Doc F1 confie l'initialisation (base, migrations) au Splash. C'est le
  /// Splash qui est retenu, car l'ecran doit a la fois afficher l'avancement,
  /// router selon le resultat du seed, et afficher une erreur reelle si la base
  /// est inaccessible — ce qu'un appel avant `runApp()` ne permet pas.
  Future<void> initialiser() async {
    _demarrerRotationEtapes();

    final debut = DateTime.now();
    try {
      // 1. Ouvre reellement la base (LazyDatabase est paresseuse) et applique
      //    les migrations en attente : la premiere requete declenche les deux.
      await _database.customSelect('SELECT 1').get();

      // 2. Peuple compte administrateur, modules actifs, catalogue et intrants
      //    si la base est vierge (Doc K4 §8, Doc D1 §3).
      final resultat = await _seed.executer();
      final aSemeAdmin = resultat.compteAdminCree;

      // 2-bis. Charge l'etat des filieres activables : la barre laterale et le
      //        `redirect` du routeur en dependent des la premiere navigation
      //        (Doc I2 §3).
      await _modulesActifs.charger();

      // 3. ECART_DELIBERE : le prototype distingue le premier lancement via
      //    `localStorage.logialvia_visited` (index.html l.70). Sans equivalent
      //    localStorage en Flutter Desktop, le signal "base vierge" — c'est-a-dire
      //    le seeder qui vient de creer le compte administrateur — porte
      //    exactement la meme information, sans stockage supplementaire.
      _routeCible = aSemeAdmin ? '/welcome' : '/login';
    } catch (e) {
      // ⚠️ Le message ne DEVINE plus la cause.
      //
      // Il annonçait un probleme de droits d'acces, quoi qu'il arrive. Un
      // poste s'est retrouve bloque par une migration qui rejouait un
      // `ALTER TABLE ... ADD COLUMN` deja applique : la Gerante a cherche
      // la panne du cote des permissions du dossier, a l'oppose de sa
      // cause.
      //
      // La cause technique est donc affichee telle quelle, en plus de la
      // piste la plus probable. Sur une exploitation sans informaticien,
      // c'est cette ligne-la qu'on recopie au telephone.
      _erreurInitialisation =
          'Impossible d\'initialiser la base de données locale.\n\n'
          'Cause technique : $e\n\n'
          'Si ce message parle de droits ou d\'accès refusé, vérifiez '
          'les permissions du dossier de l\'application. Sinon, '
          'transmettez cette ligne à l\'éditeur : la base n\'est pas '
          'perdue, elle n\'a pas pu être ouverte.';
      if (kDebugMode) {
        debugPrint('Echec initialisation LogiALVIA: $e');
      }
      _arreterRotationEtapes();
      notifyListeners();
      return;
    }

    // Duree minimale d'affichage : le travail reel est generalement plus rapide
    // que les 3 s du prototype, on complete l'attente pour un rendu identique.
    final ecoule = DateTime.now().difference(debut);
    final reste = dureeAffichage - ecoule;
    if (reste > Duration.zero) {
      await Future<void>.delayed(reste);
    }

    _arreterRotationEtapes();
    notifyListeners();
  }

  /// Relance une initialisation apres un echec.
  Future<void> reessayer() async {
    _erreurInitialisation = null;
    _indexEtape = 0;
    notifyListeners();
    await initialiser();
  }

  void _demarrerRotationEtapes() {
    _minuteurEtapes?.cancel();
    _minuteurEtapes = Timer.periodic(cadenceEtapes, (_) {
      _indexEtape = (_indexEtape + 1) % etapes.length;
      notifyListeners();
    });
  }

  void _arreterRotationEtapes() {
    _minuteurEtapes?.cancel();
    _minuteurEtapes = null;
  }

  @override
  void dispose() {
    _arreterRotationEtapes();
    super.dispose();
  }
}
