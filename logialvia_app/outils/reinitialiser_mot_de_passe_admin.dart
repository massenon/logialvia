import 'dart:io';

import 'package:logialvia_app/administration/domain/services/hachage_mot_de_passe.dart';
import 'package:sqlite3/sqlite3.dart';

/// Repose le mot de passe d'un compte sur une base **existante**.
///
///     dart run outils/reinitialiser_mot_de_passe_admin.dart <base> <mot-de-passe> [identifiant]
///
/// # Pourquoi cet outil existe
///
/// `AdminSeeder` est idempotent : il crée le compte administrateur sur une base
/// vierge et **n'écrase jamais** un compte existant. C'est voulu — sinon chaque
/// démarrage effacerait le mot de passe choisi par la Gérante.
///
/// Conséquence : changer `motDePasseInitialAdmin` ne touche que les
/// installations neuves. Une installation déjà en service garde l'ancien mot de
/// passe, et le champ de connexion suggérerait alors un mot de passe refusé.
/// Cet outil ferme cet écart, une fois, sur une base désignée.
///
/// # Ce qu'il fait, et ce qu'il ne fait pas
///
/// - Il emploie **le hachage de l'application** (`HachageMotDePasse`), jamais
///   une réimplémentation : deux algorithmes finiraient par diverger, et le
///   compte deviendrait inaccessible sans que rien ne le signale.
/// - Il **régénère le sel**. Réutiliser l'ancien ferait de deux comptes au même
///   mot de passe deux empreintes identiques.
/// - Il n'écrit jamais le mot de passe en clair, ni en base ni à l'écran.
/// - Il **vérifie** après écriture que le mot de passe rouvre bien la session.
///
/// Le mot de passe est passé en argument, jamais codé en dur : un identifiant
/// n'a pas sa place dans un fichier source qui se versionne.
///
/// ⚠️ Copiez la base avant de le lancer. Il modifie un identifiant de
/// connexion : si le nouveau mot de passe se perd, personne n'entre plus.
///
/// Il n'utilise volontairement pas `AppDatabase` : celle-ci dépend de Flutter,
/// que `dart run` ne sait pas compiler. `package:sqlite3` suffit pour un
/// `UPDATE` sur deux colonnes.
void main(List<String> arguments) {
  if (arguments.length < 2) {
    stderr.writeln(
      'Usage : dart run outils/reinitialiser_mot_de_passe_admin.dart '
      '<base> <mot-de-passe> [identifiant]',
    );
    exitCode = 2;
    return;
  }

  final chemin = arguments[0];
  final motDePasse = arguments[1];
  final identifiant = arguments.length > 2 ? arguments[2] : 'admin';

  if (!File(chemin).existsSync()) {
    stderr.writeln('Base introuvable : $chemin');
    exitCode = 2;
    return;
  }

  final db = sqlite3.open(chemin);
  try {
    final trouve = db.select(
      'SELECT id FROM utilisateurs WHERE identifiant = ?',
      [identifiant],
    );
    if (trouve.isEmpty) {
      stderr.writeln('Aucun compte « $identifiant » dans cette base.');
      exitCode = 1;
      return;
    }
    final id = trouve.first['id'] as int;

    final sel = HachageMotDePasse.genererSel();
    final hash = HachageMotDePasse.hacher(motDePasse, sel);

    db.execute(
      'UPDATE utilisateurs SET mot_de_passe_hash = ?, sel = ? WHERE id = ?',
      [hash, sel, id],
    );

    // Verification immediate : annoncer un succes sans l'eprouver serait le
    // pire des resultats — personne ne s'en apercevrait avant d'etre devant
    // l'ecran de connexion.
    final relu = db.select(
      'SELECT mot_de_passe_hash, sel FROM utilisateurs WHERE id = ?',
      [id],
    ).first;
    final ouvre = HachageMotDePasse.verifier(
      motDePasseSaisi: motDePasse,
      hashAttendu: relu['mot_de_passe_hash'] as String,
      sel: relu['sel'] as String,
    );

    if (!ouvre) {
      stderr.writeln('Le mot de passe posé ne rouvre pas la session. Échec.');
      exitCode = 1;
      return;
    }

    stdout.writeln('Compte « $identifiant » : mot de passe reposé.');
    stdout.writeln('Sel régénéré, vérification de connexion réussie.');
  } finally {
    db.close();
  }
}
