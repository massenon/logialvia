import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/domain/services/service_archivage.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/elevage/data/repositories/parametres_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/sync/identifiants_parametres_elevage.dart';

/// Migration v40 — soins, infirmerie, barèmes, taux et calendrier de prophylaxie en
/// UUID (DV-19, P7c). Les risques : perdre une ligne, perdre le lien soin -> échéance,
/// donner deux identifiants différents à la même ration sur deux postes, casser la
/// corbeille.
void main() {
  late Directory dossier;
  late File fichier;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  const jour = 1788000000; // un jour de novembre 2026, en secondes

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v40');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  /// Une base v39 : les cinq tables avec leurs identifiants ENTIERS non consécutifs.
  Future<void> baseV39({
    bool doublon = false,
    bool corbeille = true,
    bool baremesDejaConvertis = false,
  }) async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    for (final t in [
      'soins_calendrier',
      'infirmerie',
      if (!baremesDejaConvertis) 'baremes_ration',
      'taux_ration_poids',
      'calendrier_prophylaxie',
    ]) {
      await db.customStatement('DROP TABLE $t');
    }
    if (baremesDejaConvertis) {
      await db.customStatement('DELETE FROM baremes_ration');
    } else {
      await db.customStatement(
        'CREATE TABLE baremes_ration (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
        'espece TEXT NOT NULL, stade TEXT NOT NULL, ration_grammes_par_jour INTEGER NOT NULL, '
        'confirme INTEGER NOT NULL DEFAULT 0, UNIQUE (espece, stade))',
      );
    }
    await db.customStatement(
      'CREATE TABLE taux_ration_poids (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'espece TEXT NOT NULL, poids_min_g INTEGER NOT NULL, poids_max_g INTEGER NULL, '
      'taux_pourcent REAL NOT NULL, confirme INTEGER NOT NULL DEFAULT 0, '
      'UNIQUE (espece, poids_min_g))',
    );
    await db.customStatement(
      'CREATE TABLE calendrier_prophylaxie (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'espece TEXT NOT NULL, jour_cycle INTEGER NOT NULL, traitement TEXT NOT NULL, '
      'produit TEXT NOT NULL, remanence_jours INTEGER NOT NULL DEFAULT 0, dose TEXT NULL)',
    );
    await db.customStatement(
      'CREATE TABLE soins_calendrier (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'espece TEXT NOT NULL, date_prevue INTEGER NOT NULL, type_soin TEXT NOT NULL, '
      'statut TEXT NOT NULL, observations TEXT NULL, produit TEXT NULL, dose TEXT NULL, '
      'remanence_jours INTEGER NOT NULL DEFAULT 0, veterinaire TEXT NULL, '
      'symptomes TEXT NULL, cout_fcfa INTEGER NOT NULL DEFAULT 0, bande_id INTEGER NULL, '
      'echeance_prophylaxie_id INTEGER NULL)',
    );
    await db.customStatement(
      'CREATE TABLE infirmerie (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'date_entree INTEGER NOT NULL, sujet TEXT NOT NULL, motif TEXT NOT NULL, '
      'niveau_isolement TEXT NOT NULL, statut TEXT NOT NULL, date_sortie INTEGER NULL, '
      'espece TEXT NULL, categorie_mortalite INTEGER NULL)',
    );

    // Ids non consécutifs : 4, 9, 12.
    String ib(int ancien, String espece, String stade) => baremesDejaConvertis
        ? "'${IdentifiantsParametresElevage.bareme(espece, stade)}'"
        : '$ancien';
    await db.customStatement(
      "INSERT INTO baremes_ration (id, espece, stade, ration_grammes_par_jour, confirme) VALUES "
      "(${ib(4, 'goliaths', 'Mature')}, 'goliaths', 'Mature', 110, 0), "
      "(${ib(9, 'lapins', 'Reproducteur')}, 'lapins', 'Reproducteur', 120, 1), "
      "(${ib(12, 'goliaths', 'Poussins')}, 'goliaths', 'Poussins', 30, 0)",
    );
    await db.customStatement(
      "INSERT INTO taux_ration_poids (id, espece, poids_min_g, poids_max_g, taux_pourcent, confirme) VALUES "
      "(3, 'bovins', 0, 150000, 3.5, 0), (7, 'bovins', 150000, NULL, 3.0, 1)",
    );
    await db.customStatement(
      "INSERT INTO calendrier_prophylaxie (id, espece, jour_cycle, traitement, produit, remanence_jours, dose) VALUES "
      "(5, 'goliaths', 1, 'Vaccin Newcastle', 'ND-Lasota', 0, NULL), "
      "(8, 'goliaths', 15, 'Gumboro', 'Bursine', 3, '1 dose'), "
      "(11, 'lapins', 30, 'Vermifuge', 'Ivermectine', 7, NULL)"
      "${doublon ? ", (13, 'lapins', 30, 'Vermifuge', 'Ivermectine', 7, 'copie')" : ''}",
    );
    await db.customStatement(
      'INSERT INTO soins_calendrier (id, espece, date_prevue, type_soin, statut, produit, '
      'cout_fcfa, bande_id, echeance_prophylaxie_id) VALUES '
      "(2, 'goliaths', $jour, 'Vaccination', 'Planifié', 'ND-Lasota', 1500, 77, 5), "
      "(6, 'goliaths', $jour, 'Vermifuge', 'Effectué', NULL, 0, NULL, NULL), "
      "(10, 'lapins', $jour, 'Vermifuge', 'Planifié', 'Ivermectine', 300, 88, 11)",
    );
    await db.customStatement(
      'INSERT INTO infirmerie (id, date_entree, sujet, motif, niveau_isolement, statut, '
      'date_sortie, espece, categorie_mortalite) VALUES '
      "(1, $jour, 'Goliath #G-014', 'Boiterie', 'Infirmerie', 'En cours', NULL, 'goliaths', NULL), "
      "(5, $jour, 'Pintade #P-003', 'Newcastle', 'Quarantaine stricte', 'Décédé', ${jour + 86400}, 'pintades', 1)",
    );

    if (corbeille) {
      // Un barème, un taux et une échéance archivés AVANT la migration : leur
      // instantané porte un identifiant entier. Soin 14 cite l'échéance archivée 20.
      await db.customStatement('DELETE FROM corbeille');
      for (final a in [
        (
          'baremes_ration',
          {
            'id': 30,
            'espece': 'bovins',
            'stade': 'Veau',
            'ration_grammes_par_jour': 1500,
            'confirme': 0,
          },
        ),
        (
          'taux_ration_poids',
          {
            'id': 31,
            'espece': 'bovins',
            'poids_min_g': 300000,
            'poids_max_g': null,
            'taux_pourcent': 2.5,
            'confirme': 0,
          },
        ),
        (
          'calendrier_prophylaxie',
          {
            'id': 20,
            'espece': 'goliaths',
            'jour_cycle': 60,
            'traitement': 'Rappel archivé',
            'produit': 'Vieux produit',
            'remanence_jours': 0,
            'dose': null,
          },
        ),
      ]) {
        await db.customStatement(
          'INSERT INTO corbeille (nom_table, module, type_element, designation, donnees_json, archive_le) '
          "VALUES (?, 'Élevage', 'x', 'archivé', ?, $jour)",
          [a.$1, jsonEncode(a.$2)],
        );
      }
      await db.customStatement(
        'INSERT INTO soins_calendrier (id, espece, date_prevue, type_soin, statut, '
        "echeance_prophylaxie_id) VALUES (14, 'goliaths', $jour, 'Vaccination', 'Planifié', 20)",
      );
    }
    await db.customStatement('PRAGMA user_version = 39');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  test('toutes les lignes survivent avec un UUID distinct', () async {
    await baseV39();
    final db = AppDatabase.pourFichier(fichier);

    for (final (table, attendu) in const [
      ('baremes_ration', 3),
      ('taux_ration_poids', 2),
      ('calendrier_prophylaxie', 3),
      ('soins_calendrier', 4),
      ('infirmerie', 2),
    ]) {
      final l = await lire(db, 'SELECT id FROM $table');
      expect(l, hasLength(attendu), reason: 'aucune ligne perdue : $table');
      for (final r in l) {
        expect(r['id'], matches(uuid), reason: table);
      }
      expect(l.map((r) => r['id']).toSet(), hasLength(attendu), reason: table);
    }
    await db.close();
  });

  test(
    'le contenu des lignes est intact (valeurs, bande locale, ancien ordre)',
    () async {
      await baseV39();
      final db = AppDatabase.pourFichier(fichier);

      final b = await lire(
        db,
        'SELECT espece, stade, ration_grammes_par_jour AS r, confirme FROM baremes_ration ORDER BY rowid',
      );
      expect(
        b.map((r) => '${r['espece']}/${r['stade']}/${r['r']}/${r['confirme']}'),
        [
          'goliaths/Mature/110/0',
          'lapins/Reproducteur/120/1',
          'goliaths/Poussins/30/0',
        ],
        reason: 'ordre d\'insertion conservé',
      );

      final s = await lire(
        db,
        "SELECT cout_fcfa, bande_id, produit FROM soins_calendrier WHERE type_soin = 'Vaccination' AND produit = 'ND-Lasota'",
      );
      expect(s.single['cout_fcfa'], 1500);
      expect(s.single['bande_id'], '77', reason: 'le lien de bande est conserve tel quel');

      final i = await lire(
        db,
        "SELECT statut, categorie_mortalite AS c FROM infirmerie WHERE sujet LIKE 'Pintade%'",
      );
      expect(i.single['statut'], 'Décédé');
      expect(i.single['c'], 1);

      final repo = ParametresElevageRepositoryDrift(db);
      expect(
        (await repo.chargerBaremes()).map((x) => '${x.espece}/${x.stade}'),
        ['goliaths/Mature', 'goliaths/Poussins', 'lapins/Reproducteur'],
      );
      await db.close();
    },
  );

  test(
    'barèmes, taux et échéances reçoivent l\'UUID DÉTERMINISTE de leur clé naturelle',
    () async {
      await baseV39();
      final db = AppDatabase.pourFichier(fichier);

      final b = await lire(
        db,
        "SELECT id FROM baremes_ration WHERE espece = 'goliaths' AND stade = 'Mature'",
      );
      expect(
        b.single['id'],
        IdentifiantsParametresElevage.bareme('goliaths', 'Mature'),
      );
      final t = await lire(
        db,
        "SELECT id FROM taux_ration_poids WHERE poids_min_g = 150000",
      );
      expect(
        t.single['id'],
        IdentifiantsParametresElevage.taux('bovins', 150000),
      );
      final e = await lire(
        db,
        "SELECT id FROM calendrier_prophylaxie WHERE traitement = 'Gumboro'",
      );
      expect(
        e.single['id'],
        IdentifiantsParametresElevage.echeance(
          'goliaths',
          15,
          'Gumboro',
          'Bursine',
        ),
      );
      await db.close();
    },
  );

  test(
    'deux postes migrés séparément donnent les MÊMES identifiants aux référentiels',
    () async {
      await baseV39();
      final db1 = AppDatabase.pourFichier(fichier);
      final ids1 = await lire(
        db1,
        'SELECT id FROM baremes_ration UNION ALL SELECT id FROM calendrier_prophylaxie ORDER BY id',
      );
      await db1.close();
      File('${dossier.path}/logialvia.db').deleteSync();

      await baseV39();
      final db2 = AppDatabase.pourFichier(fichier);
      final ids2 = await lire(
        db2,
        'SELECT id FROM baremes_ration UNION ALL SELECT id FROM calendrier_prophylaxie ORDER BY id',
      );
      await db2.close();

      expect(ids2, ids1);
    },
  );

  test(
    'un soin garde le lien avec SON échéance (jointure par UUID), y compris une échéance archivée',
    () async {
      await baseV39();
      final db = AppDatabase.pourFichier(fichier);

      final j = await lire(
        db,
        'SELECT s.type_soin AS soin, e.traitement AS traitement '
        'FROM soins_calendrier s JOIN calendrier_prophylaxie e '
        'ON e.id = s.echeance_prophylaxie_id ORDER BY e.traitement',
      );
      expect(j.map((r) => '${r['soin']}=>${r['traitement']}'), [
        'Vaccination=>Vaccin Newcastle',
        'Vermifuge=>Vermifuge',
      ]);

      // L'échéance 20 est en corbeille : le soin 14 pointe vers l'identifiant que
      // portera l'échéance une fois restaurée.
      final archive = await lire(
        db,
        "SELECT donnees_json FROM corbeille WHERE nom_table = 'calendrier_prophylaxie'",
      );
      final idArchive =
          (jsonDecode(archive.single['donnees_json']! as String) as Map)['id'];
      expect(idArchive, matches(uuid));
      final soin = await lire(
        db,
        "SELECT echeance_prophylaxie_id AS e FROM soins_calendrier WHERE espece = 'goliaths' AND statut = 'Planifié' AND produit IS NULL",
      );
      expect(soin.single['e'], idArchive);
      await db.close();
    },
  );

  test('un soin sans échéance reste sans échéance', () async {
    await baseV39();
    final db = AppDatabase.pourFichier(fichier);
    final l = await lire(
      db,
      "SELECT echeance_prophylaxie_id AS e FROM soins_calendrier WHERE type_soin = 'Vermifuge' AND statut = 'Effectué'",
    );
    expect(l.single['e'], isNull);
    await db.close();
  });

  test(
    'la corbeille est remise en UUID : la restauration retrouve la bonne clé',
    () async {
      await baseV39();
      final db = AppDatabase.pourFichier(fichier);

      final elements = await ServiceArchivage(db).lister();
      expect(elements, hasLength(3));
      for (final e in elements) {
        await ServiceArchivage(db).restaurer(e.id, estAdmin: true);
      }

      expect(
        (await lire(
          db,
          "SELECT id FROM baremes_ration WHERE stade = 'Veau'",
        )).single['id'],
        IdentifiantsParametresElevage.bareme('bovins', 'Veau'),
      );
      expect(
        (await lire(
          db,
          'SELECT id FROM taux_ration_poids WHERE poids_min_g = 300000',
        )).single['id'],
        IdentifiantsParametresElevage.taux('bovins', 300000),
      );
      expect(
        (await lire(
          db,
          "SELECT id FROM calendrier_prophylaxie WHERE traitement = 'Rappel archivé'",
        )).single['id'],
        matches(uuid),
      );
      await db.close();
    },
  );

  test('soins et infirmerie d\'hier sont « à envoyer »', () async {
    await baseV39();
    final db = AppDatabase.pourFichier(fichier);
    for (final t in const ['soins_calendrier', 'infirmerie']) {
      final l = await lire(
        db,
        'SELECT sync_status AS s, updated_at AS u FROM $t',
      );
      expect(l, isNotEmpty);
      for (final r in l) {
        expect(r['s'], 'pending', reason: t);
        expect(DateTime.tryParse(r['u']! as String), isNotNull, reason: t);
      }
    }
    await db.close();
  });

  test(
    'deux échéances au même contenu sur un poste gardent deux identifiants',
    () async {
      await baseV39(doublon: true);
      final db = AppDatabase.pourFichier(fichier);

      final l = await lire(
        db,
        "SELECT id FROM calendrier_prophylaxie WHERE traitement = 'Vermifuge'",
      );
      expect(l, hasLength(2), reason: 'aucune ligne perdue');
      expect(l.map((r) => r['id']).toSet(), hasLength(2));
      await db.close();
    },
  );

  test(
    'intégrité intacte, tables de correspondance supprimées, version courante',
    () async {
      await baseV39();
      final db = AppDatabase.pourFichier(fichier);
      await db.customSelect('SELECT 1').get();

      expect(await lire(db, 'PRAGMA foreign_key_check'), isEmpty);
      expect(
        await lire(
          db,
          "SELECT name FROM sqlite_master WHERE name LIKE '_map_%'",
        ),
        isEmpty,
      );
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.first, AppDatabase.versionSchema);
      expect(AppDatabase.versionSchema, greaterThanOrEqualTo(40));
      await db.close();
    },
  );

  test('rejouée (version estampillée 39 à tort), aucun UUID ne change', () async {
    await baseV39();
    var db = AppDatabase.pourFichier(fichier);
    final avant = await lire(
      db,
      'SELECT id FROM soins_calendrier UNION ALL SELECT id FROM infirmerie '
      'UNION ALL SELECT id FROM baremes_ration UNION ALL SELECT id FROM taux_ration_poids '
      'UNION ALL SELECT id FROM calendrier_prophylaxie ORDER BY id',
    );
    final liens = await lire(
      db,
      'SELECT id, echeance_prophylaxie_id AS e FROM soins_calendrier ORDER BY id',
    );
    await db.customStatement('PRAGMA user_version = 39');
    await db.close();

    db = AppDatabase.pourFichier(fichier);
    final apres = await lire(
      db,
      'SELECT id FROM soins_calendrier UNION ALL SELECT id FROM infirmerie '
      'UNION ALL SELECT id FROM baremes_ration UNION ALL SELECT id FROM taux_ration_poids '
      'UNION ALL SELECT id FROM calendrier_prophylaxie ORDER BY id',
    );
    expect(apres, avant);
    expect(
      await lire(
        db,
        'SELECT id, echeance_prophylaxie_id AS e FROM soins_calendrier ORDER BY id',
      ),
      liens,
      reason: 'les liens soin -> échéance ne bougent pas non plus',
    );
    await db.close();
  });

  test(
    'reprise après interruption : barèmes déjà convertis, le reste encore entier',
    () async {
      await baseV39(baremesDejaConvertis: true);

      final db = AppDatabase.pourFichier(fichier);

      expect(
        (await lire(
          db,
          "SELECT id FROM baremes_ration WHERE stade = 'Mature'",
        )).single['id'],
        IdentifiantsParametresElevage.bareme('goliaths', 'Mature'),
      );
      expect(await lire(db, 'SELECT id FROM baremes_ration'), hasLength(3));
      for (final t in const [
        'soins_calendrier',
        'infirmerie',
        'taux_ration_poids',
        'calendrier_prophylaxie',
      ]) {
        for (final r in await lire(db, 'SELECT id FROM $t')) {
          expect(r['id'], matches(uuid), reason: t);
        }
      }
      expect(
        (await lire(
          db,
          'SELECT COUNT(*) AS n FROM soins_calendrier s JOIN calendrier_prophylaxie e '
          'ON e.id = s.echeance_prophylaxie_id',
        )).single['n'],
        2,
        reason: 'les liens soin -> échéance survivent à la reprise',
      );
      await db.close();
    },
  );

  test('une base neuve (jamais migrée) a déjà le schéma UUID', () async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    for (final t in const [
      'soins_calendrier',
      'infirmerie',
      'baremes_ration',
      'taux_ration_poids',
      'calendrier_prophylaxie',
    ]) {
      final colonnes = await lire(db, 'PRAGMA table_info("$t")');
      final id = colonnes.firstWhere((c) => c['name'] == 'id');
      expect((id['type']! as String).toUpperCase(), 'TEXT', reason: t);
    }
    await db.close();
  });
}
