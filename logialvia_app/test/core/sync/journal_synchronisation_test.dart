import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_journal_synchronisation.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';

/// Journal des tentatives de synchronisation du poste (schéma 52).
void main() {
  late AppDatabase db;
  late DepotJournalSynchronisation depot;

  setUp(() {
    db = AppDatabase.enMemoire();
    depot = DepotJournalSynchronisation(db);
  });

  tearDown(() => db.close());

  Future<void> noter(
    RapportSynchronisation rapport, {
    String declencheur = 'manuel',
  }) => depot.enregistrer(
    debut: DateTime(2026, 11, 11, 10),
    duree: const Duration(milliseconds: 420),
    declencheur: declencheur,
    rapport: rapport,
  );

  test('un cycle réussi est journalisé avec ses compteurs', () async {
    await noter(
      const RapportSynchronisation(
        IssueSynchronisation.terminee,
        'Synchronisation terminée.',
        recues: 4,
        envoyees: 3,
        acceptees: 2,
        refusees: 1,
        enAttenteDeDroit: 5,
      ),
    );

    final l = (await depot.dernieres()).single;
    expect(l.issue, 'terminee');
    expect(l.declencheur, 'manuel');
    expect(
      [l.recues, l.envoyees, l.acceptees, l.refusees, l.enAttenteDeDroit],
      [4, 3, 2, 1, 5],
    );
    expect(l.dureeMs, 420);
    expect(l.message, 'Synchronisation terminée.');
  });

  test('les 10 dernières, du plus récent au plus ancien', () async {
    for (var i = 1; i <= 12; i++) {
      await noter(
        RapportSynchronisation(IssueSynchronisation.terminee, 'cycle $i'),
      );
    }

    final dix = await depot.dernieres();
    expect(dix, hasLength(10));
    expect(dix.first.message, 'cycle 12');
    expect(dix.last.message, 'cycle 3');
  });

  test(
    'poste non appairé : rien ; hors ligne : une seule ligne de suite',
    () async {
      await noter(
        const RapportSynchronisation(IssueSynchronisation.nonAppairee, 'non'),
      );
      expect(await depot.dernieres(), isEmpty);

      const horsLigne = RapportSynchronisation(
        IssueSynchronisation.horsLigne,
        'Hors ligne',
      );
      await noter(horsLigne);
      await noter(horsLigne);
      expect(await depot.dernieres(), hasLength(1));

      await noter(
        const RapportSynchronisation(IssueSynchronisation.terminee, 'ok'),
      );
      await noter(horsLigne);
      expect(await depot.dernieres(), hasLength(3));
    },
  );

  test(
    'seuls les ${DepotJournalSynchronisation.conservees} derniers sont gardés',
    () async {
      for (var i = 1; i <= DepotJournalSynchronisation.conservees + 5; i++) {
        await noter(
          RapportSynchronisation(IssueSynchronisation.terminee, 'cycle $i'),
        );
      }

      final tous = await depot.dernieres(1000);
      expect(tous, hasLength(DepotJournalSynchronisation.conservees));
      expect(tous.last.message, 'cycle 6');
    },
  );

  test(
    'l\'export CSV : en-tête, guillemets et point-virgule du message protégés',
    () async {
      await noter(
        const RapportSynchronisation(
          IssueSynchronisation.refusee,
          'Refus ; "motif" du serveur',
          refusees: 2,
        ),
      );

      final csv = await depot.exporterCsv();
      final lignes = csv.trim().split('\r\n');
      expect(lignes.first, contains('date;duree_ms;declencheur;issue'));
      expect(lignes[1], endsWith(';"Refus ; ""motif"" du serveur"'));

      final dossier = Directory.systemTemp.createTempSync('logialvia_journal');
      addTearDown(() => dossier.deleteSync(recursive: true));
      final fichier = await depot.exporterVers(Directory('${dossier.path}/x'));
      expect(fichier.existsSync(), isTrue);
      expect(fichier.path, contains('Journal-synchronisation-'));
    },
  );

  test(
    'migration 51 -> 52 : la table est créée, et l\'ouverture est rejouable',
    () async {
      final dossier = Directory.systemTemp.createTempSync('logialvia_v52');
      addTearDown(() => dossier.deleteSync(recursive: true));
      final fichier = File('${dossier.path}/logialvia.db');

      var base = AppDatabase.pourFichier(fichier);
      await base.customSelect('SELECT 1').get();
      await base.customStatement('DROP TABLE journal_synchronisation');
      await base.customStatement('PRAGMA user_version = 51');
      await base.close();

      base = AppDatabase.pourFichier(fichier);
      final n = await base
          .customSelect('SELECT COUNT(*) AS n FROM journal_synchronisation')
          .getSingle();
      expect(n.data['n'], 0);
      final v = await base.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.first, AppDatabase.versionSchema);
      expect(AppDatabase.versionSchema, greaterThanOrEqualTo(52));
      await base.close();

      // Rejouée avec la table déjà là : aucune erreur.
      base = AppDatabase.pourFichier(fichier);
      await base.customStatement('PRAGMA user_version = 51');
      await base.close();
      base = AppDatabase.pourFichier(fichier);
      await base
          .customSelect('SELECT COUNT(*) FROM journal_synchronisation')
          .get();
      await base.close();
    },
  );
}
