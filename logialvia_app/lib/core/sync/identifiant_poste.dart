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
