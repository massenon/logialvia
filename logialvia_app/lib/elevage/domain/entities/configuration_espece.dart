/// Une categorie d'age d'une espece, avec sa ration normative.
class CategorieEspece {
  const CategorieEspece({
    required this.libelle,
    required this.rationGrammesParJour,
    this.recoitAchatEtNaissances = false,
    this.deduiteDesVentes = false,
  });

  final String libelle;

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

  int get nombreCategories => categories.length;

  int get indexCategorieJeune =>
      categories.indexWhere((c) => c.recoitAchatEtNaissances);

  int get indexCategorieCommercialisee =>
      categories.indexWhere((c) => c.deduiteDesVentes);
}

/// Referentiel des fiches (6 d'origine, plus escargots et bovins) — Doc 05 §3 (table de correspondance des
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
      ),
      CategorieEspece(
        libelle: 'Chair',
        rationGrammesParJour: 60,
        deduiteDesVentes: true,
      ),
      CategorieEspece(libelle: 'Reproducteur', rationGrammesParJour: 110),
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
      CategorieEspece(
        libelle: 'Alevin',
        rationGrammesParJour: 30,
        recoitAchatEtNaissances: true,
      ),
      CategorieEspece(
        libelle: 'Juvénile',
        rationGrammesParJour: 60,
        deduiteDesVentes: true,
      ),
      CategorieEspece(libelle: 'Mature', rationGrammesParJour: 110),
    ],
    etapesCycle: ['Alevin', 'Juvénile', 'Mature'],
    noteRationnement:
        'Seuils non confirmés pour cette filière — barème à valider avant '
        'usage réel (signalé sur le Dashboard Élevage du prototype).',
    // ÉCART_DELIBERE — arbitrage de la Gérante.
    // `fiche-poissons-chats.html` l.161 intitule cette colonne « Alevins
    // (Naissance/Empoissonnement) ». La Gérante demande « Nés » tout court :
    // « alevin » est déjà le nom de la première catégorie juste en dessous, et
    // l'empoissonnement — l'achat d'alevins pour peupler un bassin — se saisit
    // dans la colonne Achats, pas ici. Le libellé du prototype mélangeait donc
    // les deux entrées que la ligne sépare.
    libelleNaissances: 'Nés',
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

  /// Bovins — filière ajoutée après le prototype (DV-17).
  ///
  /// ⚠️ Les rations ci-dessous sont **indicatives** : un ruminant se rationne
  /// en % de son poids vif (matière sèche), pas en grammes fixes par tête. Le
  /// tableau par classe de poids de DV-17 n'existe pas encore au poste ; ces
  /// valeurs (complément seul : 1,5 / 7 / 9 kg de matière sèche) en tiennent
  /// lieu. Vente à la tête, après embouche.
  static const ConfigurationEspece bovins = ConfigurationEspece(
    identifiant: 'bovins',
    libelle: 'Bovins',
    icone: 'agriculture',
    route: '/elevage/bovins',
    categories: [
      CategorieEspece(
        libelle: 'Veau',
        rationGrammesParJour: 1500,
        recoitAchatEtNaissances: true,
      ),
      CategorieEspece(
        libelle: 'Embouche',
        rationGrammesParJour: 7000,
        deduiteDesVentes: true,
      ),
      CategorieEspece(libelle: 'Reproducteur', rationGrammesParJour: 9000),
    ],
    etapesCycle: [
      'Naissance (vêlage)',
      'Veau (0 → 6 mois)',
      'Embouche (≥ 250 kg ou 24 mois) — Éligible à la Vente',
      'Reproducteur',
    ],
    noteRationnement:
        'Rations indicatives en matière sèche (taux du poids vif × poids moyen '
        'de référence) — repères à valider par l\'animalier. Le tableau par '
        'classe de poids n\'est pas encore disponible.',
    poidsMaturiteGrammes: 250000,
    ageMaturiteJours: 730,
    libelleNaissances: 'Nés (Vêlage)',
  );

  static const Map<String, ConfigurationEspece> parIdentifiant = {
    'goliaths': goliaths,
    'pintades': pintades,
    'lapins': lapins,
    'poissons-chats': poissonsChats,
    'poulets': poulets,
    'pondeuses': pondeuses,
    'escargots': escargots,
    'bovins': bovins,
  };
}
