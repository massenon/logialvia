/// Secret d'authentification d'un compte — jamais transmis a `presentation/`.
///
/// Doc F1 "Point Ouvert" : le prototype HTML n'expose aucune logique de hachage.
/// Mecanisme retenu et valide : SHA-256 sur `sel + motDePasse`, sel aleatoire
/// propre a chaque compte.
class SecretUtilisateur {
  const SecretUtilisateur({
    required this.utilisateurId,
    required this.motDePasseHash,
    required this.sel,
  });

  final int utilisateurId;
  final String motDePasseHash;
  final String sel;
}
