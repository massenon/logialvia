import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import 'faux_serveur_sync.dart';

/// Réseau d'hébergement mutualisé (`47r_`) rejoué contre le faux serveur : 413, coupures
/// en plein lot, lenteurs, 502/503/504/429, redirections, page HTML, TLS, en-tête
/// Authorization. Le même scénario est rejoué contre le VRAI serveur derrière le
/// mandataire (`test/integration/reseau_reel_test.dart`).
const _e = 'eeeeeeee-0000-4000-8000-0000000000';

String _uuid(int n) => '$_e${n.toString().padLeft(2, '0')}';

class _Poste {
  _Poste(
    this.serveur,
    http.Client client, {
    int lot = 100,
    int octetsMax = 256 * 1024,
    Duration delai = const Duration(seconds: 30),
  }) : db = AppDatabase.enMemoire() {
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: client,
      delaisRepetition: const [
        Duration(milliseconds: 10),
        Duration(seconds: 2),
      ],
      pause: pause,
    );
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: appairage,
      tables: [TableClientsPoste(db)],
      client: client,
      tailleLot: lot,
      octetsMaxEnvoi: octetsMax,
      delai: delai,
      delaisRepetition: const [
        Duration(milliseconds: 10),
        Duration(seconds: 2),
      ],
      pause: pause,
    );
  }

  final FauxServeurSync serveur;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;

  /// Les pauses demandées (jamais attendues pour de vrai).
  final List<Duration> pauses = [];
  Future<void> pause(Duration d) async => pauses.add(d);

  Future<void> appairer({String adresse = 'http://serveur.test'}) async {
    await preferences.definirAdresseServeur(adresse);
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }

  Future<void> saisir(int n, {String? nom}) => db
      .into(db.clients)
      .insert(
        ClientsCompanion.insert(
          id: Value(_uuid(n)),
          nom: nom ?? 'Client $n',
          syncStatus: const Value('pending'),
          updatedAt: Value(
            '2026-11-09T09:00:${n.toString().padLeft(2, '0')}.000000Z',
          ),
        ),
      );

  Future<List<ClientRow>> lignes() =>
      (db.select(db.clients)..orderBy([(c) => OrderingTerm.asc(c.id)])).get();

  Future<int> nbSynchronises() async =>
      (await lignes()).where((l) => l.syncStatus == 'synced').length;

  Future<void> fermer() => db.close();
}

http.Response _json(int s, Object? corps) => http.Response(
  '{"message":"${corps ?? ''}"}',
  s,
  headers: {'content-type': 'application/json'},
);

http.Response _html(int s) => http.Response(
  '<!DOCTYPE html><html><body><h1>Maintenance</h1></body></html>',
  s,
  headers: {'content-type': 'text/html; charset=UTF-8'},
);

void main() {
  late FauxServeurSync serveur;
  final postes = <_Poste>[];

  /// [comportement] voit chaque requête, son numéro (1…) et le vrai faux serveur.
  _Poste nouveau(
    Future<http.Response> Function(
      http.Request r,
      int n,
      Future<http.Response> Function() relayer,
    )?
    comportement, {
    int lot = 100,
    int octetsMax = 256 * 1024,
    Duration delai = const Duration(seconds: 30),
  }) {
    var n = 0;
    final client = MockClient((r) {
      n++;
      return comportement == null
          ? serveur.repondre(r)
          : comportement(r, n, () => serveur.repondre(r));
    });
    final p = _Poste(
      serveur,
      client,
      lot: lot,
      octetsMax: octetsMax,
      delai: delai,
    );
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

  bool estPush(http.Request r) => r.url.path == '/api/sync/push';
  bool estPull(http.Request r) => r.url.path == '/api/sync/pull';

  group('413 Payload Too Large : le poste découpe', () {
    test(
      'dichotomie : tout arrive une fois, aucun doublon, aucune perte',
      () async {
        // Limite de l'hébergeur : 1 200 octets de corps (Apache LimitRequestBody).
        final tailles = <int>[];
        final p = nouveau((r, n, relayer) async {
          if (estPush(r)) {
            tailles.add(r.bodyBytes.length);
            if (r.bodyBytes.length > 1200) return _html(413);
          }
          return relayer();
        });
        await p.appairer();
        for (var i = 1; i <= 24; i++) {
          await p.saisir(i);
        }

        final r = await p.moteur.synchroniser();

        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(serveur.clients, hasLength(24));
        expect(await p.nbSynchronises(), 24);
        // Chaque ligne a été TRAITÉE exactement une fois (un 413 ne traite rien).
        final traitees = serveur.envois
            .expand((e) => ((e['tables'] as Map)['clients'] as List))
            .map((l) => (l as Map)['id'])
            .toList();
        expect(traitees, hasLength(24));
        expect(traitees.toSet(), hasLength(24));
        expect(
          tailles.where((t) => t > 1200),
          isNotEmpty,
          reason: 'le premier envoi dépassait la limite',
        );
        expect(r.acceptees, 24);
      },
    );

    test('le plafond appris n\'est pas redemandé au cycle suivant', () async {
      var refus = 0;
      final p = nouveau((r, n, relayer) async {
        if (estPush(r) && r.bodyBytes.length > 700) {
          refus++;
          return _html(413);
        }
        return relayer();
      });
      await p.appairer();
      for (var i = 1; i <= 10; i++) {
        await p.saisir(i);
      }
      await p.moteur.synchroniser();
      final apres = refus;
      for (var i = 11; i <= 20; i++) {
        await p.saisir(i);
      }
      final r = await p.moteur.synchroniser();

      expect(r.issue, IssueSynchronisation.terminee);
      expect(serveur.clients, hasLength(20));
      expect(refus, apres, reason: 'plus aucun 413 : le plafond est mémorisé');
    });

    test(
      'une ligne seule trop grosse : refusée avec son motif, les autres partent',
      () async {
        final p = nouveau((r, n, relayer) async {
          if (estPush(r) && r.bodyBytes.length > 2000) return _html(413);
          return relayer();
        });
        await p.appairer();
        await p.saisir(1);
        await p.saisir(2, nom: 'x' * 5000);
        await p.saisir(3);

        final r = await p.moteur.synchroniser();

        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(serveur.clients.keys, containsAll([_uuid(1), _uuid(3)]));
        expect(serveur.clients, hasLength(2));
        final grosse = (await p.lignes()).firstWhere((l) => l.id == _uuid(2));
        expect(grosse.syncStatus, 'conflict');
        expect(grosse.syncMotif, contains('trop volumineuse'));
        expect(r.refusees, 1);
      },
    );

    test(
      'plafond en octets : le lot est coupé avant même le premier 413',
      () async {
        var plusGros = 0;
        final p = nouveau((r, n, relayer) async {
          if (estPush(r) && r.bodyBytes.length > plusGros) {
            plusGros = r.bodyBytes.length;
          }
          return relayer();
        }, octetsMax: 900);
        await p.appairer();
        for (var i = 1; i <= 12; i++) {
          await p.saisir(i);
        }
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.terminee);
        expect(serveur.clients, hasLength(12));
        expect(plusGros, lessThan(1500), reason: 'jamais un seul gros envoi');
      },
    );
  });

  group('coupure en plein lot : rejeu idempotent', () {
    test(
      'requête traitée par le serveur, réponse perdue : rejeu, aucun doublon',
      () async {
        var coupe = false;
        final p = nouveau((r, n, relayer) async {
          if (estPush(r) && !coupe) {
            coupe = true;
            await relayer(); // le serveur a TOUT traité…
            throw http.ClientException(
              'Connection closed before full header was received',
            );
          }
          return relayer();
        });
        await p.appairer();
        for (var i = 1; i <= 5; i++) {
          await p.saisir(i);
        }

        final r = await p.moteur.synchroniser();

        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(serveur.clients, hasLength(5));
        expect(await p.nbSynchronises(), 5);
        expect(p.pauses, isNotEmpty, reason: 'un rejeu a eu lieu');
        expect(serveur.envois, hasLength(2), reason: 'envoyé puis rejoué');
      },
    );

    test(
      'coupure persistante : hors ligne, tout reste à envoyer ; le réseau revient, tout passe',
      () async {
        var coupe = true;
        final p = nouveau((r, n, relayer) async {
          if (estPush(r) && coupe) {
            await relayer();
            throw http.ClientException('Connection reset by peer');
          }
          return relayer();
        });
        await p.appairer();
        for (var i = 1; i <= 4; i++) {
          await p.saisir(i);
        }

        final r1 = await p.moteur.synchroniser();
        expect(r1.issue, IssueSynchronisation.horsLigne);
        expect(r1.message, contains('coupée'));
        expect(
          await p.nbSynchronises(),
          0,
          reason: 'rien n\'est marqué à tort',
        );

        coupe = false; // le réseau revient entre deux cycles
        final r2 = await p.moteur.synchroniser();
        expect(r2.issue, IssueSynchronisation.terminee);
        expect(await p.nbSynchronises(), 4);
        expect(serveur.clients, hasLength(4), reason: 'aucun doublon');
      },
    );

    test(
      'tirage coupé à la page 2 : curseur intact, rien de perdu au cycle suivant',
      () async {
        serveur.lignesParPage = 2;
        for (var i = 1; i <= 5; i++) {
          serveur.ajouterClient(_uuid(i), 'Serveur $i');
        }
        var coupe = true;
        final p = nouveau((r, n, relayer) async {
          if (estPull(r) && r.url.queryParameters['page'] == '2' && coupe) {
            throw http.ClientException(
              'Connection closed before full header was received',
            );
          }
          return relayer();
        });
        await p.appairer();

        final r1 = await p.moteur.synchroniser();
        expect(r1.issue, IssueSynchronisation.horsLigne);
        expect(await p.preferences.curseurTirage(), isNull);

        coupe = false;
        final r2 = await p.moteur.synchroniser();
        expect(r2.issue, IssueSynchronisation.terminee);
        expect((await p.lignes()), hasLength(5));
        expect(await p.preferences.curseurTirage(), isNotNull);
      },
    );

    test(
      'réseau qui revient au milieu d\'un cycle : le rejeu aboutit',
      () async {
        var echecs = 2;
        final p = nouveau((r, n, relayer) async {
          if (estPush(r) && echecs > 0) {
            echecs--;
            throw const SocketException('Connection reset by peer');
          }
          return relayer();
        });
        await p.appairer();
        await p.saisir(1);
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(p.pauses, hasLength(2));
        expect(serveur.clients, hasLength(1));
      },
    );
  });

  group('lenteur', () {
    test(
      'réponse trop lente : message de délai (pas « hors ligne »), reprise ensuite',
      () async {
        var lent = true;
        final p = nouveau((r, n, relayer) async {
          if (estPull(r) && lent) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
          return relayer();
        }, delai: const Duration(milliseconds: 100));
        await p.appairer();
        await p.saisir(1);

        final r1 = await p.moteur.synchroniser();
        expect(r1.issue, IssueSynchronisation.horsLigne);
        expect(r1.message, contains('trop de temps'));

        lent = false;
        final r2 = await p.moteur.synchroniser();
        expect(r2.issue, IssueSynchronisation.terminee, reason: r2.message);
        expect(serveur.clients, hasLength(1));
      },
    );

    test(
      'envoi traité mais réponse trop lente : le rejeu ne crée aucun doublon',
      () async {
        var lent = true;
        final p = nouveau((r, n, relayer) async {
          if (estPush(r) && lent) {
            lent = false;
            final vraie = await relayer();
            await Future<void>.delayed(const Duration(milliseconds: 400));
            return vraie;
          }
          return relayer();
        }, delai: const Duration(milliseconds: 150));
        await p.appairer();
        await p.saisir(1);
        final r1 = await p.moteur.synchroniser();
        expect(r1.issue, IssueSynchronisation.horsLigne);
        expect(
          serveur.clients,
          hasLength(1),
          reason: 'le serveur a bien traité',
        );
        expect(await p.nbSynchronises(), 0);

        final r2 = await p.moteur.synchroniser();
        expect(r2.issue, IssueSynchronisation.terminee);
        expect(serveur.clients, hasLength(1));
        expect(await p.nbSynchronises(), 1);
      },
    );
  });

  group('502 / 503 / 504 / 429', () {
    test(
      '503 avec Retry-After : le poste attend ce délai puis réussit',
      () async {
        var passe = false;
        final p = nouveau((r, n, relayer) async {
          if (estPull(r) && !passe) {
            passe = true;
            return http.Response(
              '<html>Service Unavailable</html>',
              503,
              headers: {'content-type': 'text/html', 'retry-after': '3'},
            );
          }
          return relayer();
        });
        await p.appairer();
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(p.pauses.first, const Duration(seconds: 3));
      },
    );

    for (final statut in [502, 503, 504]) {
      test(
        '$statut persistant : hors ligne, message clair, rien de perdu',
        () async {
          final p = nouveau((r, n, relayer) async => _html(statut));
          await p.appairer();
          await p.saisir(1);
          final r = await p.moteur.synchroniser();
          expect(r.issue, IssueSynchronisation.horsLigne);
          expect(r.message, contains('momentanément indisponible'));
          expect(r.message, contains('$statut'));
          expect(await p.nbSynchronises(), 0);
          expect(
            p.pauses,
            hasLength(2),
            reason: '2 rejeux puis on rend la main',
          );
        },
      );
    }

    test(
      '429 avec Retry-After long : pas d\'attente interminable, message du serveur',
      () async {
        final p = nouveau(
          (r, n, relayer) async => http.Response(
            '{"message":"Trop de tentatives. Réessayez dans 120 secondes."}',
            429,
            headers: {'content-type': 'application/json', 'retry-after': '120'},
          ),
        );
        await p.appairer();
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.horsLigne);
        expect(r.message, contains('Trop de tentatives'));
        expect(p.pauses, isEmpty);
      },
    );
  });

  group('réponse HTML d\'hébergeur, redirections, en-têtes', () {
    test(
      '200 HTML au lieu de JSON : refus clair, jamais « réponse inattendue »',
      () async {
        final p = nouveau((r, n, relayer) async => _html(200));
        await p.appairer();
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.refusee);
        expect(r.message, contains('page web'));
        expect(r.message, isNot(contains('<html')));
      },
    );

    test('404 HTML (mauvais dossier) : message d\'adresse', () async {
      final p = nouveau((r, n, relayer) async => _html(404));
      await p.appairer();
      final r = await p.moteur.synchroniser();
      expect(r.issue, IssueSynchronisation.refusee);
      expect(r.message, contains('Vérifiez l\'adresse'));
    });

    test(
      '401 HTML (protection du dossier) : le jeton valide n\'est PAS oublié',
      () async {
        final p = nouveau((r, n, relayer) async => _html(401));
        await p.appairer();
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.refusee);
        expect(await p.depot.lire(), '1|jeton');
        expect(r.message, contains('reste appairé'));
      },
    );

    test(
      '401 « jeton_absent » (Authorization retiré) : jeton gardé, cause dite',
      () async {
        final p = nouveau(
          (r, n, relayer) async => http.Response(
            '{"message":"Le serveur ne reçoit pas le jeton du poste.","code":"jeton_absent"}',
            401,
            headers: {'content-type': 'application/json'},
          ),
        );
        await p.appairer();
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.refusee);
        expect(r.message, contains('ne reçoit pas le jeton'));
        expect(await p.depot.lire(), '1|jeton');
      },
    );

    test('401 JSON ordinaire : jeton oublié (comme avant)', () async {
      final p = nouveau(
        (r, n, relayer) async => _json(401, 'Unauthenticated.'),
      );
      await p.appairer();
      final r = await p.moteur.synchroniser();
      expect(r.issue, IssueSynchronisation.revoque);
      expect(await p.depot.lire(), isNull);
    });

    test('le jeton part dans Authorization ET X-Authorization', () async {
      http.Request? vue;
      final p = nouveau((r, n, relayer) async {
        vue = r;
        return relayer();
      });
      await p.appairer();
      await p.moteur.synchroniser();
      expect(vue!.headers['Authorization'], 'Bearer 1|jeton');
      expect(vue!.headers['X-Authorization'], 'Bearer 1|jeton');
    });

    test(
      '301 http → https (POST compris) : suivi, adresse corrigée mémorisée',
      () async {
        final schemas = <String>[];
        final p = nouveau((r, n, relayer) async {
          schemas.add('${r.method} ${r.url.scheme}');
          if (r.url.scheme == 'http') {
            return http.Response(
              '',
              301,
              headers: {'location': r.url.replace(scheme: 'https').toString()},
            );
          }
          return relayer();
        });
        await p.appairer();
        await p.saisir(1);

        final r = await p.moteur.synchroniser();

        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect(await p.preferences.adresseServeur(), 'https://serveur.test');
        expect(serveur.clients, hasLength(1));
        expect(schemas.where((s) => s == 'POST https'), isNotEmpty);
        // Le jeton n'a jamais été envoyé en clair sur la route finale.
        expect(schemas.last, endsWith('https'));
      },
    );

    test(
      'redirection vers un AUTRE site : refusée, le jeton n\'y part pas',
      () async {
        final hotes = <String>[];
        final p = nouveau((r, n, relayer) async {
          hotes.add(r.url.host);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://autre.exemple/api/sync/pull'},
          );
        });
        await p.appairer();
        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.refusee);
        expect(r.message, contains('redirige'));
        expect(hotes.toSet(), {'serveur.test'});
      },
    );
  });

  group('TLS : certificat invalide refusé, vérification jamais désactivée', () {
    final cas = <String, String>{
      'auto-signé':
          'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: self signed certificate(handshake.cc:393))',
      'autorité inconnue':
          'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate(handshake.cc:393))',
      'expiré':
          'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: certificate has expired(handshake.cc:393))',
      'mauvais nom':
          'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: Hostname mismatch(handshake.cc:393))',
    };
    cas.forEach((nom, detail) {
      test('$nom : message clair au tirage et à l\'appairage', () async {
        final p = nouveau(
          (r, n, relayer) async => throw HandshakeException(detail),
        );
        await p.appairer(adresse: 'https://serveur.test');
        await p.saisir(1);

        final r = await p.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.refusee);
        expect(r.message, contains('certificat'));
        expect(r.message, contains('jamais désactivée'));
        expect(r.message, isNot(contains('HandshakeException')));
        expect(await p.depot.lire(), '1|jeton', reason: 'le jeton reste');
        expect(await p.nbSynchronises(), 0);
        expect(
          p.pauses,
          isEmpty,
          reason: 'jamais de rejeu sur un certificat refusé',
        );

        final a = await p.appairage.connecter(
          adresse: 'https://serveur.test',
          identifiant: 'g',
          motDePasse: 'x',
        );
        expect(a.issue, IssueAppairage.refuse);
        expect(a.message, contains('certificat'));
      });
    });

    test('mauvais nom : le message nomme l\'adresse saisie', () async {
      final p = nouveau(
        (r, n, relayer) async => throw HandshakeException(cas['mauvais nom']!),
      );
      await p.appairer(adresse: 'https://serveur.test');
      final r = await p.moteur.synchroniser();
      expect(r.message, contains('serveur.test'));
    });

    test('HTTPS sur un serveur en clair : message de port', () async {
      final p = nouveau(
        (r, n, relayer) async => throw const HandshakeException(
          'Handshake error in client (OS Error: WRONG_VERSION_NUMBER(tls_record.cc:242))',
        ),
      );
      await p.appairer(adresse: 'https://serveur.test:8000');
      final r = await p.moteur.synchroniser();
      expect(r.issue, IssueSynchronisation.refusee);
      expect(r.message, contains('ne répond pas en HTTPS'));
    });
  });

  group('appairage : mêmes protections', () {
    test(
      'page HTML d\'hébergeur à la connexion : message clair, poste non appairé',
      () async {
        final p = nouveau((r, n, relayer) async => _html(200));
        final a = await p.appairage.connecter(
          adresse: 'https://serveur.test',
          identifiant: 'g',
          motDePasse: 'x',
        );
        expect(a.issue, IssueAppairage.refuse);
        expect(a.message, contains('page web'));
        expect(await p.depot.lire(), isNull);
      },
    );

    test(
      '503 à la connexion : injoignable (état normal), pas de refus',
      () async {
        final p = nouveau((r, n, relayer) async => _html(503));
        final a = await p.appairage.connecter(
          adresse: 'https://serveur.test',
          identifiant: 'g',
          motDePasse: 'x',
        );
        expect(a.issue, IssueAppairage.injoignable);
        expect(a.message, contains('momentanément indisponible'));
      },
    );

    test('tester : 401 HTML ne fait pas oublier le jeton', () async {
      final p = nouveau((r, n, relayer) async => _html(401));
      await p.appairer();
      final a = await p.appairage.tester();
      expect(a.issue, IssueAppairage.refuse);
      expect(await p.depot.lire(), '1|jeton');
    });

    test(
      'redirection http → https à la connexion : adresse corrigée',
      () async {
        final p = nouveau((r, n, relayer) async {
          if (r.url.scheme == 'http') {
            return http.Response(
              '',
              301,
              headers: {'location': r.url.replace(scheme: 'https').toString()},
            );
          }
          return relayer();
        });
        await p.appairer();
        final a = await p.appairage.connecter(
          adresse: 'http://serveur.test',
          identifiant: 'g',
          motDePasse: 'x',
        );
        expect(await p.preferences.adresseServeur(), 'https://serveur.test');
        expect(a.reussi || a.issue == IssueAppairage.refuse, isTrue);
      },
    );
  });
}
