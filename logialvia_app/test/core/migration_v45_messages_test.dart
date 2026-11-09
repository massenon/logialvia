import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v45 — `messages_editeur` reçoit son UUID, l'auteur et les colonnes de
/// synchronisation (doc 47u §4).
///
/// Les risques : perdre un message, changer sa date ou son statut, ne pas pouvoir
/// rejouer la migration après une interruption, ou laisser sans UUID les messages déjà
/// supprimés (restaurés tels quels depuis la corbeille, ils reviendraient avec un entier).
void main() {
  late Directory dossier;
  late File fichier;

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v45');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  const date1 = 1788000000; // 2026-08-29T09:20:00Z
  const date2 = 1788100000;

  /// Une base v44 : schéma courant, sauf `messages_editeur` remise dans son état v44.
  Future<void> baseV44() async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP TABLE messages_editeur');
    await db.customStatement(
      'CREATE TABLE messages_editeur (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      'horodatage INTEGER NOT NULL, type TEXT NOT NULL, sujet TEXT NOT NULL, '
      'message TEXT NOT NULL, etapes TEXT NULL, utilisateur_id TEXT NOT NULL, '
      "statut TEXT NOT NULL DEFAULT 'En attente')",
    );
    await db.customStatement(
      'INSERT INTO messages_editeur (horodatage, type, sujet, message, etapes, utilisateur_id, statut) '
      "VALUES ($date1, 'question', 'Comptabilité', 'Comment clôturer ?', NULL, '1', 'En attente'), "
      "($date2, 'bug', 'Ventes & Clients', 'Le panier plante', '1. Ouvrir', '2', 'Transmis')",
    );
    // Un message déjà supprimé : son instantané dort en corbeille avec son ancien entier.
    await db.customStatement(
      'INSERT INTO corbeille (nom_table, module, type_element, designation, donnees_json, archive_le) '
      "VALUES ('messages_editeur', 'Compte', 'Message à l''éditeur', 'Ancien', ?, $date2)",
      [
        jsonEncode({
          'id': 7,
          'horodatage': date1,
          'type': 'question',
          'sujet': 'Ancien',
          'message': 'Vieux message',
          'etapes': null,
          'utilisateur_id': '1',
          'statut': 'En attente',
        }),
      ],
    );
    await db.customStatement('PRAGMA user_version = 44');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  test('chaque message reçoit un UUID distinct et rien ne se perd', () async {
    await baseV44();
    final db = AppDatabase.pourFichier(fichier);
    final m = await lire(
      db,
      'SELECT * FROM messages_editeur ORDER BY horodatage',
    );

    expect(m, hasLength(2));
    final ids = m.map((r) => r['id']! as String).toList();
    for (final id in ids) {
      expect(id, matches(uuid));
    }
    expect(ids.toSet(), hasLength(2));
    expect(m[0]['sujet'], 'Comptabilité');
    expect(m[0]['statut'], 'En attente');
    expect(m[1]['sujet'], 'Ventes & Clients');
    expect(m[1]['statut'], 'Transmis', reason: 'le statut est conservé');
    expect(m[1]['etapes'], '1. Ouvrir');
    expect(m[1]['utilisateur_id'], '2');
    await db.close();
  });

  test('les messages d\'hier sont à envoyer, datés de leur rédaction', () async {
    await baseV44();
    final db = AppDatabase.pourFichier(fichier);
    final m = await lire(
      db,
      'SELECT * FROM messages_editeur ORDER BY horodatage',
    );

    for (final r in m) {
      expect(r['sync_status'], 'pending');
      expect(r['sync_motif'], isNull);
      expect(r['auteur_nom'], isNull, reason: 'auteur inconnu avant la v45');
    }
    expect(
      DateTime.parse(m[0]['updated_at']! as String).millisecondsSinceEpoch ~/
          1000,
      date1,
      reason:
          'l\'instant de saisie est celui de la rédaction, pas de la migration',
    );
    expect(
      DateTime.parse(m[1]['updated_at']! as String).millisecondsSinceEpoch ~/
          1000,
      date2,
    );
    await db.close();
  });

  test(
    'l\'instantané de corbeille reçoit un UUID et ne renvoie aucune pierre tombale',
    () async {
      await baseV44();
      final db = AppDatabase.pourFichier(fichier);
      final c = await lire(
        db,
        "SELECT donnees_json FROM corbeille WHERE nom_table = 'messages_editeur'",
      );

      final donnees =
          jsonDecode(c.single['donnees_json']! as String)
              as Map<String, Object?>;
      expect(donnees['id'], matches(uuid));
      expect(
        donnees['sync_status'],
        'synced',
        reason: 'le serveur n\'a jamais vu ce message',
      );
      expect(donnees['sujet'], 'Ancien');
      expect(donnees['updated_at'], isA<String>());
      await db.close();
    },
  );

  test(
    'rejouée (version estampillée 44 à tort), aucun UUID ne change',
    () async {
      await baseV44();
      var db = AppDatabase.pourFichier(fichier);
      final avant = await lire(
        db,
        'SELECT id FROM messages_editeur ORDER BY horodatage',
      );
      await db.customStatement('PRAGMA user_version = 44');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      final apres = await lire(
        db,
        'SELECT id FROM messages_editeur ORDER BY horodatage',
      );
      expect(apres, avant);
      await db.close();
    },
  );

  test(
    'une base neuve crée directement la table en UUID, base à la version courante',
    () async {
      final db = AppDatabase.pourFichier(fichier);
      await db.customSelect('SELECT 1').get();
      final colonnes = await lire(db, 'PRAGMA table_info("messages_editeur")');
      final id = colonnes.firstWhere((c) => c['name'] == 'id');
      expect((id['type']! as String).toUpperCase(), 'TEXT');
      expect(
        colonnes.map((c) => c['name']),
        containsAll(['auteur_nom', 'sync_status', 'sync_motif', 'updated_at']),
      );
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.first, AppDatabase.versionSchema);
      expect(AppDatabase.versionSchema, greaterThanOrEqualTo(45));
      await db.close();
    },
  );
}
