/// Statuts d'un soin — Doc D1.
class StatutSoin {
  StatutSoin._();

  static const String planifie = 'Planifié';
  static const String effectue = 'Effectué';
  static const String enRetard = 'En retard';
  static const String traitementEnCours = 'Traitement en cours';

  static const List<String> tous = [
    planifie,
    effectue,
    enRetard,
    traitementEnCours,
  ];
}

/// Types d'action, tels que proposés par la modale « Nouveau Soin »
/// (soins-calendrier.html l.277-280) — liste fermée, pas de saisie libre.
class TypeSoin {
  TypeSoin._();

  static const List<String> tous = [
    'Vaccination',
    'Traitement curatif',
    'Vermifuge',
    'Vitamines',
  ];
}

/// Une intervention vétérinaire, planifiée ou réalisée.
class Soin {
  const Soin({
    required this.id,
    required this.espece,
    required this.datePrevue,
    required this.typeSoin,
    required this.statut,
    this.produit,
    this.dose,
    this.remanenceJours = 0,
    this.veterinaire,
    this.symptomes,
    this.coutFcfa = 0,
    this.observations,
    this.bandeId,
    this.echeanceProphylaxieId,
  });

  final int id;
  final String espece;
  final DateTime datePrevue;
  final String typeSoin;
  final String statut;
  final String? produit;
  final String? dose;
  final int remanenceJours;
  final String? veterinaire;
  final String? symptomes;
  final int coutFcfa;
  final String? observations;

  /// Bande dont ce soin decoule, quand il a ete planifie depuis le calendrier
  /// de prophylaxie d'une fiche. `null` pour un soin saisi a la main.
  final int? bandeId;

  /// Echeance du calendrier dont ce soin decoule.
  ///
  /// Avec [bandeId], c'est ce qui permet a la fiche d'afficher « deja
  /// planifie » au lieu de proposer une seconde fois le meme rappel.
  final int? echeanceProphylaxieId;

  bool get vientDuCalendrier =>
      bandeId != null && echeanceProphylaxieId != null;

  bool get estEffectue => statut == StatutSoin.effectue;
  bool get estEnRetard => statut == StatutSoin.enRetard;
  bool get estPlanifie => statut == StatutSoin.planifie;

  /// Fin du délai d'attente : au-delà, les produits de l'animal redeviennent
  /// commercialisables. `null` si aucune rémanence n'est déclarée.
  DateTime? get finRemanence => remanenceJours <= 0
      ? null
      : datePrevue.add(Duration(days: remanenceJours));

  /// Vrai si le délai d'attente court encore à la date donnée.
  bool remanenceActive(DateTime maintenant) {
    final fin = finRemanence;
    if (fin == null || !estEffectue) return false;
    return maintenant.isBefore(fin);
  }
}

/// Niveaux d'isolement de l'infirmerie (soins-calendrier.html l.308-310).
class NiveauIsolement {
  NiveauIsolement._();

  static const String surveillance = 'Simple surveillance';
  static const String infirmerie = 'Infirmerie';
  static const String quarantaineStricte = 'Quarantaine stricte';

  static const List<String> tous = [
    surveillance,
    infirmerie,
    quarantaineStricte,
  ];
}

/// Statuts d'une entrée d'infirmerie (l.220-223).
class StatutInfirmerie {
  StatutInfirmerie._();

  static const String enCours = 'En cours';
  static const String reintegre = 'Réintégré';
  static const String decede = 'Décédé';
}

/// Une entrée d'infirmerie / quarantaine.
class EntreeInfirmerie {
  const EntreeInfirmerie({
    required this.id,
    required this.dateEntree,
    required this.sujet,
    required this.motif,
    required this.niveauIsolement,
    required this.statut,
    this.dateSortie,
    this.espece,
    this.categorieMortalite,
  });

  final int id;
  final DateTime dateEntree;
  final String sujet;
  final String motif;
  final String niveauIsolement;
  final String statut;
  final DateTime? dateSortie;
  final String? espece;

  /// Index, dans `ConfigurationEspece.categories`, de la categorie ou le deces
  /// a ete porte sur la fiche d'elevage. `null` s'il ne l'a pas ete.
  final int? categorieMortalite;

  bool get estEnCours => statut == StatutInfirmerie.enCours;

  bool get estDecede => statut == StatutInfirmerie.decede;

  /// Vrai quand le deces a reellement ete compte dans la fiche d'elevage.
  ///
  /// Distinguer « decede » de « decede **et compte** » est ce qui empeche le
  /// double comptage : sans cette marque, rien ne dirait si la perte a deja
  /// ete portee sur la fiche ou s'il reste a le faire.
  bool get reporteEnFiche => estDecede && categorieMortalite != null;
}
