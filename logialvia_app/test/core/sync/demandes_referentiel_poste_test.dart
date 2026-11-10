import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/modules_actifs_repository_drift.dart';
import 'package:logialvia_app/administration/data/repositories/parametres_repository_drift.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/seed/modules_actifs_seeder.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/administration/data/sync/table_modules_actifs_poste.dart';
import 'package:logialvia_app/administration/data/sync/table_parametres_entreprise_poste.dart';
import 'package:logialvia_app/administration/domain/entities/parametres_entreprise.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import 'faux_serveur_sync.dart';

/// Le poste PROPOSE ses modifications de référentiel (`POST /sync/demandes`) :
/// file locale, adoption initiale, règle du plus récent, accusés.
void main() {
  late AppDatabase db;
  late FauxServeurSync serveur;
  late MoteurSynchronisationPoste moteur;
  late DepotDemandesReferentiel file;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    await ModulesActifsSeeder(db).executer();
    serveur = FauxServeurSync();
    final preferences = PreferencesPosteRepository(db);
    final depot = DepotJetonSyncMemoire();
    file = DepotDemandesReferentiel(db);
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: ServiceAppairage(
        preferences: preferences,
        depot: depot,
        client: serveur.client,
      ),
      tables: [TableModulesActifsPoste(db), TableParametresEntreprisePoste(db)],
      demandes: file,
      client: serveur.client,
    );
    // Le catalogue a sa propre adoption (testée à part) : ici on isole modules et paramètres.
    await preferences.definirCatalogueAdopte();
    await preferences.definirIntrantsAdoptes();
    await preferences.definirParametresElevageAdoptes();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  });

  tearDown(() => db.close());

  Future<List<DemandeReferentielRow>> demandes() =>
      db.select(db.demandesReferentiel).get();
  Future<bool> actif(String id) async => (await (db.select(
    db.modulesActifs,
  )..where((m) => m.moduleId.equals(id))).getSingle()).isActif;

  group('file locale', () {
    test('basculer un module dépose une demande', () async {
      await ModulesActifsRepositoryDrift(db).definirEtat('bovins', actif: true);

      final d = (await demandes()).single;
      expect(d.type, 'module_actif');
      expect(d.cle, 'bovins');
      expect(jsonDecode(d.donnees), {'module_id': 'bovins', 'is_actif': true});
      expect(d.syncStatus, 'pending');
      expect(d.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4')));
    });

    test(
      'deux bascules avant l\'envoi : une seule demande, la dernière',
      () async {
        final repo = ModulesActifsRepositoryDrift(db);
        await repo.definirEtat('bovins', actif: true);
        await repo.definirEtat('bovins', actif: false);

        final d = (await demandes()).single;
        expect(
          (jsonDecode(d.donnees) as Map<String, dynamic>)['is_actif'],
          false,
        );
      },
    );

    test(
      'enregistrer les paramètres dépose leur état RÉEL, sans logo ni verrou de test',
      () async {
        await db
            .into(db.parametresEntreprise)
            .insertOnConflictUpdate(
              const ParametresEntrepriseCompanion(
                cheminLogo: Value('C:\\logo.png'),
                modeDonneesTest: Value(true),
              ),
            );
        await ParametresRepositoryDrift(db).enregistrer(
          const ParametresEntrepriseModele(
            raisonSociale: 'ALLMANY SARL',
            ifu: 'IFU-1',
            modeDonneesTest: true,
          ),
        );

        final d = (await demandes()).single;
        final donnees = jsonDecode(d.donnees) as Map<String, dynamic>;
        expect(d.type, 'parametres_entreprise');
        expect(donnees['raison_sociale'], 'ALLMANY SARL');
        expect(donnees['ifu'], 'IFU-1');
        expect(donnees.keys, isNot(contains('chemin_logo')));
        expect(donnees.keys, isNot(contains('mode_donnees_test')));
      },
    );

    test(
      'une demande acceptée est conservée comme historique, la suivante en crée une nouvelle',
      () async {
        final repo = ModulesActifsRepositoryDrift(db);
        await repo.definirEtat('bovins', actif: true);
        await moteur.synchroniser();
        expect((await demandes()).single.syncStatus, 'synced');

        await repo.definirEtat('bovins', actif: false);

        final toutes = await demandes();
        expect(toutes.where((d) => d.syncStatus == 'pending'), hasLength(1));
      },
    );
  });

  group('envoi', () {
    test(
      'une modification de module est proposée, acceptée, puis marquée synchronisée',
      () async {
        await ModulesActifsRepositoryDrift(
          db,
        ).definirEtat('bovins', actif: true);

        final r = await moteur.synchroniser();

        expect(r.demandesAcceptees, 1);
        expect(r.message, contains('1 réglage(s) proposé(s) au serveur'));
        expect(serveur.demandesRecues.single['type'], 'module_actif');
        expect((await demandes()).single.syncStatus, 'synced');
      },
    );

    test('rien à proposer : aucun appel /demandes', () async {
      await moteur.synchroniser();
      expect(serveur.journal, isNot(contains('POST /api/sync/demandes')));
    });

    test(
      'une demande refusée devient « conflict » avec le motif du serveur',
      () async {
        serveur.refuserDemandes =
            'Droit insuffisant pour modifier les modules actifs.';
        await ModulesActifsRepositoryDrift(
          db,
        ).definirEtat('bovins', actif: true);

        final r = await moteur.synchroniser();

        expect(r.demandesRefusees, 1);
        final d = (await demandes()).single;
        expect(d.syncStatus, 'conflict');
        expect(
          d.syncMotif,
          'Droit insuffisant pour modifier les modules actifs.',
        );
        expect(
          await actif('bovins'),
          isTrue,
          reason: 'le choix local n\'est pas défait en silence',
        );

        // Un refus n'est pas renvoyé en boucle.
        serveur.journal.clear();
        await moteur.synchroniser();
        expect(serveur.journal, isNot(contains('POST /api/sync/demandes')));
      },
    );

    test(
      'une demande remplacée PENDANT l\'envoi repart au prochain envoi',
      () async {
        final repo = ModulesActifsRepositoryDrift(db);
        await repo.definirEtat('bovins', actif: true);
        serveur.pendantDemandes = () async {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          await repo.definirEtat('bovins', actif: false);
        };

        await moteur.synchroniser();

        final d = (await demandes()).single;
        expect(
          d.syncStatus,
          'pending',
          reason: 'remplacée après l\'envoi : jamais « synchronisée » à tort',
        );
        expect(
          (jsonDecode(d.donnees) as Map<String, dynamic>)['is_actif'],
          false,
        );
      },
    );

    test('hors ligne : la demande reste en attente', () async {
      await ModulesActifsRepositoryDrift(db).definirEtat('bovins', actif: true);
      serveur.horsLigne = true;
      await moteur.synchroniser();
      expect((await demandes()).single.syncStatus, 'pending');
    });

    test(
      'aDesSaisiesAEnvoyer voit une demande en attente (le geste la déclenche)',
      () async {
        expect(await moteur.aDesSaisiesAEnvoyer(), isFalse);
        await ModulesActifsRepositoryDrift(
          db,
        ).definirEtat('bovins', actif: true);
        expect(await moteur.aDesSaisiesAEnvoyer(), isTrue);
      },
    );
  });

  group('règle du plus récent : tirage contre demande en attente', () {
    test(
      'le choix du poste, fait APRÈS la décision du serveur, n\'est pas écrasé par le tirage',
      () async {
        serveur.ajouterModule(
          'bovins',
          actif: false,
          decisionLe: DateTime.now().subtract(const Duration(hours: 1)),
        );
        await ModulesActifsRepositoryDrift(
          db,
        ).definirEtat('bovins', actif: true);
        serveur.demandesAccepteesParLeServeur =
            false; // on ne regarde que le tirage

        await moteur.synchroniser();

        expect(await actif('bovins'), isTrue);
      },
    );

    test(
      'une décision du serveur PLUS RÉCENTE que la demande l\'emporte, et la demande tombe',
      () async {
        await ModulesActifsRepositoryDrift(
          db,
        ).definirEtat('bovins', actif: true);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        serveur.ajouterModule(
          'bovins',
          actif: false,
          decisionLe: DateTime.now().add(const Duration(minutes: 1)),
        );

        final r = await moteur.synchroniser();

        expect(await actif('bovins'), isFalse);
        expect(r.supplantees, 1);
        expect(await demandes(), isEmpty);
        expect(serveur.demandesRecues, isEmpty);
      },
    );
  });

  group('adoption initiale', () {
    test(
      'serveur de semis ≠ choix du poste : le poste propose le sien, une seule fois',
      () async {
        await (db.update(db.modulesActifs)
              ..where((m) => m.moduleId.equals('bovins')))
            .write(const ModulesActifsCompanion(isActif: Value(true)));
        serveur.ajouterModule('bovins', actif: false, decide: false);

        await moteur.synchroniser();

        expect(serveur.demandesRecues.single['donnees'], {
          'module_id': 'bovins',
          'is_actif': true,
        });
        expect(await actif('bovins'), isTrue);
        expect((await demandes()).single.syncStatus, 'synced');

        // Le serveur a désormais décidé : le tirage suivant ne reproposera rien.
        serveur.demandesRecues.clear();
        await moteur.synchroniser();
        expect(serveur.demandesRecues, isEmpty);
      },
    );

    test('serveur de semis identique au poste : rien à proposer', () async {
      serveur.ajouterModule('bovins', actif: false, decide: false);
      await moteur.synchroniser();
      expect(serveur.demandesRecues, isEmpty);
    });

    test(
      'paramètres : le web neuf (vide) apprend l\'IFU et le RCCM du poste',
      () async {
        await db
            .into(db.parametresEntreprise)
            .insertOnConflictUpdate(
              const ParametresEntrepriseCompanion(
                ifu: Value('IFU-LOCAL'),
                rccm: Value('RCCM-LOCAL'),
              ),
            );
        serveur.definirParametres({}, decide: false);

        await moteur.synchroniser();

        final d = serveur.demandesRecues.single;
        expect(d['type'], 'parametres_entreprise');
        expect((d['donnees'] as Map)['ifu'], 'IFU-LOCAL');
        expect((d['donnees'] as Map)['rccm'], 'RCCM-LOCAL');
      },
    );
  });
}
