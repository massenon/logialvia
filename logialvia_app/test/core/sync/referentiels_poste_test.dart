import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/seed/modules_actifs_seeder.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/administration/data/sync/table_modules_actifs_poste.dart';
import 'package:logialvia_app/administration/data/sync/table_parametres_entreprise_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import 'faux_serveur_sync.dart';

/// Palier 2 — les référentiels descendent du serveur (`46_` §2.2), avec leurs
/// garde-fous : valeurs de semis, champs propres à la machine, `null` qui n'efface rien.
void main() {
  late AppDatabase db;
  late FauxServeurSync serveur;
  late MoteurSynchronisationPoste moteur;
  late PreferencesPosteRepository preferences;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    await ModulesActifsSeeder(db).executer();
    serveur = FauxServeurSync();
    preferences = PreferencesPosteRepository(db);
    final depot = DepotJetonSyncMemoire();
    final appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: serveur.client,
    );
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: appairage,
      tables: [
        TableModulesActifsPoste(db),
        TableParametresEntreprisePoste(db),
        TableClientsPoste(db),
      ],
      client: serveur.client,
    );
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  });

  tearDown(() => db.close());

  Future<bool> actif(String id) async => (await (db.select(
    db.modulesActifs,
  )..where((m) => m.moduleId.equals(id))).getSingle()).isActif;

  Future<ParametresEntrepriseRow> params() => (db.select(
    db.parametresEntreprise,
  )..where((p) => p.id.equals(1))).getSingle();

  group('modules_actifs', () {
    test(
      'un changement décidé sur le serveur est appliqué, et compté',
      () async {
        expect(await actif('pisciculture'), isFalse);
        serveur.ajouterModule(
          'pisciculture',
          actif: true,
          espece: 'poissons-chats',
        );

        final r = await moteur.synchroniser();

        expect(await actif('pisciculture'), isTrue);
        expect(r.referentielsMisAJour, 1);
        expect(
          r.recues,
          0,
          reason: 'un réglage n\'est pas une « ligne reçue »',
        );
        expect(
          r.message,
          contains('1 réglage(s) mis à jour depuis le serveur'),
        );
      },
    );

    test(
      'une valeur de SEMIS du serveur n\'écrase pas le choix de la Gérante',
      () async {
        await (db.update(db.modulesActifs)
              ..where((m) => m.moduleId.equals('ovins')))
            .write(const ModulesActifsCompanion(isActif: Value(true)));
        serveur.ajouterModule('ovins', actif: false, decide: false);

        final r = await moteur.synchroniser();

        expect(await actif('ovins'), isTrue);
        expect(r.referentielsMisAJour, 0);
        expect(r.conserveesLocalement, 1);
      },
    );

    test('un module inconnu du poste est refusé, les autres passent', () async {
      serveur.ajouterModule('astrologie', actif: true);
      serveur.ajouterModule('cuniculture', actif: true, espece: 'lapins');

      final r = await moteur.synchroniser();

      expect(r.refuseesALaReception, 1);
      expect(await actif('cuniculture'), isTrue);
      final ids = (await db.select(db.modulesActifs).get()).map(
        (m) => m.moduleId,
      );
      expect(ids, isNot(contains('astrologie')));
    });

    test(
      'une valeur incohérente (is_actif = "oui") est refusée, pas devinée',
      () async {
        serveur.ajouterModule('ovins', actif: true);
        serveur.modules['ovins']!['is_actif'] = 'oui';

        final r = await moteur.synchroniser();

        expect(r.refuseesALaReception, 1);
        expect(await actif('ovins'), isFalse);
      },
    );

    test('le poste n\'envoie JAMAIS un référentiel', () async {
      await (db.update(db.modulesActifs)
            ..where((m) => m.moduleId.equals('ovins')))
          .write(const ModulesActifsCompanion(isActif: Value(true)));
      await moteur.synchroniser();
      for (final envoi in serveur.envois) {
        expect(
          (envoi['tables'] as Map).keys,
          isNot(contains('modules_actifs')),
        );
      }
    });

    test('rejouer le même tirage ne change plus rien', () async {
      serveur.ajouterModule('ovins', actif: true);
      await moteur.synchroniser();
      await preferences.definirCurseurTirage(null);

      final r = await moteur.synchroniser();

      expect(r.referentielsMisAJour, 0);
    });
  });

  group('parametres_entreprise', () {
    setUp(() async {
      await db
          .into(db.parametresEntreprise)
          .insertOnConflictUpdate(
            const ParametresEntrepriseCompanion(
              ifu: Value('IFU-LOCAL-123'),
              rccm: Value('RCCM-LOCAL'),
              cheminLogo: Value('C:\\logos\\allmany.png'),
              modeDonneesTest: Value(false),
            ),
          );
    });

    test(
      'poste neuf (aucune ligne encore enregistrée) : elle est créée',
      () async {
        await db.delete(db.parametresEntreprise).go();
        serveur.definirParametres({'raison_sociale': 'ALLMANY SARL'});

        final r = await moteur.synchroniser();

        expect((await params()).raisonSociale, 'ALLMANY SARL');
        expect(r.referentielsMisAJour, 1);
      },
    );

    test(
      'poste neuf et ligne de SEMIS du serveur : rien n\'est créé',
      () async {
        await db.delete(db.parametresEntreprise).go();
        serveur.definirParametres({'raison_sociale': 'Autre'}, decide: false);

        await moteur.synchroniser();

        expect(await db.select(db.parametresEntreprise).get(), isEmpty);
      },
    );

    test('un réglage décidé sur le serveur est appliqué', () async {
      serveur.definirParametres({
        'raison_sociale': 'ALLMANY SARL',
        'prefixe_bac': 'BC',
        'smtp_port': 587,
      });

      final r = await moteur.synchroniser();

      final p = await params();
      expect(p.raisonSociale, 'ALLMANY SARL');
      expect(p.prefixeBac, 'BC');
      expect(p.smtpPort, 587);
      expect(r.referentielsMisAJour, 1);
    });

    test(
      'une valeur NULL du serveur n\'efface jamais l\'IFU ni le RCCM du poste',
      () async {
        serveur.definirParametres({
          'raison_sociale': 'ALLMANY SARL',
          'ifu': null,
          'rccm': null,
        });

        await moteur.synchroniser();

        final p = await params();
        expect(p.raisonSociale, 'ALLMANY SARL');
        expect(p.ifu, 'IFU-LOCAL-123');
        expect(p.rccm, 'RCCM-LOCAL');
      },
    );

    test(
      'une ligne de SEMIS du serveur (web neuf, vide) n\'écrase rien',
      () async {
        serveur.definirParametres({
          'raison_sociale': 'Autre nom',
          'ifu': 'IFU-WEB',
        }, decide: false);

        final r = await moteur.synchroniser();

        final p = await params();
        expect(p.raisonSociale, isNot('Autre nom'));
        expect(p.ifu, 'IFU-LOCAL-123');
        expect(r.conserveesLocalement, 1);
      },
    );

    test(
      'jamais le chemin du logo, ni le verrou « données de test », ni l\'identifiant',
      () async {
        serveur.definirParametres({
          'raison_sociale': 'ALLMANY SARL',
          'chemin_logo': '/var/www/logo.png',
          'chemin_favicon': '/var/www/fav.ico',
          'mode_donnees_test': true,
          'id': 'uuid-du-serveur',
        });

        await moteur.synchroniser();

        final p = await params();
        expect(p.raisonSociale, 'ALLMANY SARL');
        expect(p.cheminLogo, 'C:\\logos\\allmany.png');
        expect(p.cheminFavicon, isNull);
        expect(
          p.modeDonneesTest,
          isFalse,
          reason: 'un serveur ne lève pas le verrou de sécurité du poste',
        );
        expect(p.id, 1);
      },
    );

    test(
      'un préfixe trop long ou vide est refusé : la ligne entière est écartée',
      () async {
        serveur.definirParametres({
          'raison_sociale': 'ALLMANY SARL',
          'prefixe_cage': 'TROPLONG',
        });

        final r = await moteur.synchroniser();

        expect(r.refuseesALaReception, 1);
        expect((await params()).raisonSociale, isNot('ALLMANY SARL'));
      },
    );

    test('mecef_actif accepte 0/1 comme booléen, refuse le reste', () async {
      serveur.definirParametres({'mecef_actif': 1});
      await moteur.synchroniser();
      expect((await params()).mecefActif, isTrue);

      await preferences.definirCurseurTirage(null);
      serveur.definirParametres({'mecef_actif': 'peut-être'});
      final r = await moteur.synchroniser();
      expect(r.refuseesALaReception, 1);
      expect((await params()).mecefActif, isTrue);
    });
  });

  test(
    'une remise à zéro du serveur préserve les référentiels du poste',
    () async {
      serveur.ajouterModule('ovins', actif: true);
      await moteur.synchroniser();
      expect(await actif('ovins'), isTrue);

      serveur.remettreAZero();
      final r = await moteur.synchroniser();

      expect(r.remiseAZero, isTrue);
      expect(await actif('ovins'), isTrue);
    },
  );
}
