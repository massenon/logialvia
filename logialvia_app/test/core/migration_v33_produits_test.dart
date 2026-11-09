import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v33 — `produits_vendables` et `lignes_vente` passent en UUID
/// (DV-19, palier 3a). Une VRAIE base v32 est ouverte par le code courant : le
/// risque n'est pas les UUID, c'est qu'une ligne de vente perde son produit.
void main() {
  late Directory dossier;
  late File fichier;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v33');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  /// Une base v32 : schéma courant, sauf les deux tables remises dans leur état v32.
  Future<void> baseV32() async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP TABLE lignes_vente');
    await db.customStatement('DROP TABLE produits_vendables');
    await db.customStatement(
      'CREATE TABLE produits_vendables (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'sku TEXT NULL, name TEXT NOT NULL, cat TEXT NOT NULL, price REAL NOT NULL, '
      'price_max REAL NULL, unit TEXT NOT NULL, icon TEXT NOT NULL, cout_revient REAL NULL, '
      "groupe_taxe TEXT NOT NULL DEFAULT 'A', stock INTEGER NOT NULL, threshold INTEGER NOT NULL, "
      'espece TEXT NULL)',
    );
    await db.customStatement(
      'CREATE TABLE lignes_vente (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'vente_ref TEXT NOT NULL REFERENCES ventes (ref) ON DELETE CASCADE, '
      'produit_id INTEGER NOT NULL REFERENCES produits_vendables (id), '
      'name TEXT NOT NULL, qte REAL NOT NULL, pu REAL NOT NULL, espece TEXT NULL)',
    );
    // Des ids volontairement non consécutifs : le 7 et le 12.
    await db.customStatement(
      "INSERT INTO produits_vendables (id, sku, name, cat, price, unit, icon, stock, threshold, espece) VALUES "
      "(7, 'PRD-001', 'Goliath mature', 'Avicole', 25000, 'u', 'egg', 10, 2, 'goliaths'), "
      "(12, 'PRD-002', 'Aliment ponte', 'Intrants', 18000, 'sac', 'grain', 40, 5, NULL), "
      "(13, 'PRD-003', 'Jamais vendu', 'Divers', 500, 'u', 'box', 3, 1, NULL)",
    );
    await db.customStatement(
      "INSERT INTO ventes (ref, client, date_vente, mode, status, total, paye) VALUES "
      "('V-2026-001', 'DOSSOU', 1788000000, 'Espèces', 'Payée', 68000, 68000)",
    );
    await db.customStatement(
      "INSERT INTO lignes_vente (id, vente_ref, produit_id, name, qte, pu, espece) VALUES "
      "(5, 'V-2026-001', 7, 'Goliath mature', 2, 25000, 'goliaths'), "
      "(9, 'V-2026-001', 12, 'Aliment ponte', 1, 18000, NULL)",
    );
    // Un produit déjà archivé : son instantané porte l'ancien entier.
    await db.customStatement(
      "INSERT INTO corbeille (nom_table, module, type_element, designation, donnees_json, archive_le) VALUES "
      "('produits_vendables', 'Commercial', 'Produit du catalogue', 'Ancien produit', ?, 1788000000)",
      [
        jsonEncode({
          'id': 99,
          'sku': 'PRD-099',
          'name': 'Ancien produit',
          'cat': 'Divers',
          'price': 100.0,
          'unit': 'u',
          'icon': 'box',
          'groupe_taxe': 'A',
          'stock': 0,
          'threshold': 0,
        }),
      ],
    );
    await db.customStatement('PRAGMA user_version = 32');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  test(
    'chaque produit reçoit un UUID distinct, rien d\'autre ne bouge',
    () async {
      await baseV32();
      final db = AppDatabase.pourFichier(fichier);
      final p = await lire(db, 'SELECT * FROM produits_vendables ORDER BY sku');

      expect(p, hasLength(3));
      final ids = p.map((r) => r['id']! as String).toList();
      for (final id in ids) {
        expect(id, matches(uuid));
      }
      expect(ids.toSet(), hasLength(3));
      expect(p.map((r) => r['name']), [
        'Goliath mature',
        'Aliment ponte',
        'Jamais vendu',
      ]);
      expect(p.first['price'], 25000);
      expect(p.first['stock'], 10);
      expect(p.first['espece'], 'goliaths');
      await db.close();
    },
  );

  test('chaque ligne de vente garde SON produit (jointure par UUID)', () async {
    await baseV32();
    final db = AppDatabase.pourFichier(fichier);

    final jointure = await lire(
      db,
      'SELECT l.name AS ligne, p.name AS produit, l.qte, l.pu FROM lignes_vente l '
      'JOIN produits_vendables p ON p.id = l.produit_id ORDER BY l.name',
    );

    expect(jointure, hasLength(2), reason: 'aucune ligne orpheline');
    expect(jointure.map((r) => '${r['ligne']}=>${r['produit']}'), [
      'Aliment ponte=>Aliment ponte',
      'Goliath mature=>Goliath mature',
    ]);
    expect(jointure.first['qte'], 1);
    expect(jointure.last['pu'], 25000);
    await db.close();
  });

  test('les lignes ont leur UUID et restent attachées à leur vente', () async {
    await baseV32();
    final db = AppDatabase.pourFichier(fichier);
    final l = await lire(db, 'SELECT id, vente_ref FROM lignes_vente');

    expect(l, hasLength(2));
    for (final r in l) {
      expect(r['id'], matches(uuid));
      expect(r['vente_ref'], 'V-2026-001');
    }
    expect((l.map((r) => r['id']).toSet()), hasLength(2));
    await db.close();
  });

  test('l\'intégrité référentielle est intacte', () async {
    await baseV32();
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
    await db.close();
  });

  test(
    'un produit déjà archivé revient de la corbeille avec un UUID',
    () async {
      await baseV32();
      final db = AppDatabase.pourFichier(fichier);
      final c = await lire(db, 'SELECT donnees_json FROM corbeille');
      final donnees =
          jsonDecode(c.single['donnees_json']! as String)
              as Map<String, dynamic>;

      expect(donnees['id'], matches(uuid));
      expect(donnees['name'], 'Ancien produit');
      await db.close();
    },
  );

  test('la table de correspondance temporaire ne reste pas en base', () async {
    await baseV32();
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    final t = await lire(
      db,
      "SELECT name FROM sqlite_master WHERE name = '_map_produits'",
    );
    expect(t, isEmpty);
    await db.close();
  });

  test(
    'rejouée (version estampillée 32 à tort), aucun UUID ne change',
    () async {
      await baseV32();
      var db = AppDatabase.pourFichier(fichier);
      final avant = await lire(
        db,
        'SELECT id FROM produits_vendables ORDER BY sku',
      );
      final avantLignes = await lire(
        db,
        'SELECT id, produit_id FROM lignes_vente ORDER BY name',
      );
      await db.customStatement('PRAGMA user_version = 32');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      expect(
        await lire(db, 'SELECT id FROM produits_vendables ORDER BY sku'),
        avant,
      );
      expect(
        await lire(db, 'SELECT id, produit_id FROM lignes_vente ORDER BY name'),
        avantLignes,
      );
      await db.close();
    },
  );

  test('une base neuve crée directement les deux tables en UUID', () async {
    final db = AppDatabase.enMemoire();
    await db.customSelect('SELECT 1').get();
    for (final t in ['produits_vendables', 'lignes_vente']) {
      final c = await lire(db, 'PRAGMA table_info("$t")');
      expect(c.firstWhere((r) => r['name'] == 'id')['type'], 'TEXT', reason: t);
    }
    final c = await lire(db, 'PRAGMA table_info("lignes_vente")');
    expect(c.firstWhere((r) => r['name'] == 'produit_id')['type'], 'TEXT');
    await db.close();
  });
}
