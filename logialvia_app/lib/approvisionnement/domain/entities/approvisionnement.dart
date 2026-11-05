/// Un intrant (provende, vétérinaire, marchandise).
class Intrant {
  const Intrant({
    required this.code,
    required this.nom,
    required this.categorie,
    required this.stock,
    required this.unite,
    required this.seuil,
    required this.pmp,
  });

  final String code;
  final String nom;
  final String categorie;
  final int stock;
  final String unite;
  final int seuil;

  /// Prix Moyen Pondéré, en FCFA.
  final int pmp;

  bool get estCritique => stock <= seuil;

  /// Valorisation du stock détenu — alimente le KPI « Valeur Totale Stock ».
  double get valeur => stock * pmp.toDouble();

  /// Catégories réelles (Doc D1).
  static const List<String> categories = [
    'Intrants Provende',
    'Marchandises',
    'Vétérinaire',
  ];
}

/// Types de mouvement de stock.
class TypeMouvement {
  TypeMouvement._();

  static const String entree = 'Entrée';
  static const String sortie = 'Sortie';
  static const String ajustement = 'Ajustement';
}

/// Une ligne du journal des mouvements.
class MouvementIntrant {
  const MouvementIntrant({
    required this.horodatage,
    required this.article,
    required this.type,
    required this.motif,
    required this.quantite,
    this.reference,
  });

  final DateTime horodatage;
  final String article;
  final String type;
  final String motif;
  final double quantite;
  final String? reference;
}

/// Statuts d'une commande d'achat.
class StatutAchat {
  StatutAchat._();

  static const String commande = 'Commandé';
  static const String livre = 'Livré';
  static const String annule = 'Annulé';
}

class Fournisseur {
  const Fournisseur({
    required this.id,
    required this.nom,
    this.telephone,
    this.adresse,
    this.fournit,
    this.totalAchats = 0,
    this.soldeDu = 0,
    this.nombreCommandes = 0,
  });

  final int id;
  final String nom;
  final String? telephone;
  final String? adresse;

  /// Ce que le fournisseur approvisionne (colonne « Fournit »).
  final String? fournit;

  /// Agrégats **recalculés** depuis `ACHATS`, jamais stockés.
  final double totalAchats;
  final double soldeDu;
  final int nombreCommandes;

  bool get aUneDette => soldeDu > 0;
}

class LigneAchat {
  const LigneAchat({
    required this.intrantCode,
    required this.nom,
    required this.quantite,
    required this.prixUnitaire,
  });

  final String intrantCode;
  final String nom;
  final double quantite;
  final double prixUnitaire;

  double get total => quantite * prixUnitaire;
}

class Achat {
  const Achat({
    required this.reference,
    required this.fournisseurId,
    required this.fournisseurNom,
    required this.date,
    required this.statut,
    required this.total,
    required this.paye,
    this.mode,
    this.lignes = const [],
  });

  final String reference;
  final int fournisseurId;
  final String fournisseurNom;
  final DateTime date;
  final String statut;
  final double total;
  final double paye;
  final String? mode;
  final List<LigneAchat> lignes;

  bool get estLivre => statut == StatutAchat.livre;
  bool get estAnnule => statut == StatutAchat.annule;

  double get soldeDu =>
      estAnnule ? 0 : (total - paye).clamp(0, double.infinity);

  int ancienneteJours(DateTime maintenant) =>
      maintenant.difference(date).inDays;

  bool estAncienne(DateTime maintenant) => ancienneteJours(maintenant) > 10;
}

/// Une ligne du panier d'achat en cours de saisie.
class LignePanierAchat {
  const LignePanierAchat({
    required this.intrantCode,
    required this.nom,
    required this.quantite,
    required this.prixUnitaire,
    required this.unite,
  });

  final String intrantCode;
  final String nom;
  final double quantite;
  final double prixUnitaire;
  final String unite;

  double get total => quantite * prixUnitaire;

  LignePanierAchat copyWith({double? quantite, double? prixUnitaire}) =>
      LignePanierAchat(
        intrantCode: intrantCode,
        nom: nom,
        quantite: quantite ?? this.quantite,
        prixUnitaire: prixUnitaire ?? this.prixUnitaire,
        unite: unite,
      );
}
