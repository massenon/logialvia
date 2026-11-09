import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/elevage/data/sync/identifiants_elevage.dart';

/// Migration v38 — fiches journalières, compteurs de ventes du jour et bandes en UUID ;
/// `soins_calendrier.bande_id` suit. Chaque test part d'une VRAIE base v37.
void main() {
  late Directory dossier;
  late File fichier;

  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  final uuidV5 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v38');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  int s(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

  /// Crée la base courante, puis REMET les quatre tables dans leur forme v37.
  Future<void> baseV37({bool avecIdentifiant = false}) async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    for (final t in [
      'fiche_journee',
      'fiche_ventes_jour',
      'bandes',
      'soins_calendrier',
    ]) {
      await db.customStatement('DROP TABLE $t');
    }
    await db.customStatement(
      'CREATE TABLE fiche_journee (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'espece TEXT NOT NULL, date INTEGER NOT NULL, '
      'achat INTEGER NOT NULL DEFAULT 0, ne INTEGER NOT NULL DEFAULT 0, vente INTEGER NOT NULL DEFAULT 0, '
      'mort_cat1 INTEGER NOT NULL DEFAULT 0, mort_cat2 INTEGER NOT NULL DEFAULT 0, mort_cat3 INTEGER NOT NULL DEFAULT 0, mort_cat4 INTEGER NULL, '
      'don_cat1 INTEGER NOT NULL DEFAULT 0, don_cat2 INTEGER NOT NULL DEFAULT 0, don_cat3 INTEGER NOT NULL DEFAULT 0, don_cat4 INTEGER NULL, '
      'effectif INTEGER NOT NULL DEFAULT 0, '
      'eff_cat1_day INTEGER NOT NULL DEFAULT 0, eff_cat2_day INTEGER NOT NULL DEFAULT 0, eff_cat3_day INTEGER NOT NULL DEFAULT 0, eff_cat4_day INTEGER NULL, '
      'srh INTEGER NULL, ts INTEGER NULL, stock_final_oeufs INTEGER NULL, '
      'oeufs_pondus INTEGER NULL, oeufs_casses INTEGER NULL, sorties_plateaux INTEGER NULL, '
      'poids_general_g INTEGER NULL, traitement_obs TEXT NULL, '
      'traitement_valide INTEGER NOT NULL DEFAULT 0, is_recorded INTEGER NOT NULL DEFAULT 0, '
      'UNIQUE (espece, date))',
    );
    await db.customStatement(
      'CREATE TABLE fiche_ventes_jour (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'espece TEXT NOT NULL, date INTEGER NOT NULL, qte INTEGER NOT NULL DEFAULT 0, '
      'UNIQUE (espece, date))',
    );
    await db.customStatement(
      'CREATE TABLE bandes (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'espece TEXT NOT NULL, code TEXT NOT NULL, date_mise_en_bande INTEGER NOT NULL, '
      'effectif_initial INTEGER NULL, date_cloture INTEGER NULL, observations TEXT NULL, '
      'UNIQUE (espece, code))',
    );
    await db.customStatement(
      'CREATE TABLE soins_calendrier (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'espece TEXT NOT NULL, date_prevue INTEGER NOT NULL, type_soin TEXT NOT NULL, '
      'statut TEXT NOT NULL, observations TEXT NULL, produit TEXT NULL, dose TEXT NULL, '
      'remanence_jours INTEGER NOT NULL DEFAULT 0, veterinaire TEXT NULL, symptomes TEXT NULL, '
      'cout_fcfa INTEGER NOT NULL DEFAULT 0, bande_id INTEGER NULL, '
      'echeance_prophylaxie_id INTEGER NULL)',
    );

    final j1 = s(DateTime(2026, 10, 30));
    final j2 = s(DateTime(2026, 11, 1));
    await db.customStatement(
      'INSERT INTO fiche_journee (id, espece, date, achat, ne, effectif, eff_cat1_day, eff_cat2_day, eff_cat3_day, '
      'poids_general_g, traitement_obs, traitement_valide, is_recorded) VALUES '
      "(3, 'goliaths', $j1, 20, 0, 20, 20, 0, 0, 1500, 'RAS', 1, 1), "
      "(8, 'goliaths', $j2, 0, 5, 25, 25, 0, 0, NULL, NULL, 0, 1), "
      "(9, 'pondeuses', $j2, 0, 0, 40, 10, 10, 10, NULL, NULL, 0, 1)",
    );
    await db.customStatement(
      'INSERT INTO fiche_ventes_jour (id, espece, date, qte) VALUES '
      "(2, 'goliaths', $j1, 4), (5, 'pintades', $j2, 7)",
    );
    await db.customStatement(
      'INSERT INTO bandes (id, espece, code, date_mise_en_bande, effectif_initial, date_cloture, observations) VALUES '
      "(4, 'goliaths', 'B1', ${s(DateTime(2026, 9, 1))}, 100, ${s(DateTime(2026, 10, 15))}, 'close'), "
      "(7, 'goliaths', 'B2', ${s(DateTime(2026, 10, 20))}, NULL, NULL, NULL)",
    );
    await db.customStatement(
      'INSERT INTO soins_calendrier (id, espece, date_prevue, type_soin, statut, bande_id, echeance_prophylaxie_id) VALUES '
      "(1, 'goliaths', ${s(DateTime(2026, 10, 25))}, 'Vaccination', 'Planifié', 7, 3), "
      "(2, 'goliaths', ${s(DateTime(2026, 10, 26))}, 'Vermifuge', 'Planifié', 4, 4), "
      "(3, 'goliaths', ${s(DateTime(2026, 10, 27))}, 'Soin libre', 'Planifié', NULL, NULL), "
      "(4, 'goliaths', ${s(DateTime(2026, 10, 28))}, 'Orpheline', 'Planifié', 99, 1)",
    );
    if (avecIdentifiant) {
      await db.customStatement(
        "INSERT OR REPLACE INTO preferences_poste (cle, valeur) VALUES ('poste.identifiant', 'poste-existant')",
      );
    } else {
      await db.customStatement(
        "DELETE FROM preferences_poste WHERE cle = 'poste.identifiant'",
      );
    }
    await db.customStatement('PRAGMA user_version = 37');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  group('fiche_journee', () {
    test(
      'aucune ligne perdue ; UUID déterministe de (espèce, date) ; valeurs intactes',
      () async {
        await baseV37();
        final db = AppDatabase.pourFichier(fichier);
        final f = await lire(
          db,
          'SELECT * FROM fiche_journee ORDER BY date, espece',
        );

        expect(f, hasLength(3));
        expect(f.map((r) => r['id']).toSet(), hasLength(3));
        expect(
          f[0]['id'],
          identifiantFicheJournee('goliaths', DateTime(2026, 10, 30)),
        );
        expect(f[0]['id'], matches(uuidV5));
        expect(f[0]['achat'], 20);
        expect(f[0]['poids_general_g'], 1500);
        expect(f[0]['traitement_obs'], 'RAS');
        expect(f[0]['traitement_valide'], 1);
        expect(f[1]['ne'], 5);
        expect(f[2]['espece'], 'pondeuses');
        await db.close();
      },
    );

    test(
      'chaque fiche est « à envoyer », datée du jour qu\'elle décrit (jamais de l\'instant de la migration)',
      () async {
        await baseV37();
        final db = AppDatabase.pourFichier(fichier);

        final f = await lire(
          db,
          'SELECT date, sync_status, sync_motif, updated_at FROM fiche_journee ORDER BY date',
        );

        for (final r in f) {
          expect(r['sync_status'], 'pending');
          expect(r['sync_motif'], isNull);
          final saisie = DateTime.parse(r['updated_at'] as String);
          expect(saisie.isUtc, isTrue);
          expect(
            saisie.millisecondsSinceEpoch ~/ 1000,
            r['date'],
            reason: 'instant de saisie = le jour de la fiche',
          );
        }
        await db.close();
      },
    );

    test(
      'deux bases migrées séparément donnent le MÊME UUID au même (espèce, date) : les postes convergent',
      () async {
        await baseV37();
        var db = AppDatabase.pourFichier(fichier);
        final premier = await lire(
          db,
          'SELECT id FROM fiche_journee ORDER BY date, espece',
        );
        await db.close();
        fichier.deleteSync();

        await baseV37();
        db = AppDatabase.pourFichier(fichier);
        final second = await lire(
          db,
          'SELECT id FROM fiche_journee ORDER BY date, espece',
        );

        expect(second, premier);
        await db.close();
      },
    );

    test('l\'unicité (espèce, date) est conservée', () async {
      await baseV37();
      final db = AppDatabase.pourFichier(fichier);
      await expectLater(
        db.customStatement(
          "INSERT INTO fiche_journee (id, espece, date, updated_at) VALUES ('x', 'goliaths', ${s(DateTime(2026, 10, 30))}, 'z')",
        ),
        throwsA(anything),
      );
      await db.close();
    });
  });

  group('fiche_ventes_jour', () {
    test(
      'les compteurs existants sont ceux de CE poste : origine vide, UUID (espèce, date, poste), à envoyer',
      () async {
        await baseV37(avecIdentifiant: true);
        final db = AppDatabase.pourFichier(fichier);

        final c = await lire(
          db,
          'SELECT * FROM fiche_ventes_jour ORDER BY date',
        );

        expect(c, hasLength(2));
        expect(c[0]['qte'], 4);
        expect(c[1]['qte'], 7);
        expect(
          c[0]['id'],
          identifiantVentesJour(
            'goliaths',
            DateTime(2026, 10, 30),
            'poste-existant',
          ),
        );
        for (final r in c) {
          expect(r['origine'], isNull);
          expect(r['sync_status'], 'pending');
          expect(
            (DateTime.parse(
                  r['updated_at'] as String,
                )).millisecondsSinceEpoch ~/
                1000,
            r['date'],
          );
        }
        await db.close();
      },
    );

    test(
      'l\'identifiant du poste, absent, est créé une fois et sert aux UUID',
      () async {
        await baseV37();
        final db = AppDatabase.pourFichier(fichier);

        final poste = await lire(
          db,
          "SELECT valeur FROM preferences_poste WHERE cle = 'poste.identifiant'",
        );
        expect(poste, hasLength(1));
        final id = poste.single['valeur'] as String;
        final c = await lire(
          db,
          "SELECT id FROM fiche_ventes_jour WHERE espece = 'goliaths'",
        );
        expect(
          c.single['id'],
          identifiantVentesJour('goliaths', DateTime(2026, 10, 30), id),
        );
        await db.close();
      },
    );
  });

  group('bandes et soins', () {
    test(
      'chaque bande reçoit un UUID distinct, rien d\'autre ne bouge ; datée de sa clôture, sinon de sa mise en place',
      () async {
        await baseV37();
        final db = AppDatabase.pourFichier(fichier);

        final b = await lire(db, 'SELECT * FROM bandes ORDER BY code');

        expect(b, hasLength(2));
        for (final r in b) {
          expect(r['id'], matches(uuidV4));
          expect(r['sync_status'], 'pending');
        }
        expect(b.map((r) => r['id']).toSet(), hasLength(2));
        expect(b[0]['code'], 'B1');
        expect(b[0]['effectif_initial'], 100);
        expect(b[0]['observations'], 'close');
        expect(b[1]['effectif_initial'], isNull);
        expect(
          DateTime.parse(b[0]['updated_at'] as String).millisecondsSinceEpoch ~/
              1000,
          s(DateTime(2026, 10, 15)),
        );
        expect(
          DateTime.parse(b[1]['updated_at'] as String).millisecondsSinceEpoch ~/
              1000,
          s(DateTime(2026, 10, 20)),
        );
        await db.close();
      },
    );

    test(
      'chaque soin injecté GARDE sa bande ; un soin libre reste libre ; aucun soin n\'est perdu',
      () async {
        await baseV37();
        final db = AppDatabase.pourFichier(fichier);

        final soins = await lire(
          db,
          'SELECT s.type_soin, s.bande_id, b.code, s.echeance_prophylaxie_id '
          'FROM soins_calendrier s LEFT JOIN bandes b ON b.id = s.bande_id ORDER BY s.id',
        );

        expect(soins, hasLength(4));
        expect(soins[0]['code'], 'B2');
        expect(soins[0]['echeance_prophylaxie_id'], 3);
        expect(soins[1]['code'], 'B1');
        expect(soins[2]['bande_id'], isNull);
        expect(
          soins[3]['bande_id'],
          isNull,
          reason: 'bande 99 n\'existait pas',
        );
        expect(soins[3]['type_soin'], 'Orpheline');
        await db.close();
      },
    );
  });

  group('ensemble', () {
    test(
      'intégrité référentielle intacte, base à la version courante',
      () async {
        await baseV37();
        final db = AppDatabase.pourFichier(fichier);
        await db.customSelect('SELECT 1').get();

        expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
        final v = await db.customSelect('PRAGMA user_version').getSingle();
        expect(v.data.values.first, AppDatabase.versionSchema);
        expect(AppDatabase.versionSchema, greaterThanOrEqualTo(38));
        await db.close();
      },
    );

    test(
      'rejouée (version estampillée 37 à tort), aucun UUID ne change et aucune ligne n\'est perdue',
      () async {
        await baseV37(avecIdentifiant: true);
        var db = AppDatabase.pourFichier(fichier);
        Future<List<Object?>> ids() async => [
          for (final t in ['fiche_journee', 'fiche_ventes_jour', 'bandes'])
            ...(await lire(
              db,
              'SELECT id FROM $t ORDER BY id',
            )).map((r) => r['id']),
          ...(await lire(
            db,
            'SELECT bande_id FROM soins_calendrier ORDER BY id',
          )).map((r) => r['bande_id']),
        ];
        final avant = await ids();
        await db.customStatement('PRAGMA user_version = 37');
        await db.close();

        db = AppDatabase.pourFichier(fichier);
        expect(await ids(), avant);
        await db.close();
      },
    );

    test(
      'une base neuve a les nouvelles colonnes de synchronisation',
      () async {
        final db = AppDatabase.pourFichier(fichier);
        for (final t in ['fiche_journee', 'fiche_ventes_jour', 'bandes']) {
          final colonnes = (await lire(
            db,
            'PRAGMA table_info("$t")',
          )).map((r) => r['name']).toSet();
          expect(
            colonnes,
            containsAll(['sync_status', 'sync_motif', 'updated_at']),
            reason: t,
          );
        }
        final cv = (await lire(
          db,
          'PRAGMA table_info("fiche_ventes_jour")',
        )).map((r) => r['name']).toSet();
        expect(cv, contains('origine'));
        final cb = (await lire(
          db,
          'PRAGMA table_info("bandes")',
        )).map((r) => r['name']).toSet();
        expect(
          cb.any((c) => c == 'effectif' || c == 'effectif_reel'),
          isFalse,
          reason: 'l\'effectif réel d\'une bande n\'est jamais stocké',
        );
        await db.close();
      },
    );
  });
}
