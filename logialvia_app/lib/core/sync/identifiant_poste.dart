import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// UUID v4 (RFC 4122) tiré du générateur cryptographique.
///
/// Pas de dépendance `uuid` : 12 lignes suffisent, et le serveur ne vérifie
/// que le format (`uuid` de Laravel : 8-4-4-4-12 hexadécimaux).
String genererUuidV4([Random? alea]) {
  final r = alea ?? Random.secure();
  final octets = List<int>.generate(16, (_) => r.nextInt(256));
  octets[6] = (octets[6] & 0x0f) | 0x40; // version 4
  octets[8] = (octets[8] & 0x3f) | 0x80; // variante RFC 4122
  final hex = octets.map((o) => o.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// `clientDefault` de Drift : un UUID neuf par ligne créée au poste (DV-19).
String nouvelUuid() => genererUuidV4();

/// L'horloge du poste. Seul point d'injection du temps pour la synchronisation (`47g_`) : les tests
/// (et l'essai contre le vrai serveur) y simulent une horloge en avance ou en retard ; en
/// production c'est `DateTime.now`. À remettre à `DateTime.now` après usage.
DateTime Function() horlogePoste = DateTime.now;

/// Instant de **saisie** (UTC, microsecondes) : `updated_at` des tables
/// synchronisées. Jamais l'instant d'envoi (`46_` §1) : un poste hors ligne
/// trois jours ne doit pas battre une saisie plus récente faite ailleurs.
///
/// Texte ISO 8601 et non `DateTimeColumn` : Drift stocke les dates à la
/// seconde, trop grossier pour « dernier écrivain gagne ».
String instantSaisie([DateTime? maintenant]) =>
    (maintenant ?? horlogePoste()).toUtc().toIso8601String();

/// UUID **déterministe** (version 5, SHA-1) calculé depuis une clé métier.
///
/// Pour les données SEMÉES identiquement sur tous les postes (le catalogue) : deux
/// postes installés du même programme doivent donner le MÊME identifiant au même
/// produit, sinon « Goliath mature » existerait en double sur le serveur. Une
/// donnée créée par l'utilisatrice reçoit un UUID aléatoire ([nouvelUuid]).
String uuidDeterministe(String cle) {
  final octets = sha1
      .convert(utf8.encode('logialvia:$cle'))
      .bytes
      .sublist(0, 16);
  octets[6] = (octets[6] & 0x0f) | 0x50; // version 5
  octets[8] = (octets[8] & 0x3f) | 0x80; // variante RFC 4122
  final hex = octets.map((o) => o.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
