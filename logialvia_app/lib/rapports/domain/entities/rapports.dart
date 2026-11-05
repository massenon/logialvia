/// @docImport 'package:logialvia_app/rapports/data/repositories/rapports_repository_drift.dart';
library;

/// Entités du module Rapports & États — Doc F7, `rapports-exports.html`.
///
/// Ce module est un **modèle de lecture transverse** : il n'a aucune table à
/// lui et ne persiste rien. Il agrège Comptabilité, Commercial,
/// Approvisionnement et Élevage pour produire 6 états de synthèse. C'est le
/// seul contexte du projet autorisé à lire au travers des autres, précisément
/// parce qu'un rapport de gestion est par nature transversal — et il le fait en
/// lecture seule.

/// Onglet 1 — une ligne de la synthèse Recettes / Dépenses.
class LigneRecetteDepense {
  const LigneRecetteDepense({
    required this.periode,
    required this.numeroPiece,
    required this.categorie,
    required this.centre,
    required this.encaissement,
    required this.decaissement,
  });

  final String periode;
  final String numeroPiece;
  final String categorie;
  final String centre;
  final double encaissement;
  final double decaissement;
}

/// Centres de profit du filtre de l'onglet 1.
///
/// Le prototype en propose 3 : « Aviculture (Goliaths/Pintades) »,
/// « Commerce Annexe » et « Charge Générale ». Ils sont ici **déduits du numéro
/// de compte**, seule information dont dispose réellement le grand livre :
/// 701/601/622 → Aviculture, 707/602 → Commerce Annexe, tout le reste →
/// Charge Générale. C'est la même ventilation que la Comptabilité Analytique
/// (Doc F6 §7), et pour la même raison : `ECRITURE_COMPTABLE` ne porte aucun
/// axe analytique.
class CentresProfit {
  CentresProfit._();

  static const String aviculture = 'Aviculture';
  static const String commerceAnnexe = 'Commerce Annexe';
  static const String chargeGenerale = 'Charge Générale';

  static const List<String> tous = [aviculture, commerceAnnexe, chargeGenerale];

  static String pourCompte(String numeroCompte) {
    if (numeroCompte.startsWith('701') ||
        numeroCompte.startsWith('601') ||
        numeroCompte.startsWith('622')) {
      return aviculture;
    }
    if (numeroCompte.startsWith('707') || numeroCompte.startsWith('602')) {
      return commerceAnnexe;
    }
    return chargeGenerale;
  }
}

/// Onglet 2 — un mouvement de trésorerie.
class MouvementTresorerie {
  const MouvementTresorerie({
    required this.date,
    required this.compte,
    required this.typeOperation,
    required this.libelle,
    required this.entree,
    required this.sortie,
  });

  final DateTime date;

  /// « Caisse » ou « Mobile Money », libellés du filtre du prototype.
  final String compte;
  final String typeOperation;
  final String libelle;
  final double entree;
  final double sortie;
}

/// Un compte de trésorerie et son solde d'ouverture sur la période.
class CompteTresorerie {
  const CompteTresorerie({
    required this.numero,
    required this.libelle,
    required this.soldeOuverture,
  });

  final String numero;
  final String libelle;
  final double soldeOuverture;

  /// Libellés du filtre — `531` → « Caisse », `512` → « Mobile Money ».
  static String libelleCourt(String numero) {
    if (numero.startsWith('531')) return 'Caisse';
    if (numero.startsWith('512')) return 'Mobile Money';
    return numero;
  }
}

/// Onglet 3 — une créance client.
class CreanceClient {
  const CreanceClient({
    required this.code,
    required this.client,
    required this.numeroFacture,
    required this.dateVente,
    required this.montantInitial,
    required this.acomptes,
    required this.aujourdhui,
    this.echeance,
  });

  /// « CLI-001 » — identifiant client, ou `—` pour un client comptant occasionnel.
  final String code;
  final String client;
  final String numeroFacture;
  final DateTime dateVente;
  final double montantInitial;
  final double acomptes;

  /// Date de référence du calcul de retard, injectée pour rendre l'entité
  /// testable sans dépendre de l'horloge.
  final DateTime aujourdhui;

  /// Date d'exigibilité convenue — `VENTES.echeance`, migration v17.
  ///
  /// `null` quand aucun délai n'a été fixé sur cette vente. La créance est
  /// alors « À échoir » **sans date**, et n'est jamais déclarée en retard.
  ///
  /// ⚠️ Avant la v17, ce champ n'existait pas et valait `dateVente` : toute
  /// créance née la veille était affichée « En Retard » avec un compteur qui
  /// mesurait en fait son âge. Comme la **lettre de relance** s'imprime depuis
  /// ce tableau, la Gérante pouvait réclamer un paiement non échu. Le
  /// prototype ne faisait pas mieux : sa seule créance porte la même date dans
  /// les deux colonnes.
  final DateTime? echeance;

  double get soldeDu => montantInitial - acomptes;

  /// Vrai tant qu'aucun délai n'a été convenu — l'écran l'affiche en clair
  /// plutôt qu'un tiret muet.
  bool get sansEcheance => echeance == null;

  int get joursDeRetard {
    final due = echeance;
    if (due == null) return 0;
    final retard = DateTime(
      aujourdhui.year,
      aujourdhui.month,
      aujourdhui.day,
    ).difference(DateTime(due.year, due.month, due.day)).inDays;
    return retard > 0 ? retard : 0;
  }

  bool get enRetard => joursDeRetard > 0;

  /// « Sans échéance » n'est pas « À échoir » : la première dit qu'aucune date
  /// n'a été fixée, la seconde qu'une date est fixée et pas encore atteinte.
  /// Les confondre reviendrait à affirmer un délai qui n'existe pas.
  String get statut => switch ((sansEcheance, enRetard)) {
    (true, _) => 'Sans échéance',
    (_, true) => 'En Retard',
    _ => 'À Échoir',
  };
}

/// Onglet 4 — une dette fournisseur.
class DetteFournisseur {
  const DetteFournisseur({
    required this.code,
    required this.fournisseur,
    required this.reference,
    required this.dateAchat,
    required this.montantTotal,
    required this.regle,
    required this.aujourdhui,
    this.echeance,
  });

  final String code;
  final String fournisseur;
  final String reference;
  final DateTime dateAchat;
  final double montantTotal;
  final double regle;
  final DateTime aujourdhui;

  /// Date d'exigibilité convenue — `ACHATS.echeance`, migration v17.
  ///
  /// ⚠️ Avant la v17 elle valait `dateAchat`. Le prototype allait plus loin
  /// dans l'incohérence : sa seule dette est datée du `06/08/2026` avec une
  /// échéance au `05/08/2026`, soit **exigible la veille de son propre
  /// engagement**. Cette valeur n'a jamais été reproduite.
  final DateTime? echeance;

  double get soldeRestant => montantTotal - regle;

  bool get sansEcheance => echeance == null;

  int get joursDeRetard {
    final due = echeance;
    if (due == null) return 0;
    final retard = DateTime(
      aujourdhui.year,
      aujourdhui.month,
      aujourdhui.day,
    ).difference(DateTime(due.year, due.month, due.day)).inDays;
    return retard > 0 ? retard : 0;
  }

  bool get urgente => joursDeRetard > 0;

  String get statut => switch ((sansEcheance, urgente)) {
    (true, _) => 'Sans échéance',
    (_, true) => 'Urgent',
    _ => 'Normal',
  };
}

/// Onglet 5, tableau 1 — recensement d'une filière.
class LigneRecensement {
  const LigneRecensement({
    required this.lot,
    required this.effectifTotal,
    required this.effectifMatures,
    required this.libelleJeunes,
    required this.effectifJeunes,
    required this.mortsPeriode,
    required this.donsPeriode,
    required this.effectifMalade,
  });

  final String lot;
  final int effectifTotal;
  final int effectifMatures;
  final String libelleJeunes;
  final int effectifJeunes;
  final int mortsPeriode;
  final int donsPeriode;
  final int effectifMalade;
}

/// Onglet 5, tableau 2 — mouvements, traitements et ventes d'une filière.
class LigneMouvementElevage {
  const LigneMouvementElevage({
    required this.lot,
    required this.quantiteVendue,
    required this.montantVente,
    required this.effectifFinal,
    required this.traitementAdministre,
    required this.signesObserves,
    required this.provendeServieGrammes,
  });

  final String lot;
  final int quantiteVendue;
  final double montantVente;
  final int effectifFinal;

  /// Dernier traitement réellement saisi sur le Calendrier de Soins.
  final String traitementAdministre;

  /// Motifs réellement saisis à l'Infirmerie sur la période.
  final String signesObserves;

  final int provendeServieGrammes;
}

/// Onglet 5, tableau 3 — un cycle du couvoir.
class LigneCouvoir {
  const LigneCouvoir({
    required this.codeLot,
    required this.miseEnCouvoir,
    required this.eclosionAttendue,
    required this.oeufsCouves,
    required this.nes,
    required this.mortsAuDemarrage,
    required this.statut,
  });

  final String codeLot;
  final DateTime miseEnCouvoir;
  final DateTime eclosionAttendue;
  final int oeufsCouves;
  final int? nes;
  final int? mortsAuDemarrage;
  final String statut;

  /// `null` tant que le cycle n'a pas éclos — jamais 0 %, qui se lirait comme
  /// un échec total (règle déjà appliquée au tableau de bord, Doc F2).
  double? get tauxEclosion {
    if (nes == null || oeufsCouves <= 0) return null;
    return nes! / oeufsCouves * 100;
  }
}

/// Onglet 6 — une ligne du rapport de stocks.
class LigneStock {
  const LigneStock({
    required this.sku,
    required this.designation,
    required this.categorie,
    required this.stockFinal,
    required this.unite,
    required this.cmup,
    required this.seuil,
  });

  final String sku;
  final String designation;

  /// « Intrant Provende » ou « Produit Fini », catégories du filtre réel.
  final String categorie;
  final double stockFinal;
  final String unite;

  /// Coût Moyen Unitaire Pondéré — le PMP côté intrants, le **coût de
  /// revient** côté produits finis (v18).
  ///
  /// `null` quand le coût de revient d'un produit fini n'a pas été saisi. Le
  /// prix de vente n'est jamais substitué : le prototype le fait — sa colonne
  /// « CMUP » reprend le prix du catalogue à l'identique (`price:6000` /
  /// `cmup:6000` pour le Goliath mature) — ce qui valorise un animal encore
  /// dans l'enclos au montant qu'il n'a pas encore rapporté.
  final double? cmup;

  final double seuil;

  /// `null` quand le coût unitaire est inconnu : la ligne n'entre alors dans
  /// aucun total. Un stock non valorisé se dit, il ne s'estime pas.
  double? get valeurTotale => cmup == null ? null : stockFinal * cmup!;

  bool get nonValorise => cmup == null;
  bool get critique => stockFinal <= seuil;
  String get statut => critique ? 'Critique' : 'OK';

  static const String categorieIntrant = 'Intrant Provende';
  static const String categorieProduitFini = 'Produit Fini';
}

/// Agrégat complet des 6 onglets pour une période.
class DonneesRapports {
  const DonneesRapports({
    required this.recettesDepenses,
    required this.comptesTresorerie,
    required this.mouvementsTresorerie,
    required this.creances,
    required this.dettes,
    required this.recensement,
    required this.mouvementsElevage,
    required this.couvoir,
    required this.stocks,
    required this.effectifTotal,
    required this.sujetsMalades,
    required this.cyclesEnCours,
    required this.tauxEclosionMoyen,
  });

  final List<LigneRecetteDepense> recettesDepenses;
  final List<CompteTresorerie> comptesTresorerie;
  final List<MouvementTresorerie> mouvementsTresorerie;
  final List<CreanceClient> creances;
  final List<DetteFournisseur> dettes;
  final List<LigneRecensement> recensement;
  final List<LigneMouvementElevage> mouvementsElevage;
  final List<LigneCouvoir> couvoir;
  final List<LigneStock> stocks;

  final int effectifTotal;
  final int sujetsMalades;
  final int cyclesEnCours;
  final double? tauxEclosionMoyen;

  static const DonneesRapports vide = DonneesRapports(
    recettesDepenses: [],
    comptesTresorerie: [],
    mouvementsTresorerie: [],
    creances: [],
    dettes: [],
    recensement: [],
    mouvementsElevage: [],
    couvoir: [],
    stocks: [],
    effectifTotal: 0,
    sujetsMalades: 0,
    cyclesEnCours: 0,
    tauxEclosionMoyen: null,
  );
}
