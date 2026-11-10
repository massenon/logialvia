import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../domain/entities/session_utilisateur.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../data/repositories/preferences_poste_repository.dart';
import '../../domain/usecases/connecter_utilisateur_usecase.dart';

/// Issue d'une tentative de connexion, telle que l'ecran doit la traiter.
enum IssueConnexion {
  succes,
  champsInvalides,
  identifiantsIncorrects,
  compteVerrouille,
  erreurTechnique,
}

/// Reponse rendue a l'ecran : l'issue + le message de toast a afficher.
/// `messageToast` est nul quand le prototype n'affiche aucun toast — cas du
/// 5e echec, ou seule la banniere de verrouillage apparait (login.html l.189).
class ReponseConnexion {
  const ReponseConnexion(this.issue, {this.messageToast});

  final IssueConnexion issue;
  final String? messageToast;
}

/// Etat d'authentification de l'application — Doc F1.
///
/// Enregistre globalement dans `main.dart` (Doc K4 §5 : tout ViewModel dont une
/// modale ou plusieurs ecrans peuvent avoir besoin est global, jamais local).
class AuthViewModel extends ChangeNotifier {
  AuthViewModel(
    this._connecterUtilisateur,
    this._repository,
    this._preferences,
  );

  final ConnecterUtilisateurUseCase _connecterUtilisateur;
  final AuthRepository _repository;
  final PreferencesPosteRepository _preferences;

  /// Nombre d'echecs consecutifs avant verrouillage (login.html l.189).
  static const int nombreTentativesMax = 5;

  /// Duree du verrouillage, en secondes (login.html l.161 : `lockSeconds = 900`).
  static const int dureeVerrouillageSecondes = 900;

  SessionUtilisateur? _session;
  SessionUtilisateur? get session => _session;
  bool get estConnecte => _session != null;

  bool _connexionEnCours = false;
  bool get connexionEnCours => _connexionEnCours;

  String? _erreurIdentifiant;
  String? get erreurIdentifiant => _erreurIdentifiant;

  String? _erreurMotDePasse;
  String? get erreurMotDePasse => _erreurMotDePasse;

  bool _motDePasseMasque = true;
  bool get motDePasseMasque => _motDePasseMasque;

  bool _seSouvenirDeMoi = false;
  bool get seSouvenirDeMoi => _seSouvenirDeMoi;

  int _tentatives = 0;
  int get tentatives => _tentatives;

  bool _verrouille = false;
  bool get verrouille => _verrouille;

  /// Libelle du compteur de la banniere. Vaut "15min" avant le premier tic,
  /// puis "Mmin Ss" — exactement comme le prototype (login.html l.79 et l.205).
  String _libelleVerrouillage = '15min';
  String get libelleVerrouillage => _libelleVerrouillage;

  /// Message a afficher a l'arrivee sur l'ecran de connexion, consomme une seule
  /// fois. Equivalent de `sessionStorage.logialvia_show_logout_toast`
  /// (login.html l.217).
  String? _messageDifferePourLogin;

  Timer? _minuteurVerrouillage;
  int _secondesRestantes = dureeVerrouillageSecondes;

  void basculerVisibiliteMotDePasse() {
    _motDePasseMasque = !_motDePasseMasque;
    notifyListeners();
  }

  void definirSeSouvenirDeMoi(bool valeur) {
    _seSouvenirDeMoi = valeur;
    notifyListeners();
  }

  /// Identifiant à pré-remplir dans le champ de connexion, `null` si aucun
  /// n'a été mémorisé. Lu une fois à l'ouverture de l'écran.
  String? _identifiantMemorise;
  String? get identifiantMemorise => _identifiantMemorise;

  /// Charge la préférence du poste. À appeler à l'arrivée sur l'écran de
  /// connexion.
  ///
  /// La case reflète l'état réel : si un identifiant est mémorisé, elle est
  /// cochée. Une case décochée alors que l'identifiant revient serait un
  /// mensonge de plus.
  Future<void> chargerPreferencesConnexion() async {
    _identifiantMemorise = await _preferences.identifiantMemorise();
    _seSouvenirDeMoi = _identifiantMemorise != null;
    notifyListeners();
  }

  /// Recupere et efface le message differe (toast de deconnexion).
  String? consommerMessageDiffere() {
    final message = _messageDifferePourLogin;
    _messageDifferePourLogin = null;
    return message;
  }

  Future<ReponseConnexion> seConnecter({
    required String identifiant,
    required String motDePasse,
  }) async {
    if (_verrouille) {
      return const ReponseConnexion(IssueConnexion.compteVerrouille);
    }

    // Validation locale d'abord (Doc E6 §2) : les 2 champs sont requis, non vides.
    // Les libelles sont ceux du prototype (login.html l.89 et l.98).
    _erreurIdentifiant = identifiant.trim().isEmpty
        ? 'L\'identifiant est obligatoire.'
        : null;
    _erreurMotDePasse = motDePasse.trim().isEmpty
        ? 'Le mot de passe est obligatoire.'
        : null;

    if (_erreurIdentifiant != null || _erreurMotDePasse != null) {
      notifyListeners();
      return const ReponseConnexion(
        IssueConnexion.champsInvalides,
        messageToast: 'Veuillez renseigner tous les champs requis.',
      );
    }

    _connexionEnCours = true;
    notifyListeners();

    final resultat = await _connecterUtilisateur.executer(
      identifiant: identifiant,
      motDePasse: motDePasse,
    );

    _connexionEnCours = false;

    switch (resultat) {
      case Succes(valeur: final nouvelleSession):
        _session = nouvelleSession;
        _tentatives = 0;
        // « Se souvenir de moi » n'ecrit l'identifiant qu'apres une connexion
        // REUSSIE : memoriser un identifiant refuse le proposerait ensuite en
        // boucle a chaque lancement.
        await _preferences.memoriserIdentifiant(
          _seSouvenirDeMoi ? identifiant.trim() : null,
        );
        _identifiantMemorise = _seSouvenirDeMoi ? identifiant.trim() : null;
        notifyListeners();
        return const ReponseConnexion(
          IssueConnexion.succes,
          messageToast: 'Connexion réussie — Bienvenue !',
        );

      case Echec(message: final message):
        final identifiantsInvalides =
            message == ConnecterUtilisateurUseCase.messageIdentifiantsInvalides;
        if (!identifiantsInvalides) {
          notifyListeners();
          return ReponseConnexion(
            IssueConnexion.erreurTechnique,
            messageToast: message,
          );
        }

        // DECISION CLIENT (2026-11-10) : AUCUN verrouillage apres des echecs. Le poste est un
        // ordinateur de bureau ; bloquer la connexion empechait de travailler. Les echecs restent
        // journalises (security_logs) et comptes, mais ne bloquent jamais.
        _tentatives++;
        notifyListeners();
        return ReponseConnexion(
          IssueConnexion.identifiantsIncorrects,
          messageToast: message,
        );
    }
  }

  Future<void> seDeconnecter() async {
    final utilisateur = _session?.utilisateur;
    _session = null;
    _messageDifferePourLogin = 'Déconnexion réussie. À bientôt !';
    notifyListeners();
    if (utilisateur != null) {
      await _repository.journaliserDeconnexion(utilisateur);
    }
  }

  /// Remet a zero l'etat de saisie a l'arrivee sur l'ecran de connexion.
  /// Ne touche ni au compteur de tentatives ni au verrouillage : les reinitialiser
  /// ne change rien au compteur d'echecs (plus aucun blocage depuis la decision du 2026-11-10).
  void reinitialiserErreursSaisie() {
    if (_erreurIdentifiant == null && _erreurMotDePasse == null) return;
    _erreurIdentifiant = null;
    _erreurMotDePasse = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _minuteurVerrouillage?.cancel();
    super.dispose();
  }
}
