import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/preferences_poste_repository.dart';

import '../../../core/sync/moteur_synchronisation.dart';
import '../../../core/sync/planificateur_synchronisation.dart';
import '../../../core/sync/service_appairage.dart';

/// État de l'onglet « Appairage » (Paramètres Généraux).
///
/// Le **mot de passe ne passe jamais ici** : l'écran le garde dans son champ de
/// saisie et le remet au service au moment de se connecter, puis le vide.
class AppairageViewModel extends ChangeNotifier {
  AppairageViewModel(this._service, [this._planificateur]) {
    _planificateur?.addListener(_surPlanificateur);
  }

  final ServiceAppairage _service;

  /// Le planificateur **global** (un seul moteur, une seule synchronisation à la
  /// fois). `null` dans les tests qui n'en ont pas besoin.
  final PlanificateurSynchronisation? _planificateur;

  /// Dernier rapport de synchronisation (réussie ou non), déclencheur quelconque.
  RapportSynchronisation? get dernierRapport => _planificateur?.dernierRapport;
  bool get synchronisationEnCours => _planificateur?.enCours ?? false;

  /// `true` si ce ViewModel sait synchroniser.
  bool get peutSynchroniser => _planificateur != null;

  Future<void> synchroniser() async {
    final planificateur = _planificateur;
    if (planificateur == null || planificateur.enCours) return;
    await planificateur.synchroniserMaintenant();
    // Un 401 a effacé le jeton : l'état affiché doit le refléter.
    _etat = await _service.etat();
    await _chargerDroits();
    _notifier();
  }

  /// « Réessayer » (`47g_`) : resynchronise tout de suite. Le tirage rafraîchit les droits du
  /// compte ; ce qui attendait un droit que le compte a maintenant (droit accordé au serveur,
  /// autre compte appairé) part dans le même cycle.
  Future<void> reessayer() => synchroniser();

  EtatDroitsPoste? _droits;

  /// Droits du compte appairé, demandes et saisies en attente de droit, écart d'horloge.
  /// `null` tant que non chargé (ou sans planificateur).
  EtatDroitsPoste? get droits => _droits;

  Future<void> _chargerDroits() async {
    _droits = await _planificateur?.moteur.etatDroits();
  }

  /// Une synchronisation (déclenchée ici ou par le planificateur) vient de changer l'état :
  /// les droits du compte et l'écart d'horloge sont relus à sa fin.
  void _surPlanificateur() {
    _notifier();
    if (_planificateur?.enCours ?? true) return;
    // Une synchronisation vient de finir : un 401 a pu tuer le jeton (pastille rouge,
    // « Réappairer ») ; on relit donc aussi l'état de l'appairage.
    unawaited(
      _actualiserApresCycle().then((_) => _notifier(), onError: (Object _) {}),
    );
  }

  Future<void> _actualiserApresCycle() async {
    if (_disposed) return;
    _etat = await _service.etat();
    await _chargerDroits();
  }

  EtatAppairage? _etat;
  ResultatAppairage? _dernierResultat;
  bool _occupe = false;
  bool _disposed = false;

  EtatAppairage? get etat => _etat;
  bool get chargement => _etat == null;

  /// Opération réseau en cours : les boutons se désactivent (pas de double envoi).
  bool get occupe => _occupe;

  /// Dernier message à montrer sous le formulaire (réussite comme échec).
  ResultatAppairage? get dernierResultat => _dernierResultat;

  int _intervalleMinutes =
      PreferencesPosteRepository.intervalleSynchroParDefaut;

  /// Synchro automatique : une synchronisation de routine toutes les N minutes.
  int get intervalleMinutes => _intervalleMinutes;

  /// Choisit l'intervalle de la synchro automatique : mémorisé, appliqué tout de suite.
  Future<void> definirIntervalleMinutes(int minutes) async {
    await _service.preferences.definirIntervalleSynchroMinutes(minutes);
    _intervalleMinutes = minutes;
    _planificateur?.changerIntervalleRoutine(Duration(minutes: minutes));
    _notifier();
  }

  Future<void> charger() async {
    _intervalleMinutes = await _service.preferences.intervalleSynchroMinutes();
    _etat = await _service.etat();
    await _chargerDroits();
    _notifier();
  }

  Future<ResultatAppairage> connecter({
    required String adresse,
    required String identifiant,
    required String motDePasse,
  }) => _executer(
    () => _service.connecter(
      adresse: adresse,
      identifiant: identifiant,
      motDePasse: motDePasse,
    ),
  );

  Future<ResultatAppairage> tester() => _executer(_service.tester);

  Future<ResultatAppairage> deconnecter() => _executer(_service.deconnecter);

  Future<ResultatAppairage> _executer(
    Future<ResultatAppairage> Function() action,
  ) async {
    _occupe = true;
    _dernierResultat = null;
    _notifier();
    try {
      final resultat = await action();
      _dernierResultat = resultat;
      // Un poste qui vient de s'appairer reprend sa synchronisation.
      if (resultat.reussi && resultat.codePoste != null) {
        _planificateur?.reprendre();
      }
      _etat = await _service.etat();
      await _chargerDroits();
      return resultat;
    } finally {
      _occupe = false;
      _notifier();
    }
  }

  void _notifier() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _planificateur?.removeListener(_surPlanificateur);
    _disposed = true;
    super.dispose();
  }
}
