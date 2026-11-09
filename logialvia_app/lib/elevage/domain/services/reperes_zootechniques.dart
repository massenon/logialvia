/// Niveau d'une alerte zootechnique (DV-13).
enum NiveauAlerte { normal, avertissement, critique }

/// Repères zootechniques de LogiALVIA, **tous au même endroit** (`47e_`).
///
/// Chaque constante cite sa source. Les seuils de mortalité sont ceux de DV-13
/// (`docs/logialvia/15_REGLES_METIER.md` RM-COU-06, **recommandés**, à confirmer avec le
/// technicien) ; ils sont appliqués avec des comparaisons **strictes** (« supérieur à »).
///
/// Le web les reprend à l'identique (`App\Support\ReperesZootechniques`), vérifié par
/// des tests aux mêmes valeurs chiffrées.
class ReperesZootechniques {
  const ReperesZootechniques._();

  // ------------------------------------------------------------- mortalité

  /// Mortalité **du jour** (morts ÷ effectif de la veille) : au-delà, avertissement.
  static const double mortaliteJourAvertissement = 1;

  /// Mortalité du jour : au-delà, critique.
  static const double mortaliteJourCritique = 2;

  /// Mortalité **cumulée** depuis la mise en place : au-delà, avertissement.
  static const double mortaliteCumulAvertissement = 10;

  /// Mortalité cumulée : au-delà, critique.
  static const double mortaliteCumulCritique = 20;

  static NiveauAlerte niveauMortaliteJour(double tauxPourcent) =>
      tauxPourcent > mortaliteJourCritique
      ? NiveauAlerte.critique
      : tauxPourcent > mortaliteJourAvertissement
      ? NiveauAlerte.avertissement
      : NiveauAlerte.normal;

  static NiveauAlerte niveauMortaliteCumul(double tauxPourcent) =>
      tauxPourcent > mortaliteCumulCritique
      ? NiveauAlerte.critique
      : tauxPourcent > mortaliteCumulAvertissement
      ? NiveauAlerte.avertissement
      : NiveauAlerte.normal;

  /// Taux de mortalité cumulé (en %) = morts cumulés ÷ (effectif de départ + entrées
  /// cumulées) × 100 : l'effectif **exposé** au risque, jamais le seul effectif du
  /// premier jour. `null` sans effectif exposé (« — » à l'écran, jamais « 0 % »).
  static double? tauxMortaliteCumule({
    required int morts,
    required int effectifDepart,
    required int entrees,
  }) {
    final base = effectifDepart + entrees;
    if (base <= 0) return null;
    return morts / base * 100;
  }

  // -------------------------------------------------------------- croissance

  /// Gain moyen quotidien (g/jour/sujet) = (poids moyen final − poids moyen initial)
  /// ÷ nombre de jours. `null` si l'intervalle n'est pas strictement positif.
  /// Négatif possible (perte de poids) : c'est une information, pas une erreur.
  static double? gmqGrammesParJour({
    required double poidsMoyenInitialG,
    required double poidsMoyenFinalG,
    required int jours,
  }) {
    if (jours <= 0) return null;
    return (poidsMoyenFinalG - poidsMoyenInitialG) / jours;
  }

  /// Indice de consommation = aliment consommé ÷ gain de poids total (même unité).
  /// `null` si le gain n'est pas strictement positif : un IC sans gain n'a pas de sens
  /// (diviser par zéro, ou par une perte de poids, donnerait un chiffre trompeur).
  static double? indiceConsommation({
    required num alimentConsomme,
    required num gainPoidsTotal,
  }) {
    if (gainPoidsTotal <= 0) return null;
    return alimentConsomme / gainPoidsTotal;
  }

  // ------------------------------------------------------ poids vraisemblable

  /// Fourchette du poids **moyen** d'un sujet de la filière, en grammes, toutes
  /// catégories confondues (un lot mêle des jeunes et des adultes : la borne basse est
  /// celle du plus jeune, la haute celle du plus lourd). Hors de cette fourchette, la
  /// pesée est presque certainement une erreur d'unité ou de décompte.
  ///
  /// Repères : poussin de poule ≈ 40 g, coq Goliath adulte ≤ 6 kg, pintade adulte
  /// ≤ 2,8 kg, lapin ≤ 7 kg (géant), clarias de 0,2 g (alevin) à 15 kg, achatine ≤ 250 g,
  /// bovin de 15 kg (veau) à 1,1 t.
  static ({int min, int max}) poidsMoyenPlausibleG(String espece) =>
      switch (espece) {
        'goliaths' => (min: 30, max: 6000),
        'pintades' => (min: 25, max: 2800),
        'lapins' => (min: 30, max: 7000),
        'poulets' => (min: 30, max: 6000),
        'pondeuses' => (min: 30, max: 4000),
        'poissons-chats' => (min: 0, max: 15000),
        'escargots' => (min: 0, max: 250),
        'bovins' => (min: 15000, max: 1100000),
        _ => (min: 0, max: 2000000),
      };

  // ------------------------------------------------------------------- ponte

  /// Au-delà, un taux de ponte (œufs ÷ pondeuses) est exceptionnel : le pic d'une
  /// pondeuse commerciale est de 92 à 96 %.
  static const double tauxPonteExceptionnel = 96;

  /// Œufs cassés au-delà de cette part des œufs pondus : à vérifier (un élevage
  /// maîtrisé reste sous 5 %).
  static const double partOeufsCassesAVerifier = 10;

  // --------------------------------------------------------------- incubation

  /// Durées d'incubation de référence, en jours (volailles). Seules `goliath` (poule,
  /// 21 j) et `pintade` (28 j) sont couvables dans LogiALVIA (`EspeceCouvable`) ; les
  /// autres sont consignées pour la documentation et pour un futur élargissement.
  static const Map<String, int> dureesIncubationJours = {
    'poule': 21,
    'goliath': 21,
    'pintade': 28,
    'canard': 28,
    'canard de Barbarie': 35,
    'dinde': 28,
    'oie': 30,
    'caille': 17,
  };

  /// Un mirage à J+7 ne distingue rien avant J+5 ; celui de J+14 avant J+12.
  static const int mirage1AuPlusTot = 5;
  static const int mirage2AuPlusTot = 12;

  /// Une éclosion plus de 4 jours avant le terme de l'espèce est impossible.
  static const int eclosionAvanceMaximaleJours = 4;
}
