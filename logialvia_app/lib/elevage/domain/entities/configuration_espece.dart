/// Une categorie d'age d'une espece, avec sa ration normative.
class CategorieEspece {
  const CategorieEspece({
    required this.libelle,
    required this.rationGrammesParJour,
    this.recoitAchatEtNaissances = false,
    this.deduiteDesVentes = false,
    this.stadesEquivalents = const [],
  });

  final String libelle;

  /// Autres intitulés sous lesquels le **barème** de cette catégorie peut avoir été
  /// semé ou saisi (`47e_`). Le barème est cherché par libellé de stade : sans cette
  /// équivalence, une ration modifiée dans Paramètres Élevage pour « Sevré / Lapereaux »
  /// ou « Alevins » (le stade de la pintade semé à tort, DV-09 l'interdit) restait sans
  /// effet sur la provende calculée, sans le dire.
  final List<String> stadesEquivalents;

  /// Ration normative en g/j, utilisee pour le calcul de provende.
  final int rationGrammesParJour;

  /// Categorie la plus jeune : elle seule recoit les achats et les naissances
  /// (Doc 05 §1).
  final bool recoitAchatEtNaissances;

  /// Categorie commercialisee : elle seule est decrementee par les ventes
  /// (Doc 05 §1).
  final bool deduiteDesVentes;
}

/// Configuration complete d'une fiche d'elevage.
///
/// **Un seul ecran generique parametre par cette configuration**, jamais 5
/// implementations independantes — exigence explicite de Strict Avoid §5
/// (patterns incoherents) et §15 (scalabilite : ajouter une 6ᵉ espece doit etre
/// une question de configuration, pas de duplication d'ecran).
class ConfigurationEspece {
  const ConfigurationEspece({
    required this.identifiant,
    required this.libelle,
    required this.icone,
    required this.route,
    required this.categories,
    required this.etapesCycle,
    this.noteRationnement,
    this.poidsMaturiteGrammes,
    this.ageMaturiteJours,
    this.libelleAchats = 'Achats',
    required this.libelleNaissances,
    this.rationEnPourcentagePoidsVif = false,
    this.uniteClassePoids = 'kg',
    this.tauxPoidsMaxPourcent = 10,
    this.rationMaxGrammesParJour = 5000,
  });

  /// Valeur stockee dans `FICHE_JOURNEE.espece`.
  final String identifiant;

  final String libelle;
  final String icone;
  final String route;

  /// Categories dans l'ordre : index 0 = `effCat1Day`, 1 = `effCat2Day`, etc.
  /// 3 categories pour 4 des 5 fiches, 4 pour Pondeuses (Doc 05 §4).
  final List<CategorieEspece> categories;

  /// Pastilles du bandeau « Rappel du Cycle ».
  final List<String> etapesCycle;

  /// Avertissement affiche sous le tableau de rationnement, quand le bareme
  /// n'est pas confirme pour l'espece.
  final String? noteRationnement;

  /// Seuils de l'alerte de maturite (fiche-goliaths.html l.683).
  final int? poidsMaturiteGrammes;
  final int? ageMaturiteJours;

  // ------------------------------------------------- glossaire de la filiere
  //
  // ⚠️ Les libelles de la saisie journaliere **ne sont pas les memes d'une
  // fiche a l'autre** : chaque HTML ecrit le sien. Les coder en dur dans
  // l'ecran — ce qui etait le cas — appliquait le vocabulaire avicole a toutes
  // les filieres, et faisait naitre les poissons-chats dans une couveuse.
  //
  // | Fiche | Entrees achetees | Naissances |
  // |---|---|---|
  // | Goliaths, Pintades | Achats | Nes (Couveuse) |
  // | Lapins | Achats | Nes (Mise bas) |
  // | Poissons-Chats | Achats | Nes |
  // | Poulets | Achats | Nes / Transferts |
  // | Pondeuses | Achats / Entrees | Nes / Transferts |

  /// Colonne 1 de la saisie journaliere. « Achats / Entrées » pour les
  /// Pondeuses, qui recoivent aussi des transferts depuis la fiche Poulets.
  final String libelleAchats;

  /// Colonne 2 de la saisie journaliere — alimente `FICHE_JOURNEE.ne`.
  ///
  /// Le mode d'arrivee des jeunes differe par filiere : une couveuse pour les
  /// volailles, une mise bas pour les lapins, ni l'une ni l'autre pour les
  /// poissons-chats.
  final String libelleNaissances;

  /// Vrai quand la provende se calcule en **% du poids vif** (matière sèche),
  /// d'après la pesée du jour et le tableau « Taux de ration par classe de
  /// poids » de Paramètres Élevage — le cas d'un ruminant (DV-17).
  ///
  /// À défaut de pesée, ou de classe pour le poids moyen, la fiche retombe sur
  /// les rations en g/tête/j de [categories], qui restent indicatives.
  final bool rationEnPourcentagePoidsVif;

  /// Unité dans laquelle on saisit les bornes des classes de poids : `'kg'`
  /// pour un ovin, `'g'` pour un poisson (classes de 5, 20, 100 g). Les poids
  /// sont toujours **stockés en grammes**.
  final String uniteClassePoids;

  /// Ration par tête au-delà de laquelle la saisie est une faute de frappe :
  /// 5 kg par jour pour une volaille, un lapin, un poisson ou un escargot, mais
  /// un ovin adulte ne mange guère plus de 1 à 2 kg de matière sèche par jour
  /// (plafond 4 kg).
  final int rationMaxGrammesParJour;

  /// Taux de ration au-delà duquel la saisie est une faute de frappe : un
  /// ruminant mange 2 à 4 % de son poids en matière sèche (plafond 10 %), mais
  /// un alevin de poisson-chat jusqu'à 20 % de sa biomasse (plafond 25 %).
  final double tauxPoidsMaxPourcent;

  /// Grammes dans une unité de [uniteClassePoids].
  int get grammesParUniteClassePoids => uniteClassePoids == 'g' ? 1 : 1000;

  int get nombreCategories => categories.length;

  int get indexCategorieJeune =>
      categories.indexWhere((c) => c.recoitAchatEtNaissances);

  int get indexCategorieCommercialisee =>
      categories.indexWhere((c) => c.deduiteDesVentes);
}

/// Referentiel des fiches (6 d'origine, plus escargots et ovins) — Doc 05 §3 (table de correspondance des
/// categories) et Doc F3.
///
/// Les rations proviennent du tableau de rationnement reel de chaque fiche
/// (`fiche-goliaths.html` l.644-646 : 30 / 60 / 110 g/j).
class ConfigurationsEspeces {
  ConfigurationsEspeces._();

  static const ConfigurationEspece goliaths = ConfigurationEspece(
    identifiant: 'goliaths',
    libelle: 'Goliaths',
    icone: 'pets',
    route: '/elevage/goliaths',
    categories: [
      CategorieEspece(
        libelle: 'Poussins',
        rationGrammesParJour: 30,
        recoitAchatEtNaissances: true,
      ),
      CategorieEspece(
        libelle: 'Goliathau',
        rationGrammesParJour: 60,
        deduiteDesVentes: true,
      ),
      CategorieEspece(libelle: 'Mature', rationGrammesParJour: 110),
    ],
    etapesCycle: [
      'Naissance (Couveuse)',
      'Goliathau (0 → 4 mois)',
      'Mature (≥ 4 mois, ≥ 2,8 kg) — Éligible à la Vente',
    ],
    noteRationnement:
        'Barème générique réutilisé de la référence Aviculture — aucun barème '
        'Goliath spécifique confirmé à ce jour, à valider avec la Gérante.',
    poidsMaturiteGrammes: 2800,
    ageMaturiteJours: 120,
    libelleNaissances: 'Nés (Couveuse)',
  );

  static const ConfigurationEspece pintades = ConfigurationEspece(
    identifiant: 'pintades',
    libelle: 'Pintades',
    icone: 'pets',
    route: '/elevage/pintades',
    categories: [
      CategorieEspece(
        libelle: 'Poussins',
        rationGrammesParJour: 30,
        recoitAchatEtNaissances: true,
        stadesEquivalents: ['Alevins'],
      ),
      CategorieEspece(
        libelle: 'Pintadau',
        rationGrammesParJour: 60,
        deduiteDesVentes: true,
      ),
      CategorieEspece(libelle: 'Mature', rationGrammesParJour: 110),
    ],
    etapesCycle: [
      'Naissance (Couveuse)',
      'Pintadau (0 → 4 mois)',
      'Mature — Éligible à la Vente',
    ],
    libelleNaissances: 'Nés (Couveuse)',
  );

  static const ConfigurationEspece lapins = ConfigurationEspece(
    identifiant: 'lapins',
    libelle: 'Lapins',
    icone: 'cruelty_free',
    route: '/elevage/lapins',
    categories: [
      CategorieEspece(
        libelle: 'Lapereau',
        rationGrammesParJour: 30,
        recoitAchatEtNaissances: true,
        stadesEquivalents: ['Sevré / Lapereaux'],
      ),
      CategorieEspece(
        libelle: 'Chair',
        rationGrammesParJour: 60,
        deduiteDesVentes: true,
        stadesEquivalents: ['Chair / Jeune'],
      ),
      // 120 g/j : la valeur confirmee du bareme seme (Q-ELV-2) ; le code disait 110.
      CategorieEspece(libelle: 'Reproducteur', rationGrammesParJour: 120),
    ],
    etapesCycle: ['Naissance', 'Chair', 'Reproducteur'],
    libelleNaissances: 'Nés (Mise bas)',
  );

  static const ConfigurationEspece poissonsChats = ConfigurationEspece(
    identifiant: 'poissons-chats',
    libelle: 'Poissons-Chats',
    icone: 'set_meal',
    route: '/elevage/poissons-chats',
    categories: [
      // Repli par tete SANS pesee, en g/poisson/j (`47e_`). L'ancien 30 / 60 / 110 g
      // etait absurde : un alevin de 2 g ne mange pas 30 g (15 fois son poids). Ordres
      // de grandeur : alevin ~2 g a 15 % de biomasse = 0,3 g, arrondi a 1 g (l'entier
      // le plus petit) ; juvenile ~50 g a 4 % = 2 g, arrondi a 3 g ; adulte ~500 g a
      // 1,5 % = 7,5 g, arrondi a 8 g. Des qu'une pesee existe, le % de biomasse prime.
      CategorieEspece(
        libelle: 'Alevin',
        rationGrammesParJour: 1,
        recoitAchatEtNaissances: true,
      ),
      CategorieEspece(
        libelle: 'Juvénile',
        rationGrammesParJour: 3,
        deduiteDesVentes: true,
      ),
      CategorieEspece(libelle: 'Mature', rationGrammesParJour: 8),
    ],
    etapesCycle: ['Alevin', 'Juvénile', 'Mature'],
    noteRationnement:
        'Provende calculée en % de la biomasse dès qu\'une pesée est saisie '
        '(DV-01), d\'après le tableau par classe de poids de Paramètres '
        'Élevage. Sans pesée : ration indicative par tête. Taux à valider par '
        'le technicien.',
    // ÉCART_DELIBERE — arbitrage de la Gérante.
    // `fiche-poissons-chats.html` l.161 intitule cette colonne « Alevins
    // (Naissance/Empoissonnement) ». La Gérante demande « Nés » tout court :
    // « alevin » est déjà le nom de la première catégorie juste en dessous, et
    // l'empoissonnement — l'achat d'alevins pour peupler un bassin — se saisit
    // dans la colonne Achats, pas ici. Le libellé du prototype mélangeait donc
    // les deux entrées que la ligne sépare.
    libelleNaissances: 'Nés',
    rationEnPourcentagePoidsVif: true,
    uniteClassePoids: 'g',
    tauxPoidsMaxPourcent: 25,
  );

  static const ConfigurationEspece poulets = ConfigurationEspece(
    identifiant: 'poulets',
    libelle: 'Poulets',
    icone: 'egg_alt',
    route: '/elevage/poulets-pondeuses',
    categories: [
      CategorieEspece(
        libelle: 'Poussin',
        rationGrammesParJour: 30,
        recoitAchatEtNaissances: true,
      ),
      CategorieEspece(
        libelle: 'Poulette',
        rationGrammesParJour: 60,
        deduiteDesVentes: true,
      ),
      CategorieEspece(libelle: 'Adulte', rationGrammesParJour: 110),
    ],
    etapesCycle: ['Poussin', 'Poulette', 'Adulte'],
    libelleNaissances: 'Nés / Transferts',
  );

  /// Pondeuses — 4 categories, Doc 05 §4. Les rations 30/60/80/110 g/j sont
  /// celles de `provendeTotal()` du meme document.
  static const ConfigurationEspece pondeuses = ConfigurationEspece(
    identifiant: 'pondeuses',
    libelle: 'Pondeuses',
    icone: 'egg',
    route: '/elevage/poulets-pondeuses',
    categories: [
      CategorieEspece(
        libelle: 'Poussin Ponte',
        rationGrammesParJour: 30,
        recoitAchatEtNaissances: true,
      ),
      CategorieEspece(libelle: 'Poussin Croissance', rationGrammesParJour: 60),
      CategorieEspece(libelle: 'Poulette', rationGrammesParJour: 80),
      CategorieEspece(
        libelle: 'Pondeuse',
        rationGrammesParJour: 110,
        deduiteDesVentes: true,
      ),
    ],
    etapesCycle: [
      'Poussin Ponte',
      'Poussin Croissance',
      'Poulette',
      'Pondeuse',
    ],
    // `fiche-poulets-pondeuses.html` l.368 : les Pondeuses recoivent aussi des
    // transferts depuis la fiche Poulets, d'ou « Achats / Entrees ».
    libelleAchats: 'Achats / Entrées',
    libelleNaissances: 'Nés / Transferts',
  );

  /// Escargots (achatines) — filière ajoutée après le prototype (DV-16,
  /// `docs/logialvia/16_DECISIONS_VALIDEES.md`). Sur le modèle des lapins :
  /// 3 catégories, la plus jeune reçoit achats et éclosions, la deuxième est
  /// commercialisée, à la pièce. Rations en g/tête/j : repères validés par
  /// l'animalier, modifiables dans Paramètres Élevage.
  static const ConfigurationEspece escargots = ConfigurationEspece(
    identifiant: 'escargots',
    libelle: 'Escargots',
    icone: 'eco',
    route: '/elevage/escargots',
    categories: [
      CategorieEspece(
        libelle: 'Naissain',
        rationGrammesParJour: 1,
        recoitAchatEtNaissances: true,
      ),
      CategorieEspece(
        libelle: 'Marchand',
        rationGrammesParJour: 5,
        deduiteDesVentes: true,
      ),
      CategorieEspece(libelle: 'Reproducteur', rationGrammesParJour: 8),
    ],
    etapesCycle: [
      'Ponte et éclosion',
      'Naissain',
      'Marchand (≈ 6 à 8 mois, ≈ 100 g) — Éligible à la Vente',
      'Reproducteur',
    ],
    noteRationnement:
        'Barème indicatif d\'héliciculture — repères à valider par '
        'l\'animalier. La notice de l\'aliment utilisé prévaut.',
    poidsMaturiteGrammes: 100,
    ageMaturiteJours: 180,
    libelleNaissances: 'Nés (Éclosions)',
  );

  /// Ovins — filière ajoutée après le prototype (DV-17), devenue Ovins à la
  /// demande du client (DV-22, remplace Bovins).
  ///
  /// ⚠️ Un ruminant se rationne en % de son poids vif (matière sèche), pas en
  /// grammes fixes par tête : la provende suit le tableau par classe de poids
  /// ([rationEnPourcentagePoidsVif]). Les rations ci-dessous (complément seul :
  /// 0,3 / 0,6 / 0,8 kg) ne servent que de repli quand aucune
  /// pesée n'est saisie. Vente à la tête, après embouche.
  static const ConfigurationEspece ovins = ConfigurationEspece(
    identifiant: 'ovins',
    libelle: 'Ovins',
    icone: 'grass',
    route: '/elevage/ovins',
    categories: [
      CategorieEspece(
        libelle: 'Agneau',
        rationGrammesParJour: 300,
        recoitAchatEtNaissances: true,
      ),
      CategorieEspece(
        libelle: 'Embouche',
        rationGrammesParJour: 600,
        deduiteDesVentes: true,
      ),
      CategorieEspece(libelle: 'Reproducteur', rationGrammesParJour: 800),
    ],
    etapesCycle: [
      'Naissance (agnelage)',
      'Agneau (0 → 3 mois)',
      'Embouche (≥ 35 kg ou 12 mois) — Éligible à la Vente',
      'Reproducteur',
    ],
    noteRationnement:
        'Provende calculée en % du poids vif (matière sèche) dès qu\'une '
        'pesée est saisie, d\'après le tableau par classe de poids de '
        'Paramètres Élevage. Sans pesée : ration indicative par tête. Repères à '
        'valider par l\'animalier.',
    poidsMaturiteGrammes: 35000,
    ageMaturiteJours: 365,
    libelleNaissances: 'Nés (Agnelage)',
    rationEnPourcentagePoidsVif: true,
    rationMaxGrammesParJour: 4000,
  );

  static const Map<String, ConfigurationEspece> parIdentifiant = {
    'goliaths': goliaths,
    'pintades': pintades,
    'lapins': lapins,
    'poissons-chats': poissonsChats,
    'poulets': poulets,
    'pondeuses': pondeuses,
    'escargots': escargots,
    'ovins': ovins,
  };
}
