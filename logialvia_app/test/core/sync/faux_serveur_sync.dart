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

  /// Latence artificielle de chaque réponse (réseau lent).
  Duration? delaiReponse;

  /// Erreur 500 forcée sur ce numéro de page du tirage (1-based), une fois.
  int? panneAuTirageDePage;

  final Map<String, Map<String, dynamic>> clients = {};

  /// Produits (référentiel, sans stock) et ventes (avec leurs lignes imbriquées).
  final Map<String, Map<String, dynamic>> produits = {};
  final Map<String, Map<String, dynamic>> ventes = {};

  /// Référentiels : `module_id` -> ligne ; une seule ligne de paramètres.
  final Map<String, Map<String, dynamic>> modules = {};
  Map<String, dynamic>? parametres;

  /// Drapeaux déposés par le web (`GET /api/sync/demande`).
  bool demandeSynchro = false;
  bool resyncDemandee = false;
  int acquittements = 0;

  /// Demandes de modification de référentiel reçues (`POST /api/sync/demandes`).
  final List<Map<String, dynamic>> demandesRecues = [];

  /// Non nul : le serveur refuse toute demande avec ce motif.
  String? refuserDemandes;

  /// `false` : le serveur n'applique pas les demandes (on isole le tirage).
  bool demandesAccepteesParLeServeur = true;

  Future<void> Function()? pendantDemandes;
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
    ventes.clear(); // les produits (référentiel) sont préservés
    marque = 'rz-${++_horloge}';
  }

  /// Un module tel que le serveur le sert. `decide` : le serveur l'a réellement
  /// modifié (`updated_at` > `created_at`) ; sinon c'est une valeur de semis.
  void ajouterModule(
    String id, {
    required bool actif,
    bool decide = true,
    String? espece,
    DateTime? decisionLe,
  }) {
    // `decisionLe` : instant RÉEL de la décision du serveur (pour la comparer à
    // la saisie d'un poste) ; la création est une heure plus tôt.
    final cree = decisionLe == null
        ? _instant()
        : decisionLe
              .toUtc()
              .subtract(const Duration(hours: 1))
              .toIso8601String();
    modules[id] = {
      'id': 'm-$id',
      'module_id': id,
      'is_actif': actif,
      'espece': espece,
      'created_at': cree,
      'updated_at': decisionLe != null
          ? decisionLe.toUtc().toIso8601String()
          : (decide ? _instant() : cree),
    };
  }

  /// Les paramètres tels que le serveur les sert.
  void definirParametres(Map<String, dynamic> valeurs, {bool decide = true}) {
    final cree = _instant();
    parametres = {
      'id': 'p-1',
      'raison_sociale': 'ALLMANY ET COMPAGNIE',
      'created_at': cree,
      'updated_at': decide ? _instant() : cree,
      ...valeurs,
    };
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
    if (delaiReponse != null) await Future<void>.delayed(delaiReponse!);
    journal.add('${r.method} ${r.url.path}');
    if (jetonRevoque) return _json(401, {'message': 'Non authentifié.'});

    if (r.url.path == '/api/sync/demande') {
      final reponse = _json(200, {
        'synchroniser': demandeSynchro,
        'resynchronisation_complete': resyncDemandee,
      });
      demandeSynchro = false; // servie une fois
      return reponse;
    }
    if (r.url.path == '/api/sync/resynchronisation/acquittement') {
      resyncDemandee = false;
      acquittements++;
      return _json(200, {'message': 'Resynchronisation acquittée.'});
    }
    if (r.url.path == '/api/sync/demandes') return _demandes(r);
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
        'modules_actifs': [
          for (final m in modules.values)
            if (_dans(m['updated_at'] as String, since, jusqua)) m,
        ],
        'parametres_entreprise': [
          if (parametres != null &&
              _dans(parametres!['updated_at'] as String, since, jusqua))
            parametres,
        ],
        'produits_vendables': [
          for (final p in produits.values)
            if (_dans(p['updated_at'] as String, since, jusqua)) p,
        ],
        'clients': lignes.skip(debut).take(lignesParPage).toList(),
        'ventes': [
          for (final v in ventes.values)
            if (_dans(v['serveur_modifie_le'] as String, since, jusqua)) v,
        ],
      },
    });
  }

  Future<http.Response> _demandes(http.Request r) async {
    final corps = jsonDecode(r.body) as Map<String, dynamic>;
    if (pendantDemandes != null) {
      await pendantDemandes!();
      pendantDemandes = null;
    }
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final d in (corps['demandes'] as List).cast<Map<String, dynamic>>()) {
      if (refuserDemandes != null) {
        refusees.add({'id': d['id'] as String, 'motif': refuserDemandes!});
        continue;
      }
      demandesRecues.add(d);
      acceptees.add(d['id'] as String);
      if (!demandesAccepteesParLeServeur) continue;
      final donnees = d['donnees'] as Map<String, dynamic>;
      if (d['type'] == 'produit_vendable') {
        final donnees = d['donnees'] as Map<String, dynamic>;
        if (donnees.containsKey('stock')) {
          acceptees.remove(d['id']);
          refusees.add({
            'id': d['id'] as String,
            'motif':
                'Le stock n\'est pas synchronisé : il reste propre à chaque poste.',
          });
          continue;
        }
        _produit(d);
        continue;
      }
      if (d['type'] == 'module_actif') {
        ajouterModule(
          donnees['module_id'] as String,
          actif: donnees['is_actif'] as bool,
        );
      } else if (d['type'] == 'parametres_entreprise') {
        definirParametres(donnees);
      }
    }
    return _json(200, {'accepted': acceptees, 'rejected': refusees});
  }

  bool _dans(String instant, String? since, String jusqua) =>
      (since == null || instant.compareTo(since) > 0) &&
      instant.compareTo(jusqua) <= 0;

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
    if ((corps['tables'] as Map).containsKey('ventes')) {
      reponse['ventes'] = _ventes(
        ((corps['tables'] as Map)['ventes'] as List)
            .cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    return _json(200, reponse);
  }

  /// Un instant de réception du serveur, dans le temps du faux serveur.
  String instantServeur() => _instant();

  /// Un produit tel que le serveur le garde (jamais de stock).
  void ajouterProduit(Map<String, dynamic> p, {String? saisiLe}) {
    produits[p['id'] as String] = {
      ...p,
      'saisi_le': saisiLe ?? _instant(),
      'created_at': _instant(),
      'updated_at': _instant(),
    };
  }

  void _produit(Map<String, dynamic> demande) {
    final donnees = demande['donnees'] as Map<String, dynamic>;
    final saisie = demande['saisi_le'] as String;
    final id = donnees['id'] as String;
    final existant = produits[id];
    if (existant == null) {
      ajouterProduit(donnees, saisiLe: saisie);
      return;
    }
    final identique = donnees.entries.every((e) => existant[e.key] == e.value);
    if (identique) return;
    if (!DateTime.parse(
      saisie,
    ).isAfter(DateTime.parse(existant['saisi_le'] as String))) {
      demandesAccepteesParLeServeur = true;
      return;
    }
    existant
      ..addAll(donnees)
      ..['saisi_le'] = saisie
      ..['updated_at'] = _instant();
  }

  /// Rejoue les règles du vrai serveur (`VentesTable`) : lot vente + lignes,
  /// produits connus, unicité de la référence, entête en dernier écrivain gagne,
  /// lignes immuables.
  Map<String, dynamic> _ventes(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    bool codee(String ref) => RegExp(r'^V-P\d+-\d{4}-\d{3,}$').hasMatch(ref);

    for (final v in lot) {
      final id = v['id'] as String;
      final lignes = (v['lignes'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      if (lignes.isEmpty) {
        refusees.add({
          'id': id,
          'motif': 'Une vente doit avoir au moins une ligne.',
        });
        continue;
      }
      final inconnu = lignes.where(
        (l) => !produits.containsKey(l['produit_id']),
      );
      if (inconnu.isNotEmpty) {
        refusees.add({
          'id': id,
          'motif': 'Produit inconnu du serveur : « ${inconnu.first['name']} ».',
        });
        continue;
      }
      final ref = v['reference'] as String;
      final doublon = ventes.values.any(
        (x) =>
            x['id'] != id &&
            x['reference'] == ref &&
            (codee(ref) || x['device_id'] == deviceId),
      );
      if (doublon) {
        refusees.add({
          'id': id,
          'motif': 'Cette référence est déjà utilisée par une autre vente.',
        });
        continue;
      }
      final saisie = DateTime.parse(v['updated_at'] as String);
      final existante = ventes[id];
      if (existante == null) {
        ventes[id] = {
          ...v,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
      } else if (saisie.isAfter(
        DateTime.parse(existante['updated_at'] as String),
      )) {
        for (final c in const [
          'client',
          'client_id',
          'mode',
          'status',
          'total',
          'paye',
          'motif_annulation',
          'echeance',
        ]) {
          existante[c] = v[c];
        }
        existante
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }
}
