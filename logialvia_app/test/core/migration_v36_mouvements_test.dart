import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v36 — le journal des mouvements d'intrants en UUID, avec son origine.
void main() {
  late Directory dossier;
  late File fichier;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v36');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  Future<void> baseV35() async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP TABLE mouvements_intrant');
    await db.customStatement(
      'CREATE TABLE mouvements_intrant (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'horodatage INTEGER NOT NULL, '
      'intrant_code TEXT NOT NULL REFERENCES intrants (code), '
      'article TEXT NOT NULL, type TEXT NOT NULL, motif TEXT NOT NULL, '
      'quantite REAL NOT NULL, reference TEXT NULL)',
    );
    await db.customStatement(
      "INSERT OR IGNORE INTO intrants (code, name, cat, stock, unit, threshold, pmp) "
      "VALUES ('INT-001', 'Maïs', 'Aliment', 70, 'kg', 25, 600)",
    );
    await db.customStatement(
      "INSERT INTO mouvements_intrant (id, horodatage, intrant_code, article, type, motif, quantite, reference) VALUES "
      "(4, 1788000000, 'INT-001', 'Maïs', 'Entrée', 'Réception commande ACH-2026-001', 100, 'ACH-2026-001'), "
      "(9, 1788003600, 'INT-001', 'Maïs', 'Sortie', 'Fabrication FAB-2026-0001', -30, 'FAB-2026-0001')",
    );
    await db.customStatement('PRAGMA user_version = 35');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  test(
    'chaque mouvement reçoit un UUID distinct, rien d\'autre ne bouge',
    () async {
      await baseV35();
      final db = AppDatabase.pourFichier(fichier);
      final m = await lire(
        db,
        'SELECT * FROM mouvements_intrant ORDER BY horodatage',
      );

      expect(m, hasLength(2));
      for (final r in m) {
        expect(r['id'], matches(uuid));
      }
      expect(m.map((r) => r['id']).toSet(), hasLength(2));
      expect(m.map((r) => r['quantite']), [100, -30]);
      expect(m.first['reference'], 'ACH-2026-001');
      expect(m.first['horodatage'], 1788000000);
      await db.close();
    },
  );

  test(
    'les mouvements d\'hier sont LOCAUX (origine vide) et à envoyer',
    () async {
      await baseV35();
      final db = AppDatabase.pourFichier(fichier);

      for (final r in await lire(
        db,
        'SELECT origine, sync_status, sync_motif FROM mouvements_intrant',
      )) {
        expect(
          r['origine'],
          isNull,
          reason:
              'ils ont été saisis sur CE poste : ils comptent dans son inventaire',
        );
        expect(r['sync_status'], 'pending');
        expect(r['sync_motif'], isNull);
      }
      await db.close();
    },
  );

  test('intégrité référentielle intacte, base à la version courante', () async {
    await baseV35();
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.data.values.first, AppDatabase.versionSchema);
    await db.close();
  });

  test(
    'rejouée (version estampillée 35 à tort), aucun UUID ne change',
    () async {
      await baseV35();
      var db = AppDatabase.pourFichier(fichier);
      final avant = await lire(
        db,
        'SELECT id FROM mouvements_intrant ORDER BY horodatage',
      );
      await db.customStatement('PRAGMA user_version = 35');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      expect(
        await lire(db, 'SELECT id FROM mouvements_intrant ORDER BY horodatage'),
        avant,
      );
      await db.close();
    },
  );

  test('une base neuve crée directement la table en UUID', () async {
    final db = AppDatabase.enMemoire();
    await db.customSelect('SELECT 1').get();
    final c = await lire(db, 'PRAGMA table_info("mouvements_intrant")');
    expect(c.firstWhere((r) => r['name'] == 'id')['type'], 'TEXT');
    expect(
      c.map((r) => r['name']),
      containsAll(['origine', 'sync_status', 'sync_motif']),
    );
    await db.close();
  });
}
