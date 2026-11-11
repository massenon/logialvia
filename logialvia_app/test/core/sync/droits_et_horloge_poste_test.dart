import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/administration/data/sync/table_modules_actifs_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/droits_poste.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import 'faux_serveur_sync.dart';

const _a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _b = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

/// `47g_` : le poste connaît les DROITS de son compte et l'ÉCART de son horloge. Il ne propose
/// que ce qu'il peut écrire (le reste attend, jamais `conflict`), reconnaît les refus par leur
/// CODE stable, suspend l'envoi quand son horloge avance trop et reprend sans rien geler.
void main() {
  late AppDatabase db;
  late FauxServeurSync serveur;
  late PreferencesPosteRepository preferences;
  late DepotDemandesReferentiel file;
  late MoteurSynchronisationPoste moteur;

  const caissier = DroitsPoste(
    compte: 'caissier1',
    roles: ['caissier'],
    tablesEcrites: {'clients'},
    demandes: {'produit_vendable'},
  );
  const sansEcriture = DroitsPoste(
    compte: 'vide1',
    roles: [],
    tablesEcrites: {},
    demandes: {},
  );
  const admin = DroitsPoste(
    compte: 'admin1',
    roles: ['admin'],
    tablesEcrites: {'clients'},
    demandes: {'module_actif', 'produit_vendable', 'parametres_entreprise'},
  );

  setUp(() async {
    db = AppDatabase.enMemoire();
    serveur = FauxServeurSync();
    preferences = PreferencesPosteRepository(db);
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
      tables: [TableModulesActifsPoste(db), TableClientsPoste(db)],
      demandes: file,
      client: serveur.client,
    );
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

  tearDown(() async {
    horlogePoste = DateTime.now;
    await db.close();
  });

  Future<void> client(String id, String nom, {String? maj}) => db
      .into(db.clients)
      .insert(
        ClientsCompanion.insert(
          id: Value(id),
          nom: nom,
          updatedAt: Value(maj ?? instantSaisie()),
        ),
      );

  Future<ClientRow> ligne(String id) =>
      (db.select(db.clients)..where((c) => c.id.equals(id))).getSingle();

  Future<List<DemandeReferentielRow>> demandes() =>
      db.select(db.demandesReferentiel).get();

  // ------------------------------------------------------------------ Droits

  group('droits du compte', () {
    test(
      'un compte sans droit sur un type ne le propose pas : en attente, jamais en conflit',
      () async {
        serveur.droits = caissier;
        await file.proposerModule('ovins', actif: true);

        final r = await moteur.synchroniser();

        expect(r.reussie, isTrue);
        expect(serveur.demandesRecues, isEmpty, reason: 'rien n\'est proposé');
        expect(serveur.journal, isNot(contains('POST /api/sync/demandes')));
        final d = (await demandes()).single;
        expect(d.syncStatus, 'pending', reason: 'jamais conflict');
        expect(d.syncMotif, isNull);
        expect(r.enAttenteDeDroit, 1);
        expect(r.demandesRefusees, 0);
        expect(r.message, contains('1 en attente de droit'));
      },
    );

    test(
      'une table que le compte ne peut pas écrire n\'est pas poussée',
      () async {
        serveur.droits = sansEcriture;
        await client(_a, 'Aïcha');

        final r = await moteur.synchroniser();

        expect(serveur.journal, isNot(contains('POST /api/sync/push')));
        expect((await ligne(_a)).syncStatus, 'pending');
        expect(r.enAttenteDeDroit, 1);
        expect(r.refusees, 0);
        expect(
          await moteur.aDesSaisiesAEnvoyer(),
          isFalse,
          reason: 'rien d\'envoyable : le planificateur ne relance pas',
        );
      },
    );

    test('ce que le compte peut écrire part, le reste attend', () async {
      serveur.droits = caissier;
      await client(_a, 'Aïcha');
      await file.proposerModule('ovins', actif: true);

      final r = await moteur.synchroniser();

      expect(r.acceptees, 1);
      expect(serveur.clients.keys, [_a]);
      expect(r.enAttenteDeDroit, 1);
      expect((await demandes()).single.syncStatus, 'pending');
    });

    test(
      'changement de compte : les demandes en attente de droit partent',
      () async {
        serveur.droits = caissier;
        await file.proposerModule('ovins', actif: true);
        await moteur.synchroniser();
        expect(serveur.demandesRecues, isEmpty);

        // Une session avec le bon droit (autre compte, droit accordé au serveur) synchronise.
        serveur.droits = admin;
        final r = await moteur.synchroniser();

        expect(serveur.demandesRecues, hasLength(1));
        expect((await demandes()).single.syncStatus, 'synced');
        expect(r.enAttenteDeDroit, 0);
        expect(r.demandesAcceptees, 1);
        expect((await preferences.droitsSync())!.compte, 'admin1');
      },
    );

    test(
      'un refus `droit_insuffisant` n\'est jamais définitif (droits périmés)',
      () async {
        // Le poste croit encore pouvoir tout écrire ; le serveur applique d'autres droits.
        await preferences.definirDroitsSync(admin);
        serveur
          ..droits = sansEcriture
          ..annoncerDroits = false;
        await client(_a, 'Aïcha');
        await file.proposerModule('ovins', actif: true);

        final r = await moteur.synchroniser();

        expect(r.refuseesPourDroit, 2, reason: 'une ligne et une demande');
        expect(r.refusees, 0);
        expect(r.demandesRefusees, 0);
        final c = await ligne(_a);
        expect(c.syncStatus, 'pending', reason: 'jamais conflict');
        expect(c.syncMotif, isNull);
        final d = (await demandes()).single;
        expect(d.syncStatus, 'pending');
        expect(d.syncMotif, isNull);
        expect(r.enAttenteDeDroit, 2);

        // Le droit est accordé : tout repart tout seul.
        serveur.droits = admin;
        final suite = await moteur.synchroniser();
        expect(suite.refuseesPourDroit, 0);
        expect((await ligne(_a)).syncStatus, 'synced');
        expect((await demandes()).single.syncStatus, 'synced');
      },
    );

    test('un refus ordinaire (sans code) reste, lui, un conflit', () async {
      serveur.refuserDemandes = 'Données invalides.';
      await file.proposerModule('ovins', actif: true);

      await moteur.synchroniser();

      final d = (await demandes()).single;
      expect(d.syncStatus, 'conflict');
      expect(d.syncMotif, 'Données invalides.');
    });

    test(
      'état de droits : compte, droits effectifs, nombre en attente',
      () async {
        serveur.droits = caissier;
        await file.proposerModule('ovins', actif: true);
        await moteur.synchroniser();

        final etat = await moteur.etatDroits();

        expect(etat.droits!.compte, 'caissier1');
        expect(etat.droits!.roles, ['caissier']);
        expect(etat.droits!.peutEcrireTable('clients'), isTrue);
        expect(etat.droits!.peutProposer('module_actif'), isFalse);
        expect(etat.enAttenteDeDroit, 1);
      },
    );

    test('droits inconnus (ancien serveur) : le poste propose tout', () async {
      await file.proposerModule('ovins', actif: true);

      final r = await moteur.synchroniser();

      expect(serveur.demandesRecues, hasLength(1));
      expect(r.enAttenteDeDroit, 0);
      expect(await preferences.droitsSync(), isNull);
    });

    test(
      'un tirage sans changement de droit ne perd pas les droits connus',
      () async {
        serveur.droits = admin;
        await moteur.synchroniser();
        serveur.annoncerDroits = false;
        await moteur.synchroniser();

        expect((await preferences.droitsSync())!.compte, 'admin1');
      },
    );
  });

  // ------------------------------------------------------ Appairage : droits

  group('droits mémorisés avec l\'appairage', () {
    http.Client faux(Map<String, Object?> droits) => MockClient((r) async {
      return http.Response(
        jsonEncode({
          'token': '1|jeton',
          'poste': {'id': 'p', 'code': 'P1'},
          'must_change_password': false,
          'droits': droits,
          'server_now': DateTime.now().toUtc().toIso8601String(),
        }),
        200,
      );
    });

    test(
      'la connexion mémorise les droits, un autre compte les remplace',
      () async {
        final autre = AppDatabase.enMemoire();
        addTearDown(autre.close);
        final prefs = PreferencesPosteRepository(autre);
        Future<void> connecter(Map<String, Object?> droits, String compte) =>
            ServiceAppairage(
              preferences: prefs,
              depot: DepotJetonSyncMemoire(),
              client: faux(droits),
            ).connecter(
              adresse: 'http://serveur.test',
              identifiant: compte,
              motDePasse: 'x',
            );

        await connecter(caissier.versJson(), 'caissier1');
        expect((await prefs.droitsSync())!.compte, 'caissier1');
        expect((await prefs.droitsSync())!.tablesEcrites, {'clients'});
        expect((await prefs.decalageHorloge())!.inSeconds.abs(), lessThan(5));

        await connecter(admin.versJson(), 'admin1');
        final d = (await prefs.droitsSync())!;
        expect(d.compte, 'admin1');
        expect(d.demandes, contains('module_actif'));
      },
    );

    test('rien de secret n\'est mémorisé avec les droits', () async {
      await preferences.definirDroitsSync(caissier);
      final brut = await (db.select(
        db.preferencesPoste,
      )..where((p) => p.cle.equals('sync.droits'))).getSingle();
      expect(brut.valeur, isNot(contains('password')));
      expect(brut.valeur, isNot(contains('token')));
    });

    test('se déconnecter oublie les droits', () async {
      await preferences.definirDroitsSync(caissier);
      await preferences.oublierAppairage();
      expect(await preferences.droitsSync(), isNull);
    });
  });

  // ----------------------------------------------------------------- Horloge

  group('analyse de l\'écart', () {
    test('seuils : 2 min d\'avertissement, 5 min de tolérance exacte', () {
      EtatHorloge e(Duration d) => analyserHorloge(d).etat;
      expect(e(Duration.zero), EtatHorloge.juste);
      expect(e(const Duration(minutes: 2)), EtatHorloge.juste);
      expect(
        e(const Duration(minutes: 2, seconds: 1)),
        EtatHorloge.avanceAvertissement,
      );
      expect(
        e(const Duration(minutes: 5)),
        EtatHorloge.avanceAvertissement,
        reason: 'la tolérance exacte est acceptée par le serveur',
      );
      expect(
        e(const Duration(minutes: 5, seconds: 1)),
        EtatHorloge.avanceBloquante,
      );
      expect(e(const Duration(hours: 1)), EtatHorloge.avanceBloquante);
      expect(e(const Duration(days: 730)), EtatHorloge.avanceBloquante);
      expect(e(const Duration(minutes: -5)), EtatHorloge.juste);
      expect(e(const Duration(minutes: -5, seconds: -1)), EtatHorloge.retard);
      expect(e(const Duration(hours: -1)), EtatHorloge.retard);
    });

    test('seule l\'avance au-delà de la tolérance suspend l\'envoi', () {
      expect(analyserHorloge(const Duration(minutes: 5)).suspendEnvoi, isFalse);
      expect(analyserHorloge(const Duration(minutes: 6)).suspendEnvoi, isTrue);
      expect(analyserHorloge(const Duration(hours: -3)).suspendEnvoi, isFalse);
    });

    test('la durée se dit en clair, comme le serveur', () {
      expect(formaterDuree(const Duration(days: 800)), '2 ans');
      expect(formaterDuree(const Duration(days: 365)), '1 an');
      expect(formaterDuree(const Duration(days: 2)), '2 jours');
      expect(formaterDuree(const Duration(hours: 1)), '1 h');
      expect(formaterDuree(const Duration(minutes: 65)), '1 h 05');
      expect(formaterDuree(const Duration(minutes: 7)), '7 min');
      expect(formaterDuree(const Duration(seconds: 42)), '42 s');
    });

    test('le message explicite l\'avance et la conduite à tenir', () {
      final m = analyserHorloge(const Duration(days: 2)).message!;
      expect(m, contains('avance de 2 jours'));
      expect(m, contains('corrigez la date et l\'heure du poste'));
      expect(m, contains('suspendu'));
      expect(analyserHorloge(Duration.zero).message, isNull);
      expect(
        analyserHorloge(const Duration(hours: -1)).message,
        contains('retarde de 1 h'),
      );
    });

    test('la mesure tient compte du milieu de l\'échange', () {
      final t = DateTime.utc(2026, 11, 9, 12);
      final ecart = mesurerDecalage(
        avant: t,
        apres: t.add(const Duration(seconds: 2)),
        serveur: t.add(const Duration(seconds: 1)),
      );
      expect(ecart, Duration.zero);
    });
  });

  group('horloge du poste', () {
    for (final cas in <(String, Duration, String)>[
      ('+1 h', const Duration(hours: 1), 'avance de 1 h'),
      ('+2 jours', const Duration(days: 2), 'avance de 2 jours'),
      ('+2 ans', const Duration(days: 730), 'avance de 2 ans'),
    ]) {
      test(
        'poste ${cas.$1} : saisies conservées, envoi suspendu, message clair',
        () async {
          horlogePoste = () => DateTime.now().add(cas.$2);
          await client(_a, 'Aïcha');
          await file.proposerModule('ovins', actif: true);

          final r = await moteur.synchroniser();

          expect(r.envoiSuspendu, isTrue);
          expect(r.horloge!.etat, EtatHorloge.avanceBloquante);
          expect(r.message, contains(cas.$3));
          expect(r.message, contains('suspendu'));
          expect(serveur.journal, contains('GET /api/sync/pull'));
          expect(serveur.journal, isNot(contains('POST /api/sync/push')));
          expect(serveur.journal, isNot(contains('POST /api/sync/demandes')));
          expect(serveur.clients, isEmpty, reason: 'aucune ligne gelée');
          expect((await ligne(_a)).syncStatus, 'pending', reason: 'rien perdu');
          expect((await demandes()).single.syncStatus, 'pending');
          expect(await moteur.aDesSaisiesAEnvoyer(), isFalse);
        },
      );
    }

    test('reprise après correction de l\'horloge : rien n\'est gelé', () async {
      // Deux jours d'avance : la saisie est datée DANS DEUX JOURS.
      horlogePoste = () => DateTime.now().add(const Duration(days: 2));
      await client(_a, 'Aïcha');
      await file.proposerModule('ovins', actif: true);
      await moteur.synchroniser();
      expect(serveur.clients, isEmpty);
      final dateeDuFutur = DateTime.parse((await ligne(_a)).updatedAt);
      expect(
        dateeDuFutur.isAfter(DateTime.now().add(const Duration(days: 1))),
        isTrue,
      );

      // La gérante corrige la date du poste.
      horlogePoste = DateTime.now;
      final r = await moteur.synchroniser();

      expect(r.envoiSuspendu, isFalse);
      expect(r.acceptees, 1);
      expect((await ligne(_a)).syncStatus, 'synced');
      // Ce que le serveur détient n'est PAS daté du futur : un autre poste peut écrire après.
      final sur = DateTime.parse(serveur.clients[_a]!['updated_at'] as String);
      expect(
        sur.isAfter(DateTime.now().add(const Duration(minutes: 5))),
        isFalse,
        reason: 'l\'instant est borné à l\'heure du serveur',
      );
      expect(
        DateTime.parse(
          serveur.demandesRecues.single['saisi_le'] as String,
        ).isAfter(DateTime.now().add(const Duration(minutes: 5))),
        isFalse,
      );
      expect((await demandes()).single.syncStatus, 'synced');

      // Un autre poste, à l'heure juste, écrit ensuite : il GAGNE (la ligne n'est pas gelée).
      serveur.ajouterClient(
        _a,
        'Version de l\'autre poste',
        updatedAt: DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 1))
            .toIso8601String(),
      );
      await moteur.synchroniser();
      expect((await ligne(_a)).nom, 'Version de l\'autre poste');
    });

    test('poste en retard de 1 h : avertissement, pas de blocage', () async {
      horlogePoste = () => DateTime.now().subtract(const Duration(hours: 1));
      await client(_a, 'Aïcha');

      final r = await moteur.synchroniser();

      expect(r.envoiSuspendu, isFalse);
      expect(r.horloge!.etat, EtatHorloge.retard);
      expect(r.acceptees, 1);
      expect(r.message, contains('retarde de 1 h'));
      expect(serveur.clients.keys, [_a]);
    });

    test(
      'avance de 3 min : avertie, mais l\'envoi n\'est pas suspendu',
      () async {
        horlogePoste = () => DateTime.now().add(const Duration(minutes: 3));
        await client(_a, 'Aïcha');

        final r = await moteur.synchroniser();

        expect(r.horloge!.etat, EtatHorloge.avanceAvertissement);
        expect(r.horlogeAAvertir, isTrue);
        expect(r.envoiSuspendu, isFalse);
        expect(r.acceptees, 1);
        expect(r.message, contains('avance de 3 min'));
      },
    );

    test('avance de 6 min : au-delà de la tolérance, suspendu', () async {
      horlogePoste = () => DateTime.now().add(const Duration(minutes: 6));
      await client(_a, 'Aïcha');

      final r = await moteur.synchroniser();

      expect(r.envoiSuspendu, isTrue);
      expect(serveur.clients, isEmpty);
    });

    test('horloge juste : aucun avertissement', () async {
      await client(_a, 'Aïcha');
      final r = await moteur.synchroniser();
      expect(r.horlogeAAvertir, isFalse);
      expect(r.horloge!.etat, EtatHorloge.juste);
      expect(r.message, isNot(contains('horloge')));
    });

    test('le décalage est recalculé à chaque synchronisation', () async {
      horlogePoste = () => DateTime.now().add(const Duration(hours: 1));
      await moteur.synchroniser();
      expect((await preferences.decalageHorloge())!.inMinutes, closeTo(60, 1));

      horlogePoste = DateTime.now;
      await moteur.synchroniser();
      expect(
        (await preferences.decalageHorloge())!.inSeconds.abs(),
        lessThan(5),
      );
    });

    test(
      'un serveur en retard sur la vraie heure est mesuré comme un poste en avance',
      () async {
        serveur.decalageServeur = const Duration(hours: -2);
        await client(_a, 'Aïcha');

        final r = await moteur.synchroniser();

        expect(r.envoiSuspendu, isTrue);
        expect(r.horloge!.ecart.inMinutes, closeTo(120, 1));
      },
    );

    test(
      'sans heure du serveur : le refus `horloge_en_avance` garde la ligne en attente',
      () async {
        serveur.annoncerHeure = false;
        horlogePoste = () => DateTime.now().add(const Duration(hours: 1));
        await client(_a, 'Aïcha');
        await file.proposerModule('ovins', actif: true);

        final r = await moteur.synchroniser();

        expect(r.decalageHorloge, isNull, reason: 'rien à mesurer');
        expect(r.refuseesHorloge, 2);
        expect(r.refusees, 0);
        final c = await ligne(_a);
        expect(c.syncStatus, 'pending', reason: 'jamais conflict');
        expect(c.syncMotif, isNull);
        expect((await demandes()).single.syncStatus, 'pending');
        expect(r.message, contains('horloge en avance'));
        expect(serveur.clients, isEmpty);

        // Horloge corrigée : la ligne datée du futur n'est plus refusée... après remesure.
        horlogePoste = DateTime.now;
        serveur.annoncerHeure = true;
        final suite = await moteur.synchroniser();
        expect(suite.acceptees, 1);
        expect((await ligne(_a)).syncStatus, 'synced');
      },
    );

    test('une horloge en retard ou juste n\'est jamais bornée', () async {
      final avant = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      await client(_a, 'Hier', maj: avant.toIso8601String());
      await moteur.synchroniser();
      expect(serveur.clients[_a]!['updated_at'], avant.toIso8601String());
    });

    test(
      'plusieurs postes dont un en avance : l\'autre n\'est pas gelé',
      () async {
        // Le poste B (horloge juste) écrit d'abord ; le poste A en avance est suspendu.
        serveur.ajouterClient(_b, 'Version B');
        horlogePoste = () => DateTime.now().add(const Duration(days: 2));
        await client(_b, 'Version A gelée');
        await moteur.synchroniser();
        expect(
          serveur.clients[_b]!['nom'],
          'Version B',
          reason: 'la saisie du poste en avance n\'a rien gagné',
        );
      },
    );
  });
}
