import 'package:flutter/foundation.dart';

import '../../domain/repositories/modules_actifs_repository.dart';

/// Etat des filieres activables — Doc I2 §5.
///
/// Enregistre globalement dans `main.dart` : la barre laterale, le Dashboard
/// Élevage et le `redirect` du routeur en dependent tous (Doc K4 §5).
class ModulesActifsViewModel extends ChangeNotifier {
  ModulesActifsViewModel(this._repository);

  final ModulesActifsRepository _repository;

  /// Filieres structurelles, jamais desactivables — `checked disabled` dans
  /// `parametres-generaux.html` (Doc I2 §2). Elles n'ont volontairement aucune
  /// ligne en base : leur donner un etat modifiable suggererait le contraire.
  static const Set<String> modulesNonDesactivables = {'goliaths', 'pintades'};

  Map<String, bool> _etats = const {};
  bool _charge = false;
  bool get charge => _charge;

  Future<void> charger() async {
    _etats = await _repository.chargerEtats();
    _charge = true;
    notifyListeners();
  }

  /// Desactive par defaut si le module est inconnu — jamais actif par defaut
  /// (Doc I2 §5, correctif explicite).
  bool estActif(String moduleId) {
    if (modulesNonDesactivables.contains(moduleId)) return true;
    return _etats[moduleId] ?? false;
  }

  Future<void> basculer(String moduleId, {required bool actif}) async {
    if (modulesNonDesactivables.contains(moduleId)) return; // no-op
    await _repository.definirEtat(moduleId, actif: actif);
    _etats = {..._etats, moduleId: actif};
    notifyListeners(); // rafraichit immediatement la navigation (Doc E3)
  }
}
