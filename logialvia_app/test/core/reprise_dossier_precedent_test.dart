import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/reprise_dossier_precedent.dart';
import 'package:path/path.dart' as p;

/// Reprise de la base quand le dossier de données change de nom.
///
/// ## Le défaut réel que ces tests verrouillent
///
/// Corriger `CompanyName` et `ProductName` dans `Runner.rc` — remplacer le
/// `com.example` par défaut de Flutter par la vraie raison sociale — déplace le
/// dossier rendu par `getApplicationSupportDirectory()` sur Windows.
/// L'application repart alors sur une base vide : zéro vente, zéro écriture.
/// Rien n'est perdu, mais tout en a l'air.
///
/// Le cas a été constaté sur la base réelle du poste, pas imaginé.
void main() {
  late Directory racine;
  late Directory actuel;
  late Directory ancien;

  setUp(() {
    racine = Directory.systemTemp.createTempSync('logialvia-reprise-');
    actuel = Directory(p.join(racine.path, 'ALLMANY', 'LogiALVIA'));
    ancien = Directory(p.join(racine.path, 'com.example', 'logialvia_app'));
  });

  tearDown(() {
    if (racine.existsSync()) racine.deleteSync(recursive: true);
  });

  RepriseDossierPrecedent reprise() => RepriseDossierPrecedent(
    dossierActuel: actuel,
    dossiersPrecedents: [ancien],
  );

  File baseAncienne(String contenu) {
    ancien.createSync(recursive: true);
    final f = File(p.join(ancien.path, 'logialvia.db'));
    f.writeAsStringSync(contenu);
    return f;
  }

  File baseActuelle(String contenu) {
    actuel.createSync(recursive: true);
    final f = File(p.join(actuel.path, 'logialvia.db'));
    f.writeAsStringSync(contenu);
    return f;
  }

  test('la base de l\'ancien dossier est reprise', () {
    baseAncienne('donnees-de-la-ferme');

    final repris = reprise().executer();

    expect(repris?.path, ancien.path);
    expect(
      File(p.join(actuel.path, 'logialvia.db')).readAsStringSync(),
      'donnees-de-la-ferme',
    );
  });

  test('l\'ancienne base n\'est pas déplacée, elle est copiée', () {
    final source = baseAncienne('donnees-de-la-ferme');

    reprise().executer();

    expect(
      source.existsSync(),
      isTrue,
      reason:
          'Déplacer priverait l\'ancienne installation de ses données si la '
          'reprise tournait mal.',
    );
  });

  test('une base déjà présente n\'est jamais écrasée', () {
    baseAncienne('etat-avant-mise-a-jour');
    baseActuelle('travail-de-la-journee');

    final repris = reprise().executer();

    expect(repris, isNull);
    expect(
      File(p.join(actuel.path, 'logialvia.db')).readAsStringSync(),
      'travail-de-la-journee',
      reason:
          'Un second démarrage écraserait sinon la journée avec l\'état '
          'd\'avant la mise à jour — la pire perte possible.',
    );
  });

  test('un fichier vide à la nouvelle place ne bloque pas la reprise', () {
    // Cas reel : l'application a demarre une fois, cree le fichier, puis
    // echoue avant d'ecrire quoi que ce soit.
    baseAncienne('donnees-de-la-ferme');
    baseActuelle('');

    expect(reprise().executer()?.path, ancien.path);
    expect(
      File(p.join(actuel.path, 'logialvia.db')).readAsStringSync(),
      'donnees-de-la-ferme',
    );
  });

  test('sans ancien dossier, il ne se passe rien', () {
    expect(reprise().executer(), isNull);
    expect(File(p.join(actuel.path, 'logialvia.db')).existsSync(), isFalse);
  });

  test('un ancien dossier vide est ignoré', () {
    ancien.createSync(recursive: true);
    expect(reprise().executer(), isNull);
  });

  test('le premier emplacement qui porte une base gagne', () {
    final plusAncien = Directory(p.join(racine.path, 'tres-vieux'))
      ..createSync(recursive: true);
    File(p.join(plusAncien.path, 'logialvia.db')).writeAsStringSync('vieux');
    baseAncienne('recent');

    final repris = RepriseDossierPrecedent(
      dossierActuel: actuel,
      dossiersPrecedents: [ancien, plusAncien],
    ).executer();

    expect(repris?.path, ancien.path);
    expect(
      File(p.join(actuel.path, 'logialvia.db')).readAsStringSync(),
      'recent',
      reason: 'La liste est ordonnée du plus récent au plus ancien.',
    );
  });

  test('les emplacements connus se déduisent du dossier courant', () {
    final connus = RepriseDossierPrecedent.emplacementsConnus(actuel);

    expect(connus, hasLength(1));
    expect(
      connus.single.path,
      p.join(racine.path, 'com.example', 'logialvia_app'),
      reason:
          'Le chemin est reconstruit depuis %APPDATA%, sans supposer sa '
          'valeur.',
    );
  });
}
