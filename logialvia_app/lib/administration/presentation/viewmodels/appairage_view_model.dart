import 'package:flutter/foundation.dart';

import '../../../core/sync/moteur_synchronisation.dart';
import '../../../core/sync/planificateur_synchronisation.dart';
import '../../../core/sync/service_appairage.dart';

/// État de l'onglet « Appairage » (Paramètres Généraux).
///
/// Le **mot de passe ne passe jamais ici** : l'écran le garde dans son champ de
/// saisie et le remet au service au moment de se connecter, puis le vide.
class AppairageViewModel extends ChangeNotifier {
  AppairageViewModel(this._service, [this._planificateur]) {
    _planificateur?.addListener(_notifier);
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
    _notifier();
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

  Future<void> charger() async {
    _etat = await _service.etat();
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
    _planificateur?.removeListener(_notifier);
    _disposed = true;
    super.dispose();
  }
}
