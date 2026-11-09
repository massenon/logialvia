import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../administration/data/repositories/preferences_poste_repository.dart';
import '../../administration/data/sync/depot_demandes_referentiel.dart';
import 'depot_jeton_sync.dart';
import 'service_appairage.dart';
import 'table_poste.dart';

enum IssueSynchronisation {
  /// Pull puis push se sont terminés.
  terminee,

  /// Pas de réseau : **pas une erreur** (blueprint §3), tout reste à envoyer.
  horsLigne,

  nonAppairee,

  /// 401 : jeton révoqué ou expiré, le poste redemande une connexion.
  revoque,

  /// Le serveur a refusé (409, 403, 5xx…) ; voir le message.
  refusee,
}

class RapportSynchronisation {
  const RapportSynchronisation(
    this.issue,
    this.message, {
    this.recues = 0,
    this.refuseesALaReception = 0,
    this.conserveesLocalement = 0,
    this.supplantees = 0,
    this.referentielsMisAJour = 0,
    this.demandesAcceptees = 0,
    this.demandesRefusees = 0,
    this.envoyees = 0,
    this.acceptees = 0,
    this.refusees = 0,
    this.ignorees = 0,
    this.saisiesPerdues = 0,
    this.remiseAZero = false,
  });

  final IssueSynchronisation issue;
  final String message;

  /// Lignes absorbées au tirage.
  final int recues;

  /// Lignes du serveur refusées par l'absorbeur strict.
  final int refuseesALaReception;

  /// Lignes du serveur non appliquées car le poste a une saisie non envoyée.
  final int conserveesLocalement;

  /// Saisies locales non envoyées remplacées par une version plus récente.
  final int supplantees;

  /// Lignes de référentiels (modules, paramètres) modifiées d'après le serveur.
  final int referentielsMisAJour;

  /// Demandes de modification de référentiel acceptées / refusées par le serveur.
  final int demandesAcceptees;
  final int demandesRefusees;

  final int envoyees;
  final int acceptees;

  /// Lignes refusées par le serveur : elles deviennent `conflict`.
  final int refusees;
  final int ignorees;

  /// Saisies non envoyées perdues par une remise à zéro du serveur.
  final int saisiesPerdues;
  final bool remiseAZero;

  bool get reussie => issue == IssueSynchronisation.terminee;

  RapportSynchronisation avec({
    IssueSynchronisation? issue,
    String? message,
    int? recues,
    int? refuseesALaReception,
    int? conserveesLocalement,
    int? supplantees,
    int? referentielsMisAJour,
    int? demandesAcceptees,
    int? demandesRefusees,
    int? envoyees,
    int? acceptees,
    int? refusees,
    int? ignorees,
    int? saisiesPerdues,
    bool? remiseAZero,
  }) => RapportSynchronisation(
    issue ?? this.issue,
    message ?? this.message,
    recues: recues ?? this.recues,
    refuseesALaReception: refuseesALaReception ?? this.refuseesALaReception,
    conserveesLocalement: conserveesLocalement ?? this.conserveesLocalement,
    supplantees: supplantees ?? this.supplantees,
    referentielsMisAJour: referentielsMisAJour ?? this.referentielsMisAJour,
    demandesAcceptees: demandesAcceptees ?? this.demandesAcceptees,
    demandesRefusees: demandesRefusees ?? this.demandesRefusees,
    envoyees: envoyees ?? this.envoyees,
    acceptees: acceptees ?? this.acceptees,
    refusees: refusees ?? this.refusees,
    ignorees: ignorees ?? this.ignorees,
    saisiesPerdues: saisiesPerdues ?? this.saisiesPerdues,
    remiseAZero: remiseAZero ?? this.remiseAZero,
  );
}

/// Le moteur de synchronisation du poste (`46_` §4, blueprint §3).
///
/// Ordre **toujours** : tirage (pull) d'abord, envoi (push) ensuite — sinon le
/// serveur travaillerait sur des données que le poste n'a pas encore reçues.
///
/// Le poste écrit des **faits** ; le serveur décide. Rien n'est calculé ici :
/// pas de règle métier recopiée dans le client (`46_` §5).
class MoteurSynchronisationPoste {
  MoteurSynchronisationPoste({
    required this.preferences,
    required this.depot,
    required this.appairage,
    required this.tables,
    this.demandes,
    this.client,
    this.delai = const Duration(seconds: 30),
    this.tailleLot = 100,
  });

  final PreferencesPosteRepository preferences;
  final DepotJetonSync depot;
  final ServiceAppairage appairage;

  /// Dans l'ordre des dépendances (clients avant ventes…).
  final List<TablePoste> tables;

  /// File des demandes de modification de référentiel (`null` : aucune).
  final DepotDemandesReferentiel? demandes;
  final http.Client? client;
  final Duration delai;

  /// Lignes par requête d'envoi : un envoi plus gros que la limite du
  /// mandataire (413) est un piège déjà payé (blueprint §10).
  final int tailleLot;

  bool _enCours = false;

  /// [complet] : repart d'un tirage COMPLET (« Renvoyer vers ce poste » du web).
  Future<RapportSynchronisation> synchroniser({bool complet = false}) async {
    // Une seule synchronisation à la fois : deux tirages entrelacés se
    // disputeraient le curseur.
    if (_enCours) {
      return const RapportSynchronisation(
        IssueSynchronisation.refusee,
        'Une synchronisation est déjà en cours.',
      );
    }
    _enCours = true;
    try {
      return await _synchroniser(complet: complet);
    } finally {
      _enCours = false;
    }
  }

  Future<RapportSynchronisation> _synchroniser({required bool complet}) async {
    final adresse = await preferences.adresseServeur();
    final jeton = await depot.lire();
    if (adresse == null || jeton == null || jeton.isEmpty) {
      return const RapportSynchronisation(
        IssueSynchronisation.nonAppairee,
        'Ce poste n\'est pas appairé : rien à synchroniser.',
      );
    }

    final session = _Session(
      adresse,
      jeton,
      await preferences.identifiantPoste(),
    );
    // Une seule fois : le catalogue local est propose au serveur.
    await demandes?.adopterCatalogueSiBesoin(preferences);
    await demandes?.adopterIntrantsSiBesoin(preferences);
    await demandes?.adopterParametresElevageSiBesoin(preferences);

    var rapport = const RapportSynchronisation(
      IssueSynchronisation.terminee,
      '',
    );

    // Un tirage complet ne se décide pas à moitié : le curseur est effacé AVANT,
    // et ne reprend qu'à la dernière page.
    if (complet) await preferences.definirCurseurTirage(null);

    final tirage = await _tirer(session, rapport);
    rapport = tirage.rapport;
    if (tirage.arret != null) return tirage.arret!;

    // Les DEMANDES partent avant les faits : un produit créé au poste doit être connu
    // du serveur avant que les ventes qui le portent n'arrivent (sinon : « produit
    // inconnu »).
    final proposition = await _envoyerDemandes(session, rapport);
    rapport = proposition.rapport;
    if (proposition.arret != null) return proposition.arret!;

    final envoi = await _envoyer(session, rapport);
    rapport = envoi.rapport;
    if (envoi.arret != null) return envoi.arret!;

    return rapport.avec(message: _resume(rapport));
  }

  // ------------------------------------------------- Demandes du serveur

  /// Le serveur ne joint jamais un poste (éteint, derrière un NAT) : il dépose un
  /// drapeau que le poste lit (`GET /api/sync/demande`, blueprint §5).
  Future<ReponseDemande> interrogerDemande() async {
    final adresse = await preferences.adresseServeur();
    final jeton = await depot.lire();
    if (adresse == null || jeton == null || jeton.isEmpty) {
      return const ReponseDemande(IssueSynchronisation.nonAppairee);
    }
    final reponse = await _appeler(
      (c) => c.get(
        Uri.parse('$adresse/api/sync/demande'),
        headers: _entetes(jeton),
      ),
    );
    final arret = await _verifier(reponse);
    if (arret != null) return ReponseDemande(arret.issue);

    final json = _json(reponse!.body);
    return ReponseDemande(
      IssueSynchronisation.terminee,
      synchroniser: json?['synchroniser'] == true,
      resynchronisationComplete: json?['resynchronisation_complete'] == true,
    );
  }

  /// Le tirage complet demandé est fait : le serveur peut baisser son drapeau.
  Future<bool> acquitterResynchronisation() async {
    final adresse = await preferences.adresseServeur();
    final jeton = await depot.lire();
    if (adresse == null || jeton == null || jeton.isEmpty) return false;
    final reponse = await _appeler(
      (c) => c.post(
        Uri.parse('$adresse/api/sync/resynchronisation/acquittement'),
        headers: _entetes(jeton),
      ),
    );
    return reponse != null &&
        reponse.statusCode >= 200 &&
        reponse.statusCode < 300;
  }

  /// Une saisie attend-elle d'être envoyée ? (garde « rien à envoyer »)
  Future<bool> aDesSaisiesAEnvoyer() async {
    for (final t in tables) {
      if ((await t.aEnvoyer()).isNotEmpty) return true;
    }
    return demandes != null && (await demandes!.aEnvoyer()).isNotEmpty;
  }

  /// Émet à chaque modification locale d'une table synchronisée.
  Stream<void> get modifications => StreamGroup.merge([
    ...tables.map((t) => t.modifications),
    ?demandes?.modifications,
  ]);

  // ------------------------------------------------------------------ Tirage

  Future<_Etape> _tirer(_Session s, RapportSynchronisation rapport) async {
    var since = await preferences.curseurTirage();
    var page = 1;
    String? borne; // `until` : fige les pages d'un même tirage
    var marqueVerifiee = false;

    while (true) {
      final reponse = await _appeler(
        (c) => c.get(
          Uri.parse('${s.adresse}/api/sync/pull').replace(
            queryParameters: {
              'since': ?since,
              'until': ?borne,
              'page': '$page',
            },
          ),
          headers: _entetes(s.jeton),
        ),
      );
      final arret = await _verifier(reponse);
      if (arret != null) return _Etape(rapport, arret);

      final json = _json(reponse!.body);
      if (json == null || json['tables'] is! Map) {
        return _Etape(
          rapport,
          _refus('Réponse du serveur inattendue au tirage.'),
        );
      }

      final marque = json['reset_mark'];
      if (!marqueVerifiee && marque is String) {
        marqueVerifiee = true;
        final connue = await preferences.marqueRemiseAZero();
        if (connue != null && connue != marque) {
          // Remise à zéro du serveur : le poste purge ses tables d'activité,
          // compte ce qu'il perd, puis repart d'un tirage COMPLET.
          var perdues = 0;
          // Dans l'ordre INVERSE des dependances : les achats avant leur
          // fournisseur, sinon la cle etrangere refuse la suppression.
          for (final t in tables.reversed) {
            perdues += await t.purger();
          }
          await preferences.definirCurseurTirage(null);
          await preferences.definirMarqueRemiseAZero(marque);
          rapport = rapport.avec(
            remiseAZero: true,
            saisiesPerdues: rapport.saisiesPerdues + perdues,
          );
          since = null;
          borne = null;
          page = 1;
          continue;
        }
        if (connue == null) await preferences.definirMarqueRemiseAZero(marque);
      }

      borne ??= json['server_time'] as String?;
      final lignesParTable = (json['tables'] as Map).cast<String, dynamic>();
      for (final t in tables) {
        final lignes = lignesParTable[t.nom];
        if (lignes is! List) continue;
        final r = await t.absorber(
          lignes.whereType<Map<String, dynamic>>().toList(),
        );
        rapport = rapport.avec(
          recues: rapport.recues + (t.referentiel ? 0 : r.absorbees),
          referentielsMisAJour:
              rapport.referentielsMisAJour + (t.referentiel ? r.absorbees : 0),
          refuseesALaReception: rapport.refuseesALaReception + r.refusees,
          conserveesLocalement: rapport.conserveesLocalement + r.conservees,
          supplantees: rapport.supplantees + r.supplantees,
        );
      }

      final derniere = (json['last_page'] as num?)?.toInt() ?? 1;
      if (page >= derniere) {
        // Le curseur n'avance qu'après la DERNIÈRE page.
        final fin = json['server_time'];
        if (fin is String) await preferences.definirCurseurTirage(fin);
        return _Etape(rapport, null);
      }
      page++;
    }
  }

  // ------------------------------------------------------------------- Envoi

  Future<_Etape> _envoyer(_Session s, RapportSynchronisation rapport) async {
    final marque = await preferences.marqueRemiseAZero() ?? 'initiale';

    for (final t in tables) {
      final aEnvoyer = await t.aEnvoyer();
      for (var i = 0; i < aEnvoyer.length; i += tailleLot) {
        final lot = aEnvoyer.skip(i).take(tailleLot).toList();
        final reponse = await _appeler(
          (c) => c.post(
            Uri.parse('${s.adresse}/api/sync/push'),
            headers: _entetes(s.jeton),
            body: jsonEncode({
              'device_id': s.idPoste,
              'reset_mark': marque,
              'tables': {
                t.nom: [for (final l in lot) l.corps],
              },
            }),
          ),
        );
        final arret = await _verifier(reponse);
        if (arret != null) return _Etape(rapport, arret);

        final json = _json(reponse!.body);
        final bilan = json?[t.nom];
        if (bilan is! Map) {
          return _Etape(
            rapport,
            _refus('Réponse du serveur inattendue à l\'envoi.'),
          );
        }

        final instants = {for (final l in lot) l.id: l.instantSaisie};
        var acceptees = 0;
        for (final id in (bilan['accepted'] as List? ?? const [])) {
          if (id is String && instants.containsKey(id)) {
            await t.marquerSynchronise(id, instants[id]!);
            acceptees++;
          }
        }
        var refusees = 0;
        for (final r in (bilan['rejected'] as List? ?? const [])) {
          if (r is Map && r['id'] is String) {
            await t.marquerConflit(
              r['id'] as String,
              (r['motif'] as String?) ?? 'Refusé par le serveur.',
            );
            refusees++;
          }
        }
        final ignorees = (bilan['ignored'] as List? ?? const []).length;

        rapport = rapport.avec(
          envoyees: rapport.envoyees + lot.length,
          acceptees: rapport.acceptees + acceptees,
          refusees: rapport.refusees + refusees,
          ignorees: rapport.ignorees + ignorees,
        );
      }
    }
    return _Etape(rapport, null);
  }

  // ------------------------------------------------------------ Demandes

  /// Le poste PROPOSE ses modifications de référentiel ; le serveur décide
  /// (`POST /api/sync/demandes`). Le résultat redescend au tirage suivant.
  Future<_Etape> _envoyerDemandes(
    _Session s,
    RapportSynchronisation rapport,
  ) async {
    final file = demandes;
    if (file == null) return _Etape(rapport, null);
    final aEnvoyer = await file.aEnvoyer();
    if (aEnvoyer.isEmpty) return _Etape(rapport, null);

    final reponse = await _appeler(
      (c) => c.post(
        Uri.parse('${s.adresse}/api/sync/demandes'),
        headers: _entetes(s.jeton),
        body: jsonEncode({
          'device_id': s.idPoste,
          'demandes': [
            for (final d in aEnvoyer)
              {
                'id': d.id,
                'type': d.type,
                'saisi_le': d.saisiLe,
                'donnees': jsonDecode(d.donnees),
              },
          ],
        }),
      ),
    );
    final arret = await _verifier(reponse);
    if (arret != null) return _Etape(rapport, arret);

    final json = _json(reponse!.body);
    if (json == null) {
      return _Etape(
        rapport,
        _refus('Réponse du serveur inattendue aux demandes.'),
      );
    }
    final saisies = {for (final d in aEnvoyer) d.id: d.saisiLe};
    var acceptees = 0;
    var refusees = 0;
    for (final id in (json['accepted'] as List? ?? const [])) {
      if (id is String && saisies.containsKey(id)) {
        await file.marquerSynchronisee(id, saisies[id]!);
        acceptees++;
      }
    }
    for (final r in (json['rejected'] as List? ?? const [])) {
      if (r is Map && r['id'] is String && saisies.containsKey(r['id'])) {
        await file.marquerRefusee(
          r['id'] as String,
          (r['motif'] as String?) ?? 'Refusée par le serveur.',
        );
        refusees++;
      }
    }
    return _Etape(
      rapport.avec(
        demandesAcceptees: rapport.demandesAcceptees + acceptees,
        demandesRefusees: rapport.demandesRefusees + refusees,
      ),
      null,
    );
  }

  // ------------------------------------------------------------------ Outils

  Map<String, String> _entetes(String jeton) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $jeton',
  };

  Future<http.Response?> _appeler(
    Future<http.Response> Function(http.Client) requete,
  ) async {
    final c = client ?? http.Client();
    try {
      return await requete(c).timeout(delai);
    } on Exception {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// `null` si la réponse est exploitable, sinon le rapport qui arrête tout.
  Future<RapportSynchronisation?> _verifier(http.Response? reponse) async {
    if (reponse == null) {
      return const RapportSynchronisation(
        IssueSynchronisation.horsLigne,
        'Serveur injoignable : hors ligne, tout reste à envoyer. '
        'Le poste continue de fonctionner normalement.',
      );
    }
    if (reponse.statusCode == 401) {
      await appairage.oublierLocalement();
      return const RapportSynchronisation(
        IssueSynchronisation.revoque,
        'Ce poste n\'est plus appairé : le jeton a été révoqué ou a expiré. '
        'Reconnectez-vous (Paramètres > Appairage). Vos saisies sont conservées.',
      );
    }
    if (reponse.statusCode == 409) {
      return _refus(
        _json(reponse.body)?['message'] as String? ??
            'Le serveur a été remis à zéro : tirez d\'abord ses données.',
      );
    }
    if (reponse.statusCode < 200 || reponse.statusCode >= 300) {
      final m = _json(reponse.body)?['message'];
      return _refus(
        m is String && m.isNotEmpty
            ? m
            : 'Le serveur a refusé la demande (HTTP ${reponse.statusCode}).',
      );
    }
    return null;
  }

  RapportSynchronisation _refus(String message) =>
      RapportSynchronisation(IssueSynchronisation.refusee, message);

  Map<String, dynamic>? _json(String corps) {
    try {
      final v = jsonDecode(corps);
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }

  String _resume(RapportSynchronisation r) {
    final morceaux = <String>[
      '${r.recues} reçue(s)',
      '${r.acceptees} envoyée(s)',
    ];
    if (r.demandesAcceptees > 0) {
      morceaux.add('${r.demandesAcceptees} réglage(s) proposé(s) au serveur');
    }
    if (r.demandesRefusees > 0) {
      morceaux.add(
        '${r.demandesRefusees} demande(s) de réglage refusée(s) par le serveur',
      );
    }
    if (r.referentielsMisAJour > 0) {
      morceaux.add(
        '${r.referentielsMisAJour} réglage(s) mis à jour depuis le serveur',
      );
    }
    if (r.refusees > 0) morceaux.add('${r.refusees} refusée(s) par le serveur');
    if (r.conserveesLocalement > 0) {
      morceaux.add(
        '${r.conserveesLocalement} conservée(s) (saisie locale non envoyée)',
      );
    }
    if (r.supplantees > 0) {
      morceaux.add(
        '${r.supplantees} saisie(s) locale(s) remplacée(s) par une version plus récente',
      );
    }
    if (r.refuseesALaReception > 0) {
      morceaux.add(
        '${r.refuseesALaReception} ligne(s) du serveur incohérente(s) refusée(s)',
      );
    }
    var texte = 'Synchronisation terminée : ${morceaux.join(', ')}.';
    if (r.remiseAZero) {
      texte +=
          ' Le serveur a été remis à zéro : ce poste a été vidé de ses données '
          'synchronisées (${r.saisiesPerdues} saisie(s) non envoyée(s) perdue(s)).';
    }
    return texte;
  }
}

/// Réponse à `GET /api/sync/demande`.
class ReponseDemande {
  const ReponseDemande(
    this.issue, {
    this.synchroniser = false,
    this.resynchronisationComplete = false,
  });

  /// `terminee` = le serveur a répondu ; sinon voir [IssueSynchronisation].
  final IssueSynchronisation issue;
  final bool synchroniser;
  final bool resynchronisationComplete;
}

/// Fusion minimale de flux (évite une dépendance pour une fonction).
class StreamGroup {
  static Stream<void> merge(Iterable<Stream<void>> flux) {
    final controleur = StreamController<void>.broadcast();
    final abonnements = <StreamSubscription<void>>[];
    controleur.onListen = () {
      for (final f in flux) {
        abonnements.add(f.listen((_) => controleur.add(null)));
      }
    };
    controleur.onCancel = () async {
      for (final a in abonnements) {
        await a.cancel();
      }
      abonnements.clear();
    };
    return controleur.stream;
  }
}

class _Session {
  const _Session(this.adresse, this.jeton, this.idPoste);
  final String adresse;
  final String jeton;
  final String idPoste;
}

class _Etape {
  const _Etape(this.rapport, this.arret);
  final RapportSynchronisation rapport;

  /// Non nul : la synchronisation s'arrête ici avec ce rapport.
  final RapportSynchronisation? arret;
}
