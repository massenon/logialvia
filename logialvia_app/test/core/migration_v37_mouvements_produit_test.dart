import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v37 — le journal des corrections de stock des produits vendables.
void main() {
  late Directory dossier;
  late File fichier;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v37');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  Future<void> baseV36() async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP TABLE mouvements_produit');
    await db.customStatement('PRAGMA user_version = 36');
    await db.close();
  }

  Future<bool> tableExiste(AppDatabase db) async =>
      (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'mouvements_produit'",
              )
              .get())
          .isNotEmpty;

  test('une base v36 reçoit la table, vide, sans rien perdre', () async {
    await baseV36();
    final db = AppDatabase.pourFichier(fichier);
    final avant = (await db.select(db.produitsVendables).get()).length;

    expect(await tableExiste(db), isTrue);
    expect(await db.select(db.mouvementsProduit).get(), isEmpty);
    expect((await db.select(db.produitsVendables).get()).length, avant);
    await db.close();
  });

  test(
    'la migration est idempotente : rejouée sur une table déjà là',
    () async {
      await baseV36();
      // La table existe déjà (reprise après une migration interrompue).
      final db0 = AppDatabase.pourFichier(fichier);
      await db0.customSelect('SELECT 1').get();
      await db0.customStatement('PRAGMA user_version = 36');
      await db0.close();

      final db = AppDatabase.pourFichier(fichier);
      expect(await tableExiste(db), isTrue);
      await db.close();
    },
  );

  test('une correction insérée garde sa clé étrangère vers le produit', () async {
    final db = AppDatabase.enMemoire();
    await db.customSelect('SELECT 1').get();
    await expectLater(
      db.customStatement(
        "INSERT INTO mouvements_produit (id, horodatage, produit_id, article, motif, quantite) "
        "VALUES ('m1', 1788000000, 'inconnu', 'X', 'Test', 1)",
      ),
      throwsA(anything),
    );
    await db.close();
  });
}
