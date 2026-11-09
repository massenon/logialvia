import 'dart:math';

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

/// Instant de **saisie** (UTC, microsecondes) : `updated_at` des tables
/// synchronisées. Jamais l'instant d'envoi (`46_` §1) : un poste hors ligne
/// trois jours ne doit pas battre une saisie plus récente faite ailleurs.
///
/// Texte ISO 8601 et non `DateTimeColumn` : Drift stocke les dates à la
/// seconde, trop grossier pour « dernier écrivain gagne ».
String instantSaisie([DateTime? maintenant]) =>
    (maintenant ?? DateTime.now()).toUtc().toIso8601String();
