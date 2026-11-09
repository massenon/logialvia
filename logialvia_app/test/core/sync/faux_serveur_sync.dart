import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Un faux serveur qui rejoue le CONTRAT de `logialvia_laravel`
/// (`MoteurSynchronisation`, `46_` §4 et §6), pas seulement ses formats :
///
/// - curseur de RÉCEPTION (`serveur_modifie_le`), jamais la saisie ;
/// - tirage paginé, borne `until` figée ;
/// - envoi idempotent par UUID, **dernier écrivain gagne** (strictement) ;
/// - refus avec motif français ; marque de remise à zéro (409) ;
/// - jeton révoqué (401).
///
/// L'essai contre le vrai serveur Laravel reste l'ultime étape (`45_`).
class FauxServeurSync {
  FauxServeurSync({this.lignesParPage = 200});

  int lignesParPage;
  String marque = 'initiale';
  bool jetonRevoque = false;
  bool horsLigne = false;

  /// Erreur 500 forcée sur ce numéro de page du tirage (1-based), une fois.
  int? panneAuTirageDePage;

  final Map<String, Map<String, dynamic>> clients = {};
  final List<String> journal = []; // « GET pull », « POST push »…
  final List<Map<String, dynamic>> envois = [];

  /// Appelé au milieu d'un envoi : simule une saisie faite pendant que le
  /// réseau répond.
  Future<void> Function()? pendantEnvoi;

  int _horloge = 0;

  String _instant() {
    final t = DateTime.utc(
      2026,
      11,
      9,
      10,
    ).add(Duration(milliseconds: ++_horloge));
    return t.toIso8601String();
  }

  /// `server_time` courant.
  String get maintenant => DateTime.utc(
    2026,
    11,
    9,
    10,
  ).add(Duration(milliseconds: _horloge)).toIso8601String();

  void remettreAZero() {
    clients.clear();
    marque = 'rz-${++_horloge}';
  }

  /// Une saisie faite par un autre poste, déjà reçue par le serveur.
  void ajouterClient(
    String id,
    String nom, {
    String? updatedAt,
    String? supprimeLe,
  }) {
    clients[id] = {
      'id': id,
      'device_id': 'autre-poste',
      'nom': nom,
      'telephone': null,
      'solde_creance': 0,
      'date_naissance': null,
      'dernier_contact': null,
      'updated_at': updatedAt ?? _instant(),
      'serveur_modifie_le': _instant(),
      'supprime_le': supprimeLe,
    };
  }

  http.Client get client => MockClient(repondre);

  http.Response _json(int s, Object corps) => http.Response(
    jsonEncode(corps),
    s,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> repondre(http.Request r) async {
    if (horsLigne) throw http.ClientException('réseau coupé');
    journal.add('${r.method} ${r.url.path}');
    if (jetonRevoque) return _json(401, {'message': 'Non authentifié.'});

    if (r.url.path == '/api/sync/pull') return _pull(r);
    if (r.url.path == '/api/sync/push') return _push(r);
    return _json(404, {'message': 'inconnu'});
  }

  http.Response _pull(http.Request r) {
    final page = int.parse(r.url.queryParameters['page'] ?? '1');
    if (panneAuTirageDePage == page) {
      panneAuTirageDePage = null;
      return _json(500, {'message': 'Erreur interne.'});
    }
    final since = r.url.queryParameters['since'];
    final jusqua = r.url.queryParameters['until'] ?? maintenant;

    final lignes =
        clients.values.where((c) {
          final recu = c['serveur_modifie_le'] as String;
          return (since == null || recu.compareTo(since) > 0) &&
              recu.compareTo(jusqua) <= 0;
        }).toList()..sort((a, b) {
          final c = (a['serveur_modifie_le'] as String).compareTo(
            b['serveur_modifie_le'] as String,
          );
          return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
        });

    final derniere = lignes.isEmpty
        ? 1
        : (lignes.length / lignesParPage).ceil();
    final debut = (page - 1) * lignesParPage;
    return _json(200, {
      'server_time': jusqua,
      'page': page,
      'last_page': derniere,
      'reset_mark': marque,
      'tables': {
        'modules_actifs': [], // référentiels : pas encore branchés au poste
        'clients': lignes.skip(debut).take(lignesParPage).toList(),
      },
    });
  }

  Future<http.Response> _push(http.Request r) async {
    final corps = jsonDecode(r.body) as Map<String, dynamic>;
    envois.add(corps);
    if (corps['reset_mark'] != marque) {
      return _json(409, {
        'message': 'Ce poste ne connaît pas la dernière remise à zéro.',
        'code': 'remise_a_zero_inconnue',
        'reset_mark': marque,
      });
    }
    if (pendantEnvoi != null) {
      await pendantEnvoi!();
      pendantEnvoi = null;
    }

    final reponse = <String, dynamic>{};
    final lignes = ((corps['tables'] as Map)['clients'] as List?) ?? const [];
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final l in lignes.cast<Map<String, dynamic>>()) {
      final nom = l['nom'];
      if (nom is! String || nom.trim().isEmpty) {
        refusees.add({
          'id': l['id'] as String,
          'motif': 'Le nom du client est obligatoire.',
        });
        continue;
      }
      final existant = clients[l['id']];
      final saisie = DateTime.parse(l['updated_at'] as String);
      if (existant == null) {
        clients[l['id'] as String] = {
          'id': l['id'],
          'device_id': corps['device_id'],
          'nom': nom,
          'telephone': l['telephone'],
          'solde_creance': 0,
          'date_naissance': l['date_naissance'],
          'dernier_contact': l['dernier_contact'],
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
          'supprime_le': null,
        };
      } else if (saisie.isAfter(
        DateTime.parse(existant['updated_at'] as String),
      )) {
        existant
          ..['nom'] = nom
          ..['telephone'] = l['telephone']
          ..['date_naissance'] = l['date_naissance']
          ..['dernier_contact'] = l['dernier_contact']
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      } // sinon : rejeu ou saisie plus ancienne — acceptée sans rien changer
      acceptees.add(l['id'] as String);
    }
    reponse['clients'] = {
      'accepted': acceptees,
      'rejected': refusees,
      'ignored': [],
    };
    return _json(200, reponse);
  }
}
