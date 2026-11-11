import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v32 — la file des demandes de modification de référentiel.
void main() {
  late Directory dossier;
  late File fichier;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v32');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  Future<bool> tableExiste(AppDatabase db) async =>
      (await db
              .customSelect(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='demandes_referentiel'",
              )
              .get())
          .isNotEmpty;

  test('une base v31 reçoit la table, sans rien perdre', () async {
    var db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP TABLE demandes_referentiel');
    await db.customStatement(
      "INSERT INTO clients (id, nom, updated_at) VALUES "
      "('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Garde-moi', '2026-11-09T09:00:00.000Z')",
    );
    await db.customStatement('PRAGMA user_version = 31');
    await db.close();

    db = AppDatabase.pourFichier(fichier);
    expect(await tableExiste(db), isTrue);
    final c = await db.customSelect('SELECT nom FROM clients').get();
    expect(c.single.read<String>('nom'), 'Garde-moi');
    await db.close();
  });

  test(
    'rejouée sur une base qui l\'a déjà : rien ne casse, rien ne se vide',
    () async {
      var db = AppDatabase.pourFichier(fichier);
      await db.customSelect('SELECT 1').get();
      await db.customStatement(
        "INSERT INTO demandes_referentiel (id, type, cle, donnees, saisi_le) VALUES "
        "('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'module_actif', 'ovins', '{}', '2026-11-09T09:00:00.000Z')",
      );
      await db.customStatement('PRAGMA user_version = 31');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      final lignes = await db
          .customSelect('SELECT id, sync_status FROM demandes_referentiel')
          .get();
      expect(lignes.single.read<String>('sync_status'), 'pending');
      await db.close();
    },
  );
}
