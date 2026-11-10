import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Une base au bon schéma mais mal versionnée doit démarrer quand même.
///
/// ## Le jour où l'application n'a plus démarré
///
/// Un poste s'est retrouvé avec un schéma complet en v25 et un `user_version`
/// resté à **16**. Drift a donc rejoué les migrations 17 à 25, et la première —
/// `ALTER TABLE ventes ADD COLUMN echeance` — a levé
/// « duplicate column name: echeance ». L'application ne démarrait plus.
///
/// Pire : le Splash annonçait un problème de **droits d'accès**, quoi qu'il
/// arrive. La panne a donc été cherchée du côté des permissions du dossier, à
/// l'opposé de sa cause.
///
/// Un `user_version` faux n'est pas une hypothèse d'école : il arrive dès
/// qu'une base est restaurée depuis une sauvegarde, copiée depuis un autre
/// poste, ou qu'une migration s'interrompt. Sur une exploitation sans
/// informaticien, une base illisible est une comptabilité perdue.
///
/// Les migrations vérifient donc l'état **réel** du schéma avant d'agir, au
/// lieu de faire confiance au numéro de version.
void main() {
  late Directory dossier;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_migration');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  /// Crée une base complète, puis lui recolle un `user_version` d'époque.
  Future<File> baseMalVersionnee(int versionFausse) async {
    final fichier = File('${dossier.path}/logialvia.db');

    // 1. Base neuve : `onCreate` pose le schema complet et la version courante.
    final neuve = AppDatabase.pourFichier(fichier);
    await neuve.customSelect('SELECT 1').get();
    await neuve.customStatement('PRAGMA user_version = $versionFausse');
    await neuve.close();

    return fichier;
  }

  test('une base v25 estampillée 16 s\'ouvre sans erreur', () async {
    final fichier = await baseMalVersionnee(16);

    // C'est ici que « duplicate column name: echeance » se levait.
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(
      version.data.values.first,
      db.schemaVersion,
      reason: 'La migration doit se terminer et réestampiller la base.',
    );
    await db.close();
  });

  test('le schéma reste intact — rien n\'est recréé ni perdu', () async {
    final reference = AppDatabase.enMemoire();
    await reference.customSelect('SELECT 1').get();
    final attendues = await reference
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get()
        .then((l) => l.map((r) => r.read<String>('name')).toList());
    await reference.close();

    final fichier = await baseMalVersionnee(16);
    final db = AppDatabase.pourFichier(fichier);
    final obtenues = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get()
        .then((l) => l.map((r) => r.read<String>('name')).toList());

    expect(obtenues, attendues);
    await db.close();
  });

  test('les données survivent au rattrapage de version', () async {
    final fichier = File('${dossier.path}/logialvia.db');
    final neuve = AppDatabase.pourFichier(fichier);
    await neuve.customSelect('SELECT 1').get();
    await neuve.customStatement(
      "INSERT INTO clients (id, nom, telephone, updated_at) VALUES ('33333333-3333-4333-8333-333333333333', 'AGOSSOU Prudence', '97', '2026-11-09T09:00:00.000Z')",
    );
    await neuve.customStatement('PRAGMA user_version = 16');
    await neuve.close();

    final db = AppDatabase.pourFichier(fichier);
    final lignes = await db.customSelect('SELECT nom FROM clients').get();
    expect(lignes, hasLength(1));
    expect(lignes.single.read<String>('nom'), 'AGOSSOU Prudence');
    await db.close();
  });

  test('une version très ancienne se rattrape aussi', () async {
    // Le cas d'une base restauree depuis une tres vieille sauvegarde.
    final fichier = await baseMalVersionnee(1);

    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, db.schemaVersion);
    await db.close();
  });
}
