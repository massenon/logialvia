/// Une bande — des sujets mis en place à une date, sur une filière.
///
/// C'est la donnée qui manquait pour convertir un « J5 » du calendrier de
/// prophylaxie en une date réelle. Sans elle, l'injection annoncée par
/// `parametres-elevage.html` restait impossible.
class Bande {
  const Bande({
    required this.id,
    required this.espece,
    required this.code,
    required this.dateMiseEnBande,
    this.effectifInitial,
    this.dateCloture,
    this.observations,
    this.motifConflit,
  });

  final String id;
  final String espece;
  final String code;

  /// **J1 du cycle** — le jour de la mise en place, pas le lendemain.
  final DateTime dateMiseEnBande;

  /// Déclaré à la mise en place. **Indicatif** : l'effectif réel reste celui
  /// de `FICHE_JOURNEE`, calculé jour après jour (BR-ELV-007).
  final int? effectifInitial;

  final DateTime? dateCloture;
  final String? observations;

  /// Motif de refus du serveur (« Ce code de bande est déjà utilisé… ») tant que la bande
  /// attend d'être recodée ; `null` sinon (`47e_`).
  final String? motifConflit;

  bool get enConflit => motifConflit != null;

  /// Code de recodage proposé quand deux postes ont déclaré le même code hors ligne :
  /// `B2` devient `B2-P2` (code du poste), puis `B2-P2-2`… tant qu'il est pris.
  static String proposerCodeRecodage(
    String code, {
    required String? codePoste,
    required Set<String> codesPris,
  }) {
    final racine = '${code.trim()}-${codePoste ?? 'X'}';
    if (!codesPris.contains(racine)) return racine;
    var n = 2;
    while (codesPris.contains('$racine-$n')) {
      n++;
    }
    return '$racine-$n';
  }

  bool get estEnCours => dateCloture == null;

  /// Jour de cycle à la date donnée. J1 = jour de la mise en bande.
  ///
  /// Vaut 0 ou moins avant la mise en place — un jour de cycle négatif n'est
  /// pas une erreur à masquer, c'est une date antérieure à la bande.
  int jourDeCycle(DateTime date) {
    final debut = _minuit(dateMiseEnBande);
    final jour = _minuit(date);
    return jour.difference(debut).inDays + 1;
  }

  /// Date réelle d'un jour de cycle. `jourDeCycle(dateDuJourDeCycle(n)) == n`.
  DateTime dateDuJourDeCycle(int jourCycle) =>
      _minuit(dateMiseEnBande).add(Duration(days: jourCycle - 1));

  /// Vrai si la bande couvre cette date : après la mise en place, et pas
  /// encore clôturée à cette date-là.
  bool couvre(DateTime date) {
    final jour = _minuit(date);
    if (jour.isBefore(_minuit(dateMiseEnBande))) return false;
    final fin = dateCloture;
    return fin == null || !jour.isAfter(_minuit(fin));
  }

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);
}
