/// Role RBAC — Doc I1 §1.
///
/// 3 roles reels, confirmes par `assets/js/sidebar.js` du prototype
/// ("3 roles RBAC (pas 4)... aucun role comptable") et par Doc K4 §8/§10.
class RoleUtilisateur {
  const RoleUtilisateur({required this.id, required this.libelle});

  /// Identifiant technique : 'admin', 'caissier' ou 'animalier'.
  final String id;

  /// Libelle affiche : "Administratrice", "Agent de Vente", "Agent d'Élevage".
  final String libelle;

  static const String idAdmin = 'admin';
  static const String idCaissier = 'caissier';
  static const String idAnimalier = 'animalier';

  /// Referentiel de reference, utilise par le seeder (Doc K4 §8).
  static const List<RoleUtilisateur> tous = [
    RoleUtilisateur(id: idAdmin, libelle: 'Administratrice'),
    RoleUtilisateur(id: idCaissier, libelle: 'Agent de Vente'),
    RoleUtilisateur(id: idAnimalier, libelle: 'Agent d\'Élevage'),
  ];
}
