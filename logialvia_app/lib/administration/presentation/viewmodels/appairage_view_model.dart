import 'package:flutter/foundation.dart';

import '../../../core/sync/service_appairage.dart';

/// État de l'onglet « Appairage » (Paramètres Généraux).
///
/// Le **mot de passe ne passe jamais ici** : l'écran le garde dans son champ de
/// saisie et le remet au service au moment de se connecter, puis le vide.
class AppairageViewModel extends ChangeNotifier {
  AppairageViewModel(this._service);

  final ServiceAppairage _service;

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
    _disposed = true;
    super.dispose();
  }
}
