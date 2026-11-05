import '../entities/role_utilisateur.dart';
import '../entities/secret_utilisateur.dart';
import '../entities/utilisateur.dart';

/// Interface du depot d'authentification (couche `domain`, Doc C1 §6).
/// L'implementation Drift vit dans `administration/data/repositories/`.
abstract class AuthRepository {
  Future<Utilisateur?> trouverParIdentifiant(String identifiant);

  Future<SecretUtilisateur?> chargerSecret(int utilisateurId);

  Future<RoleUtilisateur?> trouverRole(String roleId);

  /// SECURITY_LOGS, type `echec_connexion` — Doc I3 §6.
  Future<void> journaliserEchecConnexion({
    required String identifiantTente,
    String? detail,
  });

  /// AUDIT_LOGS, action `connexion` — Doc I3 §6.
  Future<void> journaliserConnexion(Utilisateur utilisateur);

  /// AUDIT_LOGS, action `connexion` egalement (evenement de deconnexion),
  /// avec un detail distinguant les deux — Doc I3 §6.
  Future<void> journaliserDeconnexion(Utilisateur utilisateur);
}
