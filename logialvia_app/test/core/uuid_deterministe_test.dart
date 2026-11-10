import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';

/// Un même produit doit porter le même identifiant sur tous les postes.
void main() {
  final v5 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('format UUID v5, stable, distinct selon la clé', () {
    final a = uuidDeterministe('produit:PRD-001|Goliath mature');
    expect(a, matches(v5));
    expect(uuidDeterministe('produit:PRD-001|Goliath mature'), a);
    expect(uuidDeterministe('produit:PRD-002|Goliath mature'), isNot(a));
    expect(uuidDeterministe('produit:PRD-001|Goliath mature '), isNot(a));
  });

  test(
    'deux postes semés du même catalogue : mêmes identifiants de produits',
    () async {
      final a = AppDatabase.enMemoire();
      final b = AppDatabase.enMemoire();
      addTearDown(a.close);
      addTearDown(b.close);
      await SeedInitial(a).executer();
      await SeedInitial(b).executer();

      Future<Map<String, String>> ids(AppDatabase db) async => {
        for (final p in await db.select(db.produitsVendables).get())
          p.name: p.id,
      };
      final ia = await ids(a);
      final ib = await ids(b);

      expect(ia, hasLength(14));
      expect(
        ia,
        ib,
        reason: 'sinon « Goliath mature » existerait en double sur le serveur',
      );
      expect(ia.values.toSet(), hasLength(14));
      for (final id in ia.values) {
        expect(id, matches(v5));
      }
    },
  );

  group('migration v33', () {
    late Directory dossier;
    setUp(
      () => dossier = Directory.systemTemp.createTempSync('logialvia_uuid5'),
    );
    tearDown(() => dossier.deleteSync(recursive: true));

    Future<List<String>> migrer(String nom, List<String> produits) async {
      final f = File('${dossier.path}/$nom.db');
      var db = AppDatabase.pourFichier(f);
      await db.customSelect('SELECT 1').get();
      await db.customStatement('DROP TABLE lignes_vente');
      await db.customStatement('DROP TABLE produits_vendables');
      await db.customStatement(
        'CREATE TABLE produits_vendables (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, sku TEXT NULL, '
        'name TEXT NOT NULL, cat TEXT NOT NULL, price REAL NOT NULL, price_max REAL NULL, unit TEXT NOT NULL, '
        "icon TEXT NOT NULL, cout_revient REAL NULL, groupe_taxe TEXT NOT NULL DEFAULT 'A', "
        'stock INTEGER NOT NULL, threshold INTEGER NOT NULL, espece TEXT NULL)',
      );
      await db.customStatement(
        'CREATE TABLE lignes_vente (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
        'vente_ref TEXT NOT NULL REFERENCES ventes (ref) ON DELETE CASCADE, '
        'produit_id INTEGER NOT NULL REFERENCES produits_vendables (id), '
        'name TEXT NOT NULL, qte REAL NOT NULL, pu REAL NOT NULL, espece TEXT NULL)',
      );
      for (final p in produits) {
        final morceaux = p.split('|');
        await db.customStatement(
          "INSERT INTO produits_vendables (sku, name, cat, price, unit, icon, stock, threshold) "
          "VALUES (?, ?, 'Divers', 100, 'u', 'box', 1, 0)",
          [morceaux[0], morceaux[1]],
        );
      }
      await db.customStatement('PRAGMA user_version = 32');
      await db.close();
      db = AppDatabase.pourFichier(f);
      final r = await db
          .customSelect('SELECT id FROM produits_vendables ORDER BY name, sku')
          .get();
      final ids = r.map((x) => x.read<String>('id')).toList();
      await db.close();
      return ids;
    }

    test(
      'deux postes qui portent le même produit lui donnent le même UUID',
      () async {
        final a = await migrer('a', ['PRD-001|Goliath', 'PRD-002|Aliment']);
        // Le poste B a les mêmes produits, créés dans un AUTRE ordre (autres entiers).
        final b = await migrer('b', ['PRD-002|Aliment', 'PRD-001|Goliath']);

        expect(a, b);
      },
    );

    test(
      'un doublon exact sur un même poste ne viole pas la clé primaire',
      () async {
        final ids = await migrer('c', ['PRD-001|Goliath', 'PRD-001|Goliath']);

        expect(ids, hasLength(2));
        expect(ids.toSet(), hasLength(2));
      },
    );
  });
}
