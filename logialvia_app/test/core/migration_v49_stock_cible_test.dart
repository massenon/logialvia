import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v49 — `poste_cible` sur achats, ventes et les deux journaux de mouvements, plus
/// la table locale `effets_appliques` (`47s_`).
///
/// Les risques : perdre une ligne existante, donner un poste cible à un fait ancien (qui
/// produirait un effet de stock rétroactif), planter si la migration est rejouée après une
/// interruption, ou oublier la table d'idempotence.
void main() {
  late Directory dossier;
  late File fichier;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v49');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  /// Une base de version [version] : schéma courant, sauf les ajouts de la v49 retirés,
  /// avec des faits déjà saisis (un achat, une vente, deux mouvements).
  Future<void> baseAvant49(int version) async {
    final db = AppDatabase.pourFichier(fichier);
    await SeedInitial(db).executer();
    final maintenant = DateTime(2026, 11, 9, 10);
    final f = await db
        .into(db.fournisseurs)
        .insertReturning(FournisseursCompanion.insert(nom: 'Maïs Local'));
    await db
        .into(db.achats)
        .insert(
          AchatsCompanion.insert(
            ref: 'ACH-2026-001',
            fournisseurId: f.id,
            dateAchat: maintenant,
            statut: 'Livré',
            total: 3000,
          ),
        );
    await db
        .into(db.ventes)
        .insert(
          VentesCompanion.insert(
            ref: 'V-2026-001',
            client: 'Client Comptant',
            dateVente: maintenant,
            mode: 'Espèces',
            status: 'Payée',
            total: 5000,
            paye: 5000,
          ),
        );
    await db
        .into(db.mouvementsIntrant)
        .insert(
          MouvementsIntrantCompanion.insert(
            horodatage: maintenant,
            intrantCode: 'INT-001',
            article: 'Maïs',
            type: 'Entrée',
            motif: 'Réception commande ACH-2026-001',
            quantite: 10,
          ),
        );
    final produit = (await db.select(db.produitsVendables).get()).first;
    await db
        .into(db.mouvementsProduit)
        .insert(
          MouvementsProduitCompanion.insert(
            horodatage: maintenant,
            produitId: produit.id,
            article: produit.name,
            motif: 'Comptage',
            quantite: 4,
          ),
        );
    for (final t in const [
      'achats',
      'ventes',
      'mouvements_intrant',
      'mouvements_produit',
    ]) {
      await db.customStatement('ALTER TABLE $t DROP COLUMN poste_cible');
    }
    await db.customStatement('DROP TABLE effets_appliques');
    await db.customStatement('PRAGMA user_version = $version');
    await db.close();
  }

  Future<List<Map<String, Object?>>> lire(AppDatabase db, String sql) =>
      db.customSelect(sql).get().then((l) => l.map((r) => r.data).toList());

  Future<Set<String>> colonnes(AppDatabase db, String table) async =>
      (await lire(
        db,
        'PRAGMA table_info("$table")',
      )).map((r) => r['name']! as String).toSet();

  for (final version in [47, 48]) {
    group('depuis une base v$version', () {
      test('les colonnes et la table d\'idempotence apparaissent', () async {
        await baseAvant49(version);
        final db = AppDatabase.pourFichier(fichier);

        for (final t in const [
          'achats',
          'ventes',
          'mouvements_intrant',
          'mouvements_produit',
        ]) {
          expect(await colonnes(db, t), contains('poste_cible'), reason: t);
        }
        expect(
          await colonnes(db, 'effets_appliques'),
          containsAll(<String>{
            'id',
            'fait_type',
            'fait_id',
            'nature',
            'reference',
            'libelle',
            'etat',
            'avertissement',
            'applique_le',
            'origine',
            'sync_status',
            'sync_motif',
          }),
        );
        expect(
          (await lire(db, 'PRAGMA user_version')).single['user_version'],
          AppDatabase.versionSchema,
        );
        await db.close();
      });

      test(
        'aucune ligne n\'est perdue et aucun fait ancien ne reçoit de poste cible',
        () async {
          await baseAvant49(version);
          final db = AppDatabase.pourFichier(fichier);

          for (final t in const [
            'achats',
            'ventes',
            'mouvements_intrant',
            'mouvements_produit',
          ]) {
            final l = await lire(db, 'SELECT * FROM $t');
            expect(l, hasLength(1), reason: t);
            expect(l.single['poste_cible'], isNull, reason: t);
          }
          expect(
            (await lire(db, 'SELECT total FROM achats')).single['total'],
            3000,
          );
          expect(
            (await lire(db, 'SELECT ref FROM ventes')).single['ref'],
            'V-2026-001',
          );
          expect(await lire(db, 'SELECT * FROM effets_appliques'), isEmpty);
          await db.close();
        },
      );

      test(
        'la migration est idempotente : rejouée sur une base déjà migrée',
        () async {
          await baseAvant49(version);
          var db = AppDatabase.pourFichier(fichier);
          await db.customSelect('SELECT 1').get();
          await db.close();

          // Un user_version resté en arrière (restauration, interruption) : on rejoue.
          db = AppDatabase.pourFichier(fichier);
          await db.customSelect('SELECT 1').get();
          await db.customStatement('PRAGMA user_version = $version');
          await db.close();

          db = AppDatabase.pourFichier(fichier);
          expect(await colonnes(db, 'achats'), contains('poste_cible'));
          expect(await lire(db, 'SELECT * FROM achats'), hasLength(1));
          await db.close();
        },
      );
    });
  }

  test(
    'la clé (fait, nature) est unique : un effet ne s\'écrit qu\'une fois',
    () async {
      final db = AppDatabase.pourFichier(fichier);
      await db.customSelect('SELECT 1').get();
      const insertion =
          "INSERT INTO effets_appliques (id, fait_type, fait_id, nature, libelle, etat, applique_le) "
          "VALUES (?, 'vente', 'e0000000-0000-4000-8000-000000000001', 'vente', 'x', 'applique', '2026-11-09T10:00:00Z')";
      await db.customStatement(insertion, [
        'i0000000-0000-4000-8000-000000000001',
      ]);
      await expectLater(
        db.customStatement(insertion, ['i0000000-0000-4000-8000-000000000002']),
        throwsA(anything),
      );
      await db.close();
    },
  );
}
