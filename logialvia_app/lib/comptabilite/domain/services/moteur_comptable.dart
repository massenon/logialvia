import '../entities/comptabilite.dart';

/// Validation d'une écriture — partie double.
class EcritureValidator {
  EcritureValidator._();

  /// Tolérance d'arrondi en FCFA (Doc F6 §3).
  static const double tolerance = 0.01;

  /// Doc D1 : « exactement un des deux > 0 ». Une écriture avec débit **et**
  /// crédit, ou avec ni l'un ni l'autre, n'est pas une écriture.
  static String? valider({
    required double debit,
    required double credit,
    required String libelle,
    required String? numeroCompte,
  }) {
    if (numeroCompte == null || numeroCompte.isEmpty) {
      return 'Le compte est obligatoire.';
    }
    if (libelle.trim().isEmpty) return 'Le libellé est obligatoire.';
    if (debit < 0 || credit < 0) {
      return 'Les montants ne peuvent être négatifs.';
    }
    if (debit > 0 && credit > 0) {
      return 'Une écriture porte un débit OU un crédit, jamais les deux.';
    }
    if (debit == 0 && credit == 0) {
      return 'Saisissez un montant au débit ou au crédit.';
    }
    return null;
  }

  /// Un lot d'écritures saisies ensemble doit être équilibré avant validation :
  /// c'est la partie double au niveau de la pièce, pas seulement de la ligne.
  static String? validerLot(List<({double debit, double credit})> lignes) {
    if (lignes.isEmpty) return 'Aucune ligne saisie.';
    final totalDebit = lignes.fold<double>(0, (s, l) => s + l.debit);
    final totalCredit = lignes.fold<double>(0, (s, l) => s + l.credit);
    if ((totalDebit - totalCredit).abs() > tolerance) {
      return 'Pièce déséquilibrée : débit ${totalDebit.toStringAsFixed(0)} ≠ '
          'crédit ${totalCredit.toStringAsFixed(0)}.';
    }
    return null;
  }
}

/// Calcul du solde progressif du Grand Livre — Doc F6 §2.
class GrandLivreCalculator {
  const GrandLivreCalculator();

  List<LigneGrandLivre> calculer({
    required CompteComptable compte,
    required double soldeOuverture,
    required List<Ecriture> ecritures,
  }) {
    final triees = [...ecritures]
      ..sort((a, b) => a.date.compareTo(b.date));

    var solde = soldeOuverture;
    return [
      for (final e in triees)
        () {
          // BR-CPT-007 : le sens du solde progressif dépend de la nature du
          // compte. Sur un compte de produits (créditeur), un crédit augmente
          // le solde ; sur un compte de charges (débiteur), c'est le débit.
          solde += compte.estDebiteurParNature
              ? (e.debit - e.credit)
              : (e.credit - e.debit);
          return LigneGrandLivre(ecriture: e, soldeProgressif: solde);
        }(),
    ];
  }
}

/// Contrôle d'équilibre de la Balance Générale — **BR-CPT-004**.
class BalanceGeneraleValidator {
  BalanceGeneraleValidator._();

  static bool estEquilibree(List<LigneBalance> lignes) {
    final totalDebit = lignes.fold<double>(0, (s, l) => s + l.finalDebit);
    final totalCredit = lignes.fold<double>(0, (s, l) => s + l.finalCredit);
    return (totalDebit - totalCredit).abs() < EcritureValidator.tolerance;
  }

  static double ecart(List<LigneBalance> lignes) {
    final totalDebit = lignes.fold<double>(0, (s, l) => s + l.finalDebit);
    final totalCredit = lignes.fold<double>(0, (s, l) => s + l.finalCredit);
    return totalDebit - totalCredit;
  }
}

/// Construction de la Balance Générale à partir des écritures.
class BalanceCalculator {
  const BalanceCalculator();

  /// [ecrituresAnterieures] : écritures antérieures à la période, qui forment
  /// les soldes d'ouverture.
  List<LigneBalance> calculer({
    required List<CompteComptable> comptes,
    required List<Ecriture> ecrituresAnterieures,
    required List<Ecriture> ecrituresPeriode,
  }) {
    final ouverture = <String, double>{};
    for (final e in ecrituresAnterieures) {
      ouverture[e.numeroCompte] =
          (ouverture[e.numeroCompte] ?? 0) + e.debit - e.credit;
    }
    return calculerDepuis(
      comptes: comptes,
      ouvertureNet: ouverture,
      ecrituresPeriode: ecrituresPeriode,
    );
  }

  /// Balance dont l'ouverture est donnée en **soldes nets** (débit − crédit) par compte :
  /// les à-nouveaux de l'exercice (voir `ReportANouveau.soldesOuverture`).
  List<LigneBalance> calculerDepuis({
    required List<CompteComptable> comptes,
    required Map<String, double> ouvertureNet,
    required List<Ecriture> ecrituresPeriode,
  }) {
    final lignes = <LigneBalance>[];

    for (final compte in comptes) {
      final periode = ecrituresPeriode.where(
        (e) => e.numeroCompte == compte.numero,
      );
      final aOuverture = ouvertureNet.containsKey(compte.numero);

      if (!aOuverture && periode.isEmpty) continue;

      final ouvertureCompte = ouvertureNet[compte.numero] ?? 0;
      final mouvementsDebit = periode.fold<double>(0, (s, e) => s + e.debit);
      final mouvementsCredit = periode.fold<double>(0, (s, e) => s + e.credit);
      final finalNet = ouvertureCompte + mouvementsDebit - mouvementsCredit;

      lignes.add(
        LigneBalance(
          numeroCompte: compte.numero,
          libelle: compte.libelle,
          // Un solde n'apparaît que d'un seul côté : positif au débit,
          // négatif au crédit (en valeur absolue).
          ouvertureDebit: ouvertureCompte > 0 ? ouvertureCompte : 0,
          ouvertureCredit: ouvertureCompte < 0 ? -ouvertureCompte : 0,
          mouvementsDebit: mouvementsDebit,
          mouvementsCredit: mouvementsCredit,
          finalDebit: finalNet > 0 ? finalNet : 0,
          finalCredit: finalNet < 0 ? -finalNet : 0,
        ),
      );
    }

    lignes.sort((a, b) => a.numeroCompte.compareTo(b.numeroCompte));
    return lignes;
  }
}

/// Agrégats par compte, base commune de tous les états financiers.
///
/// **BR-CPT-005 appliqué structurellement** : Bilan, Compte de Résultat et
/// TAFIRE lisent tous cette même agrégation. Trois calculs indépendants
/// pourraient diverger ; un seul ne le peut pas.
class SoldesComptes {
  const SoldesComptes(this._soldes);

  /// Solde net (débit − crédit) par numéro de compte.
  final Map<String, double> _soldes;

  factory SoldesComptes.depuis(List<Ecriture> ecritures) {
    final soldes = <String, double>{};
    for (final e in ecritures) {
      soldes[e.numeroCompte] =
          (soldes[e.numeroCompte] ?? 0) + e.debit - e.credit;
    }
    return SoldesComptes(soldes);
  }

  double solde(String numeroCompte) => _soldes[numeroCompte] ?? 0;

  /// Somme des soldes nets des comptes dont le numéro commence par [prefixe].
  double parPrefixe(String prefixe) {
    var total = 0.0;
    _soldes.forEach((numero, solde) {
      if (numero.startsWith(prefixe)) total += solde;
    });
    return total;
  }

  /// Soldes débiteurs des comptes dont le numéro commence par [prefixe].
  double debiteursParPrefixe(String prefixe) {
    var total = 0.0;
    _soldes.forEach((numero, solde) {
      if (numero.startsWith(prefixe) && solde > 0) total += solde;
    });
    return total;
  }

  /// Soldes créditeurs (valeur absolue) des comptes dont le numéro commence par [prefixe].
  double crediteursParPrefixe(String prefixe) {
    var total = 0.0;
    _soldes.forEach((numero, solde) {
      if (numero.startsWith(prefixe) && solde < 0) total += -solde;
    });
    return total;
  }

  /// Somme des soldes d'une classe entière.
  double parClasse(String classe) => parPrefixe(classe);

  /// Soldes **débiteurs** d'une classe (montants positifs uniquement).
  double debiteursParClasse(String classe) {
    var total = 0.0;
    _soldes.forEach((numero, solde) {
      if (numero.startsWith(classe) && solde > 0) total += solde;
    });
    return total;
  }

  /// Soldes **créditeurs** d'une classe (valeur absolue des négatifs).
  double crediteursParClasse(String classe) {
    var total = 0.0;
    _soldes.forEach((numero, solde) {
      if (numero.startsWith(classe) && solde < 0) total += -solde;
    });
    return total;
  }

  Iterable<String> get comptes => _soldes.keys;
}

/// **Source unique de vérité du Résultat Net — BR-CPT-005.**
///
/// Doc F6 §5 l'exige explicitement : « UN SEUL usecase calcule le Résultat Net,
/// réutilisé par les 3 états — jamais 3 implémentations parallèles ».
class CalculerResultatNet {
  CalculerResultatNet._();

  /// Résultat = Produits (classe 7 + soldes créditeurs de la classe 8) − Charges (classe 6
  /// + soldes débiteurs de la classe 8).
  ///
  /// La classe 8 (HAO, participation, impôt sur le résultat) fait partie du résultat net
  /// SYSCOHADA : l'ignorer fausserait le compte 13 dès qu'un compte 8x est mouvementé.
  ///
  /// Les soldes étant stockés en net (débit − crédit) :
  /// - une charge a un solde **positif**,
  /// - un produit a un solde **négatif**.
  ///
  /// D'où : Résultat = −(solde classe 6 + solde classe 7 + solde classe 8).
  static double calculer(SoldesComptes soldes) {
    return produits(soldes) - charges(soldes);
  }

  static double produits(SoldesComptes soldes) =>
      -soldes.parClasse('7') + soldes.crediteursParClasse('8');

  static double charges(SoldesComptes soldes) =>
      soldes.parClasse('6') + soldes.debiteursParClasse('8');
}

/// Construction du Bilan SYSCOHADA — Doc F6 §4 Onglet 1.
class BilanCalculator {
  const BilanCalculator();

  Bilan calculer(SoldesComptes soldes) {
    final resultatNet = CalculerResultatNet.calculer(soldes);

    // --- ACTIF ---
    final chargesImmobilisees = soldes.parPrefixe('20');
    final incorporelles = soldes.parPrefixe('21');
    final corporelles =
        soldes.parPrefixe('22') +
        soldes.parPrefixe('23') +
        soldes.parPrefixe('24') +
        soldes.parPrefixe('25');
    final financieres = soldes.parPrefixe('26') + soldes.parPrefixe('27');
    // Amortissements et dépréciations des immobilisations : soldes créditeurs, donc
    // négatifs en net, ils MINORENT l'actif. Les omettre déséquilibrait le bilan.
    final amortissements = soldes.parPrefixe('28') + soldes.parPrefixe('29');
    final totalImmobilise =
        chargesImmobilisees +
        incorporelles +
        corporelles +
        financieres +
        amortissements;

    final stocks = soldes.parClasse('3');
    final creances = soldes.debiteursParClasse('4');
    final totalCirculant = stocks + creances;

    final tresorerieActif = soldes.debiteursParClasse('5');

    final actif = <PosteEtat>[
      PosteEtat(
        libelle: 'Charges Immobilisées',
        montant: chargesImmobilisees,
        detail: 'Comptes 20',
      ),
      PosteEtat(
        libelle: 'Immobilisations Incorporelles',
        montant: incorporelles,
        detail: 'Comptes 21',
      ),
      PosteEtat(
        libelle: 'Immobilisations Corporelles',
        montant: corporelles,
        detail: 'Comptes 22 à 25',
      ),
      PosteEtat(
        libelle: 'Immobilisations Financières',
        montant: financieres,
        detail: 'Comptes 26-27',
      ),
      PosteEtat(
        libelle: 'Amortissements et Dépréciations',
        montant: amortissements,
        detail: 'Comptes 28-29 (à déduire)',
      ),
      PosteEtat(
        libelle: 'Total Actif Immobilisé',
        montant: totalImmobilise,
        estSousTotal: true,
      ),
      PosteEtat(libelle: 'Stocks', montant: stocks, detail: 'Classe 3'),
      PosteEtat(
        libelle: 'Créances et Emplois Assimilés',
        montant: creances,
        detail: 'Classe 4, soldes débiteurs',
      ),
      PosteEtat(
        libelle: 'Total Actif Circulant',
        montant: totalCirculant,
        estSousTotal: true,
      ),
      PosteEtat(
        libelle: 'Trésorerie-Actif',
        montant: tresorerieActif,
        detail: 'Classe 5, soldes débiteurs',
      ),
      PosteEtat(
        libelle: 'TOTAL GÉNÉRAL ACTIF',
        montant: totalImmobilise + totalCirculant + tresorerieActif,
        estTotal: true,
      ),
    ];

    // --- PASSIF ---
    final capital = -soldes.parPrefixe('10');
    // Réserves et Report à Nouveau (11-12), hors compte de résultat 13 qui est
    // recalculé ci-dessous pour garantir BR-CPT-005.
    final reserves = -(soldes.parPrefixe('11') + soldes.parPrefixe('12'));
    // Subventions d'investissement et provisions réglementées (14-15), et tout solde
    // résiduel du compte 13 (une clôture affecte le 13 ; seule une écriture manuelle le laisse).
    final subventions = -(soldes.parPrefixe('13') +
        soldes.parPrefixe('14') +
        soldes.parPrefixe('15'));
    final capitauxPropres = capital + reserves + subventions + resultatNet;

    final dettesFinancieres = -(soldes.parPrefixe('16') +
        soldes.parPrefixe('17') +
        soldes.parPrefixe('18') +
        soldes.parPrefixe('19'));
    final ressourcesStables = capitauxPropres + dettesFinancieres;

    final dettesCirculantes = soldes.crediteursParClasse('4');
    final tresoreriePassif = soldes.crediteursParClasse('5');

    final passif = <PosteEtat>[
      PosteEtat(libelle: 'Capital', montant: capital, detail: 'Compte 10'),
      PosteEtat(
        libelle: 'Réserves et Report à Nouveau',
        montant: reserves,
        detail: 'Comptes 11-12',
      ),
      PosteEtat(
        libelle: 'Subventions et Provisions Réglementées',
        montant: subventions,
        detail: 'Comptes 13 (résiduel), 14-15',
      ),
      PosteEtat(
        libelle: 'Résultat Net de l\'Exercice',
        // ⚠️ Ce montant vient de `CalculerResultatNet`, la même source que le
        // Compte de Résultat et le TAFIRE — BR-CPT-005 garanti par
        // construction, pas par vérification a posteriori.
        montant: resultatNet,
        detail: 'Compte 13 — source unique',
      ),
      PosteEtat(
        libelle: 'Total Capitaux Propres',
        montant: capitauxPropres,
        estSousTotal: true,
      ),
      PosteEtat(
        libelle: 'Dettes Financières',
        montant: dettesFinancieres,
        detail: 'Comptes 16-19',
      ),
      PosteEtat(
        libelle: 'Total Ressources Stables',
        montant: ressourcesStables,
        estSousTotal: true,
      ),
      PosteEtat(
        libelle: 'Dettes Circulantes',
        montant: dettesCirculantes,
        detail: 'Classe 4, soldes créditeurs',
      ),
      PosteEtat(
        libelle: 'Total Passif Circulant',
        montant: dettesCirculantes,
        estSousTotal: true,
      ),
      PosteEtat(
        libelle: 'Trésorerie-Passif',
        montant: tresoreriePassif,
        detail: 'Classe 5, soldes créditeurs',
      ),
      PosteEtat(
        libelle: 'TOTAL GÉNÉRAL PASSIF',
        montant: ressourcesStables + dettesCirculantes + tresoreriePassif,
        estTotal: true,
      ),
    ];

    return Bilan(actif: actif, passif: passif);
  }
}

/// Compte de Résultat en cascade SYSCOHADA — Doc F6 §4 Onglet 2.
class CompteResultatCalculator {
  const CompteResultatCalculator();

  CompteDeResultat calculer(SoldesComptes soldes) {
    // Produits : soldes créditeurs, donc négatifs en net -> on inverse.
    final ventesMarchandises = -soldes.parPrefixe('707');
    final ventesProduits = -soldes.parPrefixe('701');
    final ventesTotales = -soldes.parPrefixe('70');

    // Charges : soldes débiteurs, positifs en net.
    final achatsMarchandises = soldes.parPrefixe('602');
    final achatsMatieres = soldes.parPrefixe('601');

    final margeCommerciale = ventesMarchandises - achatsMarchandises;

    // Consommations en provenance des tiers : classes 60-62 hors marchandises.
    // Toute la classe 60 hors marchandises (601 matières, 603-608 variations de stocks,
    // fournitures), puis 61 transports, 62 et 63 services extérieurs.
    final consommationsTiers = achatsMatieres +
        (soldes.parPrefixe('60') - achatsMarchandises - achatsMatieres) +
        soldes.parPrefixe('61') +
        soldes.parPrefixe('62') +
        soldes.parPrefixe('63');

    final valeurAjoutee =
        ventesTotales - achatsMarchandises - consommationsTiers;

    final chargesPersonnel = soldes.parPrefixe('66');
    final impotsTaxes = soldes.parPrefixe('64');
    final excedentBrut = valeurAjoutee - chargesPersonnel - impotsTaxes;

    // Autres produits d'exploitation : tout ce que la classe 7 porte hors ventes (70) et
    // produits financiers (77) : subventions 71, production immobilisée 72, variations de
    // stocks 73, autres produits 75, transferts de charges 78, reprises 79.
    final autresProduits =
        -(soldes.parClasse('7') -
            soldes.parPrefixe('70') -
            soldes.parPrefixe('77'));
    final autresCharges = soldes.parPrefixe('65');
    final dotations = soldes.parPrefixe('68') + soldes.parPrefixe('69');
    final resultatExploitation =
        excedentBrut + autresProduits - autresCharges - dotations;

    final produitsFinanciers = -soldes.parPrefixe('77');
    final chargesFinancieres = soldes.parPrefixe('67');
    final resultatFinancier = produitsFinanciers - chargesFinancieres;
    final resultatActivitesOrdinaires =
        resultatExploitation + resultatFinancier;

    // HAO : comptes 81 à 86 et 88 de la classe 8 (cessions, charges et produits HAO,
    // dotations et reprises HAO, subventions d'équilibre), hors 87 et 89 ci-dessous.
    final resultatHao = -(soldes.parClasse('8') -
        soldes.parPrefixe('87') -
        soldes.parPrefixe('89'));

    final participation = soldes.parPrefixe('87');
    final impotSocietes = soldes.parPrefixe('89');

    // Le Résultat Net vient de la SOURCE UNIQUE, pas de la fin de cascade —
    // les deux doivent coïncider, et c'est ce que vérifie un test dédié.
    final resultatNet = CalculerResultatNet.calculer(soldes);

    return CompteDeResultat(
      resultatNet: resultatNet,
      postes: [
        PosteEtat(
          libelle: 'Ventes de Marchandises',
          montant: ventesMarchandises,
          detail: 'Compte 707',
        ),
        PosteEtat(
          libelle: 'Achats de Marchandises Consommés',
          montant: -achatsMarchandises,
          detail: 'Compte 602',
        ),
        PosteEtat(
          libelle: 'MARGE COMMERCIALE',
          montant: margeCommerciale,
          estSousTotal: true,
        ),
        PosteEtat(
          libelle: 'Ventes de Produits Avicoles',
          montant: ventesProduits,
          detail: 'Compte 701',
        ),
        PosteEtat(
          libelle: 'Consommations en Provenance des Tiers',
          montant: -consommationsTiers,
          detail: 'Comptes 60 (hors 602), 61, 62, 63',
        ),
        PosteEtat(
          libelle: 'VALEUR AJOUTÉE',
          montant: valeurAjoutee,
          estSousTotal: true,
        ),
        PosteEtat(
          libelle: 'Charges de Personnel',
          montant: -chargesPersonnel,
          detail: 'Classe 66',
        ),
        PosteEtat(
          libelle: 'Impôts et Taxes',
          montant: -impotsTaxes,
          detail: 'Classe 64',
        ),
        PosteEtat(
          libelle: 'EXCÉDENT BRUT D\'EXPLOITATION',
          montant: excedentBrut,
          estSousTotal: true,
        ),
        PosteEtat(
          libelle: 'Autres Produits',
          montant: autresProduits,
          detail: 'Classe 7 hors 70 et 77',
        ),
        PosteEtat(libelle: 'Autres Charges', montant: -autresCharges),
        PosteEtat(
          libelle: 'Dotations aux Amortissements et Provisions',
          montant: -dotations,
          detail: 'Classes 68-69',
        ),
        PosteEtat(
          libelle: 'RÉSULTAT D\'EXPLOITATION',
          montant: resultatExploitation,
          estSousTotal: true,
        ),
        PosteEtat(
          libelle: 'Résultat Financier',
          montant: resultatFinancier,
          detail: 'Classe 77 − Classe 67',
        ),
        PosteEtat(
          libelle: 'RÉSULTAT DES ACTIVITÉS ORDINAIRES',
          montant: resultatActivitesOrdinaires,
          estSousTotal: true,
        ),
        PosteEtat(
          libelle: 'Résultat Hors Activités Ordinaires',
          montant: resultatHao,
        ),
        PosteEtat(libelle: 'Participation des Travailleurs', montant: -participation),
        PosteEtat(libelle: 'Impôt sur les Sociétés', montant: -impotSocietes),
        PosteEtat(
          libelle: 'RÉSULTAT NET DE L\'EXERCICE',
          montant: resultatNet,
          estTotal: true,
        ),
      ],
    );
  }
}

/// TAFIRE simplifié — Doc F6 §4 Onglet 3.
///
/// ## Identité garantie (vérifiée par un test)
///
/// Trésorerie d'ouverture + flux d'exploitation + flux d'investissement + flux de
/// financement = **trésorerie de clôture** (soldes nets de la classe 5). Elle tient parce
/// que tout le livre est équilibré : Σ classes 1 à 5 = résultat net (les classes 6 à 8 portent
/// l'inverse), et les flux sont construits pour sommer exactement ce mouvement.
///
/// - **Exploitation** = résultat + charges non décaissées (variation des comptes 28, 29, 39,
///   49, crédités par les dotations) − variation du besoin en fonds de roulement **brut**.
/// - **Investissement** = − variation des immobilisations **brutes** (classe 2 hors 28-29).
/// - **Financement** = − variation de la classe 1. Le résultat de l'exercice n'y figure pas :
///   avant clôture il n'est pas encore au compte 13 (il est déjà dans l'exploitation) ; à
///   l'ouverture suivante, son affectation (121, réserves, dividendes à payer 465) est dans
///   l'ouverture, pas dans les flux.
class TafireCalculator {
  const TafireCalculator();

  /// Comptes de dotations/dépréciations, portés au crédit d'un compte d'actif.
  static const List<String> comptesDeProvisions = ['28', '29', '39', '49'];

  Tafire calculer({
    required SoldesComptes soldes,
    required SoldesComptes soldesOuverture,
  }) {
    final resultatNet = CalculerResultatNet.calculer(soldes);

    double provisions(SoldesComptes s) =>
        comptesDeProvisions.fold(0.0, (t, p) => t + s.parPrefixe(p));
    // Charges non décaissées : l'accroissement des provisions (soldes créditeurs, donc
    // négatifs en net : on change le signe).
    final nonDecaisse = -(provisions(soldes) - provisions(soldesOuverture));

    // Variation du BFR brut = (stocks + créances − dettes circulantes) hors provisions.
    double bfr(SoldesComptes s) =>
        s.parClasse('3') +
        s.parClasse('4') -
        s.parPrefixe('39') -
        s.parPrefixe('49');
    final variationBfr = bfr(soldes) - bfr(soldesOuverture);

    final fluxExploitation = resultatNet + nonDecaisse - variationBfr;

    // Investissement : variation des immobilisations brutes (classe 2 hors 28-29).
    double immoBrutes(SoldesComptes s) =>
        s.parClasse('2') - s.parPrefixe('28') - s.parPrefixe('29');
    final acquisitions = immoBrutes(soldes) - immoBrutes(soldesOuverture);
    final fluxInvestissement = -acquisitions;

    // Financement : variation des capitaux et dettes financières (classe 1).
    final fluxFinancement =
        -(soldes.parClasse('1') - soldesOuverture.parClasse('1'));

    final tresorerieOuverture = soldesOuverture.parClasse('5');

    return Tafire(
      fluxExploitation: fluxExploitation,
      fluxInvestissement: fluxInvestissement,
      fluxFinancement: fluxFinancement,
      tresorerieOuverture: tresorerieOuverture,
      postes: [
        PosteEtat(libelle: 'Résultat Net de l\'Exercice', montant: resultatNet),
        PosteEtat(
          libelle: 'Dotations aux Amortissements et Provisions',
          montant: nonDecaisse,
          detail: 'Charge non décaissée (comptes 28, 29, 39, 49)',
        ),
        PosteEtat(
          libelle: 'Variation du Besoin en Fonds de Roulement',
          montant: -variationBfr,
        ),
        PosteEtat(
          libelle: 'FLUX NET DE TRÉSORERIE D\'EXPLOITATION',
          montant: fluxExploitation,
          estSousTotal: true,
        ),
        PosteEtat(
          libelle: 'Acquisitions d\'Immobilisations',
          montant: -acquisitions,
        ),
        PosteEtat(
          libelle: 'FLUX NET DE TRÉSORERIE D\'INVESTISSEMENT',
          montant: fluxInvestissement,
          estSousTotal: true,
        ),
        PosteEtat(
          libelle: 'Apports en Capital et Emprunts',
          montant: fluxFinancement,
        ),
        PosteEtat(
          libelle: 'FLUX NET DE TRÉSORERIE DE FINANCEMENT',
          montant: fluxFinancement,
          estSousTotal: true,
        ),
        PosteEtat(
          libelle: 'VARIATION DE TRÉSORERIE DE LA PÉRIODE',
          montant: fluxExploitation + fluxInvestissement + fluxFinancement,
          estTotal: true,
        ),
      ],
    );
  }
}
