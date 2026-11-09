import 'dart:async';

import 'package:flutter/foundation.dart';

import 'moteur_synchronisation.dart';

/// Déclenche les synchronisations du poste (blueprint §3 : « à l'ouverture, toutes
/// les N secondes, après un geste, sur demande »).
///
/// | Déclencheur | Quand |
/// |---|---|
/// | **ouverture** | dès [demarrer] |
/// | **demande du serveur** | toutes les [intervalleDemande] (30 s) : `GET /sync/demande` ; une demande « synchronise maintenant » ou « renvoyer vers ce poste » (tirage complet) |
/// | **geste** | une saisie locale en attente d'envoi, [delaiGeste] après la dernière modification (temporisé : une rafale de saisies = un envoi) |
/// | **routine** | toutes les [intervalleRoutine] (5 min), pour recevoir ce que d'autres postes ont saisi |
/// | **à la demande** | [synchroniserMaintenant] (bouton) |
///
/// ## Ce qu'il ne fait pas
///
/// - **Rien tant que le poste n'est pas appairé**, et plus rien après une
///   révocation (401) : il se **suspend** jusqu'à [reprendre] (nouvel appairage).
///   Interroger un serveur qui répond 401 toutes les 30 s n'aurait aucun sens.
/// - **Hors ligne n'est pas une panne** : il réessaie au tick suivant, sans bruit.
/// - Pas de synchronisation à la fermeture (TODO(dette): la fermeture passe par
///   `windowManager.destroy()`, qu'on ne retarde pas sur un réseau incertain).
class PlanificateurSynchronisation extends ChangeNotifier {
  PlanificateurSynchronisation({
    required this.moteur,
    this.intervalleDemande = const Duration(seconds: 30),
    this.intervalleRoutine = const Duration(minutes: 5),
    this.delaiGeste = const Duration(seconds: 3),
    this.apresSynchronisation,
  });

  final MoteurSynchronisationPoste moteur;
  final Duration intervalleDemande;
  final Duration intervalleRoutine;
  final Duration delaiGeste;

  /// Appelé après chaque synchronisation (ex. recharger les modules actifs).
  final void Function(RapportSynchronisation rapport)? apresSynchronisation;

  Timer? _tickDemande;
  Timer? _tickRoutine;
  Timer? _tempoGeste;
  StreamSubscription<void>? _gestes;

  bool _demarre = false;
  bool _suspendu = false;
  bool _enCours = false;
  bool _ferme = false;
  RapportSynchronisation? _dernierRapport;
  DateTime? _derniereTentative;

  bool get enCours => _enCours;

  /// Suspendu : poste non appairé ou révoqué, en attente d'un appairage.
  bool get suspendu => _suspendu;
  RapportSynchronisation? get dernierRapport => _dernierRapport;
  DateTime? get derniereTentative => _derniereTentative;

  /// Démarre à l'ouverture de l'application. Un poste **non appairé** ne lance
  /// aucun minuteur : il n'a personne à qui parler.
  Future<void> demarrer() async {
    if (_demarre || _ferme) return;
    _demarre = true;

    final etat = await moteur.appairage.etat();
    if (_ferme) return;
    if (!etat.appaire) {
      _suspendu = true;
      notifyListeners();
      return;
    }
    _armer();
    await _lancer(); // à l'ouverture
  }

  /// Après un nouvel appairage : on repart.
  void reprendre() {
    if (_ferme) return;
    _demarre = true;
    _suspendu = false;
    _armer();
    notifyListeners();
    unawaited(_lancer());
  }

  void _armer() {
    _gestes ??= moteur.modifications.listen((_) => _surGeste());
    _tickDemande ??= Timer.periodic(
      intervalleDemande,
      (_) => _surTickDemande(),
    );
    _tickRoutine ??= Timer.periodic(intervalleRoutine, (_) => _lancer());
  }

  void _desarmer() {
    _tickDemande?.cancel();
    _tickRoutine?.cancel();
    _tempoGeste?.cancel();
    unawaited(_gestes?.cancel());
    _tickDemande = _tickRoutine = _tempoGeste = null;
    _gestes = null;
  }

  /// Bouton « Synchroniser maintenant ». Renvoie `null` si une synchronisation
  /// est déjà en cours.
  Future<RapportSynchronisation?> synchroniserMaintenant() async {
    final rapport = await _lancer(forcer: true);
    // Réussie : le poste est bien appairé, les minuteurs peuvent (re)partir.
    if (rapport != null && rapport.reussie && _suspendu) {
      _suspendu = false;
      _armer();
      notifyListeners();
    }
    return rapport;
  }

  void _surGeste() {
    _tempoGeste?.cancel();
    _tempoGeste = Timer(delaiGeste, () async {
      if (_suspendu || _enCours || _ferme) return;
      // Garde « rien à envoyer » : sans elle, la synchronisation se
      // relancerait elle-même à chaque écriture d'un accusé.
      if (await moteur.aDesSaisiesAEnvoyer()) await _lancer();
    });
  }

  Future<void> _surTickDemande() async {
    if (_suspendu || _enCours || _ferme) return;
    final demande = await moteur.interrogerDemande();
    if (_ferme) return;
    if (demande.issue == IssueSynchronisation.revoque ||
        demande.issue == IssueSynchronisation.nonAppairee) {
      _suspendre(demande.issue);
      return;
    }
    if (demande.issue != IssueSynchronisation.terminee) {
      return; // hors ligne : plus tard
    }
    if (demande.synchroniser || demande.resynchronisationComplete) {
      await _lancer(complet: demande.resynchronisationComplete);
    }
  }

  void _suspendre(IssueSynchronisation issue) {
    _suspendu = true;
    _desarmer();
    if (issue == IssueSynchronisation.revoque) {
      _dernierRapport = const RapportSynchronisation(
        IssueSynchronisation.revoque,
        'Ce poste n\'est plus appairé : le jeton a été révoqué ou a expiré. '
        'Reconnectez-vous (Paramètres > Appairage). Vos saisies sont conservées.',
      );
    }
    notifyListeners();
  }

  Future<RapportSynchronisation?> _lancer({
    bool complet = false,
    bool forcer = false,
  }) async {
    if (_enCours || _ferme || (_suspendu && !forcer)) return null;
    _enCours = true;
    _derniereTentative = DateTime.now();
    notifyListeners();
    try {
      final rapport = await moteur.synchroniser(complet: complet);
      if (_ferme) return rapport;
      _dernierRapport = rapport;

      // Le serveur ne baisse son drapeau qu'une fois le tirage complet FAIT.
      if (complet && rapport.reussie) await moteur.acquitterResynchronisation();

      if (rapport.issue == IssueSynchronisation.revoque ||
          rapport.issue == IssueSynchronisation.nonAppairee) {
        _suspendu = true;
        _desarmer();
      }
      apresSynchronisation?.call(rapport);
      return rapport;
    } finally {
      _enCours = false;
      if (!_ferme) notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_ferme) return;
    _ferme = true;
    _desarmer();
    super.dispose();
  }
}
