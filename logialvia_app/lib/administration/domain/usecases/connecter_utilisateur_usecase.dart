import '../../../core/resultat/resultat.dart';
import '../entities/session_utilisateur.dart';
import '../repositories/auth_repository.dart';
import '../services/hachage_mot_de_passe.dart';

/// Connexion d'un utilisateur — Doc F1 Ecran 3.
///
/// Regle de securite : le message d'echec ne precise JAMAIS lequel des deux
/// champs est errone (Doc F1 "Cas d'Erreur"). Le libelle exact est celui du
/// prototype (login.html l.192), suffixe du compteur de tentatives par l'appelant.
class ConnecterUtilisateurUseCase {
  const ConnecterUtilisateurUseCase(this._repository);

  final AuthRepository _repository;

  /// Message unique, volontairement identique que l'identifiant soit inconnu
  /// ou le mot de passe faux.
  static const String messageIdentifiantsInvalides =
      'Adresse e-mail ou mot de passe incorrect. Veuillez réessayer.';

  Future<Resultat<SessionUtilisateur>> executer({
    required String identifiant,
    required String motDePasse,
  }) async {
    final identifiantNettoye = identifiant.trim();

    try {
      final utilisateur = await _repository.trouverParIdentifiant(
        identifiantNettoye,
      );
      if (utilisateur == null) {
        await _repository.journaliserEchecConnexion(
          identifiantTente: identifiantNettoye,
          detail: 'Identifiant inconnu',
        );
        return const Echec(messageIdentifiantsInvalides);
      }

      final secret = await _repository.chargerSecret(utilisateur.id);
      if (secret == null ||
          !HachageMotDePasse.verifier(
            motDePasseSaisi: motDePasse,
            sel: secret.sel,
            hashAttendu: secret.motDePasseHash,
          )) {
        await _repository.journaliserEchecConnexion(
          identifiantTente: identifiantNettoye,
          detail: 'Mot de passe incorrect',
        );
        return const Echec(messageIdentifiantsInvalides);
      }

      final role = await _repository.trouverRole(utilisateur.roleId);
      if (role == null) {
        // Incoherence de donnees : un compte pointe vers un role inexistant.
        // Refuser la connexion plutot que d'ouvrir une session sans permissions.
        await _repository.journaliserEchecConnexion(
          identifiantTente: identifiantNettoye,
          detail: 'Rôle introuvable : ${utilisateur.roleId}',
        );
        return const Echec(
          'Votre compte n\'a pas de rôle valide. Contactez l\'administratrice.',
        );
      }

      await _repository.journaliserConnexion(utilisateur);
      return Succes(SessionUtilisateur(utilisateur: utilisateur, role: role));
    } catch (e) {
      return const Echec(
        'Connexion impossible : la base de données est inaccessible.',
      );
    }
  }
}
