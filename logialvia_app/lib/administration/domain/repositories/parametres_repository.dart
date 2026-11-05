import '../entities/parametres_entreprise.dart';
import '../entities/role_utilisateur.dart';
import '../entities/utilisateur.dart';

/// Un utilisateur avec le libellé de son rôle, pour la liste de gestion.
class UtilisateurAvecRole {
  const UtilisateurAvecRole({required this.utilisateur, required this.role});

  final Utilisateur utilisateur;
  final RoleUtilisateur role;
}

/// Dépôt des paramètres généraux et de la gestion des utilisateurs — Doc F8.
abstract class ParametresRepository {
  Future<ParametresEntrepriseModele> charger();

  Future<void> enregistrer(ParametresEntrepriseModele parametres);

  Future<List<UtilisateurAvecRole>> chargerUtilisateurs();

  /// Crée un compte secondaire. Le rôle est nécessairement `caissier` ou
  /// `animalier` — `admin` n'est attribué que par le seeder initial
  /// (Doc F8 Onglet 3, Doc K4 §8).
  Future<Utilisateur> creerUtilisateur({
    required String nom,
    required String identifiant,
    required String roleId,
    required String motDePasse,
  });

  Future<bool> identifiantExiste(String identifiant);

  Future<void> supprimerUtilisateur(
    int utilisateurId, {
    String? auteurId,
    String? auteurNom,
  });
}
