/// Périodes proposées par la barre de filtres de l'Inventaire.
enum PeriodeInventaire {
  jour('Journalier'),
  semaine('Hebdomadaire'),
  mois('Mensuel'),
  plage('Plage personnalisée');

  const PeriodeInventaire(this.libelle);

  final String libelle;
}

/// Une ligne d'inventaire d'intrant — la fiche de stock d'un article.
///
/// ## Pourquoi les quatre colonnes de mouvement
///
/// Un inventaire comptable ne dit pas seulement *combien il en reste* : il doit
/// expliquer **d'où vient l'écart**. Stock initial + entrées − sorties = stock
/// final est l'égalité que le commissaire vérifie en premier. Ne montrer que le
/// stock final rendrait tout contrôle impossible.
class LigneInventaireIntrant {
  const LigneInventaireIntrant({
    required this.code,
    required this.article,
    required this.categorie,
    required this.unite,
    required this.stockInitial,
    required this.entrees,
    required this.sorties,
    required this.stockFinal,
    required this.pmp,
  });

  final String code;
  final String article;
  final String categorie;
  final String unite;

  final double stockInitial;
  final double entrees;

  /// Toujours **positives** : une sortie de 12 sacs s'affiche « 12 », pas
  /// « −12 ». Le signe est porté par la colonne, pas par le nombre.
  final double sorties;

  final double stockFinal;

  /// Prix moyen pondéré — un vrai coût d'achat, recalculé à chaque réception.
  final int pmp;

  /// Valeur du stock final. **Au PMP, jamais à un prix de vente** : un sac de
  /// provende en magasin n'a encore rien rapporté (voir Doc D1 v18).
  double get valeur => stockFinal * pmp;

  /// L'égalité que doit vérifier tout inventaire.
  bool get equilibre =>
      (stockInitial + entrees - sorties - stockFinal).abs() < 0.001;
}

/// Une ligne d'inventaire de produit fini ou d'animal commercialisable.
class LigneInventaireProduit {
  const LigneInventaireProduit({
    required this.sku,
    required this.produit,
    required this.categorie,
    required this.unite,
    required this.stockInitial,
    required this.sorties,
    required this.stockFinal,
    this.coutRevient,
    required this.espece,
  });

  final String sku;
  final String produit;
  final String categorie;
  final String unite;

  final int stockInitial;

  /// Quantités vendues sur la période — la seule sortie tracée pour un produit
  /// fini. Les naissances et les transferts entrent par les fiches d'élevage,
  /// qui tiennent leurs propres effectifs.
  final double sorties;

  final int stockFinal;

  /// `null` tant que le coût de revient n'a pas été renseigné.
  final double? coutRevient;

  final String? espece;

  /// `null` — et non zéro — quand le coût manque : un total muet se lirait
  /// comme un total complet.
  double? get valeur => coutRevient == null ? null : stockFinal * coutRevient!;

  bool get estValorise => coutRevient != null;
}

/// Effectif vivant d'une filière à la date de clôture de l'inventaire.
///
/// Les animaux sur pied ne sont **pas** valorisés ici : leur coût de revient
/// dépend de la provende consommée depuis la mise en bande, que le modèle ne
/// cumule pas par lot. Les compter sans les valoriser dit la vérité ; leur
/// coller un prix de vente gonflerait l'actif d'une marge non réalisée.
class LigneInventaireEffectif {
  const LigneInventaireEffectif({
    required this.espece,
    required this.libelle,
    required this.effectif,
    required this.dateSaisie,
  });

  final String espece;
  final String libelle;
  final int effectif;

  /// Date de la dernière fiche saisie prise en compte. `null` si la filière
  /// n'a aucune saisie : l'effectif affiché est alors inconnu, pas nul.
  final DateTime? dateSaisie;
}

/// L'inventaire complet à une date, sur une période.
class Inventaire {
  const Inventaire({
    required this.debut,
    required this.fin,
    required this.intrants,
    required this.produits,
    required this.effectifs,
    required this.oeufsEnIncubation,
  });

  final DateTime debut;
  final DateTime fin;

  final List<LigneInventaireIntrant> intrants;
  final List<LigneInventaireProduit> produits;
  final List<LigneInventaireEffectif> effectifs;

  /// Œufs encore en machine à la date de clôture — un stock bien réel, qui ne
  /// figure ni dans les intrants ni dans les produits finis.
  final int oeufsEnIncubation;

  double get valeurIntrants => intrants.fold<double>(0, (s, l) => s + l.valeur);

  double get valeurProduits => produits
      .where((l) => l.estValorise)
      .fold<double>(0, (s, l) => s + l.valeur!);

  double get valeurTotale => valeurIntrants + valeurProduits;

  /// Nombre de produits exclus du total faute de coût de revient. Le KPI
  /// l'annonce : un total qui tait ce qu'il exclut se lit comme complet.
  int get produitsNonValorises =>
      produits.where((l) => !l.estValorise && l.stockFinal > 0).length;

  int get effectifTotal => effectifs.fold<int>(0, (s, l) => s + l.effectif);

  bool get estVide => intrants.isEmpty && produits.isEmpty && effectifs.isEmpty;

  /// Lignes dont l'égalité stock initial + entrées − sorties = stock final est
  /// rompue. Un inventaire qui ne s'explique pas doit le dire.
  List<LigneInventaireIntrant> get intrantsDesequilibres =>
      intrants.where((l) => !l.equilibre).toList();
}
