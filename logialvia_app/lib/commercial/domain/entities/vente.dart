/// Modes de règlement — `VENTES.mode` (Doc D1).
///
/// ## Arbitrage de la Gérante : « Avance » n'est pas un mode de règlement
///
/// Le prototype stockait trois valeurs dans `VENTES.mode` : Espèces, Mobile
/// Money et « Avance (Solde Restant Dû) ». Or les deux premières répondent à
/// *avec quoi le client a payé*, la troisième à *combien il a payé*. Ce sont
/// deux questions différentes, et les confondre coûtait une information :
/// une avance réglée en Mobile Money ne pouvait pas être distinguée d'une
/// avance en espèces, alors que le rapprochement de caisse en dépend.
///
/// L'écran Paramètres Généraux avait raison depuis le début avec ses deux
/// modes ; c'est `VENTES.mode` qui était surchargé. C'était le point 3 resté
/// ouvert de l'index maître — tranché ici.
///
/// Voir [ConditionPaiement] pour l'autre moitié.
class ModeReglement {
  ModeReglement._();

  static const String especes = 'Espèces';
  static const String mobileMoney = 'Mobile Money';

  /// Ventes antérieures à l'arbitrage, dont `mode` portait la condition.
  /// L'instrument réel n'a jamais été saisi : il est inconnu, pas « Espèces ».
  /// Voir la migration v15 de `AppDatabase`.
  static const String nonPrecise = 'Non précisé';

  /// Les modes **saisissables**. [nonPrecise] n'en fait pas partie : c'est une
  /// trace du passé, pas un choix offert à la caissière.
  static const List<String> tous = [especes, mobileMoney];
}

/// Condition de paiement — l'autre moitié de l'ancien `VENTES.mode`.
///
/// **Aucune colonne nouvelle n'est créée.** La condition est entièrement
/// déduite de `VENTES.status` : une vente au statut « Avance » est une vente à
/// crédit, une vente « Payée » est comptant. L'information était donc déjà
/// stockée deux fois — c'est précisément ce qui rendait la surcharge de `mode`
/// inutile en plus d'être fausse.
class ConditionPaiement {
  ConditionPaiement._();

  static const String comptant = 'Comptant';
  static const String avance = 'Avance (Solde Restant Dû)';

  static const List<String> toutes = [comptant, avance];

  /// La condition d'une vente déjà enregistrée, lue depuis son statut.
  static String depuisStatut(String statut) =>
      statut == StatutVente.avance ? avance : comptant;
}

/// Statuts d'une vente — `VENTES.status` (Doc D1).
class StatutVente {
  StatutVente._();

  static const String payee = 'Payée';
  static const String avance = 'Avance';
  static const String annulee = 'Annulée';
}

/// Motifs d'annulation proposés par la modale (Doc H1 §Onglet 3).
class MotifAnnulation {
  MotifAnnulation._();

  static const List<String> tous = [
    'Erreur de saisie',
    'Client non honoré',
    'Produit indisponible',
    'Autre',
  ];
}

/// Une ligne de vente.
class LigneVente {
  const LigneVente({
    required this.produitId,
    required this.nom,
    required this.quantite,
    required this.prixUnitaire,
    this.espece,
    this.unite,
  });

  final int produitId;

  /// Nom **au moment de la vente** — dénormalisé volontairement (Doc D1), pour
  /// que l'historique reste fidèle si le produit est renommé plus tard.
  final String nom;

  final double quantite;
  final double prixUnitaire;
  final String? espece;
  final String? unite;

  double get total => quantite * prixUnitaire;
}

/// Une vente enregistrée.
class Vente {
  const Vente({
    required this.reference,
    required this.client,
    required this.date,
    required this.mode,
    required this.statut,
    required this.total,
    required this.paye,
    this.motifAnnulation,
    this.lignes = const [],
    this.ligneMobileMoney,
    this.echeance,
  });

  final String reference;
  final String client;
  final DateTime date;
  final String mode;
  final String statut;
  final double total;
  final double paye;
  final String? motifAnnulation;
  final List<LigneVente> lignes;

  /// Ligne Mobile Money creditee, telle qu'elle etait au moment de la vente.
  /// `null` en especes, et `null` sur toute vente anterieure a la v16 — leur
  /// ligne n'a jamais ete enregistree. Voir `VENTES.ligneMobileMoney`.
  final String? ligneMobileMoney;

  /// Date d'exigibilite convenue — `null` si aucun delai n'a ete fixe.
  final DateTime? echeance;

  bool get estAnnulee => statut == StatutVente.annulee;
  bool get estEnAvance => statut == StatutVente.avance;

  /// Reste dû sur une vente à crédit.
  double get resteDu =>
      estAnnulee ? 0 : (total - paye).clamp(0, double.infinity);
}

/// Une ligne du panier en cours de saisie (POS).
/// Une ligne du panier — **vente à la pièce, à montant négocié**.
///
/// ## ⚠️ Correction majeure : ce n'est pas « quantité × prix unitaire »
///
/// `ventes.html` n'ajoute jamais un produit directement au panier. Chaque clic
/// ouvre la modale « **Vente à la Pièce** » qui demande deux valeurs
/// indépendantes : la **Quantité (unité)** et le **Montant Global de la Vente
/// (FCFA)**. Sa note est sans ambiguïté :
///
/// > « Vente à la pièce : saisissez directement le montant total convenu —
/// > **jamais un prix unitaire multiplié automatiquement**. Le prix indicatif
/// > n'est qu'une fourchette de référence. »
///
/// C'est cohérent avec le reste du catalogue, où `priceMax` définit une
/// **fourchette de négociation** (Doc D1) : sur un marché de Natitingou, le
/// prix d'un goliath se discute, il ne se calcule pas.
///
/// [montantGlobal] est donc le total **saisi** de la ligne. [prixUnitaire] en
/// est déduit pour l'historique et la comptabilité, qui ont besoin d'un prix
/// unitaire — mais il n'entre dans aucun calcul de total.
class LignePanier {
  const LignePanier({
    required this.produitId,
    required this.nom,
    required this.montantGlobal,
    required this.quantite,
    required this.stockDisponible,
    required this.prixIndicatif,
    this.prixIndicatifMax,
    this.espece,
    this.unite,
  });

  final int produitId;
  final String nom;

  /// Montant total convenu pour cette ligne, saisi par l'utilisatrice.
  final double montantGlobal;

  final double quantite;

  /// Stock du produit au moment de l'ajout — borne haute de la quantité.
  final int stockDisponible;

  /// Fourchette de référence affichée dans la modale. **Jamais multipliée.**
  final double prixIndicatif;
  final double? prixIndicatifMax;

  final String? espece;
  final String? unite;

  /// Le total de la ligne **est** le montant saisi.
  double get total => montantGlobal;

  /// Prix unitaire **déduit**, pour l'historique et l'écriture comptable.
  double get prixUnitaire => quantite <= 0 ? 0 : montantGlobal / quantite;

  /// Libellé de la fourchette — « 4 500 à 6 000 FCFA » ou « 4 500 FCFA ».
  String get libelleFourchette => prixIndicatifMax == null
      ? '${prixIndicatif.round()}'
      : '${prixIndicatif.round()} à ${prixIndicatifMax!.round()}';

  LignePanier copyWith({double? quantite, double? montantGlobal}) =>
      LignePanier(
        produitId: produitId,
        nom: nom,
        montantGlobal: montantGlobal ?? this.montantGlobal,
        quantite: quantite ?? this.quantite,
        stockDisponible: stockDisponible,
        prixIndicatif: prixIndicatif,
        prixIndicatifMax: prixIndicatifMax,
        espece: espece,
        unite: unite,
      );
}
