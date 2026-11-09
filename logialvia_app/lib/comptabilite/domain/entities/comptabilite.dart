/// Un compte du plan comptable.
class CompteComptable {
  const CompteComptable({
    required this.numero,
    required this.libelle,
    required this.classe,
    this.archive = false,
  });

  final String numero;
  final String libelle;
  final String classe;
  final bool archive;

  /// **BR-CPT-007 — sens naturel du solde selon la classe SYSCOHADA.**
  ///
  /// Classes débitrices par nature : 2 (immobilisations), 3 (stocks),
  /// 6 (charges). Classes créditrices par nature : 1 (capitaux),
  /// 7 (produits).
  ///
  /// Les classes **4 (tiers)** et **5 (trésorerie)** sont *bidirectionnelles* :
  /// un compte Clients (411) est débiteur, un compte Fournisseurs (401) est
  /// créditeur, et tous deux sont en classe 4. La classe seule ne suffit donc
  /// pas — c'est le **1ᵉʳ chiffre du numéro** qui tranche, et Doc F6 §2 le
  /// laissait ambigu en parlant de « comptes de classe 1,4,5 créditeurs vs
  /// 2,3,4,5,6 débiteurs », où 4 et 5 apparaissent des deux côtés.
  bool get estDebiteurParNature {
    if (classe == '2' || classe == '3' || classe == '6') return true;
    if (classe == '1' || classe == '7') return false;

    // Classes 4 et 5 : arbitrage sur le numéro réel du compte.
    // 40x = Fournisseurs (créditeur) · 41x = Clients (débiteur, sauf 419
    // « avances reçues » qui est créditeur) · 42x/43x/44x = dettes sociales et
    // fiscales (créditeur) · classe 5 = trésorerie, débitrice sauf découvert.
    if (numero.startsWith('419')) return false;
    if (numero.startsWith('40')) return false;
    if (numero.startsWith('42') ||
        numero.startsWith('43') ||
        numero.startsWith('44')) {
      return false;
    }
    return true;
  }

  /// Libellés de classe, repris de `plan-comptable.html`.
  static const Map<String, String> libellesClasses = {
    '1': '1 - Capitaux',
    '2': '2 - Immobilisations',
    '3': '3 - Stocks',
    '4': '4 - Tiers',
    '5': '5 - Trésorerie',
    '6': '6 - Charges',
    '7': '7 - Produits',
  };
}

/// Codes journaux SYSCOHADA usuels.
class CodeJournal {
  CodeJournal._();

  static const String ventes = 'VT';
  static const String achats = 'AC';
  static const String caisse = 'CA';
  static const String operationsDiverses = 'OD';

  static const Map<String, String> libelles = {
    ventes: 'Journal des Ventes',
    achats: 'Journal des Achats',
    caisse: 'Journal de Caisse',
    operationsDiverses: 'Opérations Diverses',
  };

  static const List<String> tous = [
    ventes,
    achats,
    caisse,
    operationsDiverses,
  ];
}

/// Une écriture comptable.
class Ecriture {
  const Ecriture({
    required this.id,
    required this.exerciceAnnee,
    required this.numeroCompte,
    required this.date,
    required this.debit,
    required this.credit,
    required this.libelle,
    required this.journalCode,
    this.numeroPiece,
    this.venteRef,
    this.achatRef,
    this.isLocked = false,
    this.axeAnalytique,
    this.pieceId = '',
    this.origine,
    this.syncStatus = 'pending',
    this.syncMotif,
    this.contrepasseDe,
  });

  /// UUID de la ligne (DV-19).
  final String id;
  final int exerciceAnnee;
  final String numeroCompte;
  final DateTime date;
  final double debit;
  final double credit;
  final String libelle;
  final String journalCode;
  final String? numeroPiece;
  final String? venteRef;
  final String? achatRef;
  final bool isLocked;

  /// Centre analytique d'imputation, `null` si la ligne n'est pas imputée.
  final String? axeAnalytique;

  /// UUID de la pièce (toutes les lignes d'une partie double le partagent).
  final String pieceId;

  /// `null` : saisie sur CE poste ; sinon le poste d'origine (ligne reçue du serveur).
  final String? origine;

  /// `pending` · `synced` · `conflict` — voir `46d_` §2.
  final String syncStatus;
  final String? syncMotif;

  /// `piece_id` de la pièce que celle-ci annule (contrepassation), sinon `null`.
  final String? contrepasseDe;

  /// Écrite sur un autre poste : visible au grand livre, jamais modifiable ici.
  bool get vientDUnAutrePoste => origine != null;

  /// Le serveur connaît cette écriture : elle est désormais un fait partagé, qui
  /// ne se modifie ni ne se supprime (elle s'annule par contrepassation).
  bool get estTransmise => syncStatus == 'synced';

  /// Origine automatique — une écriture générée par une vente ou un achat ne
  /// doit pas être modifiable à la main (elle serait désynchronisée de sa
  /// source).
  bool get estAutomatique => venteRef != null || achatRef != null;
}

/// Une ligne du Grand Livre, avec son solde progressif.
class LigneGrandLivre {
  const LigneGrandLivre({
    required this.ecriture,
    required this.soldeProgressif,
  });

  final Ecriture ecriture;
  final double soldeProgressif;
}

/// Une ligne de la Balance Générale — format standard à 6 colonnes.
class LigneBalance {
  const LigneBalance({
    required this.numeroCompte,
    required this.libelle,
    required this.ouvertureDebit,
    required this.ouvertureCredit,
    required this.mouvementsDebit,
    required this.mouvementsCredit,
    required this.finalDebit,
    required this.finalCredit,
  });

  final String numeroCompte;
  final String libelle;
  final double ouvertureDebit;
  final double ouvertureCredit;
  final double mouvementsDebit;
  final double mouvementsCredit;
  final double finalDebit;
  final double finalCredit;
}

/// Un poste d'un état financier (Bilan, Compte de Résultat, TAFIRE).
class PosteEtat {
  const PosteEtat({
    required this.libelle,
    required this.montant,
    this.estTotal = false,
    this.estSousTotal = false,
    this.detail,
  });

  final String libelle;
  final double montant;

  /// Total général — mis en avant typographiquement.
  final bool estTotal;

  /// Sous-total intermédiaire (Marge Commerciale, Valeur Ajoutée, EBE…).
  final bool estSousTotal;

  /// Comptes sources, affichés en petit sous le libellé.
  final String? detail;
}

/// Résultat du Bilan.
class Bilan {
  const Bilan({required this.actif, required this.passif});

  final List<PosteEtat> actif;
  final List<PosteEtat> passif;

  double get totalActif =>
      actif.where((p) => p.estTotal).fold(0, (s, p) => s + p.montant);

  double get totalPassif =>
      passif.where((p) => p.estTotal).fold(0, (s, p) => s + p.montant);

  /// Contrôle d'équilibre affiché en permanence (Doc F6 §4 Onglet 1).
  bool get estEquilibre => (totalActif - totalPassif).abs() < 0.01;
}

/// Résultat du Compte de Résultat en cascade.
class CompteDeResultat {
  const CompteDeResultat({required this.postes, required this.resultatNet});

  final List<PosteEtat> postes;
  final double resultatNet;
}

/// Résultat du TAFIRE.
class Tafire {
  const Tafire({
    required this.fluxExploitation,
    required this.fluxInvestissement,
    required this.fluxFinancement,
    required this.tresorerieOuverture,
    required this.postes,
  });

  final double fluxExploitation;
  final double fluxInvestissement;
  final double fluxFinancement;
  final double tresorerieOuverture;
  final List<PosteEtat> postes;

  double get variation =>
      fluxExploitation + fluxInvestissement + fluxFinancement;

  double get tresorerieCloture => tresorerieOuverture + variation;
}

/// Une note annexe.
class NoteAnnexe {
  const NoteAnnexe({
    required this.numero,
    required this.titre,
    required this.contenu,
  });

  final int numero;
  final String titre;
  final String contenu;

  /// Les 5 notes obligatoires — Doc F6 §4 Onglet 4.
  static const Map<int, String> titresObligatoires = {
    1: 'Méthodes Comptables',
    2: 'Immobilisations',
    3: 'Stocks',
    4: 'Créances et Dettes',
    5: 'Engagements Hors Bilan',
  };
}
