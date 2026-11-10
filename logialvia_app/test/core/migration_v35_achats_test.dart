import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v35 — fournisseurs, achats et lignes d'achat en UUID (DV-19, palier 4).
/// Le risque : qu'un achat perde son fournisseur, ou ses lignes (`ON DELETE CASCADE`).
void main() {
  late Directory dossier;
  late File fichier;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  const dateAchat = 1788000000;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v35');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  Future<void> baseV34() async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP TABLE lignes_achat');
    await db.customStatement('DROP TABLE achats');
    await db.customStatement('DROP TABLE fournisseurs');
    await db.customStatement(
      'CREATE TABLE fournisseurs (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'nom TEXT NOT NULL, telephone TEXT NULL, adresse TEXT NULL, fournit TEXT NULL)',
    );
    await db.customStatement(
      'CREATE TABLE achats (ref TEXT NOT NULL PRIMARY KEY, '
      'fournisseur_id INTEGER NOT NULL REFERENCES fournisseurs (id), '
      'date_achat INTEGER NOT NULL, statut TEXT NOT NULL, total REAL NOT NULL, '
      'paye REAL NOT NULL DEFAULT 0, mode TEXT NULL, echeance INTEGER NULL)',
    );
    await db.customStatement(
      'CREATE TABLE lignes_achat (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'achat_ref TEXT NOT NULL REFERENCES achats (ref) ON DELETE CASCADE, '
      'intrant_code TEXT NOT NULL REFERENCES intrants (code), '
      'nom TEXT NOT NULL, qte REAL NOT NULL, pu_achat REAL NOT NULL)',
    );
    // Ids non consécutifs : le 4 et le 9.
    await db.customStatement(
      "INSERT INTO fournisseurs (id, nom, telephone) VALUES (4, 'Maïs Local', '97000001'), (9, 'Soja Bénin', NULL)",
    );
    await db.customStatement(
      "INSERT OR IGNORE INTO intrants (code, name, cat, stock, unit, threshold, pmp) VALUES ('INT-X', 'Maïs', 'Aliment', 10, 'kg', 2, 300)",
    );
    await db.customStatement(
      'INSERT INTO achats (ref, fournisseur_id, date_achat, statut, total, paye) VALUES '
      "('ACH-2026-001', 4, $dateAchat, 'Livré', 30000, 30000), "
      "('ACH-2026-002', 9, $dateAchat, 'Commandé', 12000, 2000)",
    );
    await db.customStatement(
      'INSERT INTO lignes_achat (id, achat_ref, intrant_code, nom, qte, pu_achat) VALUES '
      "(3, 'ACH-2026-001', 'INT-X', 'Maïs', 100, 300), "
      "(8, 'ACH-2026-002', 'INT-X', 'Maïs', 40, 300)",
    );
    await db.customStatement('PRAGMA user_version = 34');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  test(
    'fournisseurs et achats reçoivent un UUID distinct, le numéro officiel ne bouge pas',
    () async {
      await baseV34();
      final db = AppDatabase.pourFichier(fichier);

      final f = await lire(db, 'SELECT * FROM fournisseurs ORDER BY nom');
      expect(f, hasLength(2));
      for (final r in f) {
        expect(r['id'], matches(uuid));
      }
      expect(f.map((r) => r['id']).toSet(), hasLength(2));
      expect(f.first['telephone'], '97000001');

      final a = await lire(db, 'SELECT * FROM achats ORDER BY ref');
      expect(a.map((r) => r['ref']), [
        'ACH-2026-001',
        'ACH-2026-002',
      ], reason: 'DV-21 : jamais renuméroté');
      for (final r in a) {
        expect(r['id'], matches(uuid));
      }
      expect(a.map((r) => r['id']).toSet(), hasLength(2));
      expect(a.last['total'], 12000);
      expect(a.last['paye'], 2000);
      expect(a.last['date_achat'], dateAchat);
      await db.close();
    },
  );

  test('chaque achat garde SON fournisseur (jointure par UUID)', () async {
    await baseV34();
    final db = AppDatabase.pourFichier(fichier);

    final j = await lire(
      db,
      'SELECT a.ref AS ref, f.nom AS fournisseur FROM achats a '
      'JOIN fournisseurs f ON f.id = a.fournisseur_id ORDER BY a.ref',
    );

    expect(j.map((r) => '${r['ref']}=>${r['fournisseur']}'), [
      'ACH-2026-001=>Maïs Local',
      'ACH-2026-002=>Soja Bénin',
    ]);
    await db.close();
  });

  test(
    'les lignes survivent à la reconstruction (pas de cascade) et gardent leur achat',
    () async {
      await baseV34();
      final db = AppDatabase.pourFichier(fichier);
      final l = await lire(
        db,
        'SELECT id, achat_ref, qte FROM lignes_achat ORDER BY achat_ref',
      );

      expect(
        l,
        hasLength(2),
        reason: 'aucune ligne emportée par ON DELETE CASCADE',
      );
      expect(l.map((r) => r['achat_ref']), ['ACH-2026-001', 'ACH-2026-002']);
      for (final r in l) {
        expect(r['id'], matches(uuid));
      }
      expect(l.first['qte'], 100);
      await db.close();
    },
  );

  test(
    'les achats existants sont à envoyer, avec leur date d\'achat comme instant de saisie',
    () async {
      await baseV34();
      final db = AppDatabase.pourFichier(fichier);
      final attendu = DateTime.fromMillisecondsSinceEpoch(
        dateAchat * 1000,
        isUtc: true,
      );

      for (final r in await lire(
        db,
        'SELECT sync_status, updated_at FROM achats',
      )) {
        expect(r['sync_status'], 'pending');
        expect(
          DateTime.parse(
            r['updated_at']! as String,
          ).difference(attendu).inSeconds.abs(),
          lessThan(2),
        );
      }
      for (final r in await lire(db, 'SELECT sync_status FROM fournisseurs')) {
        expect(r['sync_status'], 'pending');
      }
      await db.close();
    },
  );

  test(
    'intégrité référentielle intacte, table de correspondance supprimée, version courante',
    () async {
      await baseV34();
      final db = AppDatabase.pourFichier(fichier);
      await db.customSelect('SELECT 1').get();

      expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
      expect(
        await lire(
          db,
          "SELECT name FROM sqlite_master WHERE name = '_map_fournisseurs'",
        ),
        isEmpty,
      );
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.first, AppDatabase.versionSchema);
      await db.close();
    },
  );

  test(
    'rejouée (version estampillée 34 à tort), aucun UUID ne change',
    () async {
      await baseV34();
      var db = AppDatabase.pourFichier(fichier);
      final avant = await lire(
        db,
        'SELECT ref, id, fournisseur_id FROM achats ORDER BY ref',
      );
      final avantF = await lire(db, 'SELECT id FROM fournisseurs ORDER BY nom');
      await db.customStatement('PRAGMA user_version = 34');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      expect(
        await lire(
          db,
          'SELECT ref, id, fournisseur_id FROM achats ORDER BY ref',
        ),
        avant,
      );
      expect(
        await lire(db, 'SELECT id FROM fournisseurs ORDER BY nom'),
        avantF,
      );
      expect(await lire(db, 'SELECT COUNT(*) AS n FROM lignes_achat'), [
        {'n': 2},
      ]);
      await db.close();
    },
  );

  test('une base neuve crée directement les trois tables en UUID', () async {
    final db = AppDatabase.enMemoire();
    await db.customSelect('SELECT 1').get();
    for (final t in ['fournisseurs', 'achats', 'lignes_achat']) {
      final c = await lire(db, 'PRAGMA table_info("$t")');
      expect(c.firstWhere((r) => r['name'] == 'id')['type'], 'TEXT', reason: t);
    }
    final c = await lire(db, 'PRAGMA table_info("achats")');
    expect(c.firstWhere((r) => r['name'] == 'fournisseur_id')['type'], 'TEXT');
    await db.close();
  });
}
