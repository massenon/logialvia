import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/domain/services/service_archivage.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';

/// Migration v39 — lots de couveuse et incubateurs en UUID (DV-19, palier 7b).
void main() {
  late Directory dossier;
  late File fichier;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  // 1er août 2026, 00:00 UTC.
  const premierAout = 1785542400;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v39');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  /// Une vraie base de l'ancien schéma (v37) : identifiants entiers, sans colonnes
  /// de synchronisation, avec des identifiants volontairement non consécutifs.
  Future<void> baseV37({bool homonymes = false}) async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP TABLE cycle_couveuse');
    await db.customStatement('DROP TABLE machines_incubateur');
    await db.customStatement(
      'CREATE TABLE machines_incubateur (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'code TEXT NOT NULL UNIQUE, libelle TEXT NOT NULL, '
      'capacite_oeufs INTEGER NULL, active INTEGER NOT NULL DEFAULT 1)',
    );
    await db.customStatement(
      'CREATE TABLE cycle_couveuse (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'code_incubation TEXT NOT NULL UNIQUE, espece TEXT NOT NULL DEFAULT \'goliath\', '
      'bande_reproducteurs TEXT NULL, date_incubation INTEGER NOT NULL, '
      'oeufs_couves INTEGER NOT NULL, poussins_nes INTEGER NULL, oeufs_perdus INTEGER NULL, '
      'statut TEXT NOT NULL, machine_id INTEGER NULL REFERENCES machines_incubateur (id), '
      'oeufs_blancs_j7 INTEGER NULL, oeufs_gates_j14 INTEGER NULL, lot_parent_id INTEGER NULL)',
    );
    await db.customStatement(
      "INSERT INTO machines_incubateur (id, code, libelle, capacite_oeufs, active) VALUES "
      "(3, 'INC-01', 'Couveuse atelier', 528, 1), "
      "(8, ${homonymes ? "'inc-01'" : "'INC-02'"}, 'Couveuse annexe', NULL, 0)",
    );
    await db.customStatement(
      'INSERT INTO cycle_couveuse (id, code_incubation, espece, date_incubation, '
      'oeufs_couves, poussins_nes, oeufs_perdus, statut, machine_id, '
      'oeufs_blancs_j7, oeufs_gates_j14, lot_parent_id) VALUES '
      "(5, 'C-2026-001', 'goliath', $premierAout, 200, 149, 18, 'Remplacé', 3, 22, 11, NULL), "
      "(11, 'C-2026-002', 'goliath', ${premierAout + 21 * 86400}, 180, NULL, NULL, 'En Incubation', 3, NULL, NULL, 5), "
      "(20, 'C-2026-003', 'pintade', ${premierAout + 30 * 86400}, 150, NULL, NULL, 'En Incubation', 8, 19, NULL, NULL), "
      "(30, 'C-2026-004', 'goliath', ${premierAout + 40 * 86400}, 120, NULL, NULL, 'En Incubation', NULL, NULL, NULL, NULL)",
    );
    // Un lot supprimé avant la migration : son instantané porte les anciens entiers.
    await db.customStatement(
      'INSERT INTO corbeille (nom_table, module, type_element, designation, '
      'donnees_json, archive_le) VALUES (?, ?, ?, ?, ?, ?)',
      [
        'cycle_couveuse',
        'Élevage',
        'Lot d\'incubation',
        'C-2026-099 — 90 œufs',
        jsonEncode({
          'id': 99,
          'code_incubation': 'C-2026-099',
          'espece': 'goliath',
          'bande_reproducteurs': null,
          'date_incubation': premierAout,
          'oeufs_couves': 90,
          'poussins_nes': null,
          'oeufs_perdus': null,
          'statut': 'En Incubation',
          'machine_id': 3,
          'oeufs_blancs_j7': null,
          'oeufs_gates_j14': null,
          'lot_parent_id': 5,
        }),
        premierAout,
      ],
    );
    await db.customStatement('PRAGMA user_version = 37');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  test(
    'chaque lot et chaque incubateur reçoit un UUID, aucune ligne perdue',
    () async {
      await baseV37();
      final db = AppDatabase.pourFichier(fichier);

      final lots = await lire(
        db,
        'SELECT * FROM cycle_couveuse ORDER BY code_incubation',
      );
      final machines = await lire(
        db,
        'SELECT * FROM machines_incubateur ORDER BY code',
      );

      expect(lots, hasLength(4), reason: 'jamais de perte de ligne');
      expect(machines, hasLength(2));
      for (final r in [...lots, ...machines]) {
        expect(r['id'], matches(uuid));
      }
      expect(lots.map((r) => r['id']).toSet(), hasLength(4));
      expect(lots.map((r) => r['code_incubation']), [
        'C-2026-001',
        'C-2026-002',
        'C-2026-003',
        'C-2026-004',
      ]);
      // Rien d'autre ne bouge.
      expect(lots[0]['oeufs_couves'], 200);
      expect(lots[0]['poussins_nes'], 149);
      expect(lots[0]['oeufs_perdus'], 18);
      expect(lots[0]['oeufs_blancs_j7'], 22);
      expect(lots[0]['oeufs_gates_j14'], 11);
      expect(lots[0]['statut'], 'Remplacé');
      expect(lots[0]['date_incubation'], premierAout);
      expect(lots[2]['espece'], 'pintade');
      expect(machines[0]['capacite_oeufs'], 528);
      expect(machines[1]['active'], 0);
      await db.close();
    },
  );

  test('chaque lot garde son incubateur et son lot d\'origine', () async {
    await baseV37();
    final db = AppDatabase.pourFichier(fichier);

    final jointure = await lire(
      db,
      'SELECT c.code_incubation AS lot, m.code AS machine, p.code_incubation AS parent '
      'FROM cycle_couveuse c '
      'LEFT JOIN machines_incubateur m ON m.id = c.machine_id '
      'LEFT JOIN cycle_couveuse p ON p.id = c.lot_parent_id '
      'ORDER BY c.code_incubation',
    );

    expect(jointure.map((r) => [r['lot'], r['machine'], r['parent']]), [
      ['C-2026-001', 'INC-01', null],
      ['C-2026-002', 'INC-01', 'C-2026-001'],
      ['C-2026-003', 'INC-02', null],
      ['C-2026-004', null, null],
    ]);
    expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
    await db.close();
  });

  test('l\'incubateur reçoit un UUID déterministe depuis son code', () async {
    await baseV37();
    final db = AppDatabase.pourFichier(fichier);

    final m = await lire(
      db,
      'SELECT id, code FROM machines_incubateur ORDER BY code',
    );

    expect(m[0]['id'], uuidDeterministe('machine:inc-01'));
    expect(m[1]['id'], uuidDeterministe('machine:inc-02'));
    await db.close();
  });

  test(
    'deux codes qui ne diffèrent que par la casse restent deux incubateurs',
    () async {
      await baseV37(homonymes: true);
      final db = AppDatabase.pourFichier(fichier);

      final m = await lire(db, 'SELECT id FROM machines_incubateur');

      expect(m, hasLength(2));
      expect(m.map((r) => r['id']).toSet(), hasLength(2));
      await db.close();
    },
  );

  test(
    'les lots d\'hier sont à envoyer, saisis le jour de leur chargement',
    () async {
      await baseV37();
      final db = AppDatabase.pourFichier(fichier);

      final lots = await lire(
        db,
        'SELECT code_incubation, sync_status, sync_motif, updated_at FROM cycle_couveuse '
        'ORDER BY code_incubation',
      );
      for (final r in lots) {
        expect(r['sync_status'], 'pending');
        expect(r['sync_motif'], isNull);
      }
      expect(
        lots.first['updated_at'],
        DateTime.fromMillisecondsSinceEpoch(
          premierAout * 1000,
          isUtc: true,
        ).toIso8601String(),
        reason:
            'l\'instant de la migration ferait gagner un vieux lot contre une '
            'correction faite ailleurs',
      );
      final machines = await lire(
        db,
        'SELECT sync_status, updated_at FROM machines_incubateur',
      );
      for (final r in machines) {
        expect(r['sync_status'], 'pending');
        expect(r['updated_at'], isNotNull);
      }
      await db.close();
    },
  );

  test(
    'un lot déjà supprimé garde sa trace : instantané réécrit, restaurable',
    () async {
      await baseV37();
      final db = AppDatabase.pourFichier(fichier);

      final archive = (await lire(db, 'SELECT * FROM corbeille')).single;
      final donnees =
          jsonDecode(archive['donnees_json']! as String)
              as Map<String, Object?>;
      expect(donnees['id'], matches(uuid));
      final machine = (await lire(
        db,
        "SELECT id FROM machines_incubateur WHERE code = 'INC-01'",
      )).single['id'];
      final parent = (await lire(
        db,
        "SELECT id FROM cycle_couveuse WHERE code_incubation = 'C-2026-001'",
      )).single['id'];
      expect(donnees['machine_id'], machine);
      expect(donnees['lot_parent_id'], parent);

      await ServiceArchivage(
        db,
      ).restaurer(archive['id']! as int, estAdmin: false);

      final revenu = (await lire(
        db,
        "SELECT * FROM cycle_couveuse WHERE code_incubation = 'C-2026-099'",
      )).single;
      expect(revenu['id'], donnees['id']);
      expect(revenu['sync_status'], 'pending');
      expect(revenu['updated_at'], isNotNull);
      expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    },
  );

  test(
    'base à la version courante, rejouée (estampillée 37 à tort) : aucun UUID ne change',
    () async {
      await baseV37();
      var db = AppDatabase.pourFichier(fichier);
      final lotsAvant = await lire(
        db,
        'SELECT id FROM cycle_couveuse ORDER BY code_incubation',
      );
      final machinesAvant = await lire(
        db,
        'SELECT id FROM machines_incubateur ORDER BY code',
      );
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.first, AppDatabase.versionSchema);
      expect(
        AppDatabase.versionSchema,
        greaterThanOrEqualTo(39),
        reason: 'la couveuse en UUID est le schéma 39',
      );
      await db.customStatement('PRAGMA user_version = 37');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      expect(
        await lire(
          db,
          'SELECT id FROM cycle_couveuse ORDER BY code_incubation',
        ),
        lotsAvant,
      );
      expect(
        await lire(db, 'SELECT id FROM machines_incubateur ORDER BY code'),
        machinesAvant,
      );
      expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    },
  );

  test('une base neuve crée directement les tables en UUID', () async {
    final db = AppDatabase.enMemoire();
    await db.customSelect('SELECT 1').get();
    for (final table in ['cycle_couveuse', 'machines_incubateur']) {
      final c = await lire(db, 'PRAGMA table_info("$table")');
      expect(c.firstWhere((r) => r['name'] == 'id')['type'], 'TEXT');
      expect(
        c.map((r) => r['name']),
        containsAll(['sync_status', 'sync_motif', 'updated_at']),
      );
    }
    final c = await lire(db, 'PRAGMA table_info("cycle_couveuse")');
    expect(c.firstWhere((r) => r['name'] == 'machine_id')['type'], 'TEXT');
    expect(c.firstWhere((r) => r['name'] == 'lot_parent_id')['type'], 'TEXT');
    await db.close();
  });
}
