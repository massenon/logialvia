import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/domain/services/service_restauration.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:sqlite3/sqlite3.dart';

/// Restaurer une sauvegarde — l'opération la plus destructrice du logiciel.
///
/// ## Le défaut que ce service comble
///
/// L'onglet Sauvegardes savait générer, exporter, lister et supprimer. Il ne
/// savait pas **restaurer** : l'application invitait la Gérante à faire des
/// sauvegardes et ne lui permettait jamais de s'en servir.
///
/// ## Ce que ces tests protègent
///
/// Une restauration remplace toute la comptabilité d'une exploitation. Les
/// contrôles doivent donc tous avoir lieu **avant** que le moindre octet ne
/// bouge : une restauration qui échoue en cours de route laisserait la ferme
/// sans base du tout.
void main() {
  late Directory dossierBase;
  late Directory dossierSauvegardes;
  late ServiceRestauration service;

  setUp(() {
    dossierBase = Directory.systemTemp.createTempSync('logialvia_base');
    dossierSauvegardes = Directory.systemTemp.createTempSync('logialvia_sauv');
    service = ServiceRestauration(
      dossierBase: dossierBase,
      dossierSauvegardes: dossierSauvegardes,
      versionLogiciel: AppDatabase.versionSchema,
    );
  });

  tearDown(() {
    for (final d in [dossierBase, dossierSauvegardes]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  File fichierBase() =>
      File('${dossierBase.path}/${ServiceRestauration.nomBase}');

  /// Une vraie base LogiALVIA, avec une marque reconnaissable.
  Future<File> baseLogiALVIA(String chemin, {String? marque}) async {
    final db = AppDatabase.pourFichier(File(chemin));
    await db.customSelect('SELECT 1').get();
    if (marque != null) {
      await db.customStatement(
        "INSERT INTO clients (nom, telephone) VALUES ('$marque', '97')",
      );
    }
    await db.close();
    return File(chemin);
  }

  group('Contrôles — rien ne bouge tant qu\'ils ne passent pas', () {
    test('un fichier absent est refusé', () {
      final r = service.verifier(
        File('${dossierSauvegardes.path}/rien.sqlite'),
      );
      expect(r, isA<Echec<int>>());
    });

    test('un fichier vide est refusé', () {
      final f = File('${dossierSauvegardes.path}/vide.sqlite')..createSync();
      expect(service.verifier(f), isA<Echec<int>>());
    });

    test('un fichier qui n\'est pas du SQLite est refusé', () {
      // Le cas d'un document renomme en .sqlite — l'extension ne prouve rien.
      final f = File('${dossierSauvegardes.path}/faux.sqlite')
        ..writeAsStringSync('Ceci est une facture, pas une base.');
      final r = service.verifier(f);
      expect(r, isA<Echec<int>>());
      expect((r as Echec<int>).message, contains('SQLite'));
    });

    test('une base SQLite d\'un autre logiciel est refusée', () async {
      final chemin = '${dossierSauvegardes.path}/autre.sqlite';
      final autre = sqlite3.open(chemin);
      autre.execute('CREATE TABLE recettes (id INTEGER, titre TEXT)');
      autre.close();

      final r = service.verifier(File(chemin));
      expect(r, isA<Echec<int>>());
      expect(
        (r as Echec<int>).message,
        contains('utilisateurs'),
        reason: 'Le message doit dire ce qui manque, pas juste « invalide ».',
      );
    });

    test('une base d\'une version PLUS RÉCENTE est refusée', () async {
      final chemin = '${dossierSauvegardes.path}/futur.sqlite';
      await baseLogiALVIA(chemin);
      final futur = sqlite3.open(chemin);
      futur.execute('PRAGMA user_version = ${AppDatabase.versionSchema + 3}');
      futur.close();

      final r = service.verifier(File(chemin));
      expect(r, isA<Echec<int>>());
      expect(
        (r as Echec<int>).message,
        contains('plus récente'),
        reason: 'On sait migrer en avant, jamais en arrière.',
      );
    });

    test('une base d\'une version plus ANCIENNE est acceptée', () async {
      // Elle sera migree a l'ouverture : c'est le cas normal d'une vieille
      // sauvegarde.
      final chemin = '${dossierSauvegardes.path}/ancienne.sqlite';
      await baseLogiALVIA(chemin);
      final ancienne = sqlite3.open(chemin);
      ancienne.execute('PRAGMA user_version = 16');
      ancienne.close();

      expect(service.verifier(File(chemin)), isA<Succes<int>>());
    });

    test('le contrôle ne modifie pas la sauvegarde', () async {
      final chemin = '${dossierSauvegardes.path}/intacte.sqlite';
      await baseLogiALVIA(chemin);
      final avant = File(chemin).lastModifiedSync();
      final octetsAvant = File(chemin).lengthSync();

      service.verifier(File(chemin));

      // Ouvrir en lecture seule est ce qui garantit qu'on ne migre pas — donc
      // qu'on ne modifie pas — la sauvegarde qu'on est en train de verifier.
      expect(File(chemin).lengthSync(), octetsAvant);
      expect(File(chemin).lastModifiedSync(), avant);
    });
  });

  group('Mise en attente', () {
    test('rien n\'est appliqué avant le redémarrage', () async {
      await baseLogiALVIA(fichierBase().path, marque: 'BASE COURANTE');
      final sauvegarde = await baseLogiALVIA(
        '${dossierSauvegardes.path}/sauv.sqlite',
        marque: 'SAUVEGARDE',
      );

      expect(await service.preparer(sauvegarde), isA<Succes<void>>());

      // La base en service est intacte : la Gerante peut continuer a
      // travailler, et meme changer d'avis.
      final db = AppDatabase.pourFichier(fichierBase());
      final noms = await db.customSelect('SELECT nom FROM clients').get();
      expect(noms.single.read<String>('nom'), 'BASE COURANTE');
      await db.close();

      expect(service.restaurationEnAttente, isTrue);
    });

    test('une sauvegarde invalide n\'est pas mise en attente', () async {
      final f = File('${dossierSauvegardes.path}/faux.sqlite')
        ..writeAsStringSync('pas une base');
      expect(await service.preparer(f), isA<Echec<void>>());
      expect(service.restaurationEnAttente, isFalse);
    });

    test('la mise en attente s\'annule', () async {
      final sauvegarde = await baseLogiALVIA(
        '${dossierSauvegardes.path}/sauv.sqlite',
      );
      await service.preparer(sauvegarde);
      await service.annuler();
      expect(service.restaurationEnAttente, isFalse);
    });
  });

  group('Application au démarrage', () {
    test('sans demande, le démarrage ne fait rien', () async {
      expect(await service.appliquerSiDemandee(), isNull);
    });

    test('la sauvegarde remplace bien la base', () async {
      await baseLogiALVIA(fichierBase().path, marque: 'BASE COURANTE');
      await service.preparer(
        await baseLogiALVIA(
          '${dossierSauvegardes.path}/sauv.sqlite',
          marque: 'SAUVEGARDE',
        ),
      );

      final rapport = await service.appliquerSiDemandee(
        maintenant: DateTime(2026, 8, 20, 14, 30),
      );
      expect(rapport, isNotNull);

      final db = AppDatabase.pourFichier(fichierBase());
      final noms = await db.customSelect('SELECT nom FROM clients').get();
      expect(noms.single.read<String>('nom'), 'SAUVEGARDE');
      await db.close();
    });

    test(
      'la base précédente est conservée — le retour reste possible',
      () async {
        await baseLogiALVIA(fichierBase().path, marque: 'BASE COURANTE');
        await service.preparer(
          await baseLogiALVIA(
            '${dossierSauvegardes.path}/sauv.sqlite',
            marque: 'SAUVEGARDE',
          ),
        );

        final rapport = await service.appliquerSiDemandee(
          maintenant: DateTime(2026, 8, 20, 14, 30),
        );

        final copie = File(rapport!.copieDeSecurite);
        expect(
          copie.existsSync(),
          isTrue,
          reason:
              'Une restauration sans retour en arrière serait un aller simple '
              'sur la comptabilité de l\'exploitation.',
        );

        final db = AppDatabase.pourFichier(copie);
        final noms = await db.customSelect('SELECT nom FROM clients').get();
        expect(noms.single.read<String>('nom'), 'BASE COURANTE');
        await db.close();
      },
    );

    test(
      'la demande est consommée : elle ne rejoue pas au démarrage suivant',
      () async {
        await baseLogiALVIA(fichierBase().path);
        await service.preparer(
          await baseLogiALVIA('${dossierSauvegardes.path}/sauv.sqlite'),
        );

        expect(await service.appliquerSiDemandee(), isNotNull);
        expect(
          await service.appliquerSiDemandee(),
          isNull,
          reason:
              'Sans consommation, chaque démarrage écraserait le travail de la '
              'veille par la même sauvegarde.',
        );
      },
    );

    test(
      'un fichier en attente devenu illisible est écarté, pas appliqué',
      () async {
        await baseLogiALVIA(fichierBase().path, marque: 'BASE COURANTE');
        await service.preparer(
          await baseLogiALVIA('${dossierSauvegardes.path}/sauv.sqlite'),
        );

        // Le fichier est tronque entre le choix et le redemarrage.
        File(
          '${dossierBase.path}/${ServiceRestauration.nomEnAttente}',
        ).writeAsStringSync('corrompu');

        expect(await service.appliquerSiDemandee(), isNull);

        // La base en service n'a pas ete touchee.
        final db = AppDatabase.pourFichier(fichierBase());
        final noms = await db.customSelect('SELECT nom FROM clients').get();
        expect(noms.single.read<String>('nom'), 'BASE COURANTE');
        await db.close();

        expect(service.restaurationEnAttente, isFalse);
      },
    );

    test(
      'les journaux -wal et -shm de l\'ancienne base sont supprimés',
      () async {
        await baseLogiALVIA(fichierBase().path);
        File('${fichierBase().path}-wal').writeAsStringSync('vieux journal');
        File('${fichierBase().path}-shm').writeAsStringSync('vieux index');

        await service.preparer(
          await baseLogiALVIA('${dossierSauvegardes.path}/sauv.sqlite'),
        );
        await service.appliquerSiDemandee();

        // Les laisser ferait relire des pages qui ne correspondent plus au
        // fichier restaure.
        expect(File('${fichierBase().path}-wal').existsSync(), isFalse);
        expect(File('${fichierBase().path}-shm').existsSync(), isFalse);
      },
    );
  });
}
