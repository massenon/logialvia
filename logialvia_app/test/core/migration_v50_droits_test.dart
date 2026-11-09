import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v50 (`47g_`) : un refus « Droit insuffisant » n'est jamais définitif. Les demandes
/// et saisies que d'anciennes versions ont laissées en `conflict` pour ce motif repassent « en
/// attente » ; les autres conflits (motifs définitifs) ne bougent pas.
void main() {
  late Directory dossier;
  late File fichier;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v50');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  Future<void> baseV49() async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    const maj = '2026-11-09T09:00:00.000000Z';
    // 74 demandes d'un poste appairé à `caissier1`, plus une refusée pour une raison définitive.
    for (var i = 0; i < 74; i++) {
      await db.customStatement(
        'INSERT INTO demandes_referentiel (id, type, cle, donnees, saisi_le, sync_status, sync_motif) '
        "VALUES ('d$i', 'bareme_ration', 'k$i', '{}', '$maj', 'conflict', "
        "'Droit insuffisant pour modifier les paramètres d''élevage.')",
      );
    }
    await db.customStatement(
      'INSERT INTO demandes_referentiel (id, type, cle, donnees, saisi_le, sync_status, sync_motif) '
      "VALUES ('definitive', 'intrant', 'x', '{}', '$maj', 'conflict', 'Le stock n''est pas synchronisé.')",
    );
    await db.customStatement(
      'INSERT INTO demandes_referentiel (id, type, cle, donnees, saisi_le, sync_status, sync_motif) '
      "VALUES ('ok', 'intrant', 'y', '{}', '$maj', 'synced', NULL)",
    );
    // Une saisie (fait) refusée pour droit, une pour un autre motif.
    await db.customStatement(
      'INSERT INTO clients (id, nom, updated_at, sync_status, sync_motif) '
      "VALUES ('c1', 'A', '$maj', 'conflict', 'Droit insuffisant pour écrire dans « clients ».'), "
      "('c2', 'B', '$maj', 'conflict', 'Le nom du client est obligatoire.')",
    );
    await db.customStatement('PRAGMA user_version = 49');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  test(
    'les refus pour droit repassent en attente, les refus définitifs restent',
    () async {
      await baseV49();
      final db = AppDatabase.pourFichier(fichier);

      final demandes = await lire(
        db,
        "SELECT sync_status AS s, count(*) AS n FROM demandes_referentiel WHERE id LIKE 'd%' AND id <> 'definitive' GROUP BY sync_status",
      );
      expect(demandes, [
        {'s': 'pending', 'n': 74},
      ]);
      final definitive = await lire(
        db,
        "SELECT sync_status, sync_motif FROM demandes_referentiel WHERE id = 'definitive'",
      );
      expect(definitive.single['sync_status'], 'conflict');
      expect(
        definitive.single['sync_motif'],
        'Le stock n\'est pas synchronisé.',
      );
      expect(
        (await lire(
          db,
          "SELECT sync_status FROM demandes_referentiel WHERE id = 'ok'",
        )).single['sync_status'],
        'synced',
      );

      final clients = await lire(
        db,
        'SELECT id, sync_status, sync_motif FROM clients ORDER BY id',
      );
      expect(clients[0]['sync_status'], 'pending');
      expect(clients[0]['sync_motif'], isNull);
      expect(clients[1]['sync_status'], 'conflict');
      expect(clients[1]['sync_motif'], 'Le nom du client est obligatoire.');
      await db.close();
    },
  );

  test('la migration se rejoue sans erreur (idempotente)', () async {
    await baseV49();
    var db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('PRAGMA user_version = 49');
    await db.close();
    db = AppDatabase.pourFichier(fichier);
    final n = await lire(
      db,
      "SELECT count(*) AS n FROM demandes_referentiel WHERE sync_status = 'pending'",
    );
    expect(n.single['n'], 74);
    expect(AppDatabase.versionSchema, 50);
    await db.close();
  });
}
