import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v43 — `devis` reçoit son UUID, son statut, sa pierre tombale et les
/// colonnes de synchronisation (`47a2_`).
///
/// Les risques : perdre un devis, changer un numéro officiel, faire gagner un vieux
/// devis contre une correction faite ailleurs (l'instant de saisie est la date
/// d'émission, pas celle de la migration), ne pas pouvoir rejouer la migration.
void main() {
  late Directory dossier;
  late File fichier;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v43');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  const emission = 1788000000; // 2026-08-29T09:20:00Z

  /// Une base v42 : schéma courant, sauf `devis` remise dans son état v42 (entier
  /// auto-incrémenté, aucune colonne de synchronisation, aucun statut).
  Future<void> baseV42() async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP TABLE devis');
    await db.customStatement(
      'CREATE TABLE devis (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      'reference TEXT NOT NULL UNIQUE, client TEXT NOT NULL, objet TEXT NOT NULL, '
      'montant_estime REAL NOT NULL, validite_jours INTEGER NOT NULL DEFAULT 15, '
      'date_emission INTEGER NOT NULL)',
    );
    await db.customStatement(
      'INSERT INTO devis (reference, client, objet, montant_estime, validite_jours, '
      'date_emission) VALUES '
      "('DV-2026-001', 'DOSSOU', 'Construction d''un poulailler', 150000, 30, $emission), "
      "('DV-2026-002', 'Mama Rita', 'Formation', 25000.5, 15, ${emission + 86400})",
    );
    await db.customStatement('PRAGMA user_version = 42');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  test(
    'chaque devis reçoit un UUID distinct, rien d\'autre ne bouge',
    () async {
      await baseV42();
      final db = AppDatabase.pourFichier(fichier);
      final d = await lire(db, 'SELECT * FROM devis ORDER BY reference');

      expect(d, hasLength(2), reason: 'jamais de perte de devis');
      final ids = d.map((r) => r['id']! as String).toList();
      for (final id in ids) {
        expect(id, matches(uuid));
      }
      expect(ids.toSet(), hasLength(2));
      expect(d.map((r) => r['reference']), [
        'DV-2026-001',
        'DV-2026-002',
      ], reason: 'le numéro officiel ne change JAMAIS');
      expect(d.first['client'], 'DOSSOU');
      expect(d.first['objet'], 'Construction d\'un poulailler');
      expect(d.first['montant_estime'], 150000);
      expect(d.first['validite_jours'], 30);
      expect(d.first['date_emission'], emission);
      expect(d.last['montant_estime'], 25000.5);
      await db.close();
    },
  );

  test(
    'les devis d\'hier sont émis, à envoyer, vivants, datés de leur émission',
    () async {
      await baseV42();
      final db = AppDatabase.pourFichier(fichier);
      final d = await lire(
        db,
        'SELECT reference, statut, sync_status, sync_motif, supprime_le, updated_at '
        'FROM devis ORDER BY reference',
      );
      for (final r in d) {
        expect(r['statut'], 'emis');
        expect(r['sync_status'], 'pending');
        expect(r['sync_motif'], isNull);
        expect(r['supprime_le'], isNull);
      }
      final premier = DateTime.parse(d.first['updated_at']! as String);
      final attendu = DateTime.fromMillisecondsSinceEpoch(
        emission * 1000,
        isUtc: true,
      );
      expect(
        premier.difference(attendu).inSeconds.abs(),
        lessThan(2),
        reason: 'l\'instant de saisie est l\'émission, pas la migration',
      );
      await db.close();
    },
  );

  test(
    'rejouée (version estampillée 42 à tort), aucun UUID ne change',
    () async {
      await baseV42();
      var db = AppDatabase.pourFichier(fichier);
      final avant = await lire(
        db,
        'SELECT reference, id FROM devis ORDER BY reference',
      );
      await db.customStatement('PRAGMA user_version = 42');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      expect(
        await lire(db, 'SELECT reference, id FROM devis ORDER BY reference'),
        avant,
      );
      expect(await lire(db, 'SELECT COUNT(*) AS n FROM devis'), [
        {'n': 2},
      ]);
      await db.close();
    },
  );

  test(
    'table déjà convertie mais colonnes manquantes : elles sont ajoutées sans perte',
    () async {
      await baseV42();
      var db = AppDatabase.pourFichier(fichier);
      await db.customStatement('ALTER TABLE devis DROP COLUMN supprime_le');
      await db.customStatement('ALTER TABLE devis DROP COLUMN statut');
      await db.customStatement('PRAGMA user_version = 42');
      final avant = await lire(
        db,
        'SELECT reference, id FROM devis ORDER BY reference',
      );
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      expect(
        await lire(db, 'SELECT reference, id FROM devis ORDER BY reference'),
        avant,
      );
      final colonnes = await lire(db, 'PRAGMA table_info("devis")');
      expect(
        colonnes.map((c) => c['name']),
        containsAll(['statut', 'supprime_le']),
      );
      await db.close();
    },
  );

  test('base sans table devis : elle est créée directement en UUID', () async {
    final db0 = AppDatabase.pourFichier(fichier);
    await db0.customSelect('SELECT 1').get();
    await db0.customStatement('DROP TABLE devis');
    await db0.customStatement('PRAGMA user_version = 42');
    await db0.close();

    final db = AppDatabase.pourFichier(fichier);
    final colonnes = await lire(db, 'PRAGMA table_info("devis")');
    expect(colonnes.firstWhere((c) => c['name'] == 'id')['type'], 'TEXT');
    await db.close();
  });

  test(
    'deux devis ne peuvent pas porter la même référence ni le même UUID',
    () async {
      await baseV42();
      final db = AppDatabase.pourFichier(fichier);
      final id = (await lire(
        db,
        "SELECT id FROM devis WHERE reference = 'DV-2026-001'",
      )).single['id'];
      await expectLater(
        db.customStatement(
          "UPDATE devis SET id = '$id' WHERE reference = 'DV-2026-002'",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "UPDATE devis SET reference = 'DV-2026-001' WHERE reference = 'DV-2026-002'",
        ),
        throwsA(anything),
      );
      await db.close();
    },
  );

  test('base estampillée à la version courante, intégrité intacte', () async {
    await baseV42();
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.data.values.first, AppDatabase.versionSchema);
    expect(AppDatabase.versionSchema, greaterThanOrEqualTo(43));
    await db.close();
  });
}
