import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logialvia_app/elevage/data/sync/identifiants_elevage.dart';

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

  /// Fournisseurs (fait plat) et achats (avec leurs lignes imbriquées).
  final Map<String, Map<String, dynamic>> fournisseurs = {};
  final Map<String, Map<String, dynamic>> achats = {};

  /// Intrants (référentiel, SANS stock ni PMP, clé : le code) et journal des
  /// mouvements (faits immuables).
  final Map<String, Map<String, dynamic>> intrants = {};
  final Map<String, Map<String, dynamic>> mouvements = {};
  final Map<String, Map<String, dynamic>> mouvementsProduit = {};

  // --- P8 : comptabilité (rejoue `EcrituresTable` & co du vrai serveur) ---

  /// Plan comptable (référentiel, clé : le numéro de compte).
  final Map<String, Map<String, dynamic>> comptes = {};

  /// Exercices (clé : l'année).
  final Map<int, Map<String, dynamic>> exercices = {};

  /// Pièces comptables avec leurs lignes imbriquées (clé : `piece_id`).
  final Map<String, Map<String, dynamic>> pieces = {};

  /// Notes annexes (clé : « exercice-numéro »).
  final Map<String, Map<String, dynamic>> notes = {};

  /// Clôtures mensuelles (clé : l'identifiant déterministe du mois).
  final Map<String, Map<String, dynamic>> cloturesMois = {};

  /// Faux : le compte du poste n'a pas `close-fiscal-year` (le serveur refuse).
  bool clotureExerciceAutorisee = true;

  /// Paramètres d'élevage (P7c) : trois référentiels (barèmes, taux par classe de
  /// poids, calendrier de prophylaxie) et deux faits (soins, infirmerie).
  final Map<String, Map<String, dynamic>> baremes = {};
  final Map<String, Map<String, dynamic>> taux = {};
  final Map<String, Map<String, dynamic>> echeances = {};
  final Map<String, Map<String, dynamic>> soins = {};
  final Map<String, Map<String, dynamic>> infirmerie = {};

  /// Incubateurs et lots de couveuse (faits plats, dernier écrivain gagne).
  final Map<String, Map<String, dynamic>> machines = {};
  final Map<String, Map<String, dynamic>> cycles = {};

  /// Messages à l'éditeur (doc 47u §4) : fait plat, dernier écrivain gagne, pierre
  /// tombale `supprime_le`. Lecture et écriture ouvertes à tout compte.
  final Map<String, Map<String, dynamic>> messagesEditeur = {};

  /// Factures e-MECeF (avec leurs lignes imbriquées) et grille de taxation
  /// (référentiel, clé : la lettre). Le serveur ne transmet JAMAIS à la DGI.
  final Map<String, Map<String, dynamic>> factures = {};
  final Map<String, Map<String, dynamic>> groupesTaxe = {};

  /// Devis de prestations (`47a2_`) : faits plats, dernier écrivain gagne (rejoue
  /// `DevisTable` du vrai serveur).
  final Map<String, Map<String, dynamic>> devis = {};

  /// Elevage (palier 7a) : fiches journalieres, compteurs de ventes du jour (une
  /// ligne par poste) et bandes.
  final Map<String, Map<String, dynamic>> fichesJournee = {};
  final Map<String, Map<String, dynamic>> ventesJour = {};
  final Map<String, Map<String, dynamic>> bandes = {};

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

  /// Un instant de réception, STRICTEMENT postérieur à `maintenant` (donc à toute
  /// ligne déjà détenue) : une ligne émise ne peut jamais être datée avant le curseur
  /// qu'un poste a reçu.
  String _instant() {
    final depart = DateTime.utc(2026, 11, 9, 10);
    final suivant = DateTime.parse(
      maintenant,
    ).add(const Duration(milliseconds: 1));
    final ms = suivant.difference(depart).inMilliseconds;
    if (ms > _horloge) _horloge = ms;
    return depart.add(Duration(milliseconds: _horloge)).toIso8601String();
  }

  /// `server_time` courant : l'horloge du faux serveur, **jamais en retard sur une
  /// ligne qu'il détient** (un serveur ne sert pas une ligne postérieure à sa propre
  /// heure). Sans cela, un jeu d'essai daté de l'heure RÉELLE (la saisie d'un poste)
  /// dépasserait une horloge figée et le test dépendrait de l'heure de la journée.
  String get maintenant {
    var plusRecent = DateTime.utc(
      2026,
      11,
      9,
      10,
    ).add(Duration(milliseconds: _horloge));
    void voir(Iterable<Map<String, dynamic>> lignes) {
      for (final l in lignes) {
        for (final cle in const ['updated_at', 'serveur_modifie_le']) {
          final v = l[cle];
          final t = v is String ? DateTime.tryParse(v)?.toUtc() : null;
          if (t != null && t.isAfter(plusRecent)) plusRecent = t;
        }
      }
    }

    voir(modules.values);
    voir(produits.values);
    voir(clients.values);
    voir(ventes.values);
    voir(fournisseurs.values);
    voir(achats.values);
    voir(intrants.values);
    voir(mouvements.values);
    voir(mouvementsProduit.values);
    voir(comptes.values);
    voir(exercices.values);
    voir(pieces.values);
    voir(notes.values);
    voir(cloturesMois.values);
    voir(baremes.values);
    voir(taux.values);
    voir(echeances.values);
    voir(soins.values);
    voir(infirmerie.values);
    voir(machines.values);
    voir(cycles.values);
    voir(messagesEditeur.values);
    voir(factures.values);
    voir(devis.values);
    voir(groupesTaxe.values);
    voir(fichesJournee.values);
    voir(ventesJour.values);
    voir(bandes.values);
    if (parametres != null) voir([parametres!]);
    return plusRecent.toIso8601String();
  }

  void remettreAZero() {
    clients.clear();
    ventes.clear(); // les produits (référentiel) sont préservés
    achats.clear();
    fournisseurs.clear();
    mouvementsProduit.clear();
    soins
        .clear(); // les barèmes, taux et échéances (référentiels) sont préservés
    infirmerie.clear();
    factures.clear(); // la grille de taxation (référentiel) est préservée
    devis.clear();
    fichesJournee.clear();
    ventesJour.clear();
    bandes.clear();
    mouvements.clear(); // les intrants (référentiel) sont préservés
    pieces.clear(); // le plan est préservé, les exercices sont ROUVERTS
    notes.clear();
    cloturesMois.clear();
    for (final e in exercices.values) {
      e
        ..['is_cloture'] = false
        ..['date_cloture'] = null
        ..['updated_at'] = _instant();
    }
    cycles.clear();
    machines.clear();
    messagesEditeur.clear();
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
          return _dans(c['serveur_modifie_le'] as String, since, jusqua);
        }).toList()..sort((a, b) {
          final c = DateTime.parse(
            a['serveur_modifie_le'] as String,
          ).compareTo(DateTime.parse(b['serveur_modifie_le'] as String));
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
        'fournisseurs': [
          for (final f in fournisseurs.values)
            if (_dans(f['serveur_modifie_le'] as String, since, jusqua)) f,
        ],
        'achats': [
          for (final x in achats.values)
            if (_dans(x['serveur_modifie_le'] as String, since, jusqua)) x,
        ],
        'intrants': [
          for (final i in intrants.values)
            if (_dans(i['updated_at'] as String, since, jusqua)) i,
        ],
        'mouvements_intrant': [
          for (final m in mouvements.values)
            if (_dans(m['serveur_modifie_le'] as String, since, jusqua)) m,
        ],
        'plan_comptable': [
          for (final c in comptes.values)
            if (_dans(c['updated_at'] as String, since, jusqua)) c,
        ],
        'exercice_comptable': [
          for (final e in exercices.values)
            if (_dans(e['updated_at'] as String, since, jusqua)) e,
        ],
        'ecriture_comptable': [
          for (final p in pieces.values)
            if (_dans(p['serveur_modifie_le'] as String, since, jusqua)) p,
        ],
        'notes_annexes': [
          for (final n in notes.values)
            if (_dans(n['serveur_modifie_le'] as String, since, jusqua)) n,
        ],
        'clotures_periodiques': [
          for (final c in cloturesMois.values)
            if (_dans(c['serveur_modifie_le'] as String, since, jusqua)) c,
        ],
        'baremes_ration': [
          for (final b in baremes.values)
            if (_dans(b['updated_at'] as String, since, jusqua)) b,
        ],
        'taux_ration_poids': [
          for (final t in taux.values)
            if (_dans(t['updated_at'] as String, since, jusqua)) t,
        ],
        'calendrier_prophylaxie': [
          for (final e in echeances.values)
            if (_dans(e['updated_at'] as String, since, jusqua)) e,
        ],
        'soins_calendrier': [
          for (final x in soins.values)
            if (_dans(x['serveur_modifie_le'] as String, since, jusqua)) x,
        ],
        'infirmerie': [
          for (final x in infirmerie.values)
            if (_dans(x['serveur_modifie_le'] as String, since, jusqua)) x,
        ],
        'machines_incubateur': [
          for (final m in machines.values)
            if (_dans(m['serveur_modifie_le'] as String, since, jusqua)) m,
        ],
        'cycle_couveuse': [
          for (final c in cycles.values)
            if (_dans(c['serveur_modifie_le'] as String, since, jusqua)) c,
        ],
        'messages_editeur': [
          for (final m in messagesEditeur.values)
            if (_dans(m['serveur_modifie_le'] as String, since, jusqua)) m,
        ],
        'mouvements_produit': [
          for (final m in mouvementsProduit.values)
            if (_dans(m['serveur_modifie_le'] as String, since, jusqua)) m,
        ],
        'groupes_taxe': [
          for (final g in groupesTaxe.values)
            if (_dans(g['updated_at'] as String, since, jusqua)) g,
        ],
        'factures': [
          for (final f in factures.values)
            if (_dans(f['serveur_modifie_le'] as String, since, jusqua)) f,
        ],
        'devis': [
          for (final d in devis.values)
            if (_dans(d['serveur_modifie_le'] as String, since, jusqua)) d,
        ],
        'fiche_journee': [
          for (final f in fichesJournee.values)
            if (_dans(f['serveur_modifie_le'] as String, since, jusqua)) f,
        ],
        'fiche_ventes_jour': [
          for (final f in ventesJour.values)
            if (_dans(f['serveur_modifie_le'] as String, since, jusqua)) f,
        ],
        'bandes': [
          for (final b in bandes.values)
            if (_dans(b['serveur_modifie_le'] as String, since, jusqua)) b,
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
      if (d['type'] == 'intrant') {
        final donnees = d['donnees'] as Map<String, dynamic>;
        if (donnees.containsKey('stock') || donnees.containsKey('pmp')) {
          acceptees.remove(d['id']);
          refusees.add({
            'id': d['id'] as String,
            'motif':
                'Le stock n\'est pas synchronisé : il reste propre à chaque poste.',
          });
          continue;
        }
        _intrant(d);
        continue;
      }
      if (d['type'] == 'compte_comptable') {
        final motif = _compte(d);
        if (motif != null) {
          acceptees.remove(d['id']);
          refusees.add({'id': d['id'] as String, 'motif': motif});
        }
        continue;
      }
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
      if (const [
        'bareme_ration',
        'taux_ration_poids',
        'echeance_prophylaxie',
      ].contains(d['type'])) {
        final motif = _parametreElevage(d);
        if (motif != null) {
          acceptees.remove(d['id']);
          refusees.add({'id': d['id'] as String, 'motif': motif});
        }
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

  /// Compare des INSTANTS, pas des textes : `…625Z` se range après `…625655Z`
  /// en ordre lexicographique, alors qu'il lui est antérieur.
  bool _dans(String instant, String? since, String jusqua) {
    final t = DateTime.parse(instant);
    return (since == null || t.isAfter(DateTime.parse(since))) &&
        !t.isAfter(DateTime.parse(jusqua));
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
    final crochet = pendantEnvoi;
    if (crochet != null) {
      pendantEnvoi = null; // retiré AVANT l'appel : le crochet peut se ré-armer
      await crochet();
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
    final tables = corps['tables'] as Map;
    if (tables.containsKey('fournisseurs')) {
      reponse['fournisseurs'] = _fournisseurs(
        (tables['fournisseurs'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('mouvements_intrant')) {
      reponse['mouvements_intrant'] = _mouvements(
        (tables['mouvements_intrant'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('machines_incubateur')) {
      reponse['machines_incubateur'] = _machines(
        (tables['machines_incubateur'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('messages_editeur')) {
      reponse['messages_editeur'] = _messagesEditeur(
        (tables['messages_editeur'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('cycle_couveuse')) {
      reponse['cycle_couveuse'] = _cycles(
        (tables['cycle_couveuse'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('devis')) {
      reponse['devis'] = _devis(
        (tables['devis'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('factures')) {
      reponse['factures'] = _factures(
        (tables['factures'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('mouvements_produit')) {
      reponse['mouvements_produit'] = _mouvementsProduit(
        (tables['mouvements_produit'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('ecriture_comptable')) {
      reponse['ecriture_comptable'] = _pieces(
        (tables['ecriture_comptable'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('notes_annexes')) {
      reponse['notes_annexes'] = _notes(
        (tables['notes_annexes'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('clotures_periodiques')) {
      reponse['clotures_periodiques'] = _cloturesMois(
        (tables['clotures_periodiques'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('clotures_exercice')) {
      reponse['clotures_exercice'] = _cloturesExercice(
        (tables['clotures_exercice'] as List).cast<Map<String, dynamic>>(),
      );
    }
    if (tables.containsKey('soins_calendrier')) {
      reponse['soins_calendrier'] = _soins(
        (tables['soins_calendrier'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('infirmerie')) {
      reponse['infirmerie'] = _infirmerie(
        (tables['infirmerie'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('fiche_journee')) {
      reponse['fiche_journee'] = _fichesJournee(
        (tables['fiche_journee'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('fiche_ventes_jour')) {
      reponse['fiche_ventes_jour'] = _ventesJour(
        (tables['fiche_ventes_jour'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('bandes')) {
      reponse['bandes'] = _bandes(
        (tables['bandes'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
    if (tables.containsKey('achats')) {
      reponse['achats'] = _achats(
        (tables['achats'] as List).cast<Map<String, dynamic>>(),
        corps['device_id'] as String,
      );
    }
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
    var donnees = demande['donnees'] as Map<String, dynamic>;
    final saisie = demande['saisi_le'] as String;
    final id = donnees['id'] as String;
    // Pierre tombale : `archive` devient `archive_le` (jamais d'effacement).
    final archive = donnees['archive'] == true;
    donnees = {...donnees}..remove('archive');
    donnees['archive_le'] = archive ? saisie : null;
    final existant = produits[id];
    if (existant == null) {
      ajouterProduit(donnees, saisiLe: saisie);
      return;
    }
    final identique = donnees.entries.every(
      (e) => e.key == 'archive_le'
          ? (existant[e.key] != null) == (e.value != null)
          : existant[e.key] == e.value,
    );
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
    bool codee(String ref) => RegExp(r'^V-(P\d+|WEB)-\d{4}-\d{3,}$').hasMatch(ref);

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

  // ===================================================================== P8
  // Comptabilité : rejoue les règles du vrai serveur (`EcrituresTable`,
  // `ClotureExerciceTable`, …).

  /// Semis du plan : tous les postes installés du même programme l'ont à l'identique.
  /// `decide: false` = valeur de semis (`updated_at == created_at`).
  void ajouterCompte(
    String numero,
    String libelle,
    String classe, {
    bool archive = false,
    bool decide = false,
    String? saisiLe,
  }) {
    final cree = _instant();
    comptes[numero] = {
      'numero_compte': numero,
      'libelle': libelle,
      'classe': classe,
      'archive': archive,
      'saisi_le': saisiLe,
      'created_at': cree,
      'updated_at': decide ? _instant() : cree,
    };
  }

  void ajouterExercice(int annee, {bool clos = false}) {
    exercices[annee] = {
      'annee': annee,
      'is_cloture': clos,
      'date_cloture': clos
          ? DateTime.utc(annee + 1, 1, 5).toIso8601String()
          : null,
      'updated_at': _instant(),
    };
  }

  /// Une pièce saisie par un autre poste, déjà acceptée par le serveur.
  void ajouterPiece(
    String id, {
    required int annee,
    required DateTime date,
    required String numeroPiece,
    required List<Map<String, dynamic>> lignes,
    String deviceId = 'autre-poste',
    String journal = 'OD',
    String? venteRef,
    String? achatRef,
    String? contrepasseDe,
  }) {
    pieces[id] = {
      'id': id,
      'device_id': deviceId,
      'numero_piece': numeroPiece,
      'date_ecriture': date.toUtc().toIso8601String(),
      'exercice_annee': annee,
      'journal_code': journal,
      'vente_ref': venteRef,
      'achat_ref': achatRef,
      'contrepasse_de': contrepasseDe,
      'updated_at': _instant(),
      'serveur_modifie_le': _instant(),
      'lignes': lignes,
    };
  }

  String? _compte(Map<String, dynamic> demande) {
    final d = demande['donnees'] as Map<String, dynamic>;
    final numero = d['numero_compte'] as String;
    final saisie = demande['saisi_le'] as String;
    final existant = comptes[numero];
    if (existant == null) {
      ajouterCompte(
        numero,
        d['libelle'] as String,
        d['classe'] as String,
        archive: d['archive'] == true,
        decide: true,
        saisiLe: saisie,
      );
      return null;
    }
    final identique =
        existant['libelle'] == d['libelle'] &&
        existant['classe'] == d['classe'] &&
        existant['archive'] == (d['archive'] == true);
    if (identique) return null;
    final dernier = existant['saisi_le'] as String?;
    if (dernier != null &&
        !DateTime.parse(saisie).isAfter(DateTime.parse(dernier))) {
      return 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.';
    }
    existant
      ..['libelle'] = d['libelle']
      ..['classe'] = d['classe']
      ..['archive'] = d['archive'] == true
      ..['saisi_le'] = saisie
      ..['updated_at'] = _instant();
    return null;
  }

  /// Mois comptable d'un instant, dans le fuseau du serveur (Africa/Porto-Novo, UTC+1).
  (int, int) _anneeMois(String iso) {
    final t = DateTime.parse(iso).toUtc().add(const Duration(hours: 1));
    return (t.year, t.month);
  }

  Map<String, dynamic> _pieces(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final p in lot) {
      final id = p['id'] as String;
      final lignes = (p['lignes'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      if (pieces.containsKey(id)) {
        acceptees.add(id); // fait immuable : rejeu accepté sans rien changer
        continue;
      }
      if (lignes.length < 2) {
        refusees.add({
          'id': id,
          'motif': 'Une pièce comptable doit avoir au moins deux lignes.',
        });
        continue;
      }
      var debit = 0.0;
      var credit = 0.0;
      String? erreur;
      for (final l in lignes) {
        final d = (l['debit'] as num).toDouble();
        final c = (l['credit'] as num).toDouble();
        if (d < 0 || c < 0 || (d > 0) == (c > 0)) {
          erreur =
              'Une ligne porte un débit OU un crédit, jamais les deux ni aucun.';
        }
        if (!comptes.containsKey(l['numero_compte'])) {
          erreur = 'Compte inconnu du serveur : « ${l['numero_compte']} ».';
        }
        debit += d;
        credit += c;
      }
      if (erreur == null && (debit - credit).abs() > 0.01) {
        erreur =
            'Pièce déséquilibrée : débit ${debit.toStringAsFixed(0)} ≠ crédit ${credit.toStringAsFixed(0)}.';
      }
      final (annee, mois) = _anneeMois(p['date_ecriture'] as String);
      if (erreur == null && annee != p['exercice_annee']) {
        erreur = 'L\'exercice de la pièce ne correspond pas à sa date.';
      }
      if (erreur == null) {
        final e = exercices[annee];
        if (e != null && e['is_cloture'] == true) {
          erreur =
              'L\'exercice $annee est clôturé : aucune écriture ne peut y être ajoutée (BR-CPT-001).';
        }
      }
      if (erreur == null) {
        final m = cloturesMois.values.where(
          (c) =>
              c['annee'] == annee &&
              c['mois'] == mois &&
              c['is_cloture'] == true,
        );
        if (m.isNotEmpty) {
          erreur = 'Le mois $mois/$annee est clôturé (BR-CPT-006).';
        }
      }
      if (erreur != null) {
        refusees.add({'id': id, 'motif': erreur});
        continue;
      }
      exercices.putIfAbsent(
        annee,
        () => {
          'annee': annee,
          'is_cloture': false,
          'date_cloture': null,
          'updated_at': _instant(),
        },
      );
      pieces[id] = {
        ...p,
        'device_id': deviceId,
        'serveur_modifie_le': _instant(),
      };
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  Map<String, dynamic> _notes(List<Map<String, dynamic>> lot, String deviceId) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final n in lot) {
      final cle = '${n['exercice_annee']}-${n['numero_note']}';
      final saisie = DateTime.parse(n['updated_at'] as String);
      final existante = notes[cle];
      if (existante == null) {
        notes[cle] = {
          ...n,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
      } else if (saisie.isAfter(
        DateTime.parse(existante['updated_at'] as String),
      )) {
        existante
          ..['titre'] = n['titre']
          ..['contenu'] = n['contenu']
          ..['device_id'] = deviceId
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      }
      acceptees.add(n['id'] as String);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  Map<String, dynamic> _cloturesMois(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    for (final c in lot) {
      final id = c['id'] as String;
      final saisie = DateTime.parse(c['updated_at'] as String);
      final existante = cloturesMois[id];
      if (existante == null ||
          saisie.isAfter(DateTime.parse(existante['updated_at'] as String))) {
        cloturesMois[id] = {
          ...c,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': <Object>[], 'ignored': []};
  }

  Map<String, dynamic> _cloturesExercice(List<Map<String, dynamic>> lot) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final c in lot) {
      final id = c['id'] as String;
      final annee = c['annee'] as int;
      if (!clotureExerciceAutorisee) {
        refusees.add({
          'id': id,
          'motif':
              'Droit insuffisant pour clôturer un exercice (close-fiscal-year).',
        });
        continue;
      }
      var debit = 0.0;
      var credit = 0.0;
      for (final p in pieces.values.where(
        (p) => p['exercice_annee'] == annee,
      )) {
        for (final l in (p['lignes'] as List).cast<Map<String, dynamic>>()) {
          debit += (l['debit'] as num).toDouble();
          credit += (l['credit'] as num).toDouble();
        }
      }
      if ((debit - credit).abs() > 0.01) {
        refusees.add({
          'id': id,
          'motif':
              'Balance déséquilibrée : une clôture annuelle est définitive (BR-CPT-004).',
        });
        continue;
      }
      final e = exercices.putIfAbsent(
        annee,
        () => {
          'annee': annee,
          'is_cloture': false,
          'date_cloture': null,
          'updated_at': _instant(),
        },
      );
      if (e['is_cloture'] != true) {
        e
          ..['is_cloture'] = true
          ..['date_cloture'] = c['date_cloture']
          ..['updated_at'] = _instant();
        exercices.putIfAbsent(
          annee + 1,
          () => {
            'annee': annee + 1,
            'is_cloture': false,
            'date_cloture': null,
            'updated_at': _instant(),
          },
        );
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  // ------------------------------------------------ Paramètres d'élevage (P7c)

  static final RegExp _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static const List<String> _statutsSoin = [
    'Planifié',
    'Effectué',
    'En retard',
    'Traitement en cours',
  ];
  static const List<String> _niveaux = [
    'Simple surveillance',
    'Infirmerie',
    'Quarantaine stricte',
  ];
  static const List<String> _statutsInfirmerie = [
    'En cours',
    'Réintégré',
    'Décédé',
  ];

  /// Un barème tel que le serveur le garde (référentiel : `saisi_le`, `archive_le`).
  void ajouterBareme(Map<String, dynamic> b, {String? saisiLe}) {
    baremes[b['id'] as String] = {
      'archive_le': null,
      ...b,
      'saisi_le': saisiLe ?? _instant(),
      'created_at': _instant(),
      'updated_at': _instant(),
    };
  }

  void ajouterTaux(Map<String, dynamic> t, {String? saisiLe}) {
    taux[t['id'] as String] = {
      'archive_le': null,
      ...t,
      'saisi_le': saisiLe ?? _instant(),
      'created_at': _instant(),
      'updated_at': _instant(),
    };
  }

  void ajouterEcheance(Map<String, dynamic> e, {String? saisiLe}) {
    echeances[e['id'] as String] = {
      'archive_le': null,
      ...e,
      'saisi_le': saisiLe ?? _instant(),
      'created_at': _instant(),
      'updated_at': _instant(),
    };
  }

  /// Rejoue `DemandesReferentiel::bareme/tauxPoids/echeance` : validation, clé
  /// naturelle, identique accepté sans rien changer, plus ancien refusé, pierre
  /// tombale. Renvoie le motif du refus, ou `null`.
  String? _parametreElevage(Map<String, dynamic> demande) {
    final type = demande['type'] as String;
    final saisie = demande['saisi_le'] as String;
    var d = demande['donnees'] as Map<String, dynamic>;
    final archive = d['archive'] == true;
    d = {...d}..remove('archive');

    String? texte(String c) =>
        d[c] is String && (d[c] as String).trim().isNotEmpty
        ? d[c] as String
        : null;
    if (d['id'] is! String || !_uuidRe.hasMatch(d['id'] as String)) {
      return "L'identifiant de la ligne doit être un UUID.";
    }
    final id = d['id'] as String;
    if (texte('espece') == null) return "L'espèce est obligatoire.";

    final Map<String, Map<String, dynamic>> magasin;
    final List<String> champs;
    if (type == 'bareme_ration') {
      magasin = baremes;
      champs = const ['espece', 'stade', 'ration_grammes_par_jour', 'confirme'];
      final ration = d['ration_grammes_par_jour'];
      if (texte('stade') == null) return 'Le stade du barème est obligatoire.';
      if (ration is! int || ration < 1 || ration > 20000) {
        return 'La ration doit être comprise entre 1 et 20 000 g par jour.';
      }
      if (d['confirme'] is! bool) return 'Le statut du barème est invalide.';
    } else if (type == 'taux_ration_poids') {
      magasin = taux;
      champs = const [
        'espece',
        'poids_min_g',
        'poids_max_g',
        'taux_pourcent',
        'confirme',
      ];
      final min = d['poids_min_g'];
      final max = d['poids_max_g'];
      if (min is! int || min < 0) return 'Le poids minimal est invalide.';
      if (max != null && (max is! int || max <= min)) {
        return 'Le poids maximal doit dépasser le poids minimal.';
      }
      final t = d['taux_pourcent'];
      if (t is! num || t <= 0 || t > 25) {
        return 'Le taux doit être compris entre 0 et 25 % du poids vif par jour.';
      }
      if (d['confirme'] is! bool) return 'Le statut du taux est invalide.';
    } else {
      magasin = echeances;
      champs = const [
        'espece',
        'jour_cycle',
        'traitement',
        'produit',
        'remanence_jours',
        'dose',
      ];
      final jour = d['jour_cycle'];
      if (jour is! int || jour < 1 || jour > 365) {
        return 'Le jour du cycle doit être compris entre 1 et 365.';
      }
      if (texte('traitement') == null || texte('produit') == null) {
        return 'Le traitement et le produit sont obligatoires.';
      }
      final r = d['remanence_jours'];
      if (r is! int || r < 0) return 'La rémanence ne peut pas être négative.';
    }

    // Clé naturelle : une autre ligne (autre UUID) ne peut pas la porter.
    final conflit = magasin.values.any((x) {
      if (x['id'] == id) return false;
      if (type == 'bareme_ration') {
        return x['espece'] == d['espece'] && x['stade'] == d['stade'];
      }
      if (type == 'taux_ration_poids') {
        return x['espece'] == d['espece'] &&
            x['poids_min_g'] == d['poids_min_g'];
      }
      return false;
    });
    if (conflit) {
      return type == 'bareme_ration'
          ? 'Un barème existe déjà pour ce stade.'
          : 'Une classe de poids existe déjà avec ce poids minimal.';
    }

    final existant = magasin[id];
    final nouveau = {for (final c in champs) c: d[c]};
    if (existant == null) {
      magasin[id] = {
        'id': id,
        ...nouveau,
        'archive_le': archive ? saisie : null,
        'saisi_le': saisie,
        'created_at': _instant(),
        'updated_at': _instant(),
      };
      return null;
    }
    final identique =
        champs.every((c) => existant[c] == nouveau[c]) &&
        (existant['archive_le'] != null) == archive;
    if (identique) return null;
    if (!DateTime.parse(
      saisie,
    ).isAfter(DateTime.parse(existant['saisi_le'] as String))) {
      return 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.';
    }
    existant
      ..addAll(nouveau)
      ..['archive_le'] = archive ? saisie : null
      ..['saisi_le'] = saisie
      ..['updated_at'] = _instant();
    return null;
  }

  bool _jourValide(Object? v) =>
      v is String &&
      v.length >= 10 &&
      DateTime.tryParse(v.substring(0, 10)) != null;

  /// Rejoue `SoinsCalendrierTable::absorber` : validation stricte, échéance connue,
  /// dernier écrivain gagne (strictement).
  Map<String, dynamic> _soins(List<Map<String, dynamic>> lot, String deviceId) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final l in lot) {
      final id = l['id'];
      String? motif;
      if (id is! String || !_uuidRe.hasMatch(id)) {
        motif = "L'identifiant de la ligne doit être un UUID.";
      } else if (l['updated_at'] is! String ||
          DateTime.tryParse(l['updated_at'] as String) == null) {
        motif = 'La date de saisie de la ligne est invalide.';
      } else if (l['espece'] is! String ||
          (l['espece'] as String).trim().isEmpty) {
        motif = "L'espèce du soin est obligatoire.";
      } else if (!_jourValide(l['date_prevue'])) {
        motif = 'La date prévue du soin est invalide.';
      } else if (l['type_soin'] is! String ||
          (l['type_soin'] as String).trim().isEmpty) {
        motif = "Le type d'action est obligatoire.";
      } else if (!_statutsSoin.contains(l['statut'])) {
        motif = 'Le statut du soin est invalide.';
      } else if (l['remanence_jours'] is! int ||
          (l['remanence_jours'] as int) < 0) {
        motif = 'La rémanence ne peut pas être négative.';
      } else if (l['cout_fcfa'] is! int || (l['cout_fcfa'] as int) < 0) {
        motif = 'Le coût ne peut pas être négatif.';
      } else if (l['echeance_prophylaxie_id'] != null &&
          !echeances.containsKey(l['echeance_prophylaxie_id'])) {
        motif = 'Échéance de prophylaxie inconnue du serveur.';
      }
      if (motif != null) {
        refusees.add({'id': '$id', 'motif': motif});
        continue;
      }
      final cle = id! as String;
      final saisie = DateTime.parse(l['updated_at'] as String);
      final existant = soins[cle];
      final ligne = {
        for (final c in const [
          'espece',
          'date_prevue',
          'type_soin',
          'statut',
          'observations',
          'produit',
          'dose',
          'remanence_jours',
          'veterinaire',
          'symptomes',
          'cout_fcfa',
          'echeance_prophylaxie_id',
        ])
          c: l[c],
      };
      if (existant == null) {
        soins[cle] = {
          'id': cle,
          ...ligne,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
      } else if (saisie.isAfter(
        DateTime.parse(existant['updated_at'] as String),
      )) {
        existant
          ..addAll(ligne)
          ..['device_id'] = deviceId
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      } // sinon : rejeu ou saisie plus ancienne — acceptée sans rien changer
      acceptees.add(cle);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  /// Rejoue `InfirmerieTable::absorber`.
  Map<String, dynamic> _infirmerie(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final l in lot) {
      final id = l['id'];
      String? motif;
      final statut = l['statut'];
      if (id is! String || !_uuidRe.hasMatch(id)) {
        motif = "L'identifiant de la ligne doit être un UUID.";
      } else if (l['updated_at'] is! String ||
          DateTime.tryParse(l['updated_at'] as String) == null) {
        motif = 'La date de saisie de la ligne est invalide.';
      } else if (!_jourValide(l['date_entree'])) {
        motif = "La date d'entrée est invalide.";
      } else if (l['date_sortie'] != null && !_jourValide(l['date_sortie'])) {
        motif = 'La date de sortie est invalide.';
      } else if (l['sujet'] is! String ||
          (l['sujet'] as String).trim().isEmpty) {
        motif = 'Le sujet est obligatoire.';
      } else if (l['motif'] is! String ||
          (l['motif'] as String).trim().isEmpty) {
        motif = 'Le motif est obligatoire.';
      } else if (!_niveaux.contains(l['niveau_isolement'])) {
        motif = "Ce niveau d'isolement n'existe pas.";
      } else if (!_statutsInfirmerie.contains(statut)) {
        motif = "Le statut de l'entrée est invalide.";
      } else if (l['date_sortie'] != null &&
          (l['date_sortie'] as String)
                  .substring(0, 10)
                  .compareTo((l['date_entree'] as String).substring(0, 10)) <
              0) {
        motif = "La sortie ne peut précéder l'entrée.";
      } else if (statut != 'En cours' && l['date_sortie'] == null) {
        motif = 'Une entrée clôturée doit avoir une date de sortie.';
      } else if (statut == 'En cours' && l['date_sortie'] != null) {
        motif = "Une entrée en cours n'a pas de date de sortie.";
      } else if (l['categorie_mortalite'] != null &&
          (l['categorie_mortalite'] is! int ||
              (l['categorie_mortalite'] as int) < 0 ||
              statut != 'Décédé')) {
        motif = 'La marque de mortalité ne vaut que pour un sujet décédé.';
      }
      if (motif != null) {
        refusees.add({'id': '$id', 'motif': motif});
        continue;
      }
      final cle = id! as String;
      final saisie = DateTime.parse(l['updated_at'] as String);
      final existant = infirmerie[cle];
      final ligne = {
        for (final c in const [
          'date_entree',
          'sujet',
          'motif',
          'niveau_isolement',
          'statut',
          'date_sortie',
          'espece',
          'categorie_mortalite',
        ])
          c: l[c],
      };
      if (existant == null) {
        infirmerie[cle] = {
          'id': cle,
          ...ligne,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
      } else if (saisie.isAfter(
        DateTime.parse(existant['updated_at'] as String),
      )) {
        existant
          ..addAll(ligne)
          ..['device_id'] = deviceId
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      }
      acceptees.add(cle);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  /// Un incubateur déjà connu du serveur (saisi par un autre poste).
  void ajouterMachine(
    String id,
    String code, {
    String libelle = 'Couveuse',
    int? capacite,
    bool active = true,
    String? updatedAt,
  }) {
    machines[id] = {
      'id': id,
      'device_id': 'autre-poste',
      'code': code,
      'libelle': libelle,
      'capacite_oeufs': capacite,
      'active': active,
      'updated_at': updatedAt ?? _instant(),
      'serveur_modifie_le': _instant(),
      'supprime_le': null,
    };
  }

  /// Un lot déjà connu du serveur (saisi par un autre poste).
  void ajouterCycle(
    String id,
    String code, {
    String espece = 'goliath',
    String date = '2026-08-01',
    int charges = 100,
    String statut = 'En Incubation',
    String? machineId,
    int? blancs,
    int? gates,
    int? eclos,
    int? perdus,
    String? parentId,
    String? updatedAt,
    String? supprimeLe,
  }) {
    cycles[id] = {
      'id': id,
      'device_id': 'autre-poste',
      'code_incubation': code,
      'espece': espece,
      'date_incubation': date,
      'oeufs_couves': charges,
      'poussins_nes': eclos,
      'oeufs_perdus': perdus,
      'statut': statut,
      'machine_id': machineId,
      'oeufs_blancs_j7': blancs,
      'oeufs_gates_j14': gates,
      'lot_parent_id': parentId,
      'updated_at': updatedAt ?? _instant(),
      'serveur_modifie_le': _instant(),
      'supprime_le': supprimeLe,
    };
  }

  /// Rejoue les règles du vrai serveur (`MessagesEditeurTable`) : type et statut
  /// permis, objet et message obligatoires, dernier écrivain gagne, pierre tombale.
  Map<String, dynamic> _messagesEditeur(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final m in lot) {
      final id = m['id'] as String;
      String? motif;
      if (m['type'] is! String || !['question', 'bug'].contains(m['type'])) {
        motif = 'Le type du message est inconnu (question ou problème).';
      } else if (m['sujet'] is! String ||
          (m['sujet'] as String).trim().isEmpty) {
        motif = 'L\'objet est obligatoire.';
      } else if (m['message'] is! String ||
          (m['message'] as String).trim().isEmpty) {
        motif = 'Le message est obligatoire.';
      } else if (m['statut'] is! String ||
          !['En attente', 'Transmis'].contains(m['statut'])) {
        motif = 'Le statut du message est inconnu.';
      }
      if (motif != null) {
        refusees.add({'id': id, 'motif': motif});
        continue;
      }
      final saisie = DateTime.parse(m['updated_at'] as String);
      final existant = messagesEditeur[id];
      final valeurs = {
        'horodatage': m['horodatage'],
        'type': m['type'],
        'sujet': (m['sujet'] as String).trim(),
        'message': (m['message'] as String).trim(),
        'etapes': m['etapes'],
        'auteur': m['auteur'],
        'statut': m['statut'],
        'supprime_le': m['supprime_le'],
      };
      if (existant == null) {
        messagesEditeur[id] = {
          'id': id,
          'device_id': deviceId,
          ...valeurs,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
      } else if (saisie.isAfter(
        DateTime.parse(existant['updated_at'] as String),
      )) {
        existant
          ..addAll(valeurs)
          ..['device_id'] = deviceId
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  /// Rejoue les règles du vrai serveur (`MachinesIncubateurTable`) : champs
  /// obligatoires, code unique (jamais fusionné), dernier écrivain gagne.
  Map<String, dynamic> _machines(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final m in lot) {
      final id = m['id'] as String;
      final code = m['code'];
      final libelle = m['libelle'];
      final capacite = m['capacite_oeufs'];
      if (code is! String || code.trim().isEmpty) {
        refusees.add({
          'id': id,
          'motif': 'Le code de l\'incubateur est obligatoire.',
        });
        continue;
      }
      if (libelle is! String || libelle.trim().isEmpty) {
        refusees.add({
          'id': id,
          'motif': 'Le libellé de l\'incubateur est obligatoire.',
        });
        continue;
      }
      if (capacite != null && (capacite is! int || capacite < 1)) {
        refusees.add({
          'id': id,
          'motif': 'La capacité doit être supérieure à 0.',
        });
        continue;
      }
      if (m['active'] is! bool) {
        refusees.add({
          'id': id,
          'motif': 'L\'état de l\'incubateur est invalide.',
        });
        continue;
      }
      final homonyme = machines.values.any(
        (x) =>
            x['id'] != id &&
            (x['code'] as String).toLowerCase() == code.trim().toLowerCase(),
      );
      if (homonyme) {
        refusees.add({
          'id': id,
          'motif': 'Un incubateur porte déjà le code ${code.trim()}.',
        });
        continue;
      }
      final saisie = DateTime.parse(m['updated_at'] as String);
      final existant = machines[id];
      if (existant == null) {
        machines[id] = {
          'id': id,
          'device_id': deviceId,
          'code': code.trim(),
          'libelle': libelle.trim(),
          'capacite_oeufs': capacite,
          'active': m['active'],
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
          'supprime_le': null,
        };
      } else if (saisie.isAfter(
        DateTime.parse(existant['updated_at'] as String),
      )) {
        existant
          ..['code'] = code.trim()
          ..['libelle'] = libelle.trim()
          ..['capacite_oeufs'] = capacite
          ..['active'] = m['active']
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  /// Rejoue les règles du vrai serveur (`CyclesCouveuseTable`) : valeurs permises,
  /// compteurs cohérents, incubateur connu, code unique (global avec code de poste,
  /// par poste sinon, hors lots supprimés), dernier écrivain gagne, pierre tombale.
  Map<String, dynamic> _cycles(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    bool codee(String c) => RegExp(r'^C-P\d+-\d{4}-\d{3,}$').hasMatch(c);
    const champs = [
      'code_incubation',
      'espece',
      'date_incubation',
      'oeufs_couves',
      'poussins_nes',
      'oeufs_perdus',
      'statut',
      'machine_id',
      'oeufs_blancs_j7',
      'oeufs_gates_j14',
      'lot_parent_id',
      'supprime_le',
    ];

    for (final c in lot) {
      final id = c['id'] as String;
      String? motif;
      final code = c['code_incubation'];
      final charges = c['oeufs_couves'];
      int? n(String cle) => c[cle] is int ? c[cle] as int : null;
      if (code is! String || code.trim().isEmpty) {
        motif = 'Le code du lot est obligatoire.';
      } else if (c['espece'] != 'goliath' && c['espece'] != 'pintade') {
        motif = 'L\'espèce du lot est inconnue.';
      } else if (!const [
        'En Incubation',
        'Éclosion Effectuée',
        'Remplacé',
      ].contains(c['statut'])) {
        motif = 'Le statut du lot est inconnu.';
      } else if (charges is! int || charges < 1) {
        motif = 'Le nombre d\'œufs chargés est obligatoire.';
      } else if (c['date_incubation'] is! String) {
        motif = 'La date de chargement est obligatoire.';
      } else {
        for (final cle in const [
          'poussins_nes',
          'oeufs_perdus',
          'oeufs_blancs_j7',
          'oeufs_gates_j14',
        ]) {
          if (c[cle] != null && (c[cle] is! int || (c[cle] as int) < 0)) {
            motif = 'Les quantités ne peuvent être négatives.';
          }
        }
        if (motif == null) {
          final retenus =
              charges -
              (n('oeufs_blancs_j7') ?? 0) -
              (n('oeufs_gates_j14') ?? 0);
          if (retenus < 0) {
            motif =
                'Les mirages retirent plus d\'œufs que le lot n\'en contient.';
          } else if (n('poussins_nes') != null &&
              n('poussins_nes')! + (n('oeufs_perdus') ?? 0) > retenus) {
            motif =
                'Poussins éclos + œufs perdus dépasse les œufs encore en incubation.';
          }
        }
      }
      if (motif == null && c['lot_parent_id'] == id) {
        motif = 'Un lot ne peut pas se remplacer lui-même.';
      }
      if (motif == null &&
          cycles[id] != null &&
          cycles[id]!['code_incubation'] != (code as String).trim()) {
        motif = 'Le code d\'un lot ne change jamais.';
      }
      // Une pierre tombale ne demande ni incubateur connu ni code libre.
      final tombale = c['supprime_le'] != null;
      if (motif == null &&
          !tombale &&
          c['machine_id'] != null &&
          !machines.containsKey(c['machine_id'])) {
        motif = 'Incubateur inconnu du serveur.';
      }
      if (motif == null && !tombale) {
        final doublon = cycles.values.any(
          (x) =>
              x['id'] != id &&
              x['supprime_le'] == null &&
              x['code_incubation'] == (code as String).trim() &&
              (codee(code.trim()) || x['device_id'] == deviceId),
        );
        if (doublon) motif = 'Ce code est déjà utilisé par un autre lot.';
      }
      if (motif != null) {
        refusees.add({'id': id, 'motif': motif});
        continue;
      }

      final saisie = DateTime.parse(c['updated_at'] as String);
      final existant = cycles[id];
      if (existant == null) {
        cycles[id] = {
          for (final k in champs) k: c[k],
          'id': id,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
      } else if (saisie.isAfter(
        DateTime.parse(existant['updated_at'] as String),
      )) {
        for (final k in champs) {
          existant[k] = c[k];
        }
        existant
          ..['device_id'] = deviceId
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  Map<String, dynamic> _fournisseurs(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final f in lot) {
      final id = f['id'] as String;
      final nom = f['nom'];
      if (nom is! String || nom.trim().isEmpty) {
        refusees.add({
          'id': id,
          'motif': 'Le nom du fournisseur est obligatoire.',
        });
        continue;
      }
      final saisie = DateTime.parse(f['updated_at'] as String);
      final existant = fournisseurs[id];
      if (existant == null) {
        fournisseurs[id] = {
          ...f,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
          'supprime_le': null,
        };
      } else if (saisie.isAfter(
        DateTime.parse(existant['updated_at'] as String),
      )) {
        for (final c in const ['nom', 'telephone', 'adresse', 'fournit']) {
          existant[c] = f[c];
        }
        existant
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  /// Rejoue les règles du vrai serveur (`AchatsTable`).
  Map<String, dynamic> _achats(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    bool codee(String ref) =>
        RegExp(r'^ACH-(P\d+|WEB)-\d{4}-\d{3,}$').hasMatch(ref);

    for (final a in lot) {
      final id = a['id'] as String;
      final lignes = (a['lignes'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      if (lignes.isEmpty) {
        refusees.add({
          'id': id,
          'motif': 'Un achat doit avoir au moins une ligne.',
        });
        continue;
      }
      if (!fournisseurs.containsKey(a['fournisseur_id'])) {
        refusees.add({'id': id, 'motif': 'Fournisseur inconnu du serveur.'});
        continue;
      }
      final inconnuI = lignes.where(
        (l) => !intrants.containsKey(l['intrant_code']),
      );
      if (inconnuI.isNotEmpty) {
        refusees.add({
          'id': id,
          'motif':
              'Intrant inconnu du serveur : « ${inconnuI.first['intrant_code']} ».',
        });
        continue;
      }
      final ref = a['reference'] as String;
      final doublon = achats.values.any(
        (x) =>
            x['id'] != id &&
            x['reference'] == ref &&
            (codee(ref) || x['device_id'] == deviceId),
      );
      if (doublon) {
        refusees.add({
          'id': id,
          'motif': 'Cette référence est déjà utilisée par un autre achat.',
        });
        continue;
      }
      final saisie = DateTime.parse(a['updated_at'] as String);
      final existant = achats[id];
      if (existant == null) {
        achats[id] = {
          ...a,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
      } else if (saisie.isAfter(
        DateTime.parse(existant['updated_at'] as String),
      )) {
        // Les lignes ne se remplacent que tant que l'achat est « Commandé ».
        if (existant['statut'] == 'Commandé') existant['lignes'] = lignes;
        for (final c in const [
          'fournisseur_id',
          'statut',
          'total',
          'paye',
          'mode',
          'echeance',
        ]) {
          existant[c] = a[c];
        }
        existant
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  /// Un intrant tel que le serveur le garde (jamais de stock ni de PMP).
  void ajouterIntrant(Map<String, dynamic> i, {String? saisiLe}) {
    intrants[i['code'] as String] = {
      ...i,
      'saisi_le': saisiLe ?? _instant(),
      'created_at': _instant(),
      'updated_at': _instant(),
    };
  }

  void _intrant(Map<String, dynamic> demande) {
    final donnees = demande['donnees'] as Map<String, dynamic>;
    final saisie = demande['saisi_le'] as String;
    final code = donnees['code'] as String;
    final existant = intrants[code];
    if (existant == null) {
      ajouterIntrant(donnees, saisiLe: saisie);
      return;
    }
    if (donnees.entries.every((e) => existant[e.key] == e.value)) return;
    if (!DateTime.parse(
      saisie,
    ).isAfter(DateTime.parse(existant['saisi_le'] as String))) {
      return;
    }
    existant
      ..addAll(donnees)
      ..['saisi_le'] = saisie
      ..['updated_at'] = _instant();
  }

  /// Journal : faits IMMUABLES (rejeu accepté sans rien changer), intrant connu.
  Map<String, dynamic> _mouvements(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final m in lot) {
      final id = m['id'] as String;
      if (!intrants.containsKey(m['intrant_code'])) {
        refusees.add({
          'id': id,
          'motif': 'Intrant inconnu du serveur : « ${m['intrant_code']} ».',
        });
        continue;
      }
      if (!mouvements.containsKey(id)) {
        mouvements[id] = {
          ...m,
          'device_id': deviceId,
          'serveur_modifie_le': _instant(),
        };
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  /// Corrections de stock des produits : faits IMMUABLES, produit connu du serveur.
  Map<String, dynamic> _mouvementsProduit(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final m in lot) {
      final id = m['id'] as String;
      if (!produits.containsKey(m['produit_id'])) {
        refusees.add({
          'id': id,
          'motif': 'Produit inconnu du serveur : « ${m['produit_id']} ».',
        });
        continue;
      }
      if (!mouvementsProduit.containsKey(id)) {
        mouvementsProduit[id] = {
          ...m,
          'device_id': deviceId,
          'serveur_modifie_le': _instant(),
        };
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  /// Un groupe de taxe tel que le serveur le garde. `decide: false` : valeur de
  /// semis (`updated_at == created_at`), que le serveur n'a jamais modifiée.
  void ajouterGroupeTaxe(
    String code,
    String libelle,
    double taux, {
    int ordre = 1,
    bool decide = true,
    String? id,
  }) {
    final cree = _instant();
    groupesTaxe[code] = {
      'id': id,
      'code': code,
      'libelle': libelle,
      'taux': taux,
      'ordre': ordre,
      'created_at': cree,
      'updated_at': decide ? _instant() : cree,
    };
  }

  /// Une facture déjà reçue par le serveur, émise par un autre poste.
  void ajouterFacture(Map<String, dynamic> f, {String device = 'autre-poste'}) {
    factures[f['id'] as String] = {
      ...f,
      'device_id': device,
      'serveur_modifie_le': _instant(),
    };
  }

  static const _rang = {'a_transmettre': 0, 'rejetee': 1, 'normalisee': 2};

  /// Un devis déjà reçu par le serveur, émis par un autre poste (ou le web).
  void ajouterDevis(
    String id,
    String reference, {
    String client = 'Client',
    String objet = 'Prestation',
    double montant = 10000,
    int validiteJours = 15,
    String? dateEmission,
    String statut = 'emis',
    String? supprimeLe,
    String? updatedAt,
    String device = 'autre-poste',
  }) {
    devis[id] = {
      'id': id,
      'device_id': device,
      'reference': reference,
      'client': client,
      'objet': objet,
      'montant_estime': montant,
      'validite_jours': validiteJours,
      'date_emission': dateEmission ?? '2026-11-09T08:00:00.000000Z',
      'statut': statut,
      'supprime_le': supprimeLe,
      'updated_at': updatedAt ?? _instant(),
      'serveur_modifie_le': _instant(),
    };
  }

  /// Rejoue `DevisTable` : référence unique (globale si elle porte un code, sinon par
  /// poste), référence immuable, devis accepté figé, jamais supprimé une fois accepté.
  Map<String, dynamic> _devis(List<Map<String, dynamic>> lot, String deviceId) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    bool codee(String ref) =>
        RegExp(r'^DV-(P\d+|WEB)-\d{4}-\d{3,}$').hasMatch(ref);

    for (final d in lot) {
      final id = d['id'] as String;
      final ref = d['reference'] as String;
      final existant = devis[id];
      final saisie = DateTime.parse(d['updated_at'] as String);
      final doublon = devis.values.any(
        (x) =>
            x['id'] != id &&
            x['reference'] == ref &&
            (codee(ref) || x['device_id'] == deviceId),
      );
      if (doublon) {
        refusees.add({
          'id': id,
          'motif': 'Cette référence est déjà utilisée par un autre devis.',
        });
        continue;
      }
      if (existant == null) {
        devis[id] = {
          ...d,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
        acceptees.add(id);
        continue;
      }
      if (existant['reference'] != ref) {
        refusees.add({
          'id': id,
          'motif': 'La référence d\'un devis ne change jamais.',
        });
        continue;
      }
      if (existant['statut'] == 'accepte') {
        final change =
            existant['client'] != d['client'] ||
            existant['objet'] != d['objet'] ||
            existant['montant_estime'] != d['montant_estime'] ||
            existant['validite_jours'] != d['validite_jours'] ||
            d['supprime_le'] != null;
        if (change) {
          refusees.add({
            'id': id,
            'motif':
                'Un devis accepté ne se modifie plus et ne se supprime pas.',
          });
          continue;
        }
      }
      if (saisie.isAfter(DateTime.parse(existant['updated_at'] as String))) {
        existant
          ..addAll({
            for (final c in const [
              'client',
              'objet',
              'montant_estime',
              'validite_jours',
              'date_emission',
              'statut',
              'supprime_le',
            ])
              c: d[c],
          })
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  /// Rejoue les règles du vrai serveur (`FacturesTable`) : lot facture + lignes,
  /// référence unique, avoir sur une facture connue, UNE facture de vente par
  /// vente, contenu immuable, statut qui ne régresse jamais, normalisation
  /// immuable (deux codes différents : refus).
  Map<String, dynamic> _factures(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    bool codee(String? ref) =>
        ref != null && RegExp(r'^[A-Z]{2}-P\d+-\d{4}-\d{3,}$').hasMatch(ref);

    for (final f in lot) {
      final id = f['id'] as String;
      final lignes = (f['lignes'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      if (lignes.isEmpty) {
        refusees.add({
          'id': id,
          'motif': 'Une facture doit avoir au moins une ligne.',
        });
        continue;
      }
      final existante = factures[id];
      final ref = f['reference'] as String;
      final doublon = factures.values.any(
        (x) =>
            x['id'] != id &&
            x['reference'] == ref &&
            (codee(ref) || x['device_id'] == deviceId),
      );
      if (doublon) {
        refusees.add({
          'id': id,
          'motif': 'Cette référence est déjà utilisée par une autre facture.',
        });
        continue;
      }
      final saisie = DateTime.parse(f['updated_at'] as String);
      if (existante == null) {
        if (f['type'] == 'FA' &&
            !factures.values.any(
              (x) => x['type'] == 'FV' && x['reference'] == f['origine_ref'],
            )) {
          refusees.add({
            'id': id,
            'motif': 'La facture d\'origine est inconnue du serveur.',
          });
          continue;
        }
        final venteRef = f['vente_ref'];
        if (f['type'] == 'FV' && venteRef != null) {
          final autre = factures.values.where(
            (x) =>
                x['id'] != id &&
                x['type'] == 'FV' &&
                x['vente_ref'] == venteRef &&
                (x['device_id'] == deviceId ||
                    RegExp(r'^V-P\d+-').hasMatch(venteRef as String)),
          );
          if (autre.isNotEmpty) {
            refusees.add({
              'id': id,
              'motif':
                  'Cette vente porte déjà la facture ${autre.first['reference']}.',
            });
            continue;
          }
        }
        factures[id] = {
          ...f,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
        acceptees.add(id);
        continue;
      }

      // Facture connue : le contenu ne change JAMAIS.
      if (existante['reference'] != ref ||
          existante['type'] != f['type'] ||
          existante['total_ttc'] != f['total_ttc'] ||
          existante['client'] != f['client']) {
        refusees.add({
          'id': id,
          'motif': 'Une facture émise ne se modifie pas : émettez un avoir.',
        });
        continue;
      }
      final rangServeur = _rang[existante['statut']]!;
      final rangRecu = _rang[f['statut']]!;
      if (rangRecu < rangServeur) {
        refusees.add({
          'id': id,
          'motif':
              'La facture est déjà « ${existante['statut']} » sur le serveur : '
              'un statut ne régresse jamais.',
        });
        continue;
      }
      if (rangRecu == rangServeur && f['statut'] == 'normalisee') {
        if (existante['code_mecef'] != f['code_mecef'] ||
            existante['nim'] != f['nim']) {
          refusees.add({
            'id': id,
            'motif':
                'Cette facture est déjà normalisée sous un autre code '
                '(${existante['code_mecef']}) : une normalisation ne change pas.',
          });
          continue;
        }
        acceptees.add(id); // rejeu : rien ne change
        continue;
      }
      final applique =
          rangRecu > rangServeur ||
          (rangRecu == rangServeur &&
              f['statut'] == 'rejetee' &&
              saisie.isAfter(
                DateTime.parse(existante['updated_at'] as String),
              ));
      if (applique) {
        for (final c in const [
          'statut',
          'code_mecef',
          'nim',
          'compteur',
          'lien_verification',
          'date_normalisation',
          'erreur_transmission',
        ]) {
          existante[c] = f[c];
        }
        existante
          ..['updated_at'] = saisie.toUtc().toIso8601String()
          ..['serveur_modifie_le'] = _instant();
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  // ----------------------------------------------------------------- Elevage

  static const _especes = {
    'goliaths',
    'pintades',
    'lapins',
    'poissons-chats',
    'poulets',
    'pondeuses',
    'escargots',
    'bovins',
  };

  static const _entiersFiche = [
    'achat',
    'ne',
    'vente',
    'mort_cat1',
    'mort_cat2',
    'mort_cat3',
    'don_cat1',
    'don_cat2',
    'don_cat3',
    'effectif',
    'eff_cat1_day',
    'eff_cat2_day',
    'eff_cat3_day',
  ];

  static const _entiersFacultatifs = [
    'mort_cat4',
    'don_cat4',
    'eff_cat4_day',
    'srh',
    'ts',
    'stock_final_oeufs',
    'oeufs_pondus',
    'oeufs_casses',
    'sorties_plateaux',
    'poids_general_g',
  ];

  static final RegExp _uuidServeur = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// `AAAA-MM-JJ` EXACT, aller-retour (comme `date_format:Y-m-d` du vrai serveur) :
  /// « 2026-02-31 » et « 2026-11-05T10:00:00Z » sont refusés.
  DateTime? _jourOuNull(Object? v) {
    if (v is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
      return null;
    }
    final d = DateTime.tryParse(v);
    if (d == null) return null;
    return jourCivil(d) == v ? d : null;
  }

  /// Rejoue `FichesJourneeTable` : identite = (espece, date), dernier ecrivain gagne,
  /// ligne ENTIERE.
  Map<String, dynamic> _fichesJournee(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final f in lot) {
      final id = f['id'] as String;
      String? motif;
      final jour = _jourOuNull(f['date']);
      if (!_uuidServeur.hasMatch(id)) {
        motif = "L'identifiant de la fiche doit être un UUID.";
      } else if (!_especes.contains(f['espece'])) {
        motif = 'La filière « ${f['espece']} » est inconnue.';
      } else if (jour == null) {
        motif = 'La date de la fiche est invalide.';
      } else if (id != identifiantFicheJournee(f['espece'] as String, jour)) {
        motif =
            "L'identifiant de la fiche ne correspond pas à sa filière et à sa date.";
      } else {
        for (final c in _entiersFiche) {
          if (f[c] == null) {
            motif = 'La valeur de « $c » est obligatoire.';
            break;
          }
          if (f[c] is! int || (f[c] as int) < 0) {
            motif = 'La valeur de « $c » doit être un entier positif ou nul.';
            break;
          }
        }
        for (final c in _entiersFacultatifs) {
          if (motif != null) break;
          if (f[c] != null && (f[c] is! int || (f[c] as int) < 0)) {
            motif = 'La valeur de « $c » doit être un entier positif ou nul.';
          }
        }
        for (final c in const ['traitement_valide', 'is_recorded']) {
          if (motif != null) break;
          if (f[c] is! bool) {
            motif = "L'indicateur « $c » doit être vrai ou faux.";
          }
        }
      }
      if (motif != null) {
        refusees.add({'id': id, 'motif': motif});
        continue;
      }
      final saisie = DateTime.parse(f['updated_at'] as String);
      final existante = fichesJournee[id];
      if (existante == null ||
          saisie.isAfter(DateTime.parse(existante['updated_at'] as String))) {
        fichesJournee[id] = {
          ...f,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  /// Rejoue `VentesJourTable` : une ligne par (poste, espece, date), identifiant
  /// calcule avec le poste qui envoie.
  Map<String, dynamic> _ventesJour(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final f in lot) {
      final id = f['id'] as String;
      String? motif;
      final jour = _jourOuNull(f['date']);
      if (!_uuidServeur.hasMatch(id)) {
        motif = "L'identifiant du compteur doit être un UUID.";
      } else if (!_especes.contains(f['espece'])) {
        motif = 'La filière « ${f['espece']} » est inconnue.';
      } else if (jour == null) {
        motif = 'La date du compteur est invalide.';
      } else if (f['qte'] == null) {
        motif = 'La quantité vendue est obligatoire.';
      } else if (f['qte'] is! int || (f['qte'] as int) < 0) {
        motif = 'La quantité vendue doit être un entier positif ou nul.';
      } else if (id !=
          identifiantVentesJour(f['espece'] as String, jour, deviceId)) {
        motif =
            "L'identifiant du compteur ne correspond pas à sa filière, à sa date et à son poste.";
      }
      if (motif != null) {
        refusees.add({'id': id, 'motif': motif});
        continue;
      }
      final saisie = DateTime.parse(f['updated_at'] as String);
      final existante = ventesJour[id];
      if (existante == null ||
          saisie.isAfter(DateTime.parse(existante['updated_at'] as String))) {
        ventesJour[id] = {
          ...f,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }

  /// Rejoue `BandesTable` : dernier ecrivain gagne par UUID, code unique par filiere.
  Map<String, dynamic> _bandes(
    List<Map<String, dynamic>> lot,
    String deviceId,
  ) {
    final acceptees = <String>[];
    final refusees = <Map<String, String>>[];
    for (final b in lot) {
      final id = b['id'] as String;
      String? motif;
      final mise = _jourOuNull(b['date_mise_en_bande']);
      final cloture = _jourOuNull(b['date_cloture']);
      final code = b['code'];
      if (!_uuidServeur.hasMatch(id)) {
        motif = "L'identifiant de la bande doit être un UUID.";
      } else if (!_especes.contains(b['espece'])) {
        motif = 'La filière « ${b['espece']} » est inconnue.';
      } else if (code is! String || code.trim().isEmpty) {
        motif = 'Le code de la bande est obligatoire.';
      } else if (mise == null) {
        motif = 'La date de mise en place de la bande est invalide.';
      } else if (b['date_cloture'] != null && cloture == null) {
        motif = 'La date de clôture de la bande est invalide.';
      } else if (cloture != null && cloture.isBefore(mise)) {
        motif = 'La clôture ne peut pas précéder la mise en place de la bande.';
      } else if (b['effectif_initial'] != null &&
          b['effectif_initial'] is! int) {
        motif = "L'effectif mis en place doit être un entier positif ou nul.";
      } else if (b['effectif_initial'] != null &&
          (b['effectif_initial'] as int) < 0) {
        motif = "L'effectif mis en place ne peut pas être négatif.";
      } else if (bandes.values.any(
        (x) =>
            x['id'] != id &&
            x['espece'] == b['espece'] &&
            (x['code'] as String).trim() == code.trim(),
      )) {
        motif = 'Ce code de bande est déjà utilisé pour cette filière.';
      }
      if (motif != null) {
        refusees.add({'id': id, 'motif': motif});
        continue;
      }
      final saisie = DateTime.parse(b['updated_at'] as String);
      final existante = bandes[id];
      if (existante == null ||
          saisie.isAfter(DateTime.parse(existante['updated_at'] as String))) {
        bandes[id] = {
          ...b,
          'device_id': deviceId,
          'updated_at': saisie.toUtc().toIso8601String(),
          'serveur_modifie_le': _instant(),
        };
      }
      acceptees.add(id);
    }
    return {'accepted': acceptees, 'rejected': refusees, 'ignored': []};
  }
}
