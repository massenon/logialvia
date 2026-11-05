/// Depot des modules activables — Doc I2, table `MODULES_ACTIFS`.
abstract class ModulesActifsRepository {
  /// Etat de tous les modules basculables, indexe par identifiant technique.
  Future<Map<String, bool>> chargerEtats();

  /// Persiste l'activation/desactivation d'un module (BR-ADM-002).
  Future<void> definirEtat(String moduleId, {required bool actif});
}
