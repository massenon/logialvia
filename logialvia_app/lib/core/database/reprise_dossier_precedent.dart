import 'dart:io';

import 'package:path/path.dart' as p;

/// Reprend la base d'une installation antérieure quand le dossier de données
/// a changé de nom.
///
/// ## Le piège, et pourquoi ce fichier existe
///
/// Sur Windows, `getApplicationSupportDirectory()` ne choisit pas son chemin :
/// il le **construit à partir des champs `CompanyName` et `ProductName` de
/// l'exécutable**, lus dans `Runner.rc`. Tant que ces champs valaient les
/// valeurs par défaut de Flutter, la base vivait dans :
///
///     %APPDATA%\com.example\logialvia_app\logialvia.db
///
/// Leur correction — la vraie raison sociale, le vrai nom du produit — déplace
/// donc le dossier :
///
///     %APPDATA%\ALLMANY ET COMPAGNIE\LogiALVIA\logialvia.db
///
/// L'application démarre alors sur une base **neuve et vide**. Rien n'est
/// perdu, mais l'écran affiche zéro vente, zéro cycle et zéro écriture : du
/// point de vue de la Gérante, la mise à jour a effacé son exploitation.
///
/// ## Ce que fait cette reprise
///
/// Au démarrage, avant toute ouverture : si le nouveau dossier n'a pas encore
/// de base et qu'un ancien dossier connu en contient une, elle est **copiée**.
///
/// Trois précautions, chacune pour une raison :
///
/// 1. **Copie, jamais déplacement.** L'ancienne installation reste utilisable ;
///    si quoi que ce soit tourne mal, le fichier d'origine est toujours là.
/// 2. **Jamais d'écrasement.** Dès qu'une base existe à la nouvelle place, la
///    reprise ne fait rien — sinon un second démarrage écraserait le travail
///    de la journée avec l'état d'avant la mise à jour.
/// 3. **Les fichiers `-wal` et `-shm` ne sont pas copiés.** Ils appartiennent à
///    une session SQLite terminée ; les traîner risquerait de rejouer un
///    journal sur une base qui ne l'attend plus.
class RepriseDossierPrecedent {
  const RepriseDossierPrecedent({
    required this.dossierActuel,
    required this.dossiersPrecedents,
    this.nomFichier = 'logialvia.db',
  });

  /// Le dossier que l'application utilise aujourd'hui.
  final Directory dossierActuel;

  /// Les emplacements des versions antérieures, du plus récent au plus ancien.
  final List<Directory> dossiersPrecedents;

  final String nomFichier;

  /// Les emplacements historiques connus, sous `%APPDATA%`.
  ///
  /// La liste est **explicite** : deviner en balayant `%APPDATA%` ferait
  /// ramasser la base d'un autre logiciel qui porterait le même nom de fichier.
  static List<Directory> emplacementsConnus(Directory dossierActuel) {
    // `.../<Company>/<Product>` → on remonte de deux crans pour retrouver
    // `%APPDATA%`, sans supposer sa valeur.
    final appData = Directory(p.dirname(p.dirname(dossierActuel.path)));
    return [
      Directory(p.join(appData.path, 'com.example', 'logialvia_app')),
    ];
  }

  /// Effectue la reprise s'il y a lieu. Renvoie le dossier repris, ou `null`.
  Directory? executer() {
    final cible = File(p.join(dossierActuel.path, nomFichier));
    if (cible.existsSync() && cible.lengthSync() > 0) return null;

    for (final precedent in dossiersPrecedents) {
      final source = File(p.join(precedent.path, nomFichier));
      if (!source.existsSync() || source.lengthSync() == 0) continue;

      dossierActuel.createSync(recursive: true);
      source.copySync(cible.path);
      return precedent;
    }
    return null;
  }
}
