import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v42 — `factures` reçoit son UUID, son origine et les colonnes de
/// synchronisation ; `lignes_facture` passe en UUID (DV-19, palier P9).
///
/// Les risques : perdre une facture ou une ligne, changer un numéro officiel
/// (DV-21), faire gagner une vieille facture contre une correction faite ailleurs,
/// ne pas pouvoir rejouer la migration après une interruption, ou toucher à la
/// grille de taxation.
void main() {
  late Directory dossier;
  late File fichier;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v42');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  const dateFacture = 1788000000; // 2026-08-29T09:20:00Z
  const dateNormalisation = 1788100000; // un peu plus tard

  /// Une base v41 : schéma courant, sauf `factures` et `lignes_facture` remises
  /// dans leur état v41 (entiers auto-incrémentés, aucune colonne de synchro).
  /// [lignesSeules] : la migration a déjà converti `factures` (interrompue entre
  /// les deux tables).
  Future<void> baseV41({bool facturesDejaMigrees = false}) async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP TABLE lignes_facture');
    await db.customStatement('DROP TABLE factures');
    await db.customStatement(
      'CREATE TABLE lignes_facture (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      'facture_ref TEXT NOT NULL, designation TEXT NOT NULL, quantite REAL NOT NULL, '
      'unite TEXT NULL, prix_unitaire_ht REAL NOT NULL, groupe_taxe TEXT NOT NULL, '
      'taux_taxe REAL NOT NULL, montant_ht REAL NOT NULL, montant_taxe REAL NOT NULL)',
    );
    if (facturesDejaMigrees) {
      await db.customStatement(
        'CREATE TABLE factures (id TEXT NOT NULL DEFAULT \'x\', origine TEXT NULL, '
        'sync_status TEXT NOT NULL DEFAULT \'pending\', sync_motif TEXT NULL, '
        'updated_at TEXT NOT NULL DEFAULT \'2026-01-01T00:00:00.000Z\', '
        'ref TEXT NOT NULL PRIMARY KEY, type TEXT NOT NULL, vente_ref TEXT NULL, '
        'origine_ref TEXT NULL, date_facture INTEGER NOT NULL, client TEXT NOT NULL, '
        'client_ifu TEXT NULL, client_adresse TEXT NULL, total_ht REAL NOT NULL, '
        'total_taxe REAL NOT NULL, total_ttc REAL NOT NULL, motif TEXT NULL, '
        'statut TEXT NOT NULL, code_mecef TEXT NULL, nim TEXT NULL, compteur TEXT NULL, '
        'lien_verification TEXT NULL, date_normalisation INTEGER NULL, '
        'erreur_transmission TEXT NULL, cree_le INTEGER NOT NULL DEFAULT 0, '
        'UNIQUE (id))',
      );
    } else {
      await db.customStatement(
        'CREATE TABLE factures (ref TEXT NOT NULL PRIMARY KEY, type TEXT NOT NULL, '
        'vente_ref TEXT NULL, origine_ref TEXT NULL, date_facture INTEGER NOT NULL, '
        'client TEXT NOT NULL, client_ifu TEXT NULL, client_adresse TEXT NULL, '
        'total_ht REAL NOT NULL, total_taxe REAL NOT NULL, total_ttc REAL NOT NULL, '
        'motif TEXT NULL, statut TEXT NOT NULL, code_mecef TEXT NULL, nim TEXT NULL, '
        'compteur TEXT NULL, lien_verification TEXT NULL, date_normalisation INTEGER NULL, '
        'erreur_transmission TEXT NULL, cree_le INTEGER NOT NULL DEFAULT 0)',
      );
    }
    final colonnes = facturesDejaMigrees ? 'id, ref, ' : 'ref, ';
    String id(int n) =>
        facturesDejaMigrees ? "'f000000$n-0000-4000-8000-00000000000$n', " : '';
    await db.customStatement(
      'INSERT INTO factures ($colonnes type, vente_ref, origine_ref, date_facture, '
      'client, total_ht, total_taxe, total_ttc, motif, statut, code_mecef, nim, '
      'compteur, date_normalisation) VALUES '
      "(${id(1)}'FV-2026-001', 'FV', 'V-2026-001', NULL, $dateFacture, 'DOSSOU', 10000, 1800, 11800, NULL, "
      "'normalisee', 'CODE-1', 'NIM-1', '1/9', $dateNormalisation), "
      "(${id(2)}'FV-2026-002', 'FV', 'V-2026-002', NULL, $dateFacture, 'Mama Rita', 5000, 0, 5000, NULL, "
      "'a_transmettre', NULL, NULL, NULL, NULL), "
      "(${id(3)}'FA-2026-001', 'FA', NULL, 'FV-2026-001', $dateFacture, 'DOSSOU', 10000, 1800, 11800, 'Retour', "
      "'rejetee', NULL, NULL, NULL, NULL)",
    );
    await db.customStatement(
      'INSERT INTO lignes_facture (facture_ref, designation, quantite, prix_unitaire_ht, '
      'groupe_taxe, taux_taxe, montant_ht, montant_taxe) VALUES '
      "('FV-2026-001', 'Goliath', 1, 10000, 'B', 18, 10000, 1800), "
      "('FV-2026-002', 'Oeufs', 5, 1000, 'A', 0, 5000, 0), "
      "('FA-2026-001', 'Goliath', 1, 10000, 'B', 18, 10000, 1800)",
    );
    await db.customStatement('PRAGMA user_version = 41');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  test(
    'chaque facture reçoit un UUID distinct, rien d\'autre ne bouge',
    () async {
      await baseV41();
      final db = AppDatabase.pourFichier(fichier);
      final f = await lire(db, 'SELECT * FROM factures ORDER BY ref');

      expect(f, hasLength(3));
      final ids = f.map((r) => r['id']! as String).toList();
      for (final id in ids) {
        expect(id, matches(uuid));
      }
      expect(ids.toSet(), hasLength(3));
      expect(f.map((r) => r['ref']), [
        'FA-2026-001',
        'FV-2026-001',
        'FV-2026-002',
      ], reason: 'le numéro officiel ne change JAMAIS (DV-21)');
      final fv1 = f.firstWhere((r) => r['ref'] == 'FV-2026-001');
      expect(fv1['statut'], 'normalisee');
      expect(fv1['code_mecef'], 'CODE-1');
      expect(fv1['nim'], 'NIM-1');
      expect(fv1['compteur'], '1/9');
      expect(fv1['total_ttc'], 11800);
      expect(fv1['date_facture'], dateFacture);
      expect(fv1['date_normalisation'], dateNormalisation);
      expect(
        f.firstWhere((r) => r['ref'] == 'FA-2026-001')['origine_ref'],
        'FV-2026-001',
      );
      await db.close();
    },
  );

  test('les lignes survivent, chacune à sa facture, avec un UUID', () async {
    await baseV41();
    final db = AppDatabase.pourFichier(fichier);
    final l = await lire(
      db,
      'SELECT id, facture_ref, designation, quantite FROM lignes_facture ORDER BY facture_ref',
    );

    expect(l, hasLength(3), reason: 'jamais de perte de ligne');
    expect(l.map((r) => r['facture_ref']), [
      'FA-2026-001',
      'FV-2026-001',
      'FV-2026-002',
    ]);
    for (final r in l) {
      expect(r['id'], matches(uuid));
    }
    expect(l.map((r) => r['id']).toSet(), hasLength(3));
    expect(l.last['quantite'], 5);
    await db.close();
  });

  test(
    'toutes les factures d\'hier sont à envoyer, sans origine, avec leur dernier instant de saisie',
    () async {
      await baseV41();
      final db = AppDatabase.pourFichier(fichier);
      final f = {
        for (final r in await lire(
          db,
          'SELECT ref, sync_status, sync_motif, origine, updated_at FROM factures',
        ))
          r['ref']: r,
      };

      for (final r in f.values) {
        expect(r['sync_status'], 'pending');
        expect(r['sync_motif'], isNull);
        expect(r['origine'], isNull, reason: 'émise sur ce poste');
      }
      DateTime instant(Object? v) => DateTime.parse(v! as String);
      DateTime unix(int s) =>
          DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
      expect(
        instant(
          f['FV-2026-001']!['updated_at'],
        ).difference(unix(dateNormalisation)).inSeconds.abs(),
        lessThan(2),
        reason: 'une facture normalisée a été saisie à sa normalisation',
      );
      expect(
        instant(
          f['FV-2026-002']!['updated_at'],
        ).difference(unix(dateFacture)).inSeconds.abs(),
        lessThan(2),
        reason: 'sinon, à son émission — pas l\'instant de la migration',
      );
      await db.close();
    },
  );

  test('la grille de taxation n\'est pas touchée', () async {
    await baseV41();
    var db = AppDatabase.pourFichier(fichier);
    await db.customStatement(
      "INSERT INTO groupes_taxe (code, libelle, taux, ordre) VALUES "
      "('A', 'Exonéré', 0, 1), ('B', 'Taux normal 18 %', 19, 2)",
    );
    await db.customStatement('PRAGMA user_version = 41');
    await db.close();

    db = AppDatabase.pourFichier(fichier);
    expect(
      await lire(db, 'SELECT code, taux FROM groupes_taxe ORDER BY code'),
      [
        {'code': 'A', 'taux': 0.0},
        {'code': 'B', 'taux': 19.0},
      ],
      reason: 'une correction manuelle de la grille survit',
    );
    await db.close();
  });

  test(
    'intégrité référentielle intacte, base estampillée à la version courante',
    () async {
      await baseV41();
      final db = AppDatabase.pourFichier(fichier);
      await db.customSelect('SELECT 1').get();
      expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.first, AppDatabase.versionSchema);
      expect(AppDatabase.versionSchema, 42);
      await db.close();
    },
  );

  test(
    'rejouée (version estampillée 41 à tort), aucun UUID ne change',
    () async {
      await baseV41();
      var db = AppDatabase.pourFichier(fichier);
      final avant = await lire(db, 'SELECT ref, id FROM factures ORDER BY ref');
      final avantLignes = await lire(
        db,
        'SELECT id FROM lignes_facture ORDER BY id',
      );
      await db.customStatement('PRAGMA user_version = 41');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      expect(
        await lire(db, 'SELECT ref, id FROM factures ORDER BY ref'),
        avant,
      );
      expect(
        await lire(db, 'SELECT id FROM lignes_facture ORDER BY id'),
        avantLignes,
      );
      expect(await lire(db, 'SELECT COUNT(*) AS n FROM lignes_facture'), [
        {'n': 3},
      ]);
      await db.close();
    },
  );

  test(
    'interrompue entre les deux tables : reprend où elle s\'est arrêtée, sans changer un UUID de facture',
    () async {
      await baseV41(facturesDejaMigrees: true);
      final db = AppDatabase.pourFichier(fichier);

      final f = await lire(db, 'SELECT ref, id FROM factures ORDER BY ref');
      expect(f.map((r) => r['id']), [
        'f0000003-0000-4000-8000-000000000003',
        'f0000001-0000-4000-8000-000000000001',
        'f0000002-0000-4000-8000-000000000002',
      ], reason: 'les factures déjà converties ne sont pas retouchées');
      final l = await lire(db, 'SELECT id FROM lignes_facture');
      expect(l, hasLength(3));
      for (final r in l) {
        expect(
          r['id'],
          matches(uuid),
          reason: 'les lignes, elles, sont converties',
        );
      }
      await db.close();
    },
  );

  test('deux factures ne peuvent pas porter le même UUID', () async {
    await baseV41();
    final db = AppDatabase.pourFichier(fichier);
    final id = (await lire(
      db,
      "SELECT id FROM factures WHERE ref = 'FV-2026-001'",
    )).single['id'];
    await expectLater(
      db.customStatement(
        "UPDATE factures SET id = '$id' WHERE ref = 'FV-2026-002'",
      ),
      throwsA(anything),
    );
    await db.close();
  });

  test('une base neuve crée directement les tables en UUID', () async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    final colonnes = await lire(db, 'PRAGMA table_info("lignes_facture")');
    expect(colonnes.firstWhere((c) => c['name'] == 'id')['type'], 'TEXT');
    final f = await lire(db, 'PRAGMA table_info("factures")');
    expect(
      f.map((c) => c['name']),
      containsAll(['id', 'origine', 'sync_status', 'sync_motif', 'updated_at']),
    );
    await db.close();
  });
}
