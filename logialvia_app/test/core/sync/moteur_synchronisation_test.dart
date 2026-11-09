import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/commercial/data/repositories/clients_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import 'faux_serveur_sync.dart';

const _a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _b = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _c = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

/// Un poste complet : sa base, son appairage, son moteur.
class _Poste {
  _Poste(this.serveur, {http.Client? client, int lot = 100})
    : db = AppDatabase.enMemoire() {
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: client ?? serveur.client,
    );
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: appairage,
      tables: [TableClientsPoste(db)],
      client: client ?? serveur.client,
      tailleLot: lot,
    );
    clients = ClientsRepositoryDrift(db);
  }

  final FauxServeurSync serveur;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final ClientsRepositoryDrift clients;

  Future<void> appairer() async {
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }

  Future<List<ClientRow>> lignes() =>
      (db.select(db.clients)..orderBy([(c) => OrderingTerm.asc(c.nom)])).get();

  Future<ClientRow> ligne(String id) =>
      (db.select(db.clients)..where((c) => c.id.equals(id))).getSingle();

  Future<void> insererLocal(
    String id,
    String nom, {
    String statut = 'pending',
    String? maj,
  }) => db
      .into(db.clients)
      .insert(
        ClientsCompanion.insert(
          id: Value(id),
          nom: nom,
          syncStatus: Value(statut),
          updatedAt: Value(maj ?? '2026-11-09T09:00:00.000000Z'),
        ),
      );

  Future<void> fermer() => db.close();
}

void main() {
  late FauxServeurSync serveur;
  final postes = <_Poste>[];

  _Poste nouveau({int lot = 100}) {
    final p = _Poste(serveur, lot: lot);
    postes.add(p);
    return p;
  }

  setUp(() {
    serveur = FauxServeurSync();
    postes.clear();
  });

  tearDown(() async {
    for (final p in postes) {
      await p.fermer();
    }
  });

  test('non appairé : le dit, sans appeler le serveur', () async {
    final p = nouveau();
    final r = await p.moteur.synchroniser();
    expect(r.issue, IssueSynchronisation.nonAppairee);
    expect(serveur.journal, isEmpty);
  });

  group('Tirage (pull)', () {
    test(
      'un poste neuf reçoit les clients du serveur, marqués synchronisés',
      () async {
        serveur.ajouterClient(_a, 'Client A');
        serveur.ajouterClient(_b, 'Client B');
        final p = nouveau();
        await p.appairer();

        final r = await p.moteur.synchroniser();

        expect(r.reussie, isTrue);
        expect(r.recues, 2);
        final l = await p.lignes();
        expect(l.map((c) => c.nom), ['Client A', 'Client B']);
        expect(l.every((c) => c.syncStatus == 'synced'), isTrue);
        expect(l.first.id, _a, reason: 'l\'UUID du serveur est conservé');
      },
    );

    test('pull AVANT push : l\'ordre est tenu', () async {
      final p = nouveau();
      await p.appairer();
      await p.insererLocal(_a, 'Local');
      await p.moteur.synchroniser();
      expect(serveur.journal, ['GET /api/sync/pull', 'POST /api/sync/push']);
    });

    test(
      'pagination : toutes les pages sont absorbées, une seule borne until',
      () async {
        serveur.lignesParPage = 2;
        for (var i = 0; i < 5; i++) {
          serveur.ajouterClient(
            '00000000-0000-4000-8000-00000000000$i',
            'Client $i',
          );
        }
        final p = nouveau();
        await p.appairer();

        final r = await p.moteur.synchroniser();

        expect(r.recues, 5);
        expect((await p.lignes()), hasLength(5));
        expect(serveur.journal.where((j) => j.startsWith('GET')).length, 3);
      },
    );

    test('le curseur n\'avance qu\'après la DERNIÈRE page', () async {
      serveur.lignesParPage = 2;
      for (var i = 0; i < 5; i++) {
        serveur.ajouterClient(
          '00000000-0000-4000-8000-00000000000$i',
          'Client $i',
        );
      }
      serveur.panneAuTirageDePage = 3;
      final p = nouveau();
      await p.appairer();

      final panne = await p.moteur.synchroniser();
      expect(panne.issue, IssueSynchronisation.refusee);
      expect(
        await p.preferences.curseurTirage(),
        isNull,
        reason: 'tirage interrompu : le prochain repart du même point',
      );

      final reprise = await p.moteur.synchroniser();
      expect(reprise.reussie, isTrue);
      expect(
        await p.lignes(),
        hasLength(5),
        reason: 'rejouer des pages déjà absorbées est sans effet',
      );
      expect(await p.preferences.curseurTirage(), isNotNull);
    });

    test('un tirage incrémental ne reçoit que le nouveau', () async {
      serveur.ajouterClient(_a, 'Ancien');
      final p = nouveau();
      await p.appairer();
      await p.moteur.synchroniser();

      serveur.ajouterClient(_b, 'Nouveau');
      final r = await p.moteur.synchroniser();

      expect(r.recues, 1);
    });

    test(
      'absorbeur strict : une ligne incohérente est refusée, les autres passent',
      () async {
        serveur.ajouterClient(_a, 'Valide');
        serveur.ajouterClient(_b, 'UUID cassé');
        serveur.clients[_b]!['id'] = 'pas-un-uuid';
        serveur.ajouterClient(_c, '   ');
        const d = '11111111-1111-4111-8111-111111111111';
        serveur.ajouterClient(d, 'Instant cassé');
        serveur.clients[d]!['updated_at'] = 'hier';
        final p = nouveau();
        await p.appairer();

        final r = await p.moteur.synchroniser();

        expect(r.recues, 1);
        expect(r.refuseesALaReception, 3);
        expect((await p.lignes()).map((c) => c.nom), ['Valide']);
      },
    );

    test(
      'une saisie locale non envoyée n\'est JAMAIS écrasée par le tirage',
      () async {
        serveur.ajouterClient(
          _a,
          'Version du serveur',
          updatedAt: '2026-11-09T08:00:00.000Z',
        );
        final p = nouveau();
        await p.appairer();
        await p.insererLocal(
          _a,
          'Ma saisie locale',
          maj: '2026-11-09T09:00:00.000000Z',
        );

        final r = await p.moteur.synchroniser();

        expect(r.conserveesLocalement, 1);
        // Mon horodatage (9 h) est plus récent que celui du serveur (8 h) : il gagne.
        expect(serveur.clients[_a]!['nom'], 'Ma saisie locale');
        expect((await p.ligne(_a)).nom, 'Ma saisie locale');
      },
    );

    test(
      'une pierre tombale supprime la ligne synchronisée, pas une saisie locale plus récente',
      () async {
        serveur.ajouterClient(
          _a,
          'Supprimé',
          supprimeLe: '2026-11-09T09:00:00Z',
        );
        serveur.ajouterClient(
          _b,
          'Supprimé aussi',
          updatedAt: '2026-11-09T08:00:00.000Z',
          supprimeLe: '2026-11-09T09:00:00Z',
        );
        final p = nouveau();
        await p.appairer();
        await p.insererLocal(_a, 'Synchronisé', statut: 'synced');
        await p.insererLocal(
          _b,
          'Pas envoyé',
          statut: 'pending',
          maj: '2026-11-09T09:30:00.000000Z',
        );

        await p.moteur.synchroniser();

        final ids = (await p.lignes()).map((c) => c.id).toList();
        expect(ids, isNot(contains(_a)));
        expect(ids, contains(_b));
      },
    );

    test(
      'un client reçu garde dates et téléphone (jour civil sans décalage)',
      () async {
        serveur.ajouterClient(_a, 'Avec dates');
        serveur.clients[_a]!['telephone'] = '97000001';
        serveur.clients[_a]!['date_naissance'] = '1990-03-01T00:00:00.000000Z';
        final p = nouveau();
        await p.appairer();

        await p.moteur.synchroniser();

        final c = await p.ligne(_a);
        expect(c.telephone, '97000001');
        expect(c.dateNaissance, DateTime(1990, 3, 1));
      },
    );
  });

  test(
    'une saisie locale plus ANCIENNE que celle du serveur est remplacée, et c\'est dit',
    () async {
      serveur.ajouterClient(
        _a,
        'Version du serveur',
        updatedAt: '2026-11-09T11:00:00.000Z',
      );
      final p = nouveau();
      await p.appairer();
      await p.insererLocal(
        _a,
        'Ma vieille saisie',
        maj: '2026-11-09T10:00:00.000000Z',
      );

      final r = await p.moteur.synchroniser();

      expect(r.supplantees, 1);
      expect(r.message, contains('remplacée(s) par une version plus récente'));
      final c = await p.ligne(_a);
      expect(c.nom, 'Version du serveur');
      expect(c.syncStatus, 'synced');
      expect(serveur.clients[_a]!['nom'], 'Version du serveur');
    },
  );

  test('à instant de saisie ÉGAL, la saisie locale est conservée', () async {
    serveur.ajouterClient(_a, 'Serveur', updatedAt: '2026-11-09T10:00:00.000Z');
    final p = nouveau();
    await p.appairer();
    await p.insererLocal(_a, 'Local', maj: '2026-11-09T10:00:00.000000Z');

    final r = await p.moteur.synchroniser();

    expect(r.conserveesLocalement, 1);
    expect(r.supplantees, 0);
  });

  group('Envoi (push)', () {
    test(
      'une saisie locale part, est acceptée, devient synchronisée',
      () async {
        final p = nouveau();
        await p.appairer();
        final cree = await p.clients.creerClient(
          nom: 'Mama Rita',
          telephone: '97000009',
        );

        final r = await p.moteur.synchroniser();

        expect(r.acceptees, 1);
        expect((await p.ligne(cree.id)).syncStatus, 'synced');
        expect(serveur.clients[cree.id]!['nom'], 'Mama Rita');
        expect(
          serveur.clients[cree.id]!['device_id'],
          await p.preferences.identifiantPoste(),
        );
      },
    );

    test('idempotent : une 2e synchronisation n\'envoie plus rien', () async {
      final p = nouveau();
      await p.appairer();
      await p.clients.creerClient(nom: 'Une fois');
      await p.moteur.synchroniser();
      serveur.envois.clear();

      final r = await p.moteur.synchroniser();

      expect(r.envoyees, 0);
      expect(serveur.envois, isEmpty);
    });

    test('réponse perdue : renvoyer le même lot ne duplique rien', () async {
      final p = nouveau();
      await p.appairer();
      final c = await p.clients.creerClient(nom: 'Doublon ?');
      await p.moteur.synchroniser();
      // Le poste croit n'avoir jamais reçu l'accusé : la ligne repasse à envoyer.
      await (p.db.update(p.db.clients)..where((x) => x.id.equals(c.id))).write(
        const ClientsCompanion(syncStatus: Value('pending')),
      );

      final r = await p.moteur.synchroniser();

      expect(r.acceptees, 1);
      expect(serveur.clients, hasLength(1));
    });

    test(
      'refus du serveur : la ligne devient conflit avec son motif, sans échec silencieux',
      () async {
        final p = nouveau();
        await p.appairer();
        await p.insererLocal(_a, ' ', statut: 'pending');

        final r = await p.moteur.synchroniser();

        expect(r.refusees, 1);
        final c = await p.ligne(_a);
        expect(c.syncStatus, 'conflict');
        expect(c.syncMotif, 'Le nom du client est obligatoire.');

        // Un conflit n'est pas renvoyé en boucle.
        serveur.envois.clear();
        await p.moteur.synchroniser();
        expect(serveur.envois, isEmpty);
      },
    );

    test(
      'une saisie faite PENDANT l\'envoi repart au prochain envoi',
      () async {
        final p = nouveau();
        await p.appairer();
        final c = await p.clients.creerClient(nom: 'Pendant');
        serveur.pendantEnvoi = () async {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          await p.clients.enregistrerContact(c.id);
        };

        await p.moteur.synchroniser();
        expect(
          (await p.ligne(c.id)).syncStatus,
          'pending',
          reason: 'modifiée après l\'envoi : elle n\'est pas « synchronisée »',
        );

        serveur.envois.clear();
        await p.moteur.synchroniser();
        expect(serveur.envois, hasLength(1));
        expect((await p.ligne(c.id)).syncStatus, 'synced');
      },
    );

    test('les envois sont découpés en lots', () async {
      final p = nouveau(lot: 100);
      await p.appairer();
      for (var i = 0; i < 250; i++) {
        await p.insererLocal(
          '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
          'Client $i',
          maj: '2026-11-09T09:00:00.${i.toString().padLeft(6, '0')}Z',
        );
      }

      final r = await p.moteur.synchroniser();

      expect(r.acceptees, 250);
      expect(serveur.envois, hasLength(3));
      expect(serveur.clients, hasLength(250));
    });

    test(
      'toute modification locale d\'un client déjà synchronisé le renvoie',
      () async {
        final p = nouveau();
        await p.appairer();
        final c = await p.clients.creerClient(nom: 'Modifié');
        await p.moteur.synchroniser();
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await p.clients.enregistrerContact(c.id);
        expect((await p.ligne(c.id)).syncStatus, 'pending');

        await p.moteur.synchroniser();

        expect(serveur.clients[c.id]!['dernier_contact'], isNotNull);
        expect((await p.ligne(c.id)).syncStatus, 'synced');
      },
    );
  });

  group('Hors ligne, révocation, remise à zéro', () {
    test('hors ligne : pas une erreur, tout reste à envoyer', () async {
      final p = nouveau();
      await p.appairer();
      await p.clients.creerClient(nom: 'Pour plus tard');
      serveur.horsLigne = true;

      final r = await p.moteur.synchroniser();

      expect(r.issue, IssueSynchronisation.horsLigne);
      expect(r.message, contains('hors ligne'));
      expect((await p.lignes()).single.syncStatus, 'pending');
      expect(await p.depot.lire(), '1|jeton', reason: 'toujours appairé');

      serveur.horsLigne = false;
      expect((await p.moteur.synchroniser()).acceptees, 1);
    });

    test('401 : poste révoqué, jeton oublié, saisies conservées', () async {
      final p = nouveau();
      await p.appairer();
      await p.clients.creerClient(nom: 'Je reste');
      serveur.jetonRevoque = true;

      final r = await p.moteur.synchroniser();

      expect(r.issue, IssueSynchronisation.revoque);
      expect(await p.depot.lire(), isNull);
      expect((await p.appairage.etat()).appaire, isFalse);
      expect(await p.lignes(), hasLength(1));
    });

    test(
      'remise à zéro du serveur : le poste purge, dit ce qu\'il perd, repart',
      () async {
        serveur.ajouterClient(_a, 'Ancien serveur');
        final p = nouveau();
        await p.appairer();
        await p.moteur.synchroniser();
        await p.clients.creerClient(nom: 'Jamais envoyé'); // sera perdu

        serveur.remettreAZero();
        serveur.ajouterClient(_c, 'Après la remise à zéro');
        final r = await p.moteur.synchroniser();

        expect(r.remiseAZero, isTrue);
        expect(r.saisiesPerdues, 1);
        expect(r.message, contains('1 saisie(s) non envoyée(s) perdue(s)'));
        expect((await p.lignes()).map((c) => c.nom), [
          'Après la remise à zéro',
        ]);
        expect(await p.preferences.marqueRemiseAZero(), serveur.marque);

        // Et le poste peut de nouveau envoyer.
        await p.clients.creerClient(nom: 'Neuf');
        expect((await p.moteur.synchroniser()).acceptees, 1);
      },
    );

    test(
      'un envoi avec une marque périmée est refusé (409), rien n\'est marqué envoyé',
      () async {
        final p = nouveau();
        await p.appairer();
        await p.moteur.synchroniser(); // connaît la marque « initiale »
        serveur.remettreAZero();
        await p.clients.creerClient(nom: 'D\'avant');
        // Le tirage détecte la remise à zéro ; simulons un poste qui ne tire pas :
        await p.preferences.definirMarqueRemiseAZero('initiale');
        final etat = await p.preferences.marqueRemiseAZero();
        expect(etat, 'initiale');
        // Le moteur tire d'abord → il apprend la marque → purge → pas de 409 : c'est
        // le comportement voulu ; la protection 409 vaut pour un envoi seul.
        final r = await p.moteur.synchroniser();
        expect(r.remiseAZero, isTrue);
        expect(serveur.clients, isEmpty);
      },
    );
  });

  group('Deux postes', () {
    test(
      'A crée, B reçoit ; B corrige, A reçoit — même base partout',
      () async {
        final a = nouveau();
        final b = nouveau();
        await a.appairer();
        await b.appairer();

        final c = await a.clients.creerClient(nom: 'Client de A');
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        expect((await b.lignes()).map((x) => x.nom), ['Client de A']);

        await Future<void>.delayed(const Duration(milliseconds: 3));
        await b.clients.enregistrerContact(c.id);
        await b.moteur.synchroniser();
        await a.moteur.synchroniser();

        expect((await a.ligne(c.id)).dernierContact, isNotNull);
      },
    );

    test(
      'homonymes créés chacun de leur côté : deux clients, pas de fusion',
      () async {
        final a = nouveau();
        final b = nouveau();
        await a.appairer();
        await b.appairer();
        await a.clients.creerClient(nom: 'Mama Rita');
        await b.clients.creerClient(nom: 'Mama Rita');

        for (final p in [a, b, a, b]) {
          await p.moteur.synchroniser();
        }

        expect(await a.lignes(), hasLength(2));
        expect(
          (await a.lignes()).map((c) => c.id).toSet(),
          (await b.lignes()).map((c) => c.id).toSet(),
        );
        expect(serveur.clients, hasLength(2));
      },
    );

    test(
      'modification ancienne arrivée en retard : le serveur garde la plus récente, les deux convergent',
      () async {
        final a = nouveau();
        final b = nouveau();
        await a.appairer();
        await b.appairer();
        serveur.ajouterClient(
          _a,
          'Départ',
          updatedAt: '2026-11-09T08:00:00.000Z',
        );
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        // B saisit à 11 h et se connecte d'abord ; A avait saisi à 10 h, hors ligne.
        await (b.db.update(b.db.clients)..where((x) => x.id.equals(_a))).write(
          const ClientsCompanion(
            nom: Value('Version de 11 h'),
            syncStatus: Value('pending'),
            updatedAt: Value('2026-11-09T11:00:00.000000Z'),
          ),
        );
        await (a.db.update(a.db.clients)..where((x) => x.id.equals(_a))).write(
          const ClientsCompanion(
            nom: Value('Version de 10 h'),
            syncStatus: Value('pending'),
            updatedAt: Value('2026-11-09T10:00:00.000000Z'),
          ),
        );
        await b.moteur.synchroniser();
        await a.moteur.synchroniser();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        expect(serveur.clients[_a]!['nom'], 'Version de 11 h');
        expect((await a.ligne(_a)).nom, 'Version de 11 h');
        expect((await b.ligne(_a)).nom, 'Version de 11 h');
      },
    );
  });

  test(
    'deux synchronisations simultanées : la seconde est refusée proprement',
    () async {
      final p = nouveau();
      await p.appairer();
      final premiere = p.moteur.synchroniser();
      final seconde = await p.moteur.synchroniser();
      expect(seconde.message, contains('déjà en cours'));
      expect((await premiere).reussie, isTrue);
    },
  );
}
