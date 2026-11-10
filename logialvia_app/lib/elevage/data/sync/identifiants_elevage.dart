import '../../../core/sync/identifiant_poste.dart';

/// Identifiants **déterministes** des faits d'élevage (schéma v38, `46a_`).
///
/// Une fiche journalière est unique par (espèce, date) : deux postes qui saisissent le
/// même jour doivent converger sur la MÊME ligne, pas sur deux lignes qui violeraient
/// `UNIQUE(espece, date)`. Le serveur recalcule ces identifiants pour les vérifier : une
/// ligne dont l'UUID n'est pas celui de sa clé est refusée.
///
/// Les dates sont des **dates civiles** (`AAAA-MM-JJ`), jamais des instants : minuit
/// local à Porto-Novo et minuit local à Paris désignent le même jour pour l'éleveur.
String jourCivil(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// UUID de la fiche de [espece] pour le jour de [date].
String identifiantFicheJournee(String espece, DateTime date) =>
    uuidDeterministe('fiche_journee:$espece|${jourCivil(date)}');

/// UUID du compteur de ventes de [espece] pour le jour de [date], tenu par le poste
/// [poste] (son identifiant, celui du jeton côté serveur).
String identifiantVentesJour(String espece, DateTime date, String poste) =>
    uuidDeterministe('fiche_ventes_jour:$espece|${jourCivil(date)}|$poste');

/// UUID du soin engendré par l'échéance [echeanceId] du calendrier de prophylaxie pour la
/// bande [bandeId] (`47e_`). Déterministe : deux postes qui « génèrent les soins du
/// calendrier » pour la même bande écrivent la MÊME ligne, jamais deux rappels Newcastle.
String identifiantSoinProphylaxie(String bandeId, String echeanceId) =>
    uuidDeterministe('soin_prophylaxie:$bandeId|$echeanceId');
