import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../administration/data/repositories/preferences_poste_repository.dart';
import 'depot_jeton_sync.dart';

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
  });

  final String identifiantPoste;
  final String? adresse;
  final bool appaire;
  final String? codePoste;
  final String? compte;
  final DateTime? appaireLe;
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
  });

  final PreferencesPosteRepository preferences;
  final DepotJetonSync depot;
  final http.Client? client;
  final Duration delai;

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
    );
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
    final reponse = await _appeler(
      (c) => c.post(
        Uri.parse('$propre/api/auth/login'),
        headers: _entetes(),
        body: jsonEncode({
          'identifiant': identifiant.trim(),
          'password': motDePasse,
          'device_name': idPoste,
        }),
      ),
    );
    if (reponse == null) return _injoignable(propre);

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

    final reponse = await _appeler(
      (c) => c.get(
        Uri.parse('$adresse/api/auth/me'),
        headers: _entetes(jeton: jeton),
      ),
    );
    if (reponse == null) return _injoignable(adresse);

    if (reponse.statusCode == 401) {
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
      final reponse = await _appeler(
        (c) => c.post(
          Uri.parse('$adresse/api/auth/logout'),
          headers: _entetes(jeton: jeton),
        ),
      );
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
  };

  /// `null` = le serveur n'a pas répondu (réseau, DNS, délai).
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
