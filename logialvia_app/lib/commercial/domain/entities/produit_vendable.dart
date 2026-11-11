/// Produit vendable — `PRODUITS_VENDABLES` (Doc D1).
///
/// À ne jamais confondre avec un intrant (contexte Approvisionnement) :
/// Doc C1 §2 impose que les deux notions de « stock » restent des entités
/// distinctes, malgré leur ressemblance structurelle (BR-VTE-006).
class ProduitVendable {
  const ProduitVendable({
    required this.id,
    required this.nom,
    required this.categorie,
    required this.prix,
    required this.unite,
    required this.icone,
    required this.stock,
    required this.seuil,
    this.prixMax,
    this.espece,
    this.sku,
    this.coutRevient,
  });

  final String id;

  /// Référence catalogue affichée en 1ʳᵉ colonne (`catalogue-produits.html`).
  final String? sku;

  final String nom;
  final String categorie;
  final double prix;

  /// Haut de la fourchette de négociation, si le produit en a une.
  final double? prixMax;

  final String unite;
  final String icone;
  final int stock;
  final int seuil;

  /// Coût de revient unitaire, `null` s'il n'a pas été renseigné.
  final double? coutRevient;

  /// Filière d'élevage concernée si le produit est un animal vivant.
  final String? espece;

  bool get estCritique => stock <= seuil;
  bool get estEpuise => stock <= 0;

  /// Valeur du stock détenu **au prix de vente**, pour le KPI « Valeur Totale
  /// du Catalogue » — ce que la ferme espère encaisser.
  double get valeurStock => stock * prix;

  /// Valorisation du stock **au coût de revient** — `null` tant qu'il n'est
  /// pas connu.
  ///
  /// Ce que la ferme a dépensé, et non ce qu'elle espère encaisser. Les
  /// confondre — ce que fait le prototype, dont la colonne « CMUP » du Rapport
  /// de Stocks reprend exactement le prix du catalogue — surévalue le stock et
  /// anticipe une marge non réalisée : un goliath encore dans l'enclos n'a pas
  /// rapporté 6 000 F.
  double? get valeurStockAuCout =>
      coutRevient == null ? null : stock * coutRevient!;

  /// Marge unitaire attendue, `null` sans coût de revient.
  double? get margeUnitaire => coutRevient == null ? null : prix - coutRevient!;

  /// « 6 000 – 8 500 » si fourchette, « 6 000 » sinon.
  bool get aUneFourchette => prixMax != null && prixMax! > prix;

  /// Catégories réellement utilisées par le prototype — 4, et non les 2 que
  /// contraignait Doc D1 (voir la note du seeder de catalogue) — plus
  /// Héliciculture et Élevage ovin, ajoutées avec les filières escargots et
  /// ovins (DV-16, DV-17).
  static const List<String> categories = [
    'Avicole',
    'Commerce Annexe',
    'Cuniculture',
    'Héliciculture',
    'Élevage ovin',
    'Pisciculture',
  ];
}
