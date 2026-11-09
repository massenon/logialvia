import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v31 — `clients` passe en UUID (DV-19, palier 1) : une VRAIE base
/// v30 (clés entières) est ouverte par le code courant.
void main() {
  late Directory dossier;
  late File fichier;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v31');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  /// Une base v30 : schéma courant, sauf `clients` remise dans son état v30.
  Future<void> baseV30() async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP TABLE clients');
    await db.customStatement(
      'CREATE TABLE clients (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'nom TEXT NOT NULL, telephone TEXT NULL, '
      'solde_creance REAL NOT NULL DEFAULT 0, '
      'date_naissance INTEGER NULL, dernier_contact INTEGER NULL)',
    );
    await db.customStatement(
      "INSERT INTO clients (nom, telephone, date_naissance) VALUES "
      "('DOSSOU Félicité', '97000001', 631152000), "
      "('Mama Rita', NULL, NULL), ('Mama Rita', '97000003', NULL)",
    );
    await db.customStatement('PRAGMA user_version = 30');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lignes(AppDatabase db) => db
      .customSelect('SELECT * FROM clients ORDER BY nom, telephone')
      .get()
      .then((l) => l.map((r) => r.data).toList());

  test(
    'chaque client reçoit un UUID distinct, rien d\'autre ne bouge',
    () async {
      await baseV30();
      final db = AppDatabase.pourFichier(fichier);
      final l = await lignes(db);

      expect(l, hasLength(3));
      final ids = l.map((r) => r['id']! as String).toList();
      for (final id in ids) {
        expect(id, matches(uuid));
      }
      expect(
        ids.toSet(),
        hasLength(3),
        reason: 'un UUID par ligne, jamais le même',
      );
      expect(l.map((r) => r['nom']), [
        'DOSSOU Félicité',
        'Mama Rita',
        'Mama Rita',
      ]);
      expect(l.first['telephone'], '97000001');
      expect(
        l.first['date_naissance'],
        631152000,
        reason: 'les dates survivent',
      );
      await db.close();
    },
  );

  test(
    'les clients existants sont à envoyer, avec un instant de saisie',
    () async {
      await baseV30();
      final db = AppDatabase.pourFichier(fichier);
      for (final r in await lignes(db)) {
        expect(r['sync_status'], 'pending');
        expect(r['sync_motif'], isNull);
        final instant = DateTime.parse(r['updated_at']! as String);
        expect(instant.isUtc, isTrue);
        expect(
          DateTime.now().toUtc().difference(instant).inMinutes.abs(),
          lessThan(5),
        );
      }
      await db.close();
    },
  );

  test('la base est estampillée v31 et la table a le schéma courant', () async {
    await baseV30();
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.data.values.first, 31);
    final colonnes = await db
        .customSelect('PRAGMA table_info("clients")')
        .get()
        .then(
          (l) => {
            for (final r in l) r.read<String>('name'): r.read<String>('type'),
          },
        );
    expect(colonnes['id'], 'TEXT');
    expect(
      colonnes.keys,
      containsAll(['sync_status', 'sync_motif', 'updated_at']),
    );
    await db.close();
  });

  test(
    'rejouée (version estampillée 30 à tort), elle ne change aucun UUID',
    () async {
      await baseV30();
      var db = AppDatabase.pourFichier(fichier);
      final avant = (await lignes(db)).map((r) => r['id']).toList();
      await db.customStatement('PRAGMA user_version = 30');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      final apres = (await lignes(db)).map((r) => r['id']).toList();
      expect(
        apres,
        avant,
        reason: 'un UUID déjà donné est celui du serveur : il ne change plus',
      );
      await db.close();
    },
  );

  test('une base neuve crée directement la table en UUID', () async {
    final db = AppDatabase.enMemoire();
    await db.customSelect('SELECT 1').get();
    final type = await db
        .customSelect('PRAGMA table_info("clients")')
        .get()
        .then(
          (l) => l
              .firstWhere((r) => r.read<String>('name') == 'id')
              .read<String>('type'),
        );
    expect(type, 'TEXT');
    await db.close();
  });
}
