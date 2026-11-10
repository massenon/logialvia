import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

/// ESSAI DU RÉSEAU RÉEL (`47r_`) : le vrai serveur Laravel derrière le mandataire
/// `outils/mandataire_reseau.py`, qui reproduit les pièges d'un hébergement mutualisé.
///
/// Désactivé par défaut. Lancement complet (serveur, mandataires TLS, comptes) :
///
/// ```bash
/// ESSAI_RESEAU=1 bash logialvia_app/outils/essai_vrai_serveur.sh
/// ```
///
/// Variables : `LOGIALVIA_MANDATAIRE` (http, port de données, ex. `127.0.0.1:8780`),
/// `LOGIALVIA_MANDATAIRE_CTL` (port de commande), `LOGIALVIA_CERTS` (dossier des certificats),
/// `LOGIALVIA_TLS` (`autosigne=8782,expire=8783,mauvais_nom=8784,valide=8785`),
/// `LOGIALVIA_SERVEUR_PETIT` (même serveur avec `post_max_size=3K` : vrai 413 de PHP),
/// `LOGIALVIA_MDP`, `LOGIALVIA_COMPTE_DEBUT`.
///
/// La vérification TLS du poste n'est JAMAIS désactivée : le test fournit au contraire une
/// autorité maison à un client de test (comme le ferait l'installation de l'autorité dans
/// Windows) et prouve que tout autre certificat est refusé.
void main() {
  final env = Platform.environment;
  final mandataire = env['LOGIALVIA_MANDATAIRE'];
  final ctl = env['LOGIALVIA_MANDATAIRE_CTL'];
  final certs = env['LOGIALVIA_CERTS'];
  final mdp = env['LOGIALVIA_MDP'] ?? '';
  final petit = env['LOGIALVIA_SERVEUR_PETIT'];
  final tls = {
    for (final p
        in (env['LOGIALVIA_TLS'] ?? '')
            .split(',')
            .where((e) => e.contains('=')))
      p.split('=')[0]: int.parse(p.split('=')[1]),
  };
  final Object saute = mandataire == null || ctl == null
      ? 'LOGIALVIA_MANDATAIRE non défini : essai du réseau réel ignoré.'
      : false;
  var compte = int.tryParse(env['LOGIALVIA_COMPTE_DEBUT'] ?? '') ?? 100;
  final unique = DateTime.now().microsecondsSinceEpoch.toString();
  var serie = 0;

  const repetitions = [
    Duration(milliseconds: 100),
    Duration(milliseconds: 300),
  ];

  Future<void> regles(List<Map<String, Object?>> liste) async {
    final r = await http.put(
      Uri.parse('http://127.0.0.1:$ctl/regles'),
      body: jsonEncode(liste),
    );
    expect(r.statusCode, 200);
  }

  Future<List<Map<String, dynamic>>> journal() async {
    final r = await http.get(Uri.parse('http://127.0.0.1:$ctl/journal'));
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  /// Client HTTP qui fait confiance à l'autorité maison (et à elle seule).
  http.Client clientAutoriteMaison() {
    final ctx = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('$certs/ca.pem');
    return IOClient(HttpClient(context: ctx));
  }

  final postes = <_Poste>[];
  tearDown(() async {
    try {
      await regles([]);
    } on Exception {
      // mandataire absent (essai ciblé sur un serveur Apache réel) : rien à remettre à zéro
    }
    for (final p in postes) {
      await p.db.close();
    }
    postes.clear();
  });

  Future<_Poste> poste(
    String adresse, {
    http.Client? client,
    Duration delai = const Duration(seconds: 20),
    int lot = 100,
  }) async {
    final db = AppDatabase.enMemoire();
    final preferences = PreferencesPosteRepository(db);
    final depot = DepotJetonSyncMemoire();
    final appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: client,
      delaisRepetition: repetitions,
    );
    final p = _Poste(
      db,
      preferences,
      depot,
      appairage,
      MoteurSynchronisationPoste(
        preferences: preferences,
        depot: depot,
        appairage: appairage,
        tables: [TableClientsPoste(db)],
        client: client,
        delai: delai,
        tailleLot: lot,
        delaisRepetition: repetitions,
      ),
    );
    postes.add(p);
    final r = await appairage.connecter(
      adresse: adresse,
      identifiant: 'admin${++compte}',
      motDePasse: mdp,
    );
    expect(r.reussi, isTrue, reason: r.message);
    return p;
  }

  String nom(String essai, int n) => 'Réseau $essai $unique ${++serie} #$n';

  Future<void> saisir(_Poste p, String essai, int n, {int taille = 0}) => p.db
      .into(p.db.clients)
      .insert(
        ClientsCompanion.insert(
          id: Value(nouvelUuid()),
          nom: '${nom(essai, n)}${'x' * taille}',
          syncStatus: const Value('pending'),
          updatedAt: Value(
            DateTime.now().toUtc().toIso8601String().replaceFirst('Z', '000Z'),
          ),
        ),
      );

  /// Ce que le SERVEUR tient, vu par un poste neuf (tirage complet) : les clients de l'essai.
  Future<List<String>> chezLeServeur(String adresse, String essai) async {
    final autre = await poste(adresse);
    final r = await autre.moteur.synchroniser();
    expect(r.reussie, isTrue, reason: r.message);
    final lignes = await autre.db.select(autre.db.clients).get();
    return [
      for (final l in lignes)
        if (l.nom.startsWith('Réseau $essai $unique')) l.nom,
    ];
  }

  final http_ = 'http://127.0.0.1:${mandataire?.split(':').last}';

  group('TLS : le poste refuse un certificat invalide, avec un message clair', () {
    // Un certificat d'une autorité INCONNUE est refusé avant tout autre contrôle (c'est le
    // bon ordre) : expiré et mauvais nom se prouvent donc avec l'autorité maison installée.
    for (final cas in [
      ('autosigne', 'pas reconnu', false),
      ('expire', 'expiré', true),
      ('mauvais_nom', 'ne correspond pas', true),
    ]) {
      test(
        'certificat ${cas.$1} : appairage refusé (« ${cas.$2} »), jamais d\'exception, jamais de jeton',
        () async {
          final port = tls[cas.$1];
          if (port == null) markTestSkipped('port TLS ${cas.$1} absent');
          final db = AppDatabase.enMemoire();
          final preferences = PreferencesPosteRepository(db);
          final depot = DepotJetonSyncMemoire();
          final appairage = ServiceAppairage(
            preferences: preferences,
            depot: depot,
            client: cas.$3 ? clientAutoriteMaison() : null,
          );
          final r = await appairage.connecter(
            adresse: 'https://127.0.0.1:$port',
            identifiant: 'admin${++compte}',
            motDePasse: mdp,
          );
          await db.close();
          expect(r.reussi, isFalse);
          expect(r.issue, IssueAppairage.refuse);
          expect(r.message, contains(cas.$2), reason: r.message);
          expect(r.message, contains('jamais désactivée'));
          expect(r.message, isNot(contains('Exception')));
          expect(await depot.lire(), isNull);
        },
        skip: saute == false ? false : saute,
      );
    }

    test(
      'autorité maison : refusée par défaut, acceptée dès qu\'elle est installée ; la synchro passe en TLS',
      () async {
        final port = tls['valide']!;
        final adresse = 'https://127.0.0.1:$port';

        // 1. Sans l'autorité (client par défaut) : refus.
        final db = AppDatabase.enMemoire();
        final refus =
            await ServiceAppairage(
              preferences: PreferencesPosteRepository(db),
              depot: DepotJetonSyncMemoire(),
            ).connecter(
              adresse: adresse,
              identifiant: 'admin${++compte}',
              motDePasse: mdp,
            );
        await db.close();
        expect(refus.reussi, isFalse);
        expect(refus.message, contains('pas reconnu'));

        // 2. Avec l'autorité (installée dans Windows) : ça passe, de bout en bout.
        final p = await poste(adresse, client: clientAutoriteMaison());
        await saisir(p, 'tls', 1);
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(r.acceptees, 1);
      },
      skip: saute == false ? false : saute,
    );
  });

  group('413 : le poste découpe ses envois, sans perte ni doublon', () {
    test(
      'LimitRequestBody du mandataire (3 000 octets) : dichotomie, 60 clients, chacun une fois',
      () async {
        await regles([
          {
            'action': 'limite_corps',
            'octets': 3000,
            'fois': -1,
            'chemin': '/api/sync/push',
          },
        ]);
        final p = await poste(http_);
        for (var i = 1; i <= 60; i++) {
          await saisir(p, 'p413', i);
        }
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(r.acceptees, 60);
        final vus = await journal();
        expect(
          vus.where((v) => v['statut'] == 413),
          isNotEmpty,
          reason: 'le mandataire a bien refusé le premier envoi',
        );
        await regles([]);
        final serveur = await chezLeServeur(http_, 'p413');
        expect(serveur, hasLength(60));
        expect(serveur.toSet(), hasLength(60));
      },
      skip: saute == false ? false : saute,
    );

    test(
      'VRAI post_max_size de PHP (3 Ko) : 413 réel du serveur, même découpage',
      () async {
        final p = await poste(petit!);
        for (var i = 1; i <= 40; i++) {
          await saisir(p, 'ppost', i);
        }
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(r.acceptees, 40);
        final serveur = await chezLeServeur(petit, 'ppost');
        expect(serveur, hasLength(40));
        expect(serveur.toSet(), hasLength(40));
      },
      skip: saute != false
          ? saute
          : (petit == null ? 'LOGIALVIA_SERVEUR_PETIT absent' : false),
    );
  });

  group('coupures en plein lot : rejeu idempotent', () {
    test(
      'requête traitée, connexion fermée avant la réponse : rejeu, aucun doublon, curseur correct',
      () async {
        final p = await poste(http_);
        for (var i = 1; i <= 8; i++) {
          await saisir(p, 'pcoupe', i);
        }
        await regles([
          {
            'action': 'coupe_avant_reponse',
            'chemin': '/api/sync/push',
            'fois': 1,
          },
        ]);
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(r.acceptees, 8);
        final pushes = (await journal())
            .where((v) => v['chemin'] == '/api/sync/push')
            .toList();
        expect(pushes, hasLength(2), reason: 'envoi puis rejeu');
        expect(pushes.first['serveur_a_traite'], isTrue);
        expect(await p.preferences.curseurTirage(), isNotNull);
        await regles([]);
        final serveur = await chezLeServeur(http_, 'pcoupe');
        expect(serveur, hasLength(8));
        expect(serveur.toSet(), hasLength(8));
      },
      skip: saute == false ? false : saute,
    );

    test(
      'coupure PENDANT l\'envoi du corps (500 octets) : rien n\'est perdu, le réseau revient au milieu du cycle',
      () async {
        final p = await poste(http_);
        for (var i = 1; i <= 6; i++) {
          await saisir(p, 'pmilieu', i);
        }
        await regles([
          {
            'action': 'coupe_requete',
            'octets': 500,
            'chemin': '/api/sync/push',
            'fois': 2,
          },
        ]);
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(r.acceptees, 6);
        await regles([]);
        final serveur = await chezLeServeur(http_, 'pmilieu');
        expect(serveur, hasLength(6));
      },
      skip: saute == false ? false : saute,
    );

    test(
      'coupure persistante : hors ligne, rien de marqué envoyé ; le réseau revient, tout passe une fois',
      () async {
        final p = await poste(http_);
        for (var i = 1; i <= 5; i++) {
          await saisir(p, 'ppersiste', i);
        }
        await regles([
          {
            'action': 'coupe_avant_reponse',
            'chemin': '/api/sync/push',
            'fois': -1,
          },
        ]);
        final r1 = await p.moteur.synchroniser();
        expect(r1.issue, IssueSynchronisation.horsLigne);
        expect(r1.message, contains('coupée'));
        final locales = await p.db.select(p.db.clients).get();
        expect(
          locales.where(
            (l) =>
                l.nom.startsWith('Réseau ppersiste $unique') &&
                l.syncStatus == 'synced',
          ),
          isEmpty,
        );

        await regles([]);
        final r2 = await p.moteur.synchroniser();
        expect(r2.issue, IssueSynchronisation.terminee, reason: r2.message);
        final serveur = await chezLeServeur(http_, 'ppersiste');
        expect(serveur, hasLength(5));
        expect(
          serveur.toSet(),
          hasLength(5),
          reason: 'le serveur a traité plusieurs fois, sans doublon',
        );
      },
      skip: saute == false ? false : saute,
    );

    test(
      'réponse du tirage tronquée en route : curseur intact, rien de perdu au cycle suivant',
      () async {
        final auteur = await poste(http_);
        for (var i = 1; i <= 5; i++) {
          await saisir(auteur, 'ptronque', i);
        }
        expect((await auteur.moteur.synchroniser()).reussie, isTrue);

        final lecteur = await poste(http_);
        await regles([
          {
            'action': 'coupe_reponse',
            'octets': 120,
            'chemin': '/api/sync/pull',
            'fois': -1,
          },
        ]);
        final r1 = await lecteur.moteur.synchroniser();
        expect(r1.issue, IssueSynchronisation.horsLigne);
        expect(await lecteur.preferences.curseurTirage(), isNull);

        await regles([]);
        final r2 = await lecteur.moteur.synchroniser();
        expect(r2.issue, IssueSynchronisation.terminee, reason: r2.message);
        final recus = await lecteur.db.select(lecteur.db.clients).get();
        expect(
          recus.where((l) => l.nom.startsWith('Réseau ptronque $unique')),
          hasLength(5),
        );
        expect(await lecteur.preferences.curseurTirage(), isNotNull);
      },
      skip: saute == false ? false : saute,
    );
  });

  group('lenteur', () {
    test(
      'réponse en 2 s avec un délai de 700 ms : message de délai ; le serveur a traité, aucun doublon au cycle suivant',
      () async {
        final p = await poste(http_, delai: const Duration(milliseconds: 700));
        for (var i = 1; i <= 3; i++) {
          await saisir(p, 'plent', i);
        }
        await regles([
          {
            'action': 'retard_reponse',
            'ms': 2000,
            'chemin': '/api/sync/push',
            'fois': 1,
          },
        ]);
        final r1 = await p.moteur.synchroniser();
        expect(r1.issue, IssueSynchronisation.horsLigne);
        expect(r1.message, contains('trop de temps'));

        await regles([]);
        final r2 = await p.moteur.synchroniser();
        expect(r2.issue, IssueSynchronisation.terminee, reason: r2.message);
        final serveur = await chezLeServeur(http_, 'plent');
        expect(serveur, hasLength(3));
        expect(serveur.toSet(), hasLength(3));
      },
      skip: saute == false ? false : saute,
    );
  });

  group('502 / 503 / 504 / 429, page HTML, redirection, Authorization', () {
    for (final statut in [502, 503, 504]) {
      test(
        '$statut passager (page d\'hébergeur) : rejeu automatique, tout passe',
        () async {
          final p = await poste(http_);
          await saisir(p, 'p$statut', 1);
          await regles([
            {
              'action': 'statut',
              'statut': statut,
              'corps': '<html>Bad Gateway</html>',
              'chemin': '/api/sync/push',
              'fois': 2,
            },
          ]);
          final r = await p.moteur.synchroniser();
          expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
          expect(r.acceptees, 1);
        },
        skip: saute == false ? false : saute,
      );
    }

    test(
      '503 persistant avec Retry-After : hors ligne, message clair, reprise ensuite',
      () async {
        final p = await poste(http_);
        await saisir(p, 'p503p', 1);
        await regles([
          {
            'action': 'statut',
            'statut': 503,
            'corps': '<html>Maintenance</html>',
            'entetes': {'Retry-After': '1'},
            'fois': -1,
            'chemin': '/api/sync/push',
          },
        ]);
        final r1 = await p.moteur.synchroniser();
        expect(r1.issue, IssueSynchronisation.horsLigne);
        expect(r1.message, contains('momentanément indisponible'));
        await regles([]);
        expect((await p.moteur.synchroniser()).reussie, isTrue);
      },
      skip: saute == false ? false : saute,
    );

    test(
      '429 + Retry-After 120 : message du serveur, pas d\'attente de deux minutes',
      () async {
        final p = await poste(http_);
        await regles([
          {
            'action': 'statut',
            'statut': 429,
            'type': 'application/json',
            'corps': {
              'message': 'Trop de tentatives. Réessayez dans 120 secondes.',
            },
            'entetes': {'Retry-After': '120'},
            'fois': -1,
            'chemin': '/api/sync/pull',
          },
        ]);
        final chrono = Stopwatch()..start();
        final r = await p.moteur.synchroniser();
        expect(chrono.elapsed, lessThan(const Duration(seconds: 5)));
        expect(r.issue, IssueSynchronisation.horsLigne);
        expect(r.message, contains('Trop de tentatives'));
      },
      skip: saute == false ? false : saute,
    );

    test(
      'page HTML d\'hébergeur au lieu de JSON (200) : refus clair, aucune ligne marquée envoyée',
      () async {
        final p = await poste(http_);
        await saisir(p, 'phtml', 1);
        await regles([
          {'action': 'html', 'fois': -1},
        ]);
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.refusee);
        expect(r.message, contains('page web'));
        expect(await p.depot.lire(), isNotNull, reason: 'le jeton est gardé');
        final l = await p.db.select(p.db.clients).get();
        expect(l.single.syncStatus, 'pending');
        await regles([]);
        expect((await p.moteur.synchroniser()).reussie, isTrue);
      },
      skip: saute == false ? false : saute,
    );

    test(
      'Authorization retiré par Apache : le jeton passe par X-Authorization, la synchro réussit',
      () async {
        final p = await poste(http_);
        await saisir(p, 'pauth', 1);
        await regles([
          {'action': 'sans_authorization', 'fois': -1},
        ]);
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        final vus = await journal();
        expect(vus.where((v) => v['authorization'] == true), isEmpty);
        expect(r.acceptees, 1);
      },
      skip: saute == false ? false : saute,
    );

    test(
      'Authorization ET X-Authorization retirés : 401 « jeton_absent », le poste garde son jeton et dit pourquoi',
      () async {
        final p = await poste(http_);
        await regles([
          {'action': 'sans_authorization', 'aussi_x': true, 'fois': -1},
        ]);
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.refusee);
        expect(r.message, contains('ne reçoit pas le jeton'));
        expect(await p.depot.lire(), isNotNull);
        await regles([]);
        expect((await p.moteur.synchroniser()).reussie, isTrue);
      },
      skip: saute == false ? false : saute,
    );

    test(
      'redirection 301 http → https (POST compris) : suivie, adresse corrigée mémorisée, synchro réussie',
      () async {
        final p = await poste(http_, client: clientAutoriteMaison());
        await saisir(p, 'predir', 1);
        final cible = 'https://127.0.0.1:${tls['valide']}';
        await regles([
          {
            'action': 'redirige',
            'statut': 301,
            'location': '$cible/api/sync/push',
            'chemin': '/api/sync/push',
            'fois': -1,
          },
          {
            'action': 'redirige',
            'statut': 302,
            'location': '$cible/api/sync/pull',
            'chemin': '/api/sync/pull',
            'fois': -1,
          },
          {
            'action': 'redirige',
            'statut': 302,
            'location': '$cible/api/sync/demande',
            'chemin': '/api/sync/demande',
            'fois': -1,
          },
        ]);
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(await p.preferences.adresseServeur(), cible);
        expect(r.acceptees, 1);
      },
      skip: saute != false
          ? saute
          : (tls['valide'] == null ? 'LOGIALVIA_TLS absent' : false),
    );
  });
}

class _Poste {
  _Poste(this.db, this.preferences, this.depot, this.appairage, this.moteur);

  final AppDatabase db;
  final PreferencesPosteRepository preferences;
  final DepotJetonSyncMemoire depot;
  final ServiceAppairage appairage;
  final MoteurSynchronisationPoste moteur;
}
