import '../../domain/entities/configuration_espece.dart';

/// Petits outils communs aux trois `Table*Poste` d'élevage (`46a_`). Ils servent
/// l'**absorbeur strict** : une valeur incohérente est refusée, jamais lissée.
class OutilsSyncElevage {
  const OutilsSyncElevage._();

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool estUuid(Object? v) => v is String && _uuid.hasMatch(v);

  /// Une filière que ce poste connaît (les 8 de `ConfigurationsEspeces`).
  static bool especeConnue(Object? v) =>
      v is String && ConfigurationsEspeces.parIdentifiant.containsKey(v);

  /// `AAAA-MM-JJ` (ou un instant ISO dont on ne garde que la date) -> ce jour, à minuit
  /// LOCAL. `null` si le texte n'est pas une date réelle (le 31 février est refusé).
  static DateTime? jour(Object? v) {
    if (v is! String || v.length < 10) return null;
    final a = int.tryParse(v.substring(0, 4));
    final m = int.tryParse(v.substring(5, 7));
    final j = int.tryParse(v.substring(8, 10));
    if (a == null || m == null || j == null || v[4] != '-' || v[7] != '-') {
      return null;
    }
    final d = DateTime(a, m, j);
    return d.year == a && d.month == m && d.day == j ? d : null;
  }

  static DateTime? instant(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  /// Entier ≥ 0. `null` n'est PAS accepté ici : voir [entierOuNull].
  static bool entierPositif(Object? v) => v is int && v >= 0;

  /// Absent (`null`) ou entier ≥ 0.
  static bool entierOuNull(Object? v) => v == null || entierPositif(v);

  /// Texte non vide ; `null` sinon.
  static String? texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;
}
