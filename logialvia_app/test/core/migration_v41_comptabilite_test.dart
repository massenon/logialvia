import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';

/// Migration v41 (P8) — la comptabilité en UUID, regroupée par pièce, prête à envoyer.
///
/// Part d'une VRAIE base v40 : les 4 tables comptables sont recréées dans leur forme
/// d'avant (clés entières), remplies, puis la base est rouverte par l'application.
void main() {
  late Directory dossier;
  late File fichier;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[45][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v41');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  Future<void> baseV40({bool avecEcritures = true}) async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    for (final t in const [
      'ecriture_comptable',
      'notes_annexes',
      'clotures_periodiques',
      'exercice_comptable',
    ]) {
      await db.customStatement('DROP TABLE $t');
    }
    await db.customStatement(
      'CREATE TABLE exercice_comptable (annee INTEGER NOT NULL PRIMARY KEY, '
      'is_cloture INTEGER NOT NULL DEFAULT 0 CHECK (is_cloture IN (0, 1)), '
      'date_cloture INTEGER NULL)',
    );
    await db.customStatement(
      'CREATE TABLE ecriture_comptable (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'exercice_annee INTEGER NOT NULL REFERENCES exercice_comptable (annee), '
      'numero_compte TEXT NOT NULL REFERENCES plan_comptable (numero_compte), '
      'date_ecriture INTEGER NOT NULL, debit REAL NOT NULL DEFAULT 0, '
      'credit REAL NOT NULL DEFAULT 0, libelle TEXT NOT NULL, '
      "journal_code TEXT NOT NULL DEFAULT 'OD', numero_piece TEXT NULL, "
      'vente_ref TEXT NULL, achat_ref TEXT NULL, axe_analytique TEXT NULL, '
      'is_locked INTEGER NOT NULL DEFAULT 0 CHECK (is_locked IN (0, 1)))',
    );
    await db.customStatement(
      'CREATE TABLE notes_annexes (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'exercice_annee INTEGER NOT NULL REFERENCES exercice_comptable (annee), '
      'numero_note INTEGER NOT NULL, titre TEXT NOT NULL, contenu TEXT NOT NULL, '
      'UNIQUE (exercice_annee, numero_note))',
    );
    await db.customStatement(
      'CREATE TABLE clotures_periodiques (annee INTEGER NOT NULL, mois INTEGER NOT NULL, '
      'is_cloture INTEGER NOT NULL DEFAULT 0 CHECK (is_cloture IN (0, 1)), '
      'date_cloture INTEGER NULL, decloture_par_utilisateur_id TEXT NULL, '
      'PRIMARY KEY (annee, mois))',
    );
    await db.customStatement(
      "INSERT OR IGNORE INTO plan_comptable (numero_compte, libelle, classe, archive) VALUES "
      "('531', 'Caisse', '5', 0), ('701', 'Ventes', '7', 0), ('624', 'Transports', '6', 0)",
    );
    await db.customStatement(
      'INSERT INTO exercice_comptable (annee, is_cloture, date_cloture) VALUES '
      '(2025, 1, 1767225600), (2026, 0, NULL)',
    );
    if (avecEcritures) {
      await db.customStatement(
        'INSERT INTO ecriture_comptable (id, exercice_annee, numero_compte, date_ecriture, '
        'debit, credit, libelle, journal_code, numero_piece, vente_ref, is_locked) VALUES '
        // pièce VT 1 : deux lignes, même numéro
        "(11, 2026, '531', 1788000000, 12000, 0, 'Encaissement', 'VT', 'V-2026-001', 'V-2026-001', 0), "
        "(12, 2026, '701', 1788000000, 0, 12000, 'Vente', 'VT', 'V-2026-001', 'V-2026-001', 0), "
        // pièce DEP : deux lignes
        "(13, 2026, '624', 1788100000, 3500, 0, 'Transport', 'CA', 'DEP-2026-0001', NULL, 0), "
        "(14, 2026, '531', 1788100000, 0, 3500, 'Transport', 'CA', 'DEP-2026-0001', NULL, 0), "
        // exercice clos
        "(15, 2025, '531', 1767000000, 500, 0, 'Ancienne', 'OD', 'OD-2025-0001', NULL, 1), "
        "(16, 2025, '701', 1767000000, 0, 500, 'Ancienne', 'OD', 'OD-2025-0001', NULL, 1)",
      );
      // Même numéro de pièce REG-… réutilisé (règlements partiels) : un seul groupe.
      await db.customStatement(
        'INSERT INTO ecriture_comptable (id, exercice_annee, numero_compte, date_ecriture, '
        'debit, credit, libelle, journal_code, numero_piece) VALUES '
        "(17, 2026, '531', 1788200000, 100, 0, 'Reg 1', 'CA', 'REG-V-2026-001'), "
        "(18, 2026, '701', 1788200000, 0, 100, 'Reg 1', 'CA', 'REG-V-2026-001'), "
        "(19, 2026, '531', 1788300000, 50, 0, 'Reg 2', 'CA', 'REG-V-2026-001'), "
        "(20, 2026, '701', 1788300000, 0, 50, 'Reg 2', 'CA', 'REG-V-2026-001')",
      );
      // Sans numéro de pièce : chaque ligne est SA pièce (on ne devine rien).
      await db.customStatement(
        'INSERT INTO ecriture_comptable (id, exercice_annee, numero_compte, date_ecriture, '
        'debit, credit, libelle, journal_code, numero_piece) VALUES '
        "(21, 2026, '531', 1788400000, 10, 0, 'Orpheline', 'OD', NULL)",
      );
    }
    await db.customStatement(
      "INSERT INTO notes_annexes (id, exercice_annee, numero_note, titre, contenu) VALUES "
      "(7, 2025, 1, 'Méthodes Comptables', 'Coût historique'), "
      "(9, 2025, 3, 'Stocks', 'CMUP')",
    );
    await db.customStatement(
      'INSERT INTO clotures_periodiques (annee, mois, is_cloture, date_cloture, '
      'decloture_par_utilisateur_id) VALUES (2025, 12, 1, 1767225600, NULL), '
      "(2026, 3, 0, NULL, 'admin')",
    );
    await db.customStatement('PRAGMA user_version = 40');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  test(
    'chaque ligne reçoit un UUID distinct, aucune ligne perdue, montants intacts',
    () async {
      await baseV40();
      final db = AppDatabase.pourFichier(fichier);
      final l = await lire(
        db,
        'SELECT * FROM ecriture_comptable ORDER BY date_ecriture, libelle, debit',
      );

      expect(
        l,
        hasLength(11),
        reason: 'les 11 lignes d\'avant, ni plus ni moins',
      );
      for (final r in l) {
        expect(r['id'], matches(uuid));
      }
      expect(l.map((r) => r['id']).toSet(), hasLength(11));

      final somme = await lire(
        db,
        'SELECT SUM(debit) AS d, SUM(credit) AS c FROM ecriture_comptable',
      );
      expect(somme.single['d'], 12000 + 3500 + 500 + 100 + 50 + 10);
      expect(somme.single['c'], 12000 + 3500 + 500 + 100 + 50);
      await db.close();
    },
  );

  test(
    'les lignes d\'une même pièce partagent un piece_id ; une ligne sans numéro est sa propre pièce',
    () async {
      await baseV40();
      final db = AppDatabase.pourFichier(fichier);
      final pieces = await lire(
        db,
        'SELECT numero_piece, COUNT(DISTINCT piece_id) AS n, COUNT(*) AS lignes '
        'FROM ecriture_comptable GROUP BY numero_piece',
      );
      final parNumero = {for (final p in pieces) p['numero_piece']: p};

      expect(parNumero['V-2026-001']!['n'], 1);
      expect(parNumero['V-2026-001']!['lignes'], 2);
      expect(parNumero['DEP-2026-0001']!['n'], 1);
      expect(parNumero['OD-2025-0001']!['n'], 1);
      // Les deux règlements partiels portent le même numéro : un seul groupe, équilibré.
      expect(parNumero['REG-V-2026-001']!['n'], 1);
      expect(parNumero['REG-V-2026-001']!['lignes'], 4);
      expect(parNumero[null]!['n'], 1);

      // Le piece_id d'une pièce n'est pas celui d'une autre.
      final distincts = await lire(
        db,
        'SELECT COUNT(DISTINCT piece_id) AS n FROM ecriture_comptable',
      );
      expect(distincts.single['n'], 5);

      // Chaque pièce regroupée reste équilibrée.
      final desequilibrees = await lire(
        db,
        'SELECT piece_id FROM ecriture_comptable GROUP BY piece_id '
        'HAVING ABS(SUM(debit) - SUM(credit)) > 0.001 AND COUNT(*) > 1',
      );
      expect(desequilibrees, isEmpty);
      await db.close();
    },
  );

  test(
    'les écritures d\'hier sont LOCALES (origine vide), à envoyer, saisies le jour de leur date',
    () async {
      await baseV40();
      final db = AppDatabase.pourFichier(fichier);
      for (final r in await lire(
        db,
        'SELECT origine, sync_status, sync_motif, updated_at, contrepasse_de, '
        'date_ecriture FROM ecriture_comptable',
      )) {
        expect(r['origine'], isNull);
        expect(r['sync_status'], 'pending');
        expect(r['sync_motif'], isNull);
        expect(r['contrepasse_de'], isNull);
        expect(
          DateTime.parse(r['updated_at'] as String).millisecondsSinceEpoch ~/
              1000,
          r['date_ecriture'],
        );
      }
      // Le verrou des exercices clos est conservé.
      final verrous = await lire(
        db,
        'SELECT COUNT(*) AS n FROM ecriture_comptable WHERE is_locked = 1',
      );
      expect(verrous.single['n'], 2);
      await db.close();
    },
  );

  test(
    'un exercice clos est « à envoyer », un exercice ouvert non ; les dates survivent',
    () async {
      await baseV40();
      final db = AppDatabase.pourFichier(fichier);
      final e = {
        for (final r in await lire(db, 'SELECT * FROM exercice_comptable'))
          r['annee']: r,
      };
      expect(e[2025]!['is_cloture'], 1);
      expect(e[2025]!['date_cloture'], 1767225600);
      expect(e[2025]!['sync_status'], 'pending');
      expect(e[2026]!['is_cloture'], 0);
      expect(e[2026]!['sync_status'], 'synced');
      expect(e[2025]!['updated_at'], startsWith('2026-01-01T'));
      await db.close();
    },
  );

  test(
    'les notes reçoivent un UUID déterministe de (exercice, numéro), contenu intact',
    () async {
      await baseV40();
      final db = AppDatabase.pourFichier(fichier);
      final n = await lire(
        db,
        'SELECT * FROM notes_annexes ORDER BY numero_note',
      );
      expect(n, hasLength(2));
      expect(n[0]['id'], uuidDeterministe('note:2025-1'));
      expect(n[1]['id'], uuidDeterministe('note:2025-3'));
      expect(n[0]['contenu'], 'Coût historique');
      expect(n[0]['sync_status'], 'pending');
      expect(n[0]['titre'], 'Méthodes Comptables');
      await db.close();
    },
  );

  test('les clôtures mensuelles gardent leurs valeurs et partent', () async {
    await baseV40();
    final db = AppDatabase.pourFichier(fichier);
    final c = await lire(
      db,
      'SELECT * FROM clotures_periodiques ORDER BY annee, mois',
    );
    expect(c, hasLength(2));
    expect(c[0]['is_cloture'], 1);
    expect(c[0]['sync_status'], 'pending');
    expect(c[1]['is_cloture'], 0);
    expect(c[1]['decloture_par_utilisateur_id'], 'admin');
    expect(c[1]['updated_at'], isNotNull);
    await db.close();
  });

  test(
    'intégrité référentielle intacte, tables temporaires supprimées, version courante',
    () async {
      await baseV40();
      final db = AppDatabase.pourFichier(fichier);
      await db.customSelect('SELECT 1').get();
      expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
      expect(
        await lire(
          db,
          "SELECT name FROM sqlite_master WHERE name LIKE '\\_map\\_%' ESCAPE '\\'",
        ),
        isEmpty,
      );
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.first, AppDatabase.versionSchema);
      await db.close();
    },
  );

  test(
    'rejouée (version estampillée 40 à tort), aucun identifiant ne change',
    () async {
      await baseV40();
      var db = AppDatabase.pourFichier(fichier);
      final avant = await lire(
        db,
        'SELECT id, piece_id FROM ecriture_comptable ORDER BY id',
      );
      final notes = await lire(db, 'SELECT id FROM notes_annexes ORDER BY id');
      await db.customStatement('PRAGMA user_version = 40');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      expect(
        await lire(
          db,
          'SELECT id, piece_id FROM ecriture_comptable ORDER BY id',
        ),
        avant,
      );
      expect(await lire(db, 'SELECT id FROM notes_annexes ORDER BY id'), notes);
      await db.close();
    },
  );

  test('une base de comptabilité vide migre sans erreur', () async {
    await baseV40(avecEcritures: false);
    final db = AppDatabase.pourFichier(fichier);
    expect(await lire(db, 'SELECT COUNT(*) AS n FROM ecriture_comptable'), [
      {'n': 0},
    ]);
    await db.close();
  });

  test('une base neuve crée directement le schéma v41', () async {
    final db = AppDatabase.enMemoire();
    await db.customSelect('SELECT 1').get();
    final e = await lire(db, 'PRAGMA table_info("ecriture_comptable")');
    expect(e.firstWhere((r) => r['name'] == 'id')['type'], 'TEXT');
    expect(
      e.map((r) => r['name']),
      containsAll([
        'piece_id',
        'origine',
        'sync_status',
        'sync_motif',
        'updated_at',
        'contrepasse_de',
      ]),
    );
    final n = await lire(db, 'PRAGMA table_info("notes_annexes")');
    expect(n.firstWhere((r) => r['name'] == 'id')['type'], 'TEXT');
    final x = await lire(db, 'PRAGMA table_info("exercice_comptable")');
    expect(x.map((r) => r['name']), containsAll(['sync_status', 'updated_at']));
    await db.close();
  });
}
