import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Ce qui s'est mal passé AVANT d'obtenir une réponse HTTP.
enum GenreErreurReseau {
  /// Serveur éteint, DNS, pas de réseau : un état normal du poste (hors ligne).
  horsLigne,

  /// Pas de réponse dans le délai (réseau lent, serveur saturé).
  delai,

  /// Connexion coupée en plein échange (mandataire, Wi-Fi qui saute).
  interrompue,

  /// Certificat HTTPS refusé : la vérification n'est JAMAIS désactivée.
  certificat,

  /// Le serveur ne parle pas HTTPS comme attendu (version TLS, mauvais port).
  securite,
}

class ErreurReseau {
  const ErreurReseau(this.genre, this.message);

  final GenreErreurReseau genre;

  /// Message en français, destiné à l'utilisatrice (jamais d'exception brute).
  final String message;

  /// Une coupure peut être rejouée sur-le-champ : tout envoi du poste est
  /// idempotent (UUID, `46_` §4). Une panne franche (serveur éteint) ne l'est pas.
  bool get rejouable => genre == GenreErreurReseau.interrompue;
}

/// Résultat d'un appel : une réponse HTTP, ou l'erreur réseau qui l'a empêchée.
class ResultatHttp {
  const ResultatHttp({this.reponse, this.erreur, this.adresseCorrigee});

  final http.Response? reponse;
  final ErreurReseau? erreur;

  /// Non nul : le serveur a redirigé `http://` vers `https://` (même hôte) ; la
  /// requête a été rejouée en HTTPS et c'est l'adresse à garder désormais.
  final String? adresseCorrigee;
}

/// Couche HTTP unique du poste (moteur de synchronisation, appairage).
///
/// Elle absorbe les pièges d'un hébergement réel (`47r_`) sans jamais lever
/// d'exception vers l'écran :
///
/// - **TLS** : un certificat invalide (auto-signé, autorité inconnue, expiré, mauvais nom)
///   est REFUSÉ avec un message clair ; la vérification n'est jamais désactivée ;
/// - **coupure en plein échange** et **502/503/504/429** : rejeu (3 essais au plus),
///   en respectant `Retry-After` (plafonné) ; l'envoi est idempotent, le rejeu est sûr ;
/// - **redirection http → https** du même hôte : suivie (POST compris, que `dart:io` ne
///   suit pas), l'adresse corrigée est rendue pour être mémorisée ; toute autre
///   redirection est rendue telle quelle (jamais de jeton vers un autre site) ;
/// - **délai** : borné, message distinct de « hors ligne ».
class TransportHttp {
  TransportHttp({
    this.client,
    this.delai = const Duration(seconds: 30),
    this.delaisRepetition = const [
      Duration(milliseconds: 500),
      Duration(seconds: 2),
    ],
    this.attenteMax = const Duration(seconds: 15),
    Future<void> Function(Duration)? pause,
  }) : _pause = pause ?? Future<void>.delayed;

  final http.Client? client;
  final Duration delai;

  /// Pause avant chaque rejeu (la longueur de la liste = nombre de rejeux).
  final List<Duration> delaisRepetition;

  /// `Retry-After` au-delà de ce plafond : on n'attend pas, on rend la réponse.
  final Duration attenteMax;
  final Future<void> Function(Duration) _pause;

  /// [requete] reçoit le client ET l'adresse de base courante (qui change si
  /// le serveur impose HTTPS).
  Future<ResultatHttp> appeler(
    Future<http.Response> Function(http.Client c, String base) requete, {
    required String adresse,
  }) async {
    var base = adresse;
    String? corrigee;
    var redirige = false;

    for (var essai = 0; ; essai++) {
      final c = client ?? http.Client();
      http.Response? reponse;
      ErreurReseau? erreur;
      try {
        reponse = await requete(c, base).timeout(delai);
      } on TimeoutException {
        erreur = ErreurReseau(
          GenreErreurReseau.delai,
          'Le serveur met trop de temps à répondre (plus de ${delai.inSeconds} s). '
          'Réseau lent ou serveur saturé : nouvel essai au prochain cycle.',
        );
      } on HandshakeException catch (e) {
        erreur = _erreurTls(e.toString(), base);
      } on TlsException catch (e) {
        erreur = _erreurTls(e.toString(), base);
      } on Object catch (e) {
        erreur = _classer(e);
      } finally {
        if (client == null) c.close();
      }

      if (reponse != null) {
        final r = reponse;
        final cible = _redirectionHttps(r, base);
        if (cible != null && !redirige) {
          redirige = true;
          base = cible;
          corrigee = cible;
          continue;
        }
        if (_transitoire(r.statusCode) && essai < delaisRepetition.length) {
          final voulue = _retryAfter(r);
          final attente = voulue ?? delaisRepetition[essai];
          if (attente <= attenteMax) {
            await _pause(attente);
            continue;
          }
        }
        return ResultatHttp(reponse: r, adresseCorrigee: corrigee);
      }

      if (erreur!.rejouable && essai < delaisRepetition.length) {
        await _pause(delaisRepetition[essai]);
        continue;
      }
      return ResultatHttp(erreur: erreur, adresseCorrigee: corrigee);
    }
  }

  static bool _transitoire(int statut) =>
      statut == 429 || statut == 502 || statut == 503 || statut == 504;

  /// `Retry-After` en secondes ou en date HTTP ; `null` si absent/illisible.
  static Duration? _retryAfter(http.Response r) {
    final brut = r.headers['retry-after']?.trim();
    if (brut == null || brut.isEmpty) return null;
    final secondes = int.tryParse(brut);
    if (secondes != null) return Duration(seconds: secondes < 0 ? 0 : secondes);
    try {
      final d = HttpDate.parse(brut).difference(DateTime.now().toUtc());
      return d.isNegative ? Duration.zero : d;
    } on Exception {
      return null;
    }
  }

  /// Adresse HTTPS à adopter si [r] redirige `http://hôte` vers `https://` du MÊME
  /// hôte ; `null` sinon (on ne suit rien d'autre : le jeton ne part pas ailleurs).
  static String? _redirectionHttps(http.Response r, String base) {
    if (![301, 302, 303, 307, 308].contains(r.statusCode)) return null;
    final origine = Uri.tryParse(base);
    final lieu = r.headers['location'];
    if (origine == null || lieu == null || origine.scheme != 'http') {
      return null;
    }
    final cible = (r.request?.url ?? origine).resolve(lieu);
    if (cible.scheme != 'https' || cible.host != origine.host) return null;
    final port = cible.hasPort && cible.port != 443 ? ':${cible.port}' : '';
    final chemin = origine.path.replaceAll(RegExp(r'/+$'), '');
    return 'https://${cible.host}$port$chemin';
  }

  static ErreurReseau _classer(Object e) {
    final texte = e.toString().toLowerCase();
    const coupure = [
      'closed',
      'reset',
      'broken pipe',
      'aborted',
      'eof',
      'before full header',
    ];
    if (coupure.any(texte.contains)) {
      return const ErreurReseau(
        GenreErreurReseau.interrompue,
        'La connexion avec le serveur a été coupée en cours d\'échange.',
      );
    }
    return const ErreurReseau(
      GenreErreurReseau.horsLigne,
      'Serveur injoignable : hors ligne, tout reste à envoyer. '
      'Le poste continue de fonctionner normalement.',
    );
  }

  static ErreurReseau _erreurTls(String detail, String base) {
    final t = detail.toLowerCase();
    const garantie =
        ' La vérification du certificat n\'est jamais désactivée : '
        'rien n\'est envoyé tant que le certificat n\'est pas valide.';
    if (t.contains('expired')) {
      return const ErreurReseau(
        GenreErreurReseau.certificat,
        'Le certificat HTTPS du serveur est expiré : son propriétaire doit '
        'le renouveler.$garantie',
      );
    }
    if (t.contains('hostname mismatch') ||
        t.contains('ip address mismatch') ||
        t.contains('subject alternative')) {
      final hote = Uri.tryParse(base)?.host ?? base;
      return ErreurReseau(
        GenreErreurReseau.certificat,
        'Le certificat HTTPS du serveur ne correspond pas à l\'adresse « $hote » : '
        'vérifiez l\'adresse saisie, ou faites établir un certificat pour ce nom.'
        '$garantie',
      );
    }
    if (t.contains('self signed') ||
        t.contains('self-signed') ||
        t.contains('unable to get local issuer') ||
        t.contains('unable to get issuer') ||
        t.contains('unknown ca')) {
      return const ErreurReseau(
        GenreErreurReseau.certificat,
        'Le certificat HTTPS du serveur n\'est pas reconnu (auto-signé ou '
        'autorité inconnue). Utilisez un certificat public (Let\'s Encrypt) ou '
        'installez l\'autorité de certification de l\'entreprise dans Windows '
        '(Certificats > Autorités de certification racines de confiance).'
        '$garantie',
      );
    }
    if (t.contains('wrong_version_number') ||
        t.contains('unknown protocol') ||
        t.contains('record layer')) {
      return const ErreurReseau(
        GenreErreurReseau.securite,
        'Le serveur ne répond pas en HTTPS à cette adresse : vérifiez le '
        'port, ou utilisez « http:// » s\'il s\'agit d\'un réseau local.',
      );
    }
    if (t.contains('certificate_verify_failed') || t.contains('certificate')) {
      return const ErreurReseau(
        GenreErreurReseau.certificat,
        'Le certificat HTTPS du serveur est invalide.$garantie',
      );
    }
    return const ErreurReseau(
      GenreErreurReseau.securite,
      'Connexion sécurisée (HTTPS) impossible avec le serveur : version TLS ou '
      'chiffrement incompatible. Contactez l\'hébergeur.',
    );
  }
}

/// La réponse est-elle une PAGE WEB (page d'erreur, de maintenance, d'identification
/// de l'hébergeur) au lieu des données JSON attendues ?
bool reponseEstHtml(http.Response r) {
  final type = (r.headers['content-type'] ?? '').toLowerCase();
  if (type.contains('json')) return false;
  if (type.contains('html')) return true;
  final debut = r.body.trimLeft();
  return debut.startsWith('<!') || debut.toLowerCase().startsWith('<html');
}

/// Message français d'une réponse non exploitable, ou `null` si c'est une
/// réponse ordinaire (le serveur écrit déjà ses refus métier en français).
String? messageReponseInattendue(http.Response r) {
  final s = r.statusCode;
  if (s == 413) {
    return 'Le serveur refuse un envoi trop volumineux (limite de l\'hébergeur, '
        'HTTP 413).';
  }
  if (s == 429) {
    // Le serveur écrit déjà ce refus en français (ex. « Trop de tentatives. »).
    final propre = _messageJson(r);
    if (propre != null) return propre;
    final attente = TransportHttp._retryAfter(r);
    return 'Trop de requêtes : le serveur demande de patienter'
        '${attente == null ? '' : ' (${attente.inSeconds} s)'}. '
        'Nouvel essai au prochain cycle.';
  }
  if (s == 502 || s == 503 || s == 504) {
    return 'Le serveur est momentanément indisponible (HTTP $s : maintenance '
        'ou surcharge de l\'hébergeur). Nouvel essai au prochain cycle.';
  }
  if (reponseEstHtml(r)) {
    return 'Le serveur a répondu une page web au lieu de données (page d\'erreur '
        'ou de maintenance de l\'hébergeur, HTTP $s). Vérifiez l\'adresse du '
        'serveur (dossier, https).';
  }
  if (s >= 300 && s < 400) {
    return 'Le serveur redirige vers une autre adresse (HTTP $s) : vérifiez '
        'l\'adresse saisie (https, dossier).';
  }
  if (s == 500) {
    return 'Erreur interne du serveur (HTTP 500). Si elle persiste, prévenez '
        'l\'administrateur du serveur.';
  }
  return null;
}

String? _messageJson(http.Response r) {
  try {
    final v = jsonDecode(r.body);
    final m = v is Map ? v['message'] : null;
    return m is String && m.trim().isNotEmpty ? m.trim() : null;
  } on FormatException {
    return null;
  }
}
