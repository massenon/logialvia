/// Utilisateur — Doc D1 §2, table `UTILISATEURS`.
///
/// Ne porte volontairement AUCUN secret d'authentification : le hash et le sel
/// vivent dans [SecretUtilisateur], charge uniquement par le cas d'usage de
/// connexion et jamais expose a la couche `presentation/`.
class Utilisateur {
  const Utilisateur({
    required this.id,
    required this.nom,
    required this.identifiant,
    required this.roleId,
  });

  final int id;
  final String nom;
  final String identifiant;
  final String roleId;
}
