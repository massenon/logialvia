import 'package:drift/drift.dart';

import 'roles_table.dart';

/// Table `UTILISATEURS` — Doc D1 §2.
///
/// ECART_DELIBERE (documente et repercute dans Doc D1) : le dictionnaire de
/// donnees D1 ne listait que `id`, `nom`, `identifiant`, `roleId`. Aucune
/// colonne ne permettait de stocker un secret d'authentification, alors que
/// Doc F1 Ecran 3 exige une verification reelle des identifiants et que
/// Doc K4 §8 reference explicitement un champ `motDePasseHash`.
/// Les 2 colonnes `motDePasseHash` et `sel` sont donc ajoutees ici, conformement
/// a la recommandation Doc F1 "Point Ouvert" (SHA-256 + sel par compte).
@DataClassName('UtilisateurRow')
class Utilisateurs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nom => text()();

  /// Libelle du champ cote prototype : "NOM D'UTILISATEUR OU EMAIL"
  /// (login.html l.84) — un identifiant peut donc etre un pseudo ou un e-mail.
  TextColumn get identifiant => text().unique()();

  TextColumn get roleId => text().references(Roles, #id)();

  /// SHA-256 hexadecimal de `sel + motDePasse` — jamais le mot de passe en clair.
  TextColumn get motDePasseHash => text()();

  /// Sel aleatoire (base64), propre a chaque compte.
  TextColumn get sel => text()();
}
