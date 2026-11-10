import 'package:flutter/foundation.dart';

import '../../data/repositories/comptabilite_repository_drift.dart';
import '../plan_syscohada.dart';

/// Clé de ventilation d'une vente : (compte de produit, centre analytique, taux de TVA en %).
///
/// Le montant associé est **TTC** (les prix du catalogue sont TTC) : la génération en extrait la TVA.
typedef CleVentilationVente = (String compte, String? centre, double taux);

/// Clé de ventilation d'un achat : (compte de charge, taux de TVA en %). Montant **TTC**.
typedef CleVentilationAchat = (String compte, double taux);

/// Génère les écritures comptables d'une vente et d'un achat — BR-CPT-003.
///
/// ## Schéma d'écriture d'une vente
///
/// Vente réglée comptant de 12 000 F (produits avicoles) :
/// ```
/// 571 Caisse                    D 12 000
/// 702 Ventes de produits finis          C 12 000
/// ```
///
/// Vente à crédit (statut « Avance ») de 12 000 F dont 3 500 F encaissés :
/// ```
/// 571 Caisse                    D  3 500
/// 411 Clients                   D  8 500
/// 702 Ventes de produits finis          C 12 000
/// ```
///
/// Produit **taxable à 18 %** de 11 800 F TTC (TVA arrondie au franc) :
/// ```
/// 571 Caisse                    D 11 800
/// 701 Ventes de marchandises            C 10 000
/// 4431 TVA facturée sur ventes          C  1 800
/// ```
///
/// La ventilation entre 702 (produits des filières) et 701 (marchandises du commerce annexe) suit
/// la catégorie du produit vendu — c'est la même distinction que celle du KPI
/// « Avicole / Commerce annexe » du tableau de bord (Doc F2). Plan : `PlanSyscohada` (`47p_`).
class GenererEcrituresAutomatiques {
  const GenererEcrituresAutomatiques(this._repository);

  final ComptabiliteRepository _repository;

  /// Part de TVA de chaque entrée de [ventilation] (TTC) ; HT et TVA de la livraison facturée.
  static ({double ht, double tva}) _scinder(double ttc, double taux) {
    final tva = PlanSyscohada.tvaDuTtc(ttc, taux);
    return (ht: ttc - tva, tva: tva);
  }

  /// [ventilation] : montant **TTC** par (compte de produit, centre, taux de TVA) ;
  /// [tauxLivraison] : taux de TVA des frais de livraison facturés (TTC comme le reste).
  Future<void> pourVente({
    required String reference,
    required DateTime date,
    required String mode,
    required String statut,
    required double total,
    required double paye,
    required Map<CleVentilationVente, double> ventilation,
    double fraisLivraison = 0,
    double tauxLivraison = 0,
  }) async {
    if (total <= 0) return;

    final lignes = <LigneAEcrire>[];
    final resteDu = (total - paye).clamp(0.0, total);

    if (paye > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: PlanSyscohada.tresoreriePour(mode),
          debit: paye,
          credit: 0,
          libelle: 'Encaissement vente $reference',
        ),
      );
    }
    if (resteDu > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: PlanSyscohada.clients,
          debit: resteDu,
          credit: 0,
          libelle: 'Créance client — vente $reference',
        ),
      );
    }

    // Produits HT, centre par centre ; la TVA collectée est UNE ligne par nature (biens 4431,
    // prestations 4432) : le résultat ne contient plus de TVA.
    var tvaBiens = 0.0;
    ventilation.forEach((cle, montant) {
      if (montant <= 0) return;
      final (compte, centre, taux) = cle;
      final part = _scinder(montant, taux);
      tvaBiens += part.tva;
      lignes.add(
        LigneAEcrire(
          numeroCompte: compte,
          debit: 0,
          credit: part.ht,
          libelle: centre == null
              ? 'Vente $reference'
              : 'Vente $reference — $centre',
          axeAnalytique: centre,
        ),
      );
    });
    if (tvaBiens > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: PlanSyscohada.tvaCollectee,
          debit: 0,
          credit: tvaBiens,
          libelle: 'TVA collectée — vente $reference',
        ),
      );
    }

    // Les frais d'une livraison facturée sont DANS le total : sans cette ligne la
    // pièce serait déséquilibrée de leur montant (le serveur la refuserait).
    if (fraisLivraison > 0) {
      final part = _scinder(fraisLivraison, tauxLivraison);
      lignes.add(
        LigneAEcrire(
          numeroCompte: PlanSyscohada.fraisLivraison,
          debit: 0,
          credit: part.ht,
          libelle: 'Frais de livraison facturés — vente $reference',
        ),
      );
      if (part.tva > 0) {
        lignes.add(
          LigneAEcrire(
            numeroCompte: PlanSyscohada.tvaCollecteeServices,
            debit: 0,
            credit: part.tva,
            libelle: 'TVA collectée sur livraison — vente $reference',
          ),
        );
      }
    }

    await _enregistrer(
      date: date,
      journalCode: 'VT',
      numeroPiece: reference,
      lignes: lignes,
      venteRef: reference,
    );
  }

  /// Contrepassation d'une vente annulée.
  ///
  /// **Une écriture n'est jamais supprimée** — on enregistre l'écriture
  /// inverse. C'est la règle comptable de base : un journal ne se réécrit pas,
  /// il s'annule par contrepassation.
  Future<void> pourAnnulationVente({
    required String reference,
    required DateTime date,
    required String mode,
    required double total,
    required double paye,
    required Map<CleVentilationVente, double> ventilation,
    double fraisLivraison = 0,
    double tauxLivraison = 0,
  }) async {
    if (total <= 0) return;

    final lignes = <LigneAEcrire>[];
    final resteDu = (total - paye).clamp(0.0, total);

    if (paye > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: PlanSyscohada.tresoreriePour(mode),
          debit: 0,
          credit: paye,
          libelle: 'Annulation vente $reference',
        ),
      );
    }
    if (resteDu > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: PlanSyscohada.clients,
          debit: 0,
          credit: resteDu,
          libelle: 'Annulation créance — vente $reference',
        ),
      );
    }

    var tvaBiens = 0.0;
    ventilation.forEach((cle, montant) {
      if (montant <= 0) return;
      final (compte, centre, taux) = cle;
      final part = _scinder(montant, taux);
      tvaBiens += part.tva;
      lignes.add(
        LigneAEcrire(
          numeroCompte: compte,
          debit: part.ht,
          credit: 0,
          libelle: 'Annulation vente $reference',
          // La contrepassation porte le MEME centre que l'ecriture d'origine :
          // annuler une vente de goliaths ne doit pas retirer du revenu a une
          // autre filiere.
          axeAnalytique: centre,
        ),
      );
    });
    if (tvaBiens > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: PlanSyscohada.tvaCollectee,
          debit: tvaBiens,
          credit: 0,
          libelle: 'Annulation TVA collectée — vente $reference',
        ),
      );
    }

    if (fraisLivraison > 0) {
      final part = _scinder(fraisLivraison, tauxLivraison);
      lignes.add(
        LigneAEcrire(
          numeroCompte: PlanSyscohada.fraisLivraison,
          debit: part.ht,
          credit: 0,
          libelle: 'Annulation frais de livraison — vente $reference',
        ),
      );
      if (part.tva > 0) {
        lignes.add(
          LigneAEcrire(
            numeroCompte: PlanSyscohada.tvaCollecteeServices,
            debit: part.tva,
            credit: 0,
            libelle: 'Annulation TVA sur livraison — vente $reference',
          ),
        );
      }
    }

    await _enregistrer(
      date: date,
      journalCode: 'OD',
      numeroPiece: 'ANN-$reference',
      lignes: lignes,
      venteRef: reference,
    );
  }

  /// Achat d'intrants — Doc F5 : « Débit Achats / Crédit Fournisseur ou Caisse
  /// selon le mode de règlement » (BR-CPT-003).
  ///
  /// ```
  /// 602 Achats de matières        D 30 000
  /// 571 Caisse                            C 10 000
  /// 401 Fournisseurs                      C 20 000
  /// ```
  Future<void> pourAchat({
    required String reference,
    required DateTime date,
    required String mode,
    required double total,
    required double paye,
    required Map<CleVentilationAchat, double> ventilation,
  }) async {
    if (total <= 0) return;

    final lignes = <LigneAEcrire>[];

    // Charges HT au débit, TVA déductible (4452) au débit : le résultat ne contient plus la TVA
    // récupérable. Un achat exonéré (taux 0) reste intégralement en charge.
    var tvaDeductible = 0.0;
    ventilation.forEach((cle, montant) {
      if (montant <= 0) return;
      final (compte, taux) = cle;
      final part = _scinder(montant, taux);
      tvaDeductible += part.tva;
      lignes.add(
        LigneAEcrire(
          numeroCompte: compte,
          debit: part.ht,
          credit: 0,
          libelle: 'Achat $reference',
        ),
      );
    });
    if (tvaDeductible > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: PlanSyscohada.tvaDeductible,
          debit: tvaDeductible,
          credit: 0,
          libelle: 'TVA déductible — achat $reference',
        ),
      );
    }

    final resteDu = (total - paye).clamp(0.0, total);
    if (paye > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: PlanSyscohada.tresoreriePour(mode),
          debit: 0,
          credit: paye,
          libelle: 'Règlement achat $reference',
        ),
      );
    }
    if (resteDu > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: PlanSyscohada.fournisseurs,
          debit: 0,
          credit: resteDu,
          libelle: 'Dette fournisseur — achat $reference',
        ),
      );
    }

    await _enregistrer(
      date: date,
      journalCode: 'AC',
      numeroPiece: reference,
      lignes: lignes,
      achatRef: reference,
    );
  }

  /// Règlement d'une créance ou d'une dette.
  Future<void> pourReglement({
    required String reference,
    required DateTime date,
    required String mode,
    required double montant,
    required bool estEncaissement,
  }) async {
    if (montant <= 0) return;

    final tresorerie = PlanSyscohada.tresoreriePour(mode);
    final tiers = estEncaissement
        ? PlanSyscohada.clients
        : PlanSyscohada.fournisseurs;

    await _enregistrer(
      date: date,
      journalCode: 'CA',
      numeroPiece: 'REG-$reference',
      lignes: [
        LigneAEcrire(
          numeroCompte: estEncaissement ? tresorerie : tiers,
          debit: montant,
          credit: 0,
          libelle: estEncaissement
              ? 'Encaissement créance $reference'
              : 'Règlement dette $reference',
        ),
        LigneAEcrire(
          numeroCompte: estEncaissement ? tiers : tresorerie,
          debit: 0,
          credit: montant,
          libelle: estEncaissement
              ? 'Encaissement créance $reference'
              : 'Règlement dette $reference',
        ),
      ],
      venteRef: estEncaissement ? reference : null,
      achatRef: estEncaissement ? null : reference,
    );
  }

  /// La génération automatique **ne doit jamais faire échouer l'opération
  /// métier**. Si le mois ou l'exercice est clôturé, la vente reste valide —
  /// c'est son écriture comptable qui ne peut pas être passée, et l'anomalie
  /// est signalée en développement plutôt que de bloquer une caissière.
  Future<void> _enregistrer({
    required DateTime date,
    required String journalCode,
    required String numeroPiece,
    required List<LigneAEcrire> lignes,
    String? venteRef,
    String? achatRef,
  }) async {
    if (lignes.isEmpty) return;
    try {
      await _repository.enregistrerPiece(
        date: date,
        journalCode: journalCode,
        numeroPiece: numeroPiece,
        lignes: lignes,
        venteRef: venteRef,
        achatRef: achatRef,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Ecriture automatique non passee ($numeroPiece) : $e');
      }
    }
  }
}
