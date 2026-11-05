import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/seed/admin_seeder.dart';
import 'package:logialvia_app/administration/domain/services/service_sauvegarde.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:path/path.dart' as p;

/// Sauvegardes de la base — onglet ajouté aux Paramètres Généraux.
///
/// ⚠️ Le prototype affiche « Sauvegarde quotidienne effectuée — 05:00 » dans
/// ses notifications alors qu'aucun mécanisme de sauvegarde n'existe.
void main() {
  late AppDatabase db;
  late Directory documents;
  late ServiceSauvegarde service;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    await AdminSeeder(db).executer();
    documents = await Directory.systemTemp.createTemp('logialvia_sauvegardes');
    service = ServiceSauvegarde(db, documents);
  });

  tearDown(() async {
    await db.close();
    if (await documents.exists()) {
      await documents.delete(recursive: true);
    }
  });

  group('Sauvegarde complète de la base', () {
    test('le fichier est créé et n\'est pas vide', () async {
      final sauvegarde = await service.genererBaseComplete();

      final fichier = File(sauvegarde.chemin);
      expect(await fichier.exists(), isTrue);
      expect(
        sauvegarde.tailleOctets,
        greaterThan(1024),
        reason:
            'Une base seedee pese forcement plus d\'un kilo-octet : un fichier '
            'quasi vide signalerait un VACUUM qui n\'a rien copie.',
      );
      expect(sauvegarde.portee, ServiceSauvegarde.porteeBaseComplete);
    });

    test('la copie est réellement ouvrable et contient les données', () async {
      final sauvegarde = await service.genererBaseComplete();

      // C'est le seul test qui compte vraiment : une sauvegarde qu'on ne peut
      // pas relire ne sauvegarde rien.
      final copie = AppDatabase.pourFichier(File(sauvegarde.chemin));
      addTearDown(copie.close);

      final utilisateurs = await copie.select(copie.utilisateurs).get();
      expect(
        utilisateurs,
        isNotEmpty,
        reason: 'Le compte administrateur seede doit s\'y retrouver.',
      );

      final produits = await copie.select(copie.produitsVendables).get();
      expect(produits, isNotEmpty);
    });

    test('deux sauvegardes ne se marchent pas dessus', () async {
      final a = await service.genererBaseComplete(
        maintenant: DateTime(2026, 8, 18, 14, 30, 12),
      );
      final b = await service.genererBaseComplete(
        maintenant: DateTime(2026, 8, 18, 14, 30, 13),
      );

      expect(a.nom, isNot(b.nom));
      expect(await File(a.chemin).exists(), isTrue);
      expect(await File(b.chemin).exists(), isTrue);
    });

    test('le nom est triable et sans caractère interdit sous Windows', () {
      final nom =
          'logialvia-${ServiceSauvegarde.horodatage(DateTime(2026, 8, 18, 9, 5, 3))}'
          '.sqlite';

      expect(nom, 'logialvia-2026-08-18-090503.sqlite');
      for (final interdit in const [':', '*', '?', '"', '<', '>', '|']) {
        expect(nom.contains(interdit), isFalse, reason: interdit);
      }
    });

    test('le dossier est dans Documents, pas dans le support applicatif', () {
      expect(service.dossier.path, startsWith(documents.path));
      expect(
        service.dossier.path,
        contains('Sauvegardes'),
        reason:
            'Une sauvegarde rangee dans le support applicatif disparaitrait a '
            'la desinstallation.',
      );
    });
  });

  group('Export CSV d\'une table', () {
    test('les en-têtes et les lignes y sont', () async {
      final export = await service.exporterTable('produits_vendables');

      final contenu = await File(export.chemin).readAsString();
      expect(export.portee, 'produits_vendables');
      expect(contenu, contains('name'));
      expect(contenu, contains('Goliath mature'));
    });

    test('le séparateur est le point-virgule — Excel en français', () async {
      final export = await service.exporterTable('produits_vendables');
      final premiere = (await File(export.chemin).readAsLines()).first;

      expect(
        premiere.contains(';'),
        isTrue,
        reason:
            'En locale francaise la virgule est le separateur decimal : un CSV '
            'a virgules casse toutes les colonnes de montants.',
      );
    });

    test('le fichier porte le BOM UTF-8', () async {
      final export = await service.exporterTable('produits_vendables');
      final octets = await File(export.chemin).readAsBytes();

      expect(
        octets.take(3),
        [0xEF, 0xBB, 0xBF],
        reason:
            'Sans BOM, Excel sous Windows affiche « Mais » au lieu de « Maïs ».',
      );
    });

    test(
      'une table vide produit quand même son fichier avec ses en-têtes',
      () async {
        final export = await service.exporterTable('ventes');

        final lignes = await File(export.chemin).readAsLines();
        expect(await File(export.chemin).exists(), isTrue);
        expect(
          lignes.first,
          contains('ref'),
          reason:
              'Un export absent se confondrait avec un export echoue : la table '
              'vide doit produire ses colonnes.',
        );
      },
    );

    test('une valeur contenant un point-virgule est échappée', () async {
      await db.customStatement(
        "INSERT INTO clients (nom, telephone) VALUES ('DUPONT; Marie', '97')",
      );
      final export = await service.exporterTable('clients');
      final contenu = await File(export.chemin).readAsString();

      expect(
        contenu,
        contains('"DUPONT; Marie"'),
        reason: 'Sans guillemets, le nom deborderait sur la colonne suivante.',
      );
    });

    test('une table inconnue est refusée', () async {
      // Le nom part dans une requete SQL : il doit venir du schema.
      expect(
        () => service.exporterTable('ventes; DROP TABLE utilisateurs'),
        throwsArgumentError,
      );
    });

    test('toutes les tables du schéma sont exportables', () {
      final tables = service.tablesExportables;
      expect(tables, contains('ventes'));
      expect(tables, contains('ecriture_comptable'));
      expect(tables, contains('preferences_poste'));
      expect(tables, equals(List.of(tables)..sort()));
    });
  });

  group('Listing du dossier', () {
    test('vide au départ, sans créer le dossier pour rien', () async {
      expect(await service.lister(), isEmpty);
    });

    test('les sauvegardes remontent, la plus récente en premier', () async {
      final ancienne = await service.genererBaseComplete(
        maintenant: DateTime(2026, 8, 18, 10),
      );
      final recente = await service.exporterTable(
        'ventes',
        maintenant: DateTime(2026, 8, 18, 11),
      );

      // `lister()` lit la date REELLE du fichier, pas celle devinee depuis son
      // nom — un fichier renomme a la main ne doit pas mentir sur sa date. Les
      // deux venant d'etre ecrits dans la meme seconde, on les date
      // explicitement pour eprouver le tri.
      await File(ancienne.chemin).setLastModified(DateTime(2026, 8, 18, 10));
      await File(recente.chemin).setLastModified(DateTime(2026, 8, 18, 11));

      final liste = await service.lister();
      expect(liste, hasLength(2));
      expect(liste.first.nom, recente.nom);
      expect(liste.last.nom, ancienne.nom);
      expect(liste.first.date.isAfter(liste.last.date), isTrue);
    });

    test(
      'la date affichée est celle du fichier, pas celle de son nom',
      () async {
        final sauvegarde = await service.genererBaseComplete(
          maintenant: DateTime(2026, 8, 18, 10),
        );
        await File(sauvegarde.chemin).setLastModified(DateTime(2026, 9, 1, 8));

        final liste = await service.lister();
        expect(
          liste.single.date,
          DateTime(2026, 9, 1, 8),
          reason:
              'Un fichier copie ou renomme garderait sinon une date trompeuse.',
        );
      },
    );

    test('la portée est relue depuis le nom du fichier', () async {
      await service.genererBaseComplete();
      await service.exporterTable('ecriture_comptable');

      final liste = await service.lister();
      final portees = liste.map((f) => f.portee).toSet();

      expect(portees, contains(ServiceSauvegarde.porteeBaseComplete));
      expect(
        portees,
        contains('ecriture_comptable'),
        reason:
            'Le nom de table doit rester lisible malgre l\'horodatage accole.',
      );
    });

    test('un fichier étranger au dossier est ignoré', () async {
      await service.genererBaseComplete();
      await File(p.join(service.dossier.path, 'notes.txt')).writeAsString('x');

      final liste = await service.lister();
      expect(liste, hasLength(1));
      expect(liste.single.nom, endsWith('.sqlite'));
    });

    test('une sauvegarde supprimée disparaît de la liste', () async {
      final sauvegarde = await service.genererBaseComplete();
      expect(await service.lister(), hasLength(1));

      await service.supprimer(sauvegarde);

      expect(await service.lister(), isEmpty);
      expect(await File(sauvegarde.chemin).exists(), isFalse);
    });
  });

  group('Taille lisible', () {
    test('les octets, kilo-octets et méga-octets sont distingués', () {
      FichierSauvegarde avec(int octets) => FichierSauvegarde(
        chemin: 'x',
        nom: 'x',
        date: DateTime(2026),
        portee: 'x',
        tailleOctets: octets,
      );

      expect(avec(512).taille, '512 octets');
      expect(avec(2048).taille, '2 Ko');
      expect(avec(3 * 1024 * 1024).taille, '3,0 Mo');
    });
  });
}
