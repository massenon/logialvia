import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/adresse_serveur.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

/// P1 — appairage du poste, contre un FAUX serveur qui rejoue les réponses
/// réelles de `logialvia_laravel` (`AuthController`). L'essai contre le vrai
/// serveur Laravel est la dernière étape (`45_`).
void main() {
  late AppDatabase db;
  late PreferencesPosteRepository preferences;
  late DepotJetonSyncMemoire depot;
  late List<http.Request> requetes;

  setUp(() {
    db = AppDatabase.enMemoire();
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    requetes = [];
  });

  tearDown(() => db.close());

  ServiceAppairage service(
    Future<http.Response> Function(http.Request) serveur, {
    DepotJetonSync? magasin,
  }) => ServiceAppairage(
    preferences: preferences,
    depot: magasin ?? depot,
    client: MockClient((r) {
      requetes.add(r);
      return serveur(r);
    }),
  );

  http.Response json(int statut, Map<String, dynamic> corps) => http.Response(
    jsonEncode(corps),
    statut,
    headers: {'content-type': 'application/json'},
  );

  Map<String, dynamic> loginOk({bool temporaire = false}) => {
    'token': '1|abcdef',
    'expires_at': '2027-02-07T10:00:00+00:00',
    'user': {'username': 'gerante'},
    'must_change_password': temporaire,
    'poste': {'id': 'x', 'code': 'P2'},
  };

  group('Identifiant du poste', () {
    test('est un UUID v4 valide', () {
      final id = genererUuidV4();
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('est tiré UNE fois, puis jamais régénéré', () async {
      final premier = await preferences.identifiantPoste();
      expect(await preferences.identifiantPoste(), premier);
      expect(
        await PreferencesPosteRepository(db).identifiantPoste(),
        premier,
        reason: 'un autre accès à la même base voit le même poste',
      );
    });

    test('deux postes ont deux identifiants', () async {
      final autre = AppDatabase.enMemoire();
      addTearDown(autre.close);
      expect(
        await PreferencesPosteRepository(autre).identifiantPoste(),
        isNot(await preferences.identifiantPoste()),
      );
    });
  });

  group('Adresse du serveur', () {
    test('ajoute le schéma : http en réseau local, https ailleurs', () {
      expect(
        normaliserAdresseServeur('192.168.1.10:8000'),
        'http://192.168.1.10:8000',
      );
      expect(
        normaliserAdresseServeur('localhost:8000'),
        'http://localhost:8000',
      );
      expect(normaliserAdresseServeur('172.20.0.5'), 'http://172.20.0.5');
      expect(
        normaliserAdresseServeur('logialvia.exemple.bj'),
        'https://logialvia.exemple.bj',
      );
      expect(normaliserAdresseServeur('172.40.0.5'), 'https://172.40.0.5');
    });

    test('retire les / finaux, garde un schéma explicite', () {
      expect(normaliserAdresseServeur('  https://a.bj///  '), 'https://a.bj');
      expect(normaliserAdresseServeur('http://a.bj/app/'), 'http://a.bj/app');
    });

    test('refuse le vide, l\'absence d\'hôte et les autres schémas', () {
      expect(normaliserAdresseServeur(''), isNull);
      expect(normaliserAdresseServeur('   '), isNull);
      expect(normaliserAdresseServeur('https://'), isNull);
      expect(normaliserAdresseServeur('ftp://a.bj'), isNull);
    });
  });

  group('Appairage', () {
    test(
      'envoie l\'identifiant du poste comme device_name et garde le jeton',
      () async {
        final s = service((_) async => json(200, loginOk()));

        final r = await s.connecter(
          adresse: 'logialvia.exemple.bj/',
          identifiant: ' gerante ',
          motDePasse: 'secret-1',
        );

        expect(r.issue, IssueAppairage.appaire);
        expect(r.codePoste, 'P2');
        final envoyee = requetes.single;
        expect(
          envoyee.url.toString(),
          'https://logialvia.exemple.bj/api/auth/login',
        );
        final corps = jsonDecode(envoyee.body) as Map<String, dynamic>;
        expect(corps['device_name'], await preferences.identifiantPoste());
        expect(corps['identifiant'], 'gerante');
        expect(await depot.lire(), '1|abcdef');
        final etat = await s.etat();
        expect(etat.appaire, isTrue);
        expect(etat.codePoste, 'P2');
        expect(etat.compte, 'gerante');
        expect(etat.adresse, 'https://logialvia.exemple.bj');
      },
    );

    test('le mot de passe n\'est écrit nulle part', () async {
      final s = service((_) async => json(200, loginOk()));
      await s.connecter(
        adresse: 'a.bj',
        identifiant: 'gerante',
        motDePasse: 'MotDePasseUnique-9137',
      );

      final lignes = await db.select(db.preferencesPoste).get();
      for (final l in lignes) {
        expect(l.valeur, isNot(contains('MotDePasseUnique-9137')));
      }
      expect(await depot.lire(), isNot(contains('MotDePasseUnique-9137')));
    });

    test('le jeton n\'est JAMAIS écrit dans la base', () async {
      final s = service((_) async => json(200, loginOk()));
      await s.connecter(adresse: 'a.bj', identifiant: 'g', motDePasse: 'x');

      final lignes = await db.select(db.preferencesPoste).get();
      for (final l in lignes) {
        expect(l.valeur, isNot(contains('abcdef')));
        expect(l.cle, isNot(contains('jeton')));
      }
    });

    test('mot de passe temporaire : appairé, mais le dit', () async {
      final s = service((_) async => json(200, loginOk(temporaire: true)));
      final r = await s.connecter(
        adresse: 'a.bj',
        identifiant: 'g',
        motDePasse: 'x',
      );

      expect(r.reussi, isTrue);
      expect(r.message, contains('mot de passe temporaire'));
    });

    test(
      'refus du serveur : son message français est montré, rien n\'est gardé',
      () async {
        final s = service(
          (_) async =>
              json(401, {'message': 'Identifiant ou mot de passe incorrect.'}),
        );
        final r = await s.connecter(
          adresse: 'a.bj',
          identifiant: 'g',
          motDePasse: 'x',
        );

        expect(r.issue, IssueAppairage.refuse);
        expect(r.message, 'Identifiant ou mot de passe incorrect.');
        expect(await depot.lire(), isNull);
        expect((await s.etat()).appaire, isFalse);
      },
    );

    test('compte désactivé et trop d\'essais : messages du serveur', () async {
      var statut = 403;
      final s = service(
        (_) async => json(statut, {
          'message': statut == 403
              ? 'Ce compte a été désactivé.'
              : 'Trop de tentatives.',
        }),
      );
      expect(
        (await s.connecter(
          adresse: 'a.bj',
          identifiant: 'g',
          motDePasse: 'x',
        )).message,
        'Ce compte a été désactivé.',
      );
      statut = 429;
      expect(
        (await s.connecter(
          adresse: 'a.bj',
          identifiant: 'g',
          motDePasse: 'x',
        )).message,
        'Trop de tentatives.',
      );
    });

    test(
      'serveur injoignable : état clair, poste non appairé, pas d\'exception',
      () async {
        final s = service(
          (_) async => throw http.ClientException('connexion refusée'),
        );
        final r = await s.connecter(
          adresse: 'a.bj',
          identifiant: 'g',
          motDePasse: 'x',
        );

        expect(r.issue, IssueAppairage.injoignable);
        expect(r.message, contains('hors ligne'));
        expect((await s.etat()).appaire, isFalse);
      },
    );

    test('adresse invalide : rien n\'est envoyé', () async {
      final s = service((_) async => json(200, loginOk()));
      final r = await s.connecter(
        adresse: 'ftp://a.bj',
        identifiant: 'g',
        motDePasse: 'x',
      );

      expect(r.issue, IssueAppairage.adresseInvalide);
      expect(requetes, isEmpty);
    });

    test('identifiant ou mot de passe vide : rien n\'est envoyé', () async {
      final s = service((_) async => json(200, loginOk()));
      expect(
        (await s.connecter(
          adresse: 'a.bj',
          identifiant: '  ',
          motDePasse: 'x',
        )).reussi,
        isFalse,
      );
      expect(
        (await s.connecter(
          adresse: 'a.bj',
          identifiant: 'g',
          motDePasse: '',
        )).reussi,
        isFalse,
      );
      expect(requetes, isEmpty);
    });

    test(
      'réponse inattendue (sans jeton) : appairage non enregistré',
      () async {
        final s = service((_) async => json(200, {'ok': true}));
        final r = await s.connecter(
          adresse: 'a.bj',
          identifiant: 'g',
          motDePasse: 'x',
        );

        expect(r.reussi, isFalse);
        expect((await s.etat()).appaire, isFalse);
      },
    );

    test(
      'coffre qui refuse d\'écrire : appairage raté, pas de faux « appairé »',
      () async {
        final s = service(
          (_) async => json(200, loginOk()),
          magasin: DepotJetonSyncMemoire(refuseEcriture: true),
        );
        final r = await s.connecter(
          adresse: 'a.bj',
          identifiant: 'g',
          motDePasse: 'x',
        );

        expect(r.reussi, isFalse);
        expect(r.message, contains('coffre'));
        expect((await s.etat()).appaire, isFalse);
        expect(await preferences.codePoste(), isNull);
      },
    );

    test('se reconnecter garde le même identifiant de poste', () async {
      final s = service((_) async => json(200, loginOk()));
      await s.connecter(adresse: 'a.bj', identifiant: 'g', motDePasse: 'x');
      final avant = (await s.etat()).identifiantPoste;
      await s.deconnecter();
      await s.connecter(adresse: 'a.bj', identifiant: 'g', motDePasse: 'x');

      expect((await s.etat()).identifiantPoste, avant);
    });
  });

  group('Test de connexion', () {
    Future<ServiceAppairage> appaire(
      Future<http.Response> Function(http.Request) apres,
    ) async {
      final s = service((r) async {
        if (r.url.path == '/api/auth/login') return json(200, loginOk());
        return apres(r);
      });
      await s.connecter(adresse: 'a.bj', identifiant: 'g', motDePasse: 'x');
      requetes.clear();
      return s;
    }

    test('envoie le jeton en Bearer sur /api/auth/me', () async {
      final s = await appaire(
        (_) async => json(200, {
          'poste': {'code': 'P2'},
        }),
      );
      final r = await s.tester();

      expect(r.reussi, isTrue);
      expect(requetes.single.url.path, '/api/auth/me');
      expect(requetes.single.headers['Authorization'], 'Bearer 1|abcdef');
    });

    test(
      '401 : jeton révoqué — le poste l\'oublie et redemande une connexion',
      () async {
        final s = await appaire(
          (_) async => json(401, {'message': 'Non authentifié.'}),
        );
        final r = await s.tester();

        expect(r.issue, IssueAppairage.revoque);
        expect(r.message, contains('conservées'));
        expect(await depot.lire(), isNull);
        expect((await s.etat()).appaire, isFalse);
      },
    );

    test(
      'hors ligne : le poste RESTE appairé (ce n\'est pas une révocation)',
      () async {
        final s = await appaire(
          (_) async => throw http.ClientException('réseau coupé'),
        );
        final r = await s.tester();

        expect(r.issue, IssueAppairage.injoignable);
        expect((await s.etat()).appaire, isTrue);
        expect(await depot.lire(), '1|abcdef');
      },
    );

    test('non appairé : le dit, sans appeler le serveur', () async {
      final s = service((_) async => json(200, {}));
      final r = await s.tester();

      expect(r.reussi, isFalse);
      expect(requetes, isEmpty);
    });
  });

  group('Déconnexion', () {
    Future<ServiceAppairage> appaire(
      Future<http.Response> Function(http.Request) apres,
    ) async {
      final s = service((r) async {
        if (r.url.path == '/api/auth/login') return json(200, loginOk());
        return apres(r);
      });
      await s.connecter(adresse: 'a.bj', identifiant: 'g', motDePasse: 'x');
      requetes.clear();
      return s;
    }

    test('prévient le serveur puis efface le jeton et l\'appairage', () async {
      final s = await appaire(
        (_) async => json(200, {'message': 'Déconnecté.'}),
      );
      final r = await s.deconnecter();

      expect(r.issue, IssueAppairage.deconnecte);
      expect(r.message, 'Poste déconnecté.');
      expect(requetes.single.url.path, '/api/auth/logout');
      expect(await depot.lire(), isNull);
      final etat = await s.etat();
      expect(etat.appaire, isFalse);
      expect(etat.codePoste, isNull);
      expect(
        etat.adresse,
        'https://a.bj',
        reason: 'l\'adresse sert à se reconnecter',
      );
    });

    test(
      'serveur injoignable : le jeton local est effacé quand même, et c\'est dit',
      () async {
        final s = await appaire(
          (_) async => throw http.ClientException('coupé'),
        );
        final r = await s.deconnecter();

        expect(await depot.lire(), isNull);
        expect((await s.etat()).appaire, isFalse);
        expect(r.message, contains('n\'a pas pu être prévenu'));
      },
    );
  });

  test('un coffre illisible équivaut à un poste non appairé', () async {
    final s = service((_) async => json(200, loginOk()));
    await s.connecter(adresse: 'a.bj', identifiant: 'g', motDePasse: 'x');
    await depot.effacer();

    expect((await s.etat()).appaire, isFalse);
  });
}
