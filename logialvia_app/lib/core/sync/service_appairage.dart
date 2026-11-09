import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../administration/data/repositories/preferences_poste_repository.dart';
import 'depot_jeton_sync.dart';
import 'droits_poste.dart';
import 'identifiant_poste.dart';
import 'transport_http.dart';

/// Issue d'une tentative d'appairage ou de test de connexion.
enum IssueAppairage {
  /// Le serveur a répondu, le jeton est gardé.
  appaire,

  /// Identifiant ou mot de passe refusé, compte désactivé, trop d'essais…
  refuse,

  /// Pas de réseau, serveur éteint, délai dépassé. **Pas une erreur de poste** :
  /// hors ligne est un état normal (blueprint §3).
  injoignable,

  /// Adresse manquante ou illisible : rien n'a été envoyé.
  adresseInvalide,

  /// Jeton révoqué ou expiré (401 sur un poste appairé).
  revoque,

  /// Appairage rompu à la demande de l'utilisatrice.
  deconnecte,
}

class ResultatAppairage {
  const ResultatAppairage(this.issue, this.message, {this.codePoste});

  final IssueAppairage issue;

  /// Message en français, destiné à l'utilisatrice.
  final String message;
  final String? codePoste;

  bool get reussi => issue == IssueAppairage.appaire;
}

/// Ce que le poste sait de son propre appairage.
class EtatAppairage {
  const EtatAppairage({
    required this.identifiantPoste,
    required this.adresse,
    required this.appaire,
    this.codePoste,
    this.compte,
    this.appaireLe,
    this.droits,
    this.decalageHorloge,
  });

  final String identifiantPoste;
  final String? adresse;
  final bool appaire;
  final String? codePoste;
  final String? compte;
  final DateTime? appaireLe;

  /// Droits du compte appairé (`47g_`), `null` : inconnus.
  final DroitsPoste? droits;

  /// Dernier écart mesuré de l'horloge (poste − serveur), `null` : jamais mesuré.
  final Duration? decalageHorloge;

  AnalyseHorloge? get horloge =>
      decalageHorloge == null ? null : analyserHorloge(decalageHorloge!);
}

/// Appairage du poste avec le serveur web (`45_`, `46_`, blueprint §2).
///
/// **Appairage = connexion** : `POST /api/auth/login {identifiant, password,
/// device_name}`. `device_name` est l'UUID du poste ; le serveur crée un jeton
/// nommé d'après lui (un seul actif par poste).
///
/// - Le **mot de passe n'est jamais gardé** ni journalisé : il traverse cette
///   méthode et disparaît. Seul le jeton est conservé, au coffre du système.
/// - Les **comptes locaux ne changent pas** (DV-20) : l'appairage ne sert qu'à
///   la synchronisation, il n'ouvre aucune session dans l'application.
class ServiceAppairage {
  ServiceAppairage({
    required this.preferences,
    required this.depot,
    this.client,
    this.delai = const Duration(seconds: 15),
    this.delaisRepetition = const [
      Duration(milliseconds: 500),
      Duration(seconds: 2),
    ],
    this.pause,
  });

  final PreferencesPosteRepository preferences;
  final DepotJetonSync depot;
  final http.Client? client;
  final Duration delai;
  final List<Duration> delaisRepetition;
  final Future<void> Function(Duration)? pause;

  late final TransportHttp _transport = TransportHttp(
    client: client,
    delai: delai,
    delaisRepetition: delaisRepetition,
    pause: pause,
  );

  Future<EtatAppairage> etat() async {
    final jeton = await depot.lire();
    final code = await preferences.codePoste();
    return EtatAppairage(
      identifiantPoste: await preferences.identifiantPoste(),
      adresse: await preferences.adresseServeur(),
      appaire: jeton != null && jeton.isNotEmpty && code != null,
      codePoste: code,
      compte: await preferences.compteAppaire(),
      appaireLe: await preferences.appaireLe(),
      droits: await preferences.droitsSync(),
      decalageHorloge: await preferences.decalageHorloge(),
    );
  }

  /// Retient les droits et l'écart d'horloge que le serveur vient d'annoncer.
  Future<void> _memoriserDroitsEtHorloge(
    Map<String, dynamic>? json,
    DateTime avant,
    DateTime apres,
  ) async {
    final droits = DroitsPoste.depuisJson(json?['droits']);
    if (droits != null) await preferences.definirDroitsSync(droits);
    final serveur = json?['server_now'] is String
        ? DateTime.tryParse(json!['server_now'] as String)
        : null;
    if (serveur != null) {
      await preferences.definirDecalageHorloge(
        mesurerDecalage(avant: avant, apres: apres, serveur: serveur),
      );
    }
  }

  Future<ResultatAppairage> connecter({
    required String adresse,
    required String identifiant,
    required String motDePasse,
  }) async {
    final propre = await preferences.definirAdresseServeur(adresse);
    if (propre == null) {
      return const ResultatAppairage(
        IssueAppairage.adresseInvalide,
        'Adresse du serveur invalide. Exemple : https://logialvia.exemple.bj '
        'ou 192.168.1.10:8000.',
      );
    }
    if (identifiant.trim().isEmpty || motDePasse.isEmpty) {
      return const ResultatAppairage(
        IssueAppairage.refuse,
        'Renseignez l\'identifiant et le mot de passe du compte web.',
      );
    }

    final idPoste = await preferences.identifiantPoste();
    final avant = horlogePoste();
    final resultat = await _appeler(
      propre,
      (c, base) => c.post(
        Uri.parse('$base/api/auth/login'),
        headers: _entetes(),
        body: jsonEncode({
          'identifiant': identifiant.trim(),
          'password': motDePasse,
          'device_name': idPoste,
        }),
      ),
    );
    final echec = _echecReseau(resultat, propre);
    if (echec != null) return echec;
    final reponse = resultat.reponse!;

    final apres = horlogePoste();
    final json = _json(reponse.body);
    if (reponse.statusCode != 200) {
      return ResultatAppairage(
        IssueAppairage.refuse,
        _messageServeur(reponse, json),
      );
    }

    final jeton = json?['token'];
    final code = (json?['poste'] as Map?)?['code'];
    if (jeton is! String || jeton.isEmpty || code is! String) {
      return const ResultatAppairage(
        IssueAppairage.refuse,
        'Réponse du serveur inattendue : appairage non enregistré.',
      );
    }

    try {
      await depot.ecrire(jeton);
    } on Exception {
      return const ResultatAppairage(
        IssueAppairage.refuse,
        'Le coffre sécurisé du système a refusé de garder le jeton : '
        'appairage non enregistré.',
      );
    }
    await preferences.memoriserAppairage(
      codePoste: code,
      compte: identifiant.trim(),
      le: DateTime.now(),
    );
    // `47g_` : les droits de CE compte accompagnent l'appairage (changement de compte compris),
    // et l'écart d'horloge est mesuré dès la connexion.
    await preferences.definirDroitsSync(null);
    await _memoriserDroitsEtHorloge(json, avant, apres);

    final temporaire = json?['must_change_password'] == true;
    return ResultatAppairage(
      IssueAppairage.appaire,
      temporaire
          ? 'Poste appairé (code $code). Ce compte a un mot de passe '
                'temporaire : changez-le sur le web avant de synchroniser.'
          : 'Poste appairé (code $code).',
      codePoste: code,
    );
  }

  /// « Tester la connexion » : `GET /api/auth/me` avec le jeton gardé.
  Future<ResultatAppairage> tester() async {
    final adresse = await preferences.adresseServeur();
    final jeton = await depot.lire();
    if (adresse == null || jeton == null || jeton.isEmpty) {
      return const ResultatAppairage(
        IssueAppairage.refuse,
        'Ce poste n\'est pas appairé.',
      );
    }

    final avant = horlogePoste();
    final resultat = await _appeler(
      adresse,
      (c, base) => c.get(
        Uri.parse('$base/api/auth/me'),
        headers: _entetes(jeton: jeton),
      ),
    );
    final apres = horlogePoste();
    final echec = _echecReseau(resultat, adresse);
    if (echec != null) return echec;
    final reponse = resultat.reponse!;

    if (reponse.statusCode == 401 && _estRefusDeJeton(reponse)) {
      // Jeton révoqué ou expiré : on l'oublie, le poste redemande une connexion
      // (blueprint §2). Les saisies locales ne sont pas touchées.
      await oublierLocalement();
      return const ResultatAppairage(
        IssueAppairage.revoque,
        'Ce poste n\'est plus appairé : le jeton a été révoqué ou a expiré. '
        'Reconnectez-vous. Vos saisies sur ce poste sont conservées.',
      );
    }
    if (reponse.statusCode != 200) {
      return ResultatAppairage(
        IssueAppairage.refuse,
        _messageServeur(reponse, _json(reponse.body)),
      );
    }

    final json = _json(reponse.body);
    await _memoriserDroitsEtHorloge(json, avant, apres);
    final code =
        (json?['poste'] as Map?)?['code'] ?? await preferences.codePoste();
    return ResultatAppairage(
      IssueAppairage.appaire,
      'Connexion réussie — poste $code.',
      codePoste: code is String ? code : null,
    );
  }

  /// Le serveur a répondu 401 : le jeton est mort. Le poste l'oublie et redemande
  /// une connexion ; ses saisies locales ne sont pas touchées.
  Future<void> oublierLocalement() async {
    await depot.effacer();
    await preferences.oublierAppairage();
  }

  /// Rompt l'appairage. Le jeton local est **toujours** effacé ; le serveur est
  /// prévenu au mieux (s'il est injoignable, le jeton y reste valide jusqu'à
  /// sa révocation depuis le web, ce que le message dit).
  Future<ResultatAppairage> deconnecter() async {
    final adresse = await preferences.adresseServeur();
    final jeton = await depot.lire();

    var serveurPrevenu = false;
    if (adresse != null && jeton != null && jeton.isNotEmpty) {
      final reponse = (await _appeler(
        adresse,
        (c, base) => c.post(
          Uri.parse('$base/api/auth/logout'),
          headers: _entetes(jeton: jeton),
        ),
      )).reponse;
      serveurPrevenu = reponse != null && reponse.statusCode < 300;
      // 401 : le jeton était déjà mort, le serveur n'a rien à savoir de plus.
      if (reponse?.statusCode == 401) serveurPrevenu = true;
    }

    await depot.effacer();
    await preferences.oublierAppairage();

    return ResultatAppairage(
      IssueAppairage.deconnecte,
      serveurPrevenu
          ? 'Poste déconnecté.'
          : 'Poste déconnecté localement, mais le serveur n\'a pas pu être '
                'prévenu : son jeton reste valide jusqu\'à sa révocation '
                'depuis le web (Postes & Appairage).',
    );
  }

  // ------------------------------------------------------------------ Outils

  Map<String, String> _entetes({String? jeton}) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (jeton != null) 'Authorization': 'Bearer $jeton',
    // Double pour les hébergeurs qui retirent `Authorization` (`47r_`).
    if (jeton != null) 'X-Authorization': 'Bearer $jeton',
  };

  /// Appel HTTP : jamais d'exception ; l'adresse corrigée (http → https) est mémorisée.
  Future<ResultatHttp> _appeler(
    String adresse,
    Future<http.Response> Function(http.Client c, String base) requete,
  ) async {
    final r = await _transport.appeler(requete, adresse: adresse);
    if (r.adresseCorrigee != null) {
      await preferences.definirAdresseServeur(r.adresseCorrigee!);
    }
    return r;
  }

  /// Le résultat d'un échec avant toute réponse, ou d'une réponse qui n'est pas celle de
  /// l'application (page de l'hébergeur, 502/503, 413…) ; `null` sinon.
  ResultatAppairage? _echecReseau(ResultatHttp resultat, String adresse) {
    final erreur = resultat.erreur;
    if (erreur != null) {
      return erreur.genre == GenreErreurReseau.horsLigne
          ? _injoignable(adresse)
          : ResultatAppairage(
              erreur.genre == GenreErreurReseau.certificat ||
                      erreur.genre == GenreErreurReseau.securite
                  ? IssueAppairage.refuse
                  : IssueAppairage.injoignable,
              erreur.message,
            );
    }
    final inattendu = messageReponseInattendue(resultat.reponse!);
    if (inattendu == null) return null;
    final transitoire = [
      429,
      502,
      503,
      504,
    ].contains(resultat.reponse!.statusCode);
    return ResultatAppairage(
      transitoire ? IssueAppairage.injoignable : IssueAppairage.refuse,
      inattendu,
    );
  }

  /// 401 JSON de l'application seulement (cf. moteur) : une page de l'hébergeur ou un
  /// en-tête `Authorization` jamais arrivé ne fait pas oublier un jeton valide.
  bool _estRefusDeJeton(http.Response reponse) {
    if (reponseEstHtml(reponse)) return false;
    return _json(reponse.body)?['code'] != 'jeton_absent';
  }

  ResultatAppairage _injoignable(String adresse) => ResultatAppairage(
    IssueAppairage.injoignable,
    'Serveur injoignable ($adresse). Vérifiez l\'adresse et la connexion ; '
    'hors ligne, le poste continue de fonctionner normalement.',
  );

  Map<String, dynamic>? _json(String corps) {
    try {
      final v = jsonDecode(corps);
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }

  /// Le serveur écrit déjà ses refus en français : on les montre tels quels.
  String _messageServeur(http.Response reponse, Map<String, dynamic>? json) {
    final message = json?['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
    return 'Le serveur a refusé la demande (HTTP ${reponse.statusCode}).';
  }
}
