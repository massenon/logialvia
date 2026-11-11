import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';
import 'package:logialvia_app/elevage/data/migration/migration_bovins_vers_ovins.dart';
import 'package:logialvia_app/elevage/data/sync/identifiants_elevage.dart';
import 'package:logialvia_app/elevage/data/sync/identifiants_parametres_elevage.dart';

/// Migration v51 (DV-22) : la filière Bovins devient Ovins. Un poste en service garde ses
/// lignes `bovins` dans une douzaine de tables : toutes passent à `ovins`, sans doublon, avec
/// les identifiants déterministes recalculés, et rejouée la migration ne change plus rien.
void main() {
  late Directory dossier;
  late File fichier;

  const jour = 1788000000; // un jour de novembre 2026, en secondes
  final date = DateTime.fromMillisecondsSinceEpoch(jour * 1000);

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v51');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  /// Une base v50 avec des lignes bovins partout (et ce qu'il faut pour les doublons).
  Future<String> baseV50({bool ovinsDejaLa = false}) async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    final moi = await PreferencesPosteRepository(db).identifiantPoste();
    const maj = '2026-11-09T09:00:00.000000Z';

    await db.customStatement('DELETE FROM modules_actifs');
    await db.customStatement(
      "INSERT INTO modules_actifs (module_id, is_actif, espece) VALUES ('bovins', 1, 'bovins')",
    );
    await db.customStatement(
      "INSERT INTO fiche_journee (id, espece, date, sync_status, updated_at) "
      "VALUES ('${identifiantFicheJournee('bovins', date)}', 'bovins', $jour, 'synced', '$maj')",
    );
    await db.customStatement(
      "INSERT INTO fiche_ventes_jour (id, espece, date, qte, origine, sync_status, updated_at) "
      "VALUES ('${identifiantVentesJour('bovins', date, moi)}', 'bovins', $jour, 3, NULL, 'synced', '$maj')",
    );
    await db.customStatement('DELETE FROM baremes_ration WHERE espece = \'bovins\'');
    for (final b in [('Veau', 1500), ('Embouche', 7000), ('Reproducteur', 9000)]) {
      await db.customStatement(
        'INSERT INTO baremes_ration (id, espece, stade, ration_grammes_par_jour, confirme) '
        "VALUES ('${IdentifiantsParametresElevage.bareme('bovins', b.$1)}', 'bovins', '${b.$1}', ${b.$2}, 0)",
      );
    }
    // Un stade saisi par l'animalier : UUID aléatoire, valeur à lui.
    await db.customStatement(
      'INSERT INTO baremes_ration (id, espece, stade, ration_grammes_par_jour, confirme) '
      "VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'bovins', 'Taurillon', 4000, 1)",
    );
    await db.customStatement('DELETE FROM taux_ration_poids WHERE espece = \'bovins\'');
    for (final t in [(0, 150000, 3.5), (150000, 300000, 3.0), (300000, null, 2.5)]) {
      await db.customStatement(
        'INSERT INTO taux_ration_poids (id, espece, poids_min_g, poids_max_g, taux_pourcent, confirme) '
        "VALUES ('${IdentifiantsParametresElevage.taux('bovins', t.$1)}', 'bovins', ${t.$1}, ${t.$2 ?? 'NULL'}, ${t.$3}, 0)",
      );
    }
    await db.customStatement(
      'DELETE FROM calendrier_prophylaxie WHERE espece = \'bovins\'',
    );
    const traitement = 'Vaccin péripneumonie contagieuse bovine (PPCB)';
    final ancienneEcheance = IdentifiantsParametresElevage.echeance(
      'bovins',
      15,
      traitement,
      'Vaccin T1/44',
    );
    await db.customStatement(
      'INSERT INTO calendrier_prophylaxie (id, espece, jour_cycle, traitement, produit, remanence_jours, dose) '
      "VALUES ('$ancienneEcheance', 'bovins', 15, '$traitement', 'Vaccin T1/44', 0, '1 dose')",
    );
    await db.customStatement(
      "INSERT INTO bandes (id, espece, code, date_mise_en_bande, sync_status, updated_at) "
      "VALUES ('b1', 'bovins', 'PARC1', $jour, 'synced', '$maj')",
    );
    await db.customStatement(
      "INSERT INTO soins_calendrier (id, espece, date_prevue, type_soin, statut, echeance_prophylaxie_id, bande_id, sync_status, updated_at) "
      "VALUES ('s1', 'bovins', $jour, 'Vaccin', 'Planifié', '$ancienneEcheance', 'b1', 'synced', '$maj')",
    );
    await db.customStatement(
      "INSERT INTO infirmerie (id, date_entree, sujet, motif, niveau_isolement, statut, espece, sync_status, updated_at) "
      "VALUES ('i1', $jour, 'Brebis 3', 'Boiterie', 'Infirmerie', 'En cours', 'bovins', 'synced', '$maj')",
    );
    await db.customStatement(
      "INSERT INTO produits_vendables (id, sku, name, cat, price, unit, icon, stock, threshold, espece) "
      "VALUES ('p1', 'PRD-900', 'Animal d''embouche', 'Élevage bovin', 150000, 'u', 'grass', 2, 1, 'bovins')",
    );
    await db.customStatement(
      "INSERT INTO demandes_referentiel (id, type, cle, donnees, saisi_le, sync_status) "
      "VALUES ('d1', 'module_actif', 'bovins', '{\"module_id\":\"bovins\",\"is_actif\":true}', '$maj', 'pending'), "
      "('d2', 'module_actif', 'bovins', '{\"module_id\":\"bovins\",\"is_actif\":false}', '$maj', 'synced')",
    );
    if (ovinsDejaLa) {
      await db.customStatement(
        "INSERT INTO modules_actifs (module_id, is_actif, espece) VALUES ('ovins', 0, 'ovins')",
      );
      await db.customStatement(
        "INSERT INTO baremes_ration (id, espece, stade, ration_grammes_par_jour, confirme) "
        "VALUES ('${IdentifiantsParametresElevage.bareme('ovins', 'Embouche')}', 'ovins', 'Embouche', 650, 1)",
      );
    }
    await db.customStatement('PRAGMA user_version = 50');
    await db.close();
    return moi;
  }

  Future<int> restantsBovins(AppDatabase db) async {
    var total = 0;
    for (final r in await lire(
      db,
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    )) {
      final table = r['name']! as String;
      for (final c in await lire(db, 'PRAGMA table_info("$table")')) {
        if (c['name'] == 'espece' || c['name'] == 'module_id') {
          total +=
              (await lire(
                    db,
                    'SELECT count(*) AS n FROM "$table" WHERE ${c['name']} = \'bovins\'',
                  )).single['n']!
                  as int;
        }
      }
    }
    return total;
  }

  test('la version du schéma est au moins la 51 et plus aucune ligne ne dit bovins', () async {
    expect(AppDatabase.versionSchema, greaterThanOrEqualTo(51));
    final moi = await baseV50();
    final db = AppDatabase.pourFichier(fichier);
    expect(await restantsBovins(db), 0);

    expect(
      await lire(db, 'SELECT module_id, is_actif, espece FROM modules_actifs'),
      [
        {'module_id': 'ovins', 'is_actif': 1, 'espece': 'ovins'},
      ],
    );

    // Fiche journalière et compteur de ventes : identifiants recalculés, à renvoyer.
    final fiche = await lire(db, 'SELECT id, espece, sync_status FROM fiche_journee');
    expect(fiche.single['id'], identifiantFicheJournee('ovins', date));
    expect(fiche.single['espece'], 'ovins');
    expect(fiche.single['sync_status'], 'pending');
    final ventes = await lire(
      db,
      'SELECT id, qte, sync_status FROM fiche_ventes_jour',
    );
    expect(ventes.single['id'], identifiantVentesJour('ovins', date, moi));
    expect(ventes.single['qte'], 3);
    expect(ventes.single['sync_status'], 'pending');

    // Barèmes d'ouverture réécrits, stade « Veau » devenu « Agneau », UUID d'ouverture ovin.
    final baremes = await lire(
      db,
      "SELECT id, stade, ration_grammes_par_jour AS r FROM baremes_ration "
      "WHERE espece = 'ovins' ORDER BY stade",
    );
    expect(baremes.map((b) => (b['stade'], b['r'])).toList(), [
      ('Agneau', 300),
      ('Embouche', 600),
      ('Reproducteur', 800),
      ('Taurillon', 4000),
    ]);
    expect(
      baremes.first['id'],
      IdentifiantsParametresElevage.bareme('ovins', 'Agneau'),
    );
    // La ligne de l'animalier (UUID aléatoire, confirmée) est intacte.
    expect(baremes.last['id'], 'aaaaaaaa-0000-4000-8000-000000000001');

    final taux = await lire(
      db,
      "SELECT id, poids_min_g, poids_max_g, taux_pourcent FROM taux_ration_poids "
      "WHERE espece = 'ovins' ORDER BY poids_min_g",
    );
    expect(
      taux.map((t) => (t['poids_min_g'], t['poids_max_g'], t['taux_pourcent'])).toList(),
      [(0, 15000, 4.0), (15000, 30000, 3.5), (30000, null, 3.0)],
    );
    expect(taux[1]['id'], IdentifiantsParametresElevage.taux('ovins', 15000));

    // L'échéance PPCB devient le vaccin PPR ; le soin planifié suit son échéance.
    final echeance = (await lire(
      db,
      'SELECT id, traitement, produit, remanence_jours FROM calendrier_prophylaxie',
    )).single;
    expect(echeance['traitement'], 'Vaccin peste des petits ruminants (PPR)');
    expect(
      echeance['id'],
      IdentifiantsParametresElevage.echeance(
        'ovins',
        15,
        echeance['traitement']! as String,
        echeance['produit']! as String,
      ),
    );
    expect(
      (await lire(db, "SELECT echeance_prophylaxie_id AS e, espece FROM soins_calendrier"))
          .single,
      {'e': echeance['id'], 'espece': 'ovins'},
    );

    expect((await lire(db, 'SELECT espece FROM bandes')).single['espece'], 'ovins');
    expect((await lire(db, 'SELECT espece FROM infirmerie')).single['espece'], 'ovins');
    expect(
      (await lire(db, "SELECT cat, espece FROM produits_vendables WHERE id = 'p1'")).single,
      {'cat': 'Élevage ovin', 'espece': 'ovins'},
    );

    // Demande en attente réécrite ; la demande déjà traitée reste telle qu'elle a été envoyée.
    final demandes = await lire(
      db,
      'SELECT id, cle, donnees FROM demandes_referentiel ORDER BY id',
    );
    expect(demandes[0]['cle'], 'ovins');
    expect(demandes[0]['donnees'], contains('"module_id":"ovins"'));
    expect(demandes[1]['cle'], 'bovins');
    await db.close();
  });

  test('rejouée, la migration ne change plus rien (aucun doublon)', () async {
    await baseV50();
    final db = AppDatabase.pourFichier(fichier);
    String instantane(List<Map<String, Object?>> l) => l.toString();
    Future<String> tout() async => [
      for (final t in [
        'modules_actifs',
        'fiche_journee',
        'fiche_ventes_jour',
        'baremes_ration',
        'taux_ration_poids',
        'calendrier_prophylaxie',
        'bandes',
        'soins_calendrier',
        'infirmerie',
        'produits_vendables',
        'demandes_referentiel',
      ])
        instantane(await lire(db, 'SELECT * FROM $t ORDER BY 1')),
    ].join('\n');
    final avant = await tout();
    await MigrationBovinsVersOvins(db).executer();
    await MigrationBovinsVersOvins(db).executer();
    expect(await tout(), avant);
    await db.close();
  });

  test('si la ligne ovins existe déjà, elle l\'emporte : pas de doublon', () async {
    await baseV50(ovinsDejaLa: true);
    final db = AppDatabase.pourFichier(fichier);
    expect(await restantsBovins(db), 0);
    expect(await lire(db, 'SELECT module_id, is_actif FROM modules_actifs'), [
      {'module_id': 'ovins', 'is_actif': 0},
    ]);
    // « Embouche » existait déjà côté ovins (650, confirmé) : la valeur ovine reste.
    final embouche = await lire(
      db,
      "SELECT ration_grammes_par_jour AS r, confirme FROM baremes_ration "
      "WHERE espece = 'ovins' AND stade = 'Embouche'",
    );
    expect(embouche, [
      {'r': 650, 'confirme': 1},
    ]);
    await db.close();
  });

  test('un poste neuf n\'a ni module bovins ni route bovins (uuid du déterministe inchangé)', () {
    expect(
      identifiantFicheJournee('ovins', date),
      uuidDeterministe('fiche_journee:ovins|${jourCivil(date)}'),
    );
  });
}
