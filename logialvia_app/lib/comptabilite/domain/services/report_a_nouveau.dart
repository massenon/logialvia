import '../entities/comptabilite.dart';
import 'moteur_comptable.dart';

/// # Report à nouveau et clôture annuelle — SYSCOHADA révisé (OHADA 2018)
///
/// Ce fichier est la **source** des règles de clôture : le serveur Laravel
/// (`App\Services\Comptabilite\ReportANouveau`) en est un port fidèle, comparé
/// chiffre à chiffre par les tests. Voir `docs/logialvia/47c_COMPTABILITE_SYSCOHADA_RAN.md`.
///
/// ## Ce que fait la clôture d'un exercice N
///
/// 1. **Résultat** : classes 6, 7 et 8 (charges − produits, HAO compris) → compte
///    **131** (bénéfice, créditeur) ou **139** (perte, débiteur). Pièce `CL-N-RESULTAT`,
///    journal `CL`, au 31/12/N : chaque compte de gestion est soldé, sa contrepartie est
///    le compte 13.
/// 2. **Affectation** : pièce `CL-N-AFFECTATION`, journal `CL`. Bénéfice : le 131 est soldé
///    au profit des réserves (111 légale, 118 autres), des dividendes à payer (465) et du
///    **report à nouveau créditeur 121** (le reste). Perte : le 139 est soldé au débit du
///    **report à nouveau débiteur 129**.
/// 3. **À-nouveaux** : pièce `AN-(N+1)`, journal `AN`, au 01/01/N+1 : les soldes des comptes
///    de bilan (classes 1 à 5) après affectation. Les classes 6, 7 et 8 ne sont **jamais**
///    reportées : leur solde est nul après la clôture.
///
/// ## Lecture des états après clôture
///
/// - Le **compte de résultat**, le **bilan** et le **TAFIRE** de N se lisent « avant
///   affectation » : ils ignorent les écritures de clôture (`CL`), sinon le résultat de N
///   disparaîtrait de son propre compte de résultat.
/// - Le **bilan de N+1** part de l'ouverture : il cumule les à-nouveaux (`AN`) et les
///   mouvements de N+1. La **trésorerie d'ouverture** du TAFIRE est la somme des soldes 5xx
///   reportés.
/// - La **balance** et le **grand livre** lisent le livre complet (`CL` compris) : un compte
///   de gestion y est bien soldé.
///
/// ## Ouverture d'un exercice qui n'a pas (encore) d'à-nouveaux
///
/// Tant que N−1 n'est pas clôturé (ou si N−1 a été clôturé avant l'existence de ce code),
/// l'ouverture de N est calculée par une **clôture virtuelle** de N−1 : mêmes soldes de
/// bilan, résultat de N−1 porté au 121 (bénéfice) ou 129 (perte). Elle ne s'écrit nulle
/// part ; elle disparaît dès que les vrais à-nouveaux existent.
class JournauxDeCloture {
  JournauxDeCloture._();

  /// Écritures de clôture de l'exercice (solde des comptes de gestion, affectation).
  static const String cloture = 'CL';

  /// Écritures d'à-nouveaux (report à nouveau) de l'exercice qui s'ouvre.
  static const String reportANouveau = 'AN';

  static const Map<String, String> libelles = {
    reportANouveau: 'À-Nouveaux (Report à Nouveau)',
    cloture: 'Écritures de Clôture',
  };

  /// Journaux qui ne se saisissent pas à la main : générés par la clôture.
  static bool estDeCloture(String code) =>
      code == cloture || code == reportANouveau;
}

/// Comptes SYSCOHADA révisé utilisés par la clôture.
class ComptesCloture {
  ComptesCloture._();

  static const String reserveLegale = '111';
  static const String autresReserves = '118';
  static const String reportCrediteur = '121';
  static const String reportDebiteur = '129';
  static const String resultatBenefice = '131';
  static const String resultatPerte = '139';
  static const String dividendesAPayer = '465';
}

/// Décision d'affectation du bénéfice (Assemblée) : ce qui part en réserves et en
/// dividendes. Le reste est reporté à nouveau (121). Sur une perte, rien ne se distribue :
/// la perte va au 129.
class AffectationResultat {
  const AffectationResultat({
    this.reserveLegale = 0,
    this.autresReserves = 0,
    this.dividendes = 0,
  });

  /// Tout au report à nouveau : la décision par défaut, sans Assemblée.
  static const AffectationResultat aucune = AffectationResultat();

  final double reserveLegale;
  final double autresReserves;
  final double dividendes;

  double get totalDistribue => reserveLegale + autresReserves + dividendes;

  /// Part du bénéfice qui reste au report à nouveau créditeur (121).
  double reportANouveau(double resultat) =>
      resultat > 0 ? resultat - totalDistribue : 0;

  /// Motif du refus, ou `null`. [reportDebiteurAnterieur] : solde débiteur du 129 avant la
  /// clôture (perte antérieure non absorbée) : aucun dividende ne peut être servi tant que
  /// le bénéfice ne la couvre pas.
  String? valider(double resultat, {double reportDebiteurAnterieur = 0}) {
    if (reserveLegale < 0 || autresReserves < 0 || dividendes < 0) {
      return 'Les montants d\'affectation ne peuvent pas être négatifs.';
    }
    if (resultat <= EcritureValidator.tolerance) {
      if (totalDistribue > EcritureValidator.tolerance) {
        return 'Aucune distribution n\'est possible sur un résultat nul ou déficitaire : '
            'la perte est portée au report à nouveau débiteur (129).';
      }
      return null;
    }
    if (totalDistribue > resultat + EcritureValidator.tolerance) {
      return 'L\'affectation (${totalDistribue.toStringAsFixed(0)}) dépasse le '
          'bénéfice (${resultat.toStringAsFixed(0)}).';
    }
    if (dividendes > EcritureValidator.tolerance &&
        reportDebiteurAnterieur > EcritureValidator.tolerance &&
        dividendes + reserveLegale + autresReserves + reportDebiteurAnterieur >
            resultat + EcritureValidator.tolerance) {
      return 'Un report à nouveau débiteur de '
          '${reportDebiteurAnterieur.toStringAsFixed(0)} subsiste : le bénéfice doit '
          'd\'abord l\'absorber avant tout dividende.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'reserve_legale': reserveLegale,
    'autres_reserves': autresReserves,
    'dividendes': dividendes,
  };

  static AffectationResultat depuisJson(Object? json) {
    if (json is! Map) return aucune;
    double lire(String cle) {
      final v = json[cle];
      return v is num && v >= 0 ? v.toDouble() : 0;
    }

    return AffectationResultat(
      reserveLegale: lire('reserve_legale'),
      autresReserves: lire('autres_reserves'),
      dividendes: lire('dividendes'),
    );
  }
}

/// Une ligne à écrire par la clôture (un seul des deux montants est positif).
class LigneCloture {
  const LigneCloture({
    required this.numeroCompte,
    required this.debit,
    required this.credit,
    required this.libelle,
  });

  final String numeroCompte;
  final double debit;
  final double credit;
  final String libelle;
}

/// Une pièce de clôture : numéro, journal, date, lignes. [cle] sert à dériver les
/// identifiants **déterministes** (pièce et lignes) : deux postes, ou le poste et le
/// serveur, qui clôturent le même exercice produisent les MÊMES identifiants — la
/// clôture rejouée ne duplique rien.
class PieceCloture {
  const PieceCloture({
    required this.cle,
    required this.numeroPiece,
    required this.journalCode,
    required this.date,
    required this.exerciceAnnee,
    required this.lignes,
  });

  final String cle;
  final String numeroPiece;
  final String journalCode;
  final DateTime date;
  final int exerciceAnnee;
  final List<LigneCloture> lignes;

  double get totalDebit => lignes.fold(0, (s, l) => s + l.debit);
  double get totalCredit => lignes.fold(0, (s, l) => s + l.credit);
}

/// Résultat du calcul de clôture (aperçu ou écriture).
class ClotureCalculee {
  const ClotureCalculee({
    required this.exercice,
    required this.resultat,
    required this.pieces,
    required this.anomalies,
  });

  final int exercice;

  /// Résultat net arrêté (classes 6, 7, 8) : positif = bénéfice.
  final double resultat;

  /// Dans l'ordre d'écriture : résultat, affectation, à-nouveaux.
  final List<PieceCloture> pieces;

  /// Anomalies bloquantes (balance déséquilibrée, affectation refusée, …).
  final List<String> anomalies;

  bool get bloquee => anomalies.isNotEmpty;

  List<PieceCloture> get piecesDeCloture =>
      pieces.where((p) => p.journalCode == JournauxDeCloture.cloture).toList();

  PieceCloture? get aNouveaux {
    for (final p in pieces) {
      if (p.journalCode == JournauxDeCloture.reportANouveau) return p;
    }
    return null;
  }

  /// Soldes reportés (compte → net débit − crédit), tels que les à-nouveaux les portent.
  Map<String, double> get soldesReportes {
    final map = <String, double>{};
    final an = aNouveaux;
    if (an == null) return map;
    for (final l in an.lignes) {
      map[l.numeroCompte] = l.debit - l.credit;
    }
    return map;
  }
}

class ReportANouveau {
  const ReportANouveau();

  static const double tolerance = EcritureValidator.tolerance;

  /// Arrondi au centime : les à-nouveaux et la clôture n'écrivent que des montants
  /// exacts au centime, sinon une dérive de virgule flottante ferait déborder la
  /// tolérance d'équilibre.
  static double centime(double v) => (v * 100).roundToDouble() / 100;

  // ---------------------------------------------------------------- lectures

  /// Lignes que les états de N lisent : tout l'exercice SAUF les à-nouveaux (ils sont
  /// l'ouverture, comptés à part) et les écritures de clôture (états « avant affectation »).
  List<Ecriture> mouvementsCourants(List<Ecriture> toutes, int annee) => [
    for (final e in toutes)
      if (e.exerciceAnnee == annee &&
          !JournauxDeCloture.estDeCloture(e.journalCode))
        e,
  ];

  /// Lignes du **livre** de N : tout sauf les à-nouveaux (l'ouverture) ; les écritures de
  /// clôture y figurent (un compte de gestion y est soldé).
  List<Ecriture> mouvementsDuLivre(List<Ecriture> toutes, int annee) => [
    for (final e in toutes)
      if (e.exerciceAnnee == annee &&
          e.journalCode != JournauxDeCloture.reportANouveau)
        e,
  ];

  /// Soldes nets (débit − crédit) au 1ᵉʳ janvier de [annee] : les à-nouveaux s'ils existent,
  /// sinon la clôture virtuelle de l'exercice précédent. Jamais de classe 6, 7 ni 8.
  Map<String, double> soldesOuverture(List<Ecriture> toutes, int annee) {
    final an = <String, double>{};
    var aDesANouveaux = false;
    for (final e in toutes) {
      if (e.exerciceAnnee == annee &&
          e.journalCode == JournauxDeCloture.reportANouveau) {
        aDesANouveaux = true;
        an[e.numeroCompte] = (an[e.numeroCompte] ?? 0) + e.debit - e.credit;
      }
    }
    if (aDesANouveaux) return _sansNuls(an);

    int? precedent;
    for (final e in toutes) {
      if (e.exerciceAnnee < annee &&
          (precedent == null || e.exerciceAnnee > precedent)) {
        precedent = e.exerciceAnnee;
      }
    }
    if (precedent == null) return {};
    return _clotureVirtuelle(toutes, precedent);
  }

  /// Soldes de fin de l'exercice [annee], clôture comprise, ouverture comprise : la base de
  /// la clôture virtuelle et des à-nouveaux. Les classes 1 à 5 sont conservées ; le solde
  /// résiduel des classes 6, 7 et 8 (exercice non clôturé) est porté au 121 ou 129.
  Map<String, double> _clotureVirtuelle(List<Ecriture> toutes, int annee) {
    final soldes = Map<String, double>.of(soldesOuverture(toutes, annee));
    for (final e in mouvementsDuLivre(toutes, annee)) {
      soldes[e.numeroCompte] =
          (soldes[e.numeroCompte] ?? 0) + e.debit - e.credit;
    }
    final bilan = <String, double>{};
    var residuGestion = 0.0;
    soldes.forEach((compte, net) {
      if (_estCompteDeGestion(compte)) {
        residuGestion += net;
      } else {
        bilan[compte] = net;
      }
    });
    residuGestion = centime(residuGestion);
    if (residuGestion.abs() >= tolerance) {
      // net débiteur (charges > produits) = perte → 129 ; net créditeur = bénéfice → 121.
      final cible = residuGestion > 0
          ? ComptesCloture.reportDebiteur
          : ComptesCloture.reportCrediteur;
      bilan[cible] = (bilan[cible] ?? 0) + residuGestion;
    }
    return _sansNuls(bilan);
  }

  static bool _estCompteDeGestion(String compte) =>
      compte.startsWith('6') ||
      compte.startsWith('7') ||
      compte.startsWith('8');

  Map<String, double> _sansNuls(Map<String, double> m) => {
    for (final e in m.entries)
      if (centime(e.value).abs() >= tolerance) e.key: centime(e.value),
  };

  /// Soldes de FIN de N pour les états : ouverture + mouvements courants (clôture exclue).
  SoldesComptes soldesDeFin(List<Ecriture> toutes, int annee) {
    final soldes = Map<String, double>.of(soldesOuverture(toutes, annee));
    for (final e in mouvementsCourants(toutes, annee)) {
      soldes[e.numeroCompte] =
          (soldes[e.numeroCompte] ?? 0) + e.debit - e.credit;
    }
    return SoldesComptes(soldes);
  }

  SoldesComptes soldesDOuverture(List<Ecriture> toutes, int annee) =>
      SoldesComptes(soldesOuverture(toutes, annee));

  // ---------------------------------------------------------------- clôture

  /// Calcule (sans rien écrire) les pièces que la clôture de [annee] produira.
  ///
  /// [toutes] : toutes les lignes du livre, tous exercices. La fonction est **pure** et
  /// **idempotente** : ses pièces ne dépendent pas des écritures de clôture déjà présentes
  /// (elles sont ignorées), donc recalculer après clôture redonne les mêmes pièces.
  ClotureCalculee calculer(
    List<Ecriture> toutes,
    int annee, {
    AffectationResultat affectation = AffectationResultat.aucune,
    Set<String> comptesConnus = const {},
  }) {
    final anomalies = <String>[];

    // Mouvements courants de N (hors clôture et à-nouveaux) : la base du résultat.
    final nets = <String, double>{};
    for (final e in mouvementsCourants(toutes, annee)) {
      nets[e.numeroCompte] = (nets[e.numeroCompte] ?? 0) + e.debit - e.credit;
    }

    // Équilibre du livre de N (BR-CPT-004) : sur les écritures courantes, ouverture
    // comprise (elle est équilibrée par construction).
    var ecart = 0.0;
    final ouverture = soldesOuverture(toutes, annee);
    for (final v in ouverture.values) {
      ecart += v;
    }
    for (final v in nets.values) {
      ecart += v;
    }
    if (centime(ecart).abs() >= tolerance) {
      anomalies.add(
        'Balance déséquilibrée de ${centime(ecart).abs().toStringAsFixed(0)} FCFA : '
        'la clôture est refusée (BR-CPT-004).',
      );
    }

    final gestion = <String>[
      for (final c in nets.keys)
        if (_estCompteDeGestion(c) && centime(nets[c]!).abs() >= tolerance) c,
    ]..sort();
    var resultat = 0.0;
    for (final c in gestion) {
      resultat -= nets[c]!;
    }
    resultat = centime(resultat);

    final reportDebiteurAnterieur = () {
      final net = ouverture[ComptesCloture.reportDebiteur] ?? 0;
      return net > 0 ? net : 0.0;
    }();
    final refus = affectation.valider(
      resultat,
      reportDebiteurAnterieur: reportDebiteurAnterieur,
    );
    if (refus != null) {
      // Affectation refusée : aucune pièce n'est proposée (elles ne s'équilibreraient pas).
      anomalies.add(refus);
      return ClotureCalculee(
        exercice: annee,
        resultat: resultat,
        pieces: const [],
        anomalies: anomalies,
      );
    }

    final dateCloture = DateTime(annee, 12, 31, 12);
    final dateOuverture = DateTime(annee + 1, 1, 1, 12);
    final pieces = <PieceCloture>[];

    // 1. Solde des comptes de gestion → compte 13.
    if (gestion.isNotEmpty) {
      final lignes = <LigneCloture>[
        for (final c in gestion)
          LigneCloture(
            numeroCompte: c,
            // Solde d'un compte débiteur (charge) : on le crédite ; créditeur : on le débite.
            debit: nets[c]! < 0 ? centime(-nets[c]!) : 0,
            credit: nets[c]! > 0 ? centime(nets[c]!) : 0,
            libelle: 'Solde du compte de gestion — Exercice $annee',
          ),
      ];
      if (resultat >= tolerance) {
        lignes.add(
          LigneCloture(
            numeroCompte: ComptesCloture.resultatBenefice,
            debit: 0,
            credit: resultat,
            libelle: 'Résultat net (bénéfice) de l\'exercice $annee',
          ),
        );
      } else if (resultat <= -tolerance) {
        lignes.add(
          LigneCloture(
            numeroCompte: ComptesCloture.resultatPerte,
            debit: -resultat,
            credit: 0,
            libelle: 'Résultat net (perte) de l\'exercice $annee',
          ),
        );
      }
      if (lignes.length >= 2) {
        pieces.add(
          PieceCloture(
            cle: 'cloture:$annee:resultat',
            numeroPiece: 'CL-$annee-RESULTAT',
            journalCode: JournauxDeCloture.cloture,
            date: dateCloture,
            exerciceAnnee: annee,
            lignes: lignes,
          ),
        );
      }
    }

    // 2. Affectation du résultat.
    if (resultat >= tolerance) {
      final lignes = <LigneCloture>[
        LigneCloture(
          numeroCompte: ComptesCloture.resultatBenefice,
          debit: resultat,
          credit: 0,
          libelle: 'Affectation du résultat $annee',
        ),
      ];
      void credit(String compte, double montant, String libelle) {
        if (montant < tolerance) return;
        lignes.add(
          LigneCloture(
            numeroCompte: compte,
            debit: 0,
            credit: centime(montant),
            libelle: libelle,
          ),
        );
      }

      credit(
        ComptesCloture.reserveLegale,
        affectation.reserveLegale,
        'Dotation à la réserve légale — résultat $annee',
      );
      credit(
        ComptesCloture.autresReserves,
        affectation.autresReserves,
        'Dotation aux autres réserves — résultat $annee',
      );
      credit(
        ComptesCloture.dividendesAPayer,
        affectation.dividendes,
        'Dividendes à payer — résultat $annee',
      );
      credit(
        ComptesCloture.reportCrediteur,
        centime(
          resultat -
              affectation.reserveLegale -
              affectation.autresReserves -
              affectation.dividendes,
        ),
        'Report à nouveau — résultat $annee',
      );
      pieces.add(
        PieceCloture(
          cle: 'cloture:$annee:affectation',
          numeroPiece: 'CL-$annee-AFFECTATION',
          journalCode: JournauxDeCloture.cloture,
          date: dateCloture,
          exerciceAnnee: annee,
          lignes: lignes,
        ),
      );
    } else if (resultat <= -tolerance) {
      pieces.add(
        PieceCloture(
          cle: 'cloture:$annee:affectation',
          numeroPiece: 'CL-$annee-AFFECTATION',
          journalCode: JournauxDeCloture.cloture,
          date: dateCloture,
          exerciceAnnee: annee,
          lignes: [
            LigneCloture(
              numeroCompte: ComptesCloture.reportDebiteur,
              debit: -resultat,
              credit: 0,
              libelle: 'Perte $annee portée en report à nouveau débiteur',
            ),
            LigneCloture(
              numeroCompte: ComptesCloture.resultatPerte,
              debit: 0,
              credit: -resultat,
              libelle: 'Affectation de la perte $annee',
            ),
          ],
        ),
      );
    }

    // Soldes après clôture : ouverture + mouvements courants + pièces de clôture. Les
    // classes 6, 7 et 8 y sont soldées, le 13 aussi (affecté) : seules restent les classes 1 à 5.
    final apres = Map<String, double>.of(ouverture);
    nets.forEach((c, v) => apres[c] = (apres[c] ?? 0) + v);
    for (final p in pieces) {
      for (final l in p.lignes) {
        apres[l.numeroCompte] =
            (apres[l.numeroCompte] ?? 0) + l.debit - l.credit;
      }
    }
    final reportes = <String, double>{};
    apres.forEach((c, v) {
      if (_estCompteDeGestion(c)) return;
      if (centime(v).abs() >= tolerance) reportes[c] = centime(v);
    });
    final comptesAn = reportes.keys.toList()..sort();
    final lignesAn = <LigneCloture>[
      for (final c in comptesAn)
        LigneCloture(
          numeroCompte: c,
          debit: reportes[c]! > 0 ? reportes[c]! : 0,
          credit: reportes[c]! < 0 ? -reportes[c]! : 0,
          libelle: 'À-nouveau — Exercice $annee',
        ),
    ];
    if (lignesAn.length >= 2) {
      final ecartAn = lignesAn.fold<double>(
        0,
        (s, l) => s + l.debit - l.credit,
      );
      if (centime(ecartAn).abs() >= tolerance) {
        anomalies.add(
          'Les à-nouveaux ne s\'équilibrent pas (écart ${centime(ecartAn)}) : '
          'clôture refusée.',
        );
      }
      pieces.add(
        PieceCloture(
          cle: 'an:${annee + 1}',
          numeroPiece: 'AN-${annee + 1}',
          journalCode: JournauxDeCloture.reportANouveau,
          date: dateOuverture,
          exerciceAnnee: annee + 1,
          lignes: lignesAn,
        ),
      );
    } else if (lignesAn.isNotEmpty) {
      anomalies.add('Les à-nouveaux ne peuvent pas être équilibrés.');
    }

    if (comptesConnus.isNotEmpty) {
      final manquants = <String>{
        for (final p in pieces)
          for (final l in p.lignes)
            if (!comptesConnus.contains(l.numeroCompte)) l.numeroCompte,
      };
      if (manquants.isNotEmpty) {
        anomalies.add(
          'Compte(s) absent(s) du plan comptable : ${(manquants.toList()..sort()).join(', ')}.',
        );
      }
    }

    return ClotureCalculee(
      exercice: annee,
      resultat: resultat,
      pieces: pieces,
      anomalies: anomalies,
    );
  }
}
