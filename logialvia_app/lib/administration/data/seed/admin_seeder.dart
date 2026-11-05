import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../domain/entities/role_utilisateur.dart';
import '../../domain/services/hachage_mot_de_passe.dart';

/// Peuplement initial — Doc K4 §8.
///
/// Au premier lancement la base est vide : aucun compte ne permet de se
/// connecter (Doc F1 Ecran 3). Ce seeder cree les 3 roles reels (Doc I1 §1) et
/// le compte administrateur initial, **de facon idempotente** : il ne recree
/// jamais un compte existant et ne reinitialise jamais des donnees deja saisies.
class AdminSeeder {
  const AdminSeeder(this._db);

  final AppDatabase _db;

  /// Identifiant du compte semeur — valeur litterale de Doc K4 §8
  /// (`u.identifiant.equals('admin')`).
  static const String identifiantAdmin = 'admin';

  /// Doc K4 §8 laisse le mot de passe a definir. Valeur retenue : celle du
  /// placeholder du champ mot de passe du prototype (login.html l.95), seule
  /// valeur reellement observable dans les sources.
  ///
  /// Ce mot de passe n'est qu'une **valeur initiale** : l'ecran Mon Profil
  /// (Doc F9) permet a la Gerante de le changer reellement, avec verification
  /// de l'ancien et regeneration du sel. La dette posee ici est donc levee.
  ///
  /// Reste ouvert : **forcer** ce changement a la premiere connexion. Rien ne
  /// distingue aujourd'hui un compte encore sur sa valeur d'origine d'un compte
  /// dont la Gerante aurait choisi le meme mot de passe — le hash est sale, il
  /// n'est pas comparable. Il faudrait pour cela une colonne
  /// `motDePasseAChanger` sur `UTILISATEURS`.
  static const String motDePasseInitialAdmin = 'ALLMANY2026';

  static const String nomAdmin = 'Administratrice Principale';

  /// Retourne `true` si le compte administrateur vient d'etre cree
  /// (donc : base vierge, tout premier lancement), `false` s'il existait deja.
  Future<bool> executer() async {
    final adminExistant = await (_db.select(
      _db.utilisateurs,
    )..where((u) => u.identifiant.equals(identifiantAdmin))).getSingleOrNull();
    if (adminExistant != null) return false; // idempotent

    await _db.transaction(() async {
      // `insertOrIgnore` : si les roles existent deja (compte admin supprime
      // manuellement, par exemple), leurs libelles ne sont pas ecrases.
      for (final role in RoleUtilisateur.tous) {
        await _db
            .into(_db.roles)
            .insert(
              RolesCompanion.insert(id: role.id, libelle: role.libelle),
              mode: InsertMode.insertOrIgnore,
            );
      }

      final sel = HachageMotDePasse.genererSel();
      await _db
          .into(_db.utilisateurs)
          .insert(
            UtilisateursCompanion.insert(
              nom: nomAdmin,
              identifiant: identifiantAdmin,
              roleId: RoleUtilisateur.idAdmin,
              motDePasseHash: HachageMotDePasse.hacher(
                motDePasseInitialAdmin,
                sel,
              ),
              sel: sel,
            ),
          );
    });

    return true;
  }
}

// NOTE (choix explicite, Strict Avoid §12) : la table `PERMISSIONS_ROLE`
// (Doc D1) n'est volontairement PAS peuplee par ce seeder. Doc I1 §4 designe le
// dictionnaire Dart `PermissionService._routesAutoriseesParRole` comme source
// unique de verite des permissions, traduite de `sidebar.js`. Peupler aussi la
// table creerait deux sources de verite divergentes. La table reste declaree
// pour rester conforme au schema D1, mais n'est alimentee par personne
// aujourd'hui — a trancher si un jour les permissions deviennent editables
// depuis l'interface Parametres (Doc F8).
