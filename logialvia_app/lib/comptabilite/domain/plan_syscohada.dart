/// Plan comptable SYSCOHADA révisé (Acte uniforme OHADA 2017, en vigueur depuis le
/// 1er janvier 2018) — **unique** endroit du poste qui porte des numéros de compte.
///
/// Aucun autre fichier ne doit contenir de numéro de compte littéral : il lit une constante
/// de [PlanSyscohada]. Le port web est `app/Support/PlanSyscohada.php` (comparé à ce fichier par
/// `ConformitePlanSyscohadaDartTest`). Doc `47p_PLAN_COMPTABLE_SYSCOHADA.md`.
///
/// ## ⚠️ Source
///
/// Les numéros et libellés ont été **reconstitués** de la connaissance du plan révisé et
/// recoupés avec un plan public tiers (voir `docs/logialvia/syscohada/`) : ils ne sont **pas
/// vérifiés contre le texte officiel de l'OHADA** (inaccessible depuis l'environnement de
/// développement). Décision à valider par l'expert-comptable (`47p_` §9).
library;

/// Un compte du plan : numéro, libellé officiel, classe (1er chiffre).
typedef CompteSyscohada = ({String numero, String libelle, String classe});

/// Une règle de renumérotation de l'ancien plan (prototype) vers le plan SYSCOHADA.
///
/// [fraisLivraisonSeulement] restreint la règle aux lignes d'une vente SANS centre analytique
/// (cas du 707 ancien : « ventes de marchandises » — toujours au centre « Commerce Annexe » —
/// **et** « frais de livraison » facturés, sans centre : ceux-là deviennent 7071).
typedef RegleRenumerotation = ({
  String ancien,
  String nouveau,
  String libelleAncien,
  bool fraisLivraisonSeulement,
});

class PlanSyscohada {
  PlanSyscohada._();

  /// Version du plan portée par les lots d'écritures et par le plan lui-même.
  /// 1 = ancien plan du prototype (jamais envoyé : absent) ; 2 = SYSCOHADA révisé.
  static const int version = 2;

  // --- Classe 1 : capitaux ---
  static const String capital = '101';
  static const String reserveLegale = '111';
  static const String autresReserves = '118';
  static const String reportCrediteur = '121';
  static const String reportDebiteur = '129';
  static const String resultatBenefice = '131';
  static const String resultatPerte = '139';

  // --- Classe 3 : stocks ---
  static const String stockMarchandises = '31';
  static const String stockMatieres = '32';

  // --- Classe 4 : tiers, État ---
  static const String fournisseurs = '401';
  static const String clients = '411';
  static const String clientsAvances = '419';

  /// TVA facturée sur les ventes de biens (taux appliqué aux produits vendus).
  static const String tvaCollectee = '4431';

  /// TVA facturée sur prestations de services (frais de livraison facturés).
  static const String tvaCollecteeServices = '4432';

  /// TVA récupérable sur achats : la TVA déductible.
  static const String tvaDeductible = '4452';
  static const String dividendesAPayer = '465';

  // --- Classe 5 : trésorerie ---

  /// Monnaie électronique : téléphone portable (Mobile Money).
  static const String mobileMoney = '552';
  static const String caisse = '571';

  // --- Classe 6 : charges ---
  static const String achatsMarchandises = '601';
  static const String achatsMatieres = '602';

  /// Achats stockés de matières et fournitures consommables : produits et soins
  /// vétérinaires (ancien « 622 Frais vétérinaires »).
  static const String fraisVeterinaires = '604';
  static const String transports = '618';
  static const String locations = '622';
  static const String assurances = '625';
  static const String chargesDiverses = '658';

  // --- Classe 7 : produits ---
  static const String ventesMarchandises = '701';

  /// Ventes de produits finis : les produits des filières d'élevage (animaux, œufs…).
  static const String ventesProduitsFinis = '702';
  static const String produitsAccessoires = '707';

  /// Ports, emballages perdus et autres frais facturés : frais de livraison facturés.
  static const String fraisLivraison = '7071';

  /// Charges réputées **fixes** (KPI « Charges Fixes ») : locations et assurances.
  static const Set<String> comptesChargesFixes = {locations, assurances};

  /// Compte de trésorerie du mode de règlement : Mobile Money → 552, le reste → 571.
  static String tresoreriePour(String mode) =>
      mode == 'Mobile Money' ? mobileMoney : caisse;

  /// Taux de TVA (en %) d'un groupe de taxe exprimé en pourcentage → montant de TVA
  /// extrait d'un montant **TTC**, arrondi au franc (le FCFA n'a pas de décimale).
  /// `0` pour un groupe exonéré : le montant n'est alors pas arrondi (inchangé).
  static double tvaDuTtc(double ttc, double taux) =>
      taux > 0 ? (ttc * taux / (100 + taux)).roundToDouble() : 0.0;

  /// Le plan applicable de la ferme : sous-ensemble utile du plan officiel.
  static const List<CompteSyscohada> comptes = [
    // Classe 1
    (numero: '101', libelle: 'Capital social', classe: '1'),
    (numero: '111', libelle: 'Réserve légale', classe: '1'),
    (numero: '118', libelle: 'Autres réserves', classe: '1'),
    (numero: '121', libelle: 'Report à nouveau créditeur', classe: '1'),
    (numero: '129', libelle: 'Report à nouveau débiteur', classe: '1'),
    (
      numero: '131',
      libelle: 'Résultat net de l\'exercice : bénéfice',
      classe: '1',
    ),
    (
      numero: '139',
      libelle: 'Résultat net de l\'exercice : perte',
      classe: '1',
    ),
    (
      numero: '162',
      libelle: 'Emprunts et dettes auprès des établissements de crédit',
      classe: '1',
    ),
    // Classe 2
    (
      numero: '231',
      libelle:
          'Bâtiments industriels, agricoles, administratifs et commerciaux sur sol propre',
      classe: '2',
    ),
    (numero: '242', libelle: 'Matériel et outillage agricole', classe: '2'),
    (numero: '244', libelle: 'Matériel et mobilier', classe: '2'),
    (numero: '245', libelle: 'Matériel de transport', classe: '2'),
    (
      numero: '246',
      libelle: 'Actifs biologiques',
      classe: '2',
    ),
    (
      numero: '283',
      libelle:
          'Amortissements des bâtiments, installations techniques et agencements',
      classe: '2',
    ),
    (numero: '284', libelle: 'Amortissements du matériel', classe: '2'),
    // Classe 3
    (numero: '31', libelle: 'Marchandises', classe: '3'),
    (
      numero: '32',
      libelle: 'Matières premières et fournitures liées',
      classe: '3',
    ),
    (numero: '36', libelle: 'Produits finis', classe: '3'),
    // Classe 4
    (numero: '401', libelle: 'Fournisseurs, dettes en compte', classe: '4'),
    (
      numero: '409',
      libelle: 'Fournisseurs débiteurs : avances et acomptes versés',
      classe: '4',
    ),
    (numero: '411', libelle: 'Clients', classe: '4'),
    (
      numero: '419',
      libelle: 'Clients créditeurs, avances et acomptes reçus',
      classe: '4',
    ),
    (numero: '421', libelle: 'Personnel, avances et acomptes', classe: '4'),
    (numero: '422', libelle: 'Personnel, rémunérations dues', classe: '4'),
    (numero: '431', libelle: 'Sécurité sociale', classe: '4'),
    (numero: '4431', libelle: 'TVA facturée sur ventes', classe: '4'),
    (
      numero: '4432',
      libelle: 'TVA facturée sur prestations de services',
      classe: '4',
    ),
    (numero: '4441', libelle: 'État, TVA due', classe: '4'),
    (numero: '4449', libelle: 'État, crédit de TVA à reporter', classe: '4'),
    (
      numero: '4451',
      libelle: 'État, TVA récupérable sur immobilisations',
      classe: '4',
    ),
    (numero: '4452', libelle: 'État, TVA récupérable sur achats', classe: '4'),
    (numero: '465', libelle: 'Associés, dividendes à payer', classe: '4'),
    // Classe 5
    (
      numero: '552',
      libelle: 'Monnaie électronique : téléphone portable',
      classe: '5',
    ),
    (numero: '571', libelle: 'Caisse siège social', classe: '5'),
    // Classe 6
    (numero: '601', libelle: 'Achats de marchandises', classe: '6'),
    (
      numero: '602',
      libelle: 'Achats de matières premières et fournitures liées',
      classe: '6',
    ),
    (
      numero: '604',
      libelle: 'Achats stockés de matières et fournitures consommables',
      classe: '6',
    ),
    (numero: '605', libelle: 'Autres achats', classe: '6'),
    (numero: '611', libelle: 'Transports sur achats', classe: '6'),
    (numero: '612', libelle: 'Transports sur ventes', classe: '6'),
    (numero: '618', libelle: 'Autres frais de transport', classe: '6'),
    (numero: '622', libelle: 'Locations et charges locatives', classe: '6'),
    (
      numero: '624',
      libelle: 'Entretien, réparations et maintenance',
      classe: '6',
    ),
    (numero: '625', libelle: 'Primes d\'assurance', classe: '6'),
    (numero: '628', libelle: 'Frais de télécommunications', classe: '6'),
    (numero: '631', libelle: 'Frais bancaires', classe: '6'),
    (
      numero: '632',
      libelle: 'Rémunérations d\'intermédiaires et de conseils',
      classe: '6',
    ),
    (numero: '641', libelle: 'Impôts et taxes directs', classe: '6'),
    (numero: '658', libelle: 'Charges diverses', classe: '6'),
    (
      numero: '661',
      libelle: 'Rémunérations directes versées au personnel national',
      classe: '6',
    ),
    (numero: '664', libelle: 'Charges sociales', classe: '6'),
    (numero: '671', libelle: 'Intérêts des emprunts', classe: '6'),
    (
      numero: '681',
      libelle: 'Dotations aux amortissements d\'exploitation',
      classe: '6',
    ),
    // Classe 7
    (numero: '701', libelle: 'Ventes de marchandises', classe: '7'),
    (numero: '702', libelle: 'Ventes de produits finis', classe: '7'),
    (numero: '706', libelle: 'Services vendus', classe: '7'),
    (numero: '707', libelle: 'Produits accessoires', classe: '7'),
    (
      numero: '7071',
      libelle: 'Ports, emballages perdus et autres frais facturés',
      classe: '7',
    ),
    (numero: '758', libelle: 'Produits divers', classe: '7'),
    (
      numero: '771',
      libelle: 'Intérêts de prêts et créances diverses',
      classe: '7',
    ),
  ];

  /// Libellés de l'ANCIEN plan (prototype) : un compte renumérotée dont le libellé est
  /// encore celui d'origine prend le libellé officiel ; un libellé modifié à la main est gardé.
  static const Map<String, String> libellesAnciens = {
    '31': 'Stocks de Marchandises (Commerce Annexe)',
    '32': 'Stocks de Matières (Intrants Provende)',
    '401': 'Fournisseurs',
    '411': 'Clients',
    '419': 'Clients — Avances Reçues',
    '512': 'Banques — Mobile Money',
    '531': 'Caisse',
    '601': 'Achats de Matières (Intrants Provende)',
    '602': 'Achats de Marchandises (Commerce Annexe)',
    '622': 'Frais Vétérinaires',
    '701': 'Ventes de Produits Avicoles',
    '707': 'Ventes de Marchandises (Commerce Annexe)',
    '101': 'Capital Social',
    '121': 'Report à Nouveau',
    '131': 'Résultat de l\'Exercice',
    '613': 'Locations',
    '616': 'Assurances',
    '624': 'Transports',
    '628': 'Charges Diverses de Gestion',
    '111': 'Réserve Légale',
    '118': 'Autres Réserves',
    '129': 'Report à Nouveau — Solde Débiteur',
    '139': 'Résultat Net : Perte',
    '465': 'Associés — Dividendes à Payer',
  };

  /// Table de correspondance ancien → nouveau (comptes dont le numéro CHANGE ; les autres
  /// comptes de l'ancien plan gardent leur numéro). Appliquée en deux temps (numéros
  /// temporaires) : 601↔602 se croisent, 613→622 reprend le numéro de l'ancien 622.
  ///
  /// La règle spécialisée (frais de livraison) passe AVANT la règle générale du 707.
  static const List<RegleRenumerotation> correspondance = [
    (
      ancien: '531',
      nouveau: '571',
      libelleAncien: 'Caisse',
      fraisLivraisonSeulement: false,
    ),
    (
      ancien: '512',
      nouveau: '552',
      libelleAncien: 'Banques — Mobile Money',
      fraisLivraisonSeulement: false,
    ),
    (
      ancien: '601',
      nouveau: '602',
      libelleAncien: 'Achats de Matières (Intrants Provende)',
      fraisLivraisonSeulement: false,
    ),
    (
      ancien: '602',
      nouveau: '601',
      libelleAncien: 'Achats de Marchandises (Commerce Annexe)',
      fraisLivraisonSeulement: false,
    ),
    (
      ancien: '622',
      nouveau: '604',
      libelleAncien: 'Frais Vétérinaires',
      fraisLivraisonSeulement: false,
    ),
    (
      ancien: '613',
      nouveau: '622',
      libelleAncien: 'Locations',
      fraisLivraisonSeulement: false,
    ),
    (
      ancien: '616',
      nouveau: '625',
      libelleAncien: 'Assurances',
      fraisLivraisonSeulement: false,
    ),
    (
      ancien: '624',
      nouveau: '618',
      libelleAncien: 'Transports',
      fraisLivraisonSeulement: false,
    ),
    (
      ancien: '628',
      nouveau: '658',
      libelleAncien: 'Charges Diverses de Gestion',
      fraisLivraisonSeulement: false,
    ),
    (
      ancien: '701',
      nouveau: '702',
      libelleAncien: 'Ventes de Produits Avicoles',
      fraisLivraisonSeulement: false,
    ),
    (
      ancien: '707',
      nouveau: '7071',
      libelleAncien: 'Ventes de Marchandises (Commerce Annexe)',
      fraisLivraisonSeulement: true,
    ),
    (
      ancien: '707',
      nouveau: '701',
      libelleAncien: 'Ventes de Marchandises (Commerce Annexe)',
      fraisLivraisonSeulement: false,
    ),
  ];
}
