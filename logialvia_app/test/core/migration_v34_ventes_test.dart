import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v34 — `ventes` reçoit son UUID, son `client_id` et les colonnes de
/// synchronisation (DV-19, palier 3b). Le risque : que la reconstruction de la
/// table des ventes emporte ses lignes (`ON DELETE CASCADE`).
void main() {
  late Directory dossier;
  late File fichier;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v34');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  const dateVente = 1788000000; // 2026-08-29T09:20:00Z

  /// Une base v33 : schéma courant, sauf `ventes` remise dans son état v33.
  Future<void> baseV33() async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP TABLE lignes_vente');
    await db.customStatement('DROP TABLE ventes');
    await db.customStatement(
      'CREATE TABLE ventes (ref TEXT NOT NULL PRIMARY KEY, client TEXT NOT NULL, '
      'date_vente INTEGER NOT NULL, mode TEXT NOT NULL, status TEXT NOT NULL, '
      'total REAL NOT NULL, paye REAL NOT NULL, motif_annulation TEXT NULL, '
      'livraison_mode TEXT NULL, livraison_frais REAL NULL, livraison_adresse TEXT NULL, '
      'livraison_contact TEXT NULL, echeance INTEGER NULL, ligne_mobile_money TEXT NULL)',
    );
    await db.customStatement(
      'CREATE TABLE lignes_vente (id TEXT NOT NULL PRIMARY KEY, '
      'vente_ref TEXT NOT NULL REFERENCES ventes (ref) ON DELETE CASCADE, '
      'produit_id TEXT NOT NULL REFERENCES produits_vendables (id), '
      'name TEXT NOT NULL, qte REAL NOT NULL, pu REAL NOT NULL, espece TEXT NULL)',
    );
    await db.customStatement(
      "INSERT INTO produits_vendables (id, name, cat, price, unit, icon, stock, threshold) VALUES "
      "('11111111-1111-4111-8111-111111111111', 'Goliath', 'Avicole', 25000, 'u', 'egg', 10, 2)",
    );
    await db.customStatement(
      "INSERT INTO clients (id, nom, updated_at) VALUES "
      "('c0000001-0000-4000-8000-000000000001', 'DOSSOU Félicité', '2026-08-01T00:00:00.000Z'), "
      "('c0000002-0000-4000-8000-000000000002', 'Mama Rita', '2026-08-01T00:00:00.000Z'), "
      "('c0000003-0000-4000-8000-000000000003', 'MAMA RITA ', '2026-08-01T00:00:00.000Z')",
    );
    await db.customStatement(
      'INSERT INTO ventes (ref, client, date_vente, mode, status, total, paye) VALUES '
      "('V-2026-001', 'dossou félicité', $dateVente, 'Espèces', 'Payée', 50000, 50000), "
      "('V-2026-002', 'Mama Rita', $dateVente, 'Espèces', 'Avance', 25000, 5000), "
      "('V-2026-003', 'Client Comptant', $dateVente, 'Espèces', 'Payée', 25000, 25000)",
    );
    await db.customStatement(
      "INSERT INTO lignes_vente (id, vente_ref, produit_id, name, qte, pu) VALUES "
      "('l0000001-0000-4000-8000-000000000001', 'V-2026-001', '11111111-1111-4111-8111-111111111111', 'Goliath', 2, 25000), "
      "('l0000002-0000-4000-8000-000000000002', 'V-2026-002', '11111111-1111-4111-8111-111111111111', 'Goliath', 1, 25000), "
      "('l0000003-0000-4000-8000-000000000003', 'V-2026-003', '11111111-1111-4111-8111-111111111111', 'Goliath', 1, 25000)",
    );
    await db.customStatement('PRAGMA user_version = 33');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  test(
    'chaque vente reçoit un UUID distinct, rien d\'autre ne bouge',
    () async {
      await baseV33();
      final db = AppDatabase.pourFichier(fichier);
      final v = await lire(db, 'SELECT * FROM ventes ORDER BY ref');

      expect(v, hasLength(3));
      final ids = v.map((r) => r['id']! as String).toList();
      for (final id in ids) {
        expect(id, matches(uuid));
      }
      expect(ids.toSet(), hasLength(3));
      expect(v.map((r) => r['ref']), [
        'V-2026-001',
        'V-2026-002',
        'V-2026-003',
      ], reason: 'le numéro officiel ne change JAMAIS (DV-21)');
      expect(v[1]['total'], 25000);
      expect(v[1]['paye'], 5000);
      expect(v[1]['date_vente'], dateVente);
      await db.close();
    },
  );

  test(
    'les lignes de vente survivent à la reconstruction (pas de cascade)',
    () async {
      await baseV33();
      final db = AppDatabase.pourFichier(fichier);
      final l = await lire(
        db,
        'SELECT vente_ref, qte FROM lignes_vente ORDER BY vente_ref',
      );

      expect(
        l,
        hasLength(3),
        reason: 'aucune ligne emportée par ON DELETE CASCADE',
      );
      expect(l.map((r) => r['vente_ref']), [
        'V-2026-001',
        'V-2026-002',
        'V-2026-003',
      ]);
      expect(l.first['qte'], 2);
      await db.close();
    },
  );

  test(
    'client_id : un seul client du nom → lié ; homonymes ou nom libre → vide',
    () async {
      await baseV33();
      final db = AppDatabase.pourFichier(fichier);
      final v = {
        for (final r in await lire(db, 'SELECT ref, client_id FROM ventes'))
          r['ref']: r['client_id'],
      };

      expect(
        v['V-2026-001'],
        'c0000001-0000-4000-8000-000000000001',
        reason: 'casse et accents du nom ignorés, un seul client : lié',
      );
      expect(
        v['V-2026-002'],
        isNull,
        reason: 'deux clients « Mama Rita » : on ne devine pas qui a acheté',
      );
      expect(v['V-2026-003'], isNull, reason: 'nom libre : aucun client');
      await db.close();
    },
  );

  test(
    'les ventes existantes sont à envoyer, avec leur date de vente comme instant de saisie',
    () async {
      await baseV33();
      final db = AppDatabase.pourFichier(fichier);
      final attendu = DateTime.fromMillisecondsSinceEpoch(
        dateVente * 1000,
        isUtc: true,
      );

      for (final r in await lire(
        db,
        'SELECT sync_status, sync_motif, updated_at FROM ventes',
      )) {
        expect(r['sync_status'], 'pending');
        expect(r['sync_motif'], isNull);
        expect(
          DateTime.parse(
            r['updated_at']! as String,
          ).difference(attendu).inSeconds.abs(),
          lessThan(2),
          reason:
              'pas l\'instant de la migration : il ferait gagner une vieille vente contre une correction',
        );
      }
      await db.close();
    },
  );

  test(
    'intégrité référentielle intacte, base estampillée à la version courante',
    () async {
      await baseV33();
      final db = AppDatabase.pourFichier(fichier);
      await db.customSelect('SELECT 1').get();
      expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.first, AppDatabase.versionSchema);
      await db.close();
    },
  );

  test(
    'rejouée (version estampillée 33 à tort), aucun UUID ne change',
    () async {
      await baseV33();
      var db = AppDatabase.pourFichier(fichier);
      final avant = await lire(
        db,
        'SELECT ref, id, client_id FROM ventes ORDER BY ref',
      );
      await db.customStatement('PRAGMA user_version = 33');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      expect(
        await lire(db, 'SELECT ref, id, client_id FROM ventes ORDER BY ref'),
        avant,
      );
      expect(await lire(db, 'SELECT COUNT(*) AS n FROM lignes_vente'), [
        {'n': 3},
      ]);
      await db.close();
    },
  );

  test('deux ventes ne peuvent pas porter le même UUID', () async {
    await baseV33();
    final db = AppDatabase.pourFichier(fichier);
    final id = (await lire(
      db,
      "SELECT id FROM ventes WHERE ref = 'V-2026-001'",
    )).single['id'];
    await expectLater(
      db.customStatement(
        "UPDATE ventes SET id = '$id' WHERE ref = 'V-2026-002'",
      ),
      throwsA(anything),
    );
    await db.close();
  });
}
