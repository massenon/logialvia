import 'role_utilisateur.dart';
import 'utilisateur.dart';

/// Session ouverte apres une connexion reussie — Doc F1 Ecran 3 :
/// "redirige vers /dashboard avec le role charge en session".
class SessionUtilisateur {
  const SessionUtilisateur({required this.utilisateur, required this.role});

  final Utilisateur utilisateur;
  final RoleUtilisateur role;
}
