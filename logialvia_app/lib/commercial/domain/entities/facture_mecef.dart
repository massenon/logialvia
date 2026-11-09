/// Les entités de la facturation normalisée MeCeF.
///
/// ## Une facture n'est pas une vente
///
/// La vente est un fait de caisse : de l'argent a changé de main. La facture
/// est une pièce fiscale : elle engage l'entreprise devant l'administration.
/// Les deux se ressemblent, et c'est précisément pourquoi elles sont
/// distinctes ici — une vente peut exister sans facture (client comptant qui
/// n'en demande pas), et une facture peut être annulée par un avoir sans que
/// la vente disparaisse.
library;

/// Identifiant du « poste » web : émetteur des factures émises depuis le web
/// (`47a2_`). Le web n'a ni jeton ni accès à e-MECeF : ces factures se transmettent
/// depuis un poste appairé, après une réservation au serveur (verrou contre la double
/// normalisation).
const String identifiantPosteWeb = '00000000-0000-0000-0000-000000000000';

/// Nature de la pièce.
enum TypeFacture {
  /// Facture de vente.
  vente('FV', 'Facture de vente'),

  /// Facture d'avoir — corrige ou annule une facture de vente.
  avoir('FA', 'Facture d\'avoir');

  const TypeFacture(this.code, this.libelle);

  /// Préfixe de la référence, et code attendu par la DGI.
  final String code;
  final String libelle;

  static TypeFacture depuis(String code) =>
      values.firstWhere((t) => t.code == code, orElse: () => TypeFacture.vente);
}

/// Où en est la pièce vis-à-vis de la DGI.
enum StatutFacture {
  /// Émise, pas encore transmise. C'est l'état normal hors ligne.
  aTransmettre('a_transmettre', 'À transmettre'),

  /// La DGI a rendu un code : la facture est normalisée.
  normalisee('normalisee', 'Normalisée'),

  /// La transmission a été refusée. `erreurTransmission` dit pourquoi.
  rejetee('rejetee', 'Rejetée');

  const StatutFacture(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutFacture depuis(String code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => StatutFacture.aTransmettre,
  );

  /// Rang de la machine à états : `à transmettre` < `rejetée` < `normalisée`.
  ///
  /// Un statut **ne régresse jamais** : une facture normalisée est immuable
  /// (règle fiscale), une rejetée peut être retransmise (donc devenir normalisée)
  /// mais ne redevient jamais « à transmettre ». La synchronisation arbitre sur ce
  /// rang, pas sur l'horloge (`46e_` §2).
  int get rang => switch (this) {
    StatutFacture.aTransmettre => 0,
    StatutFacture.rejetee => 1,
    StatutFacture.normalisee => 2,
  };
}

/// Un groupe de la grille de taxation.
class GroupeTaxe {
  const GroupeTaxe({
    required this.code,
    required this.libelle,
    required this.taux,
    this.ordre = 0,
  });

  /// La lettre imprimée en face de la ligne.
  final String code;
  final String libelle;

  /// Taux en pourcentage — `0` pour un groupe exonéré.
  final double taux;
  final int ordre;

  bool get exonere => taux == 0;

  /// Le groupe appliqué quand rien n'est précisé.
  ///
  /// Exonéré, délibérément : facturer une taxe non due engage l'entreprise,
  /// alors qu'un oubli de taxe se corrige par un avoir.
  static const GroupeTaxe parDefaut = GroupeTaxe(
    code: 'A',
    libelle: 'Exonéré',
    taux: 0,
  );
}

/// Une ligne de facture, montants figés à l'émission.
class LigneFacture {
  const LigneFacture({
    required this.designation,
    required this.quantite,
    required this.prixUnitaireHt,
    required this.groupeTaxe,
    required this.tauxTaxe,
    this.unite,
    this.id,
  });

  /// UUID de la ligne (DV-19).
  final String? id;
  final String designation;
  final double quantite;
  final String? unite;
  final double prixUnitaireHt;
  final String groupeTaxe;
  final double tauxTaxe;

  double get montantHt => quantite * prixUnitaireHt;
  double get montantTaxe => montantHt * tauxTaxe / 100;
  double get montantTtc => montantHt + montantTaxe;
}

/// Le cumul par groupe de taxe, tel qu'il figure au pied d'une facture.
class TotalParGroupe {
  const TotalParGroupe({
    required this.groupe,
    required this.taux,
    required this.baseHt,
    required this.taxe,
  });

  final String groupe;
  final double taux;
  final double baseHt;
  final double taxe;
}

/// Une facture — de vente ou d'avoir.
class FactureMecef {
  const FactureMecef({
    required this.reference,
    required this.type,
    required this.date,
    required this.client,
    required this.lignes,
    required this.statut,
    this.venteRef,
    this.origineRef,
    this.clientIfu,
    this.clientAdresse,
    this.motif,
    this.codeMecef,
    this.nim,
    this.compteur,
    this.lienVerification,
    this.dateNormalisation,
    this.erreurTransmission,
    this.origine,
    this.id = '',
  });

  /// UUID de la facture (DV-19) : son identité synchronisée.
  final String id;
  final String reference;
  final TypeFacture type;
  final DateTime date;
  final String client;
  final String? clientIfu;
  final String? clientAdresse;
  final List<LigneFacture> lignes;
  final StatutFacture statut;

  /// La vente d'origine, si la facture en vient.
  final String? venteRef;

  /// La facture corrigée — renseignée sur un avoir, et sur lui seul.
  final String? origineRef;

  final String? motif;

  final String? codeMecef;
  final String? nim;
  final String? compteur;
  final String? lienVerification;
  final DateTime? dateNormalisation;
  final String? erreurTransmission;

  /// `null` : émise sur ce poste. Sinon l'identifiant du poste émetteur.
  final String? origine;

  /// Une facture absorbée du serveur : lisible, imprimable, mais **jamais
  /// transmise d'ici** (un seul poste normalise, `46e_` §3).
  ///
  /// Une facture émise au **web** n'est PAS « d'un autre poste » : n'ayant pas de poste
  /// émetteur, elle peut être transmise par n'importe quel poste appairé (après
  /// réservation au serveur, voir [estWeb]).
  bool get estDUnAutrePoste =>
      origine != null && origine != identifiantPosteWeb;

  /// Émise depuis le web : sa transmission passe par une réservation serveur.
  bool get estWeb => origine == identifiantPosteWeb;

  double get totalHt => lignes.fold(0, (s, l) => s + l.montantHt);
  double get totalTaxe => lignes.fold(0, (s, l) => s + l.montantTaxe);
  double get totalTtc => totalHt + totalTaxe;

  /// `true` seulement si la DGI a réellement rendu un code.
  ///
  /// Le statut seul ne suffit pas : une facture marquée normalisée sans code
  /// serait un mensonge sur le document imprimé.
  bool get estNormalisee =>
      statut == StatutFacture.normalisee &&
      codeMecef != null &&
      codeMecef!.isNotEmpty;

  /// Le cumul par groupe, dans l'ordre des lettres.
  List<TotalParGroupe> get totauxParGroupe {
    final parGroupe = <String, ({double taux, double base, double taxe})>{};
    for (final l in lignes) {
      final actuel = parGroupe[l.groupeTaxe];
      parGroupe[l.groupeTaxe] = (
        taux: l.tauxTaxe,
        base: (actuel?.base ?? 0) + l.montantHt,
        taxe: (actuel?.taxe ?? 0) + l.montantTaxe,
      );
    }
    final codes = parGroupe.keys.toList()..sort();
    return [
      for (final c in codes)
        TotalParGroupe(
          groupe: c,
          taux: parGroupe[c]!.taux,
          baseHt: parGroupe[c]!.base,
          taxe: parGroupe[c]!.taxe,
        ),
    ];
  }
}

/// La numérotation des pièces.
///
/// `FV-2026-001`, `FA-2026-001` : une séquence par type **et** par année. Le
/// compteur repart à 1 le 1er janvier, comme l'exige une numérotation
/// chronologique annuelle.
///
/// **Poste appairé (DV-21)** : `FV-P2-2026-001`, `FA-P2-2026-001`. Le préfixe de
/// poste fait l'unicité entre postes sans passer par le serveur, et une facture
/// déjà remise au client ne change jamais de numéro.
class NumerotationFacture {
  const NumerotationFacture._();

  /// Construit la référence suivante à partir de la dernière connue.
  ///
  /// [derniere] est la référence la plus élevée de la même année et du même
  /// type, ou `null` s'il n'y en a aucune.
  static String suivante({
    required TypeFacture type,
    required DateTime date,
    String? derniere,
    String? codePoste,
  }) {
    final prefixe = prefixeDe(type, date.year, codePoste);
    var rang = 1;
    if (derniere != null && derniere.startsWith(prefixe)) {
      rang = (int.tryParse(derniere.substring(prefixe.length)) ?? 0) + 1;
    }
    return '$prefixe${rang.toString().padLeft(3, '0')}';
  }

  /// `FV-P2-2026-` ou, sans code de poste, `FV-2026-`.
  static String prefixeDe(TypeFacture type, int annee, String? codePoste) =>
      codePoste == null || codePoste.isEmpty
      ? '${type.code}-$annee-'
      : '${type.code}-$codePoste-$annee-';
}
