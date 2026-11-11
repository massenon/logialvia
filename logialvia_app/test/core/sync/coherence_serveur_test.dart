import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

/// « Vérifier la cohérence » : ce que le serveur a de plus récent que le dernier tirage du poste.
void main() {
  late AppDatabase db;
  late PreferencesPosteRepository preferences;
  late DepotJetonSyncMemoire depot;
  late List<http.Request> requetes;
  late Future<http.Response> Function(http.Request) serveur;
  late MoteurSynchronisationPoste moteur;

  http.Response json(int statut, Map<String, dynamic> corps) => http.Response(
    jsonEncode(corps),
    statut,
    headers: {'content-type': 'application/json'},
  );

  Future<void> appairer() async {
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }

  setUp(() {
    db = AppDatabase.enMemoire();
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    requetes = [];
    serveur = (_) async =>
        json(200, {'retard': {}, 'curseur': 'x', 'total': 0});
    final client = MockClient((r) {
      requetes.add(r);
      return serveur(r);
    });
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: ServiceAppairage(
        preferences: preferences,
        depot: depot,
        client: client,
      ),
      tables: const [],
      client: client,
    );
  });

  tearDown(() => db.close());

  test('poste non appairé : aucun appel, issue nonAppairee', () async {
    final r = await moteur.coherenceServeur();

    expect(r.issue, IssueSynchronisation.nonAppairee);
    expect(r.repondu, isFalse);
    expect(requetes, isEmpty);
  });

  test(
    'à jour : aucun retard, curseur connu ; l\'identifiant du poste est envoyé',
    () async {
      await appairer();

      final r = await moteur.coherenceServeur();

      expect(r.aJour, isTrue);
      expect(r.total, 0);
      expect(requetes.single.url.path, '/api/sync/coherence');
      expect(
        requetes.single.url.queryParameters['device_id'],
        await preferences.identifiantPoste(),
      );
    },
  );

  test(
    'retard : lignes à recevoir par table, les zéros sont ignorés',
    () async {
      await appairer();
      serveur = (_) async => json(200, {
        'retard': {'clients': 3, 'ventes': 2, 'devis': 0},
        'curseur': '2026-11-11T10:00:00.000000Z',
        'total': 5,
      });

      final r = await moteur.coherenceServeur();

      expect(r.repondu, isTrue);
      expect(r.aJour, isFalse);
      expect(r.retard, {'clients': 3, 'ventes': 2});
      expect(r.total, 5);
    },
  );

  test('jamais synchronisé : curseur nul', () async {
    await appairer();
    serveur = (_) async =>
        json(200, {'retard': {}, 'curseur': null, 'total': 0});

    final r = await moteur.coherenceServeur();

    expect(r.jamaisSynchronise, isTrue);
    expect(r.aJour, isFalse);
  });

  test('hors ligne : issue horsLigne, jamais d\'exception', () async {
    await appairer();
    serveur = (_) async => throw http.ClientException('pas de réseau');

    final r = await moteur.coherenceServeur();

    expect(r.issue, IssueSynchronisation.horsLigne);
    expect(r.repondu, isFalse);
  });

  test(
    'jeton refusé (401) : issue revoque, le poste oublie son jeton',
    () async {
      await appairer();
      serveur = (_) async => json(401, {'message': 'Non authentifié.'});

      final r = await moteur.coherenceServeur();

      expect(r.issue, IssueSynchronisation.revoque);
      expect(await depot.lire(), isNull);
      expect(await preferences.jetonRevoqueLe(), isNotNull);
    },
  );

  test('réponse inattendue du serveur : refusée, sans exception', () async {
    await appairer();
    serveur = (_) async => json(500, {'message': 'Erreur'});

    final r = await moteur.coherenceServeur();

    expect(r.repondu, isFalse);
  });
}
