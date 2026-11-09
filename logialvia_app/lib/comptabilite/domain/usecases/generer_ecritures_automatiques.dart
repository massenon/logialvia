import 'package:flutter/foundation.dart';

import '../../data/repositories/comptabilite_repository_drift.dart';

/// Comptes utilisés par la génération automatique — **BR-CPT-003**.
///
/// Ils font tous partie du plan comptable réel de `plan-comptable.html`, à
/// l'exception d'aucun : la génération n'invente aucun compte.
class ComptesAutomatiques {
  ComptesAutomatiques._();

  static const String caisse = '531';
  static const String mobileMoney = '512';
  static const String clients = '411';
  static const String clientsAvances = '419';
  static const String fournisseurs = '401';

  static const String ventesAvicoles = '701';
  static const String ventesMarchandises = '707';

  /// Frais de livraison **facturés séparément** : un produit accessoire de la
  /// vente, crédité sans centre analytique (il n'appartient à aucune filière).
  /// Le plan ne compte que 701 et 707 ; la génération n'invente aucun compte.
  static const String fraisLivraison = '707';

  static const String achatsMatieres = '601';
  static const String achatsMarchandises = '602';
  static const String fraisVeterinaires = '622';

  /// Compte de trésorerie correspondant au mode de règlement.
  static String tresoreriePour(String mode) =>
      mode == 'Mobile Money' ? mobileMoney : caisse;
}

/// Génère les écritures comptables d'une vente et d'un achat — BR-CPT-003.
///
/// ## Schéma d'écriture d'une vente
///
/// Vente réglée comptant de 12 000 F (produits avicoles) :
/// ```
/// 531 Caisse                    D 12 000
/// 701 Ventes Produits Avicoles          C 12 000
/// ```
///
/// Vente à crédit (statut « Avance ») de 12 000 F dont 3 500 F encaissés :
/// ```
/// 531 Caisse                    D  3 500
/// 411 Clients                   D  8 500
/// 701 Ventes Produits Avicoles          C 12 000
/// ```
///
/// La ventilation entre 701 (avicole) et 707 (commerce annexe) suit la
/// catégorie du produit vendu — c'est la même distinction que celle du KPI
/// « Avicole / Commerce annexe » du tableau de bord (Doc F2).
class GenererEcrituresAutomatiques {
  const GenererEcrituresAutomatiques(this._repository);

  final ComptabiliteRepository _repository;

  /// [ventilation] : montant par compte de produit (701 / 707).
  Future<void> pourVente({
    required String reference,
    required DateTime date,
    required String mode,
    required String statut,
    required double total,
    required double paye,
    required Map<(String, String?), double> ventilation,
    double fraisLivraison = 0,
  }) async {
    if (total <= 0) return;

    final lignes = <LigneAEcrire>[];
    final resteDu = (total - paye).clamp(0.0, total);

    if (paye > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: ComptesAutomatiques.tresoreriePour(mode),
          debit: paye,
          credit: 0,
          libelle: 'Encaissement vente $reference',
        ),
      );
    }
    if (resteDu > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: ComptesAutomatiques.clients,
          debit: resteDu,
          credit: 0,
          libelle: 'Créance client — vente $reference',
        ),
      );
    }

    ventilation.forEach((cle, montant) {
      if (montant <= 0) return;
      final (compte, centre) = cle;
      lignes.add(
        LigneAEcrire(
          numeroCompte: compte,
          debit: 0,
          credit: montant,
          libelle: centre == null
              ? 'Vente $reference'
              : 'Vente $reference — $centre',
          axeAnalytique: centre,
        ),
      );
    });

    // Les frais d'une livraison facturée sont DANS le total : sans cette ligne la
    // pièce serait déséquilibrée de leur montant (le serveur la refuserait).
    if (fraisLivraison > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: ComptesAutomatiques.fraisLivraison,
          debit: 0,
          credit: fraisLivraison,
          libelle: 'Frais de livraison facturés — vente $reference',
        ),
      );
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
    required Map<(String, String?), double> ventilation,
    double fraisLivraison = 0,
  }) async {
    if (total <= 0) return;

    final lignes = <LigneAEcrire>[];
    final resteDu = (total - paye).clamp(0.0, total);

    if (paye > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: ComptesAutomatiques.tresoreriePour(mode),
          debit: 0,
          credit: paye,
          libelle: 'Annulation vente $reference',
        ),
      );
    }
    if (resteDu > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: ComptesAutomatiques.clients,
          debit: 0,
          credit: resteDu,
          libelle: 'Annulation créance — vente $reference',
        ),
      );
    }

    ventilation.forEach((cle, montant) {
      if (montant <= 0) return;
      final (compte, centre) = cle;
      lignes.add(
        LigneAEcrire(
          numeroCompte: compte,
          debit: montant,
          credit: 0,
          libelle: 'Annulation vente $reference',
          // La contrepassation porte le MEME centre que l'ecriture d'origine :
          // annuler une vente de goliaths ne doit pas retirer du revenu a une
          // autre filiere.
          axeAnalytique: centre,
        ),
      );
    });

    if (fraisLivraison > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: ComptesAutomatiques.fraisLivraison,
          debit: fraisLivraison,
          credit: 0,
          libelle: 'Annulation frais de livraison — vente $reference',
        ),
      );
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
  /// 601 Achats de Matières        D 30 000
  /// 531 Caisse                            C 10 000
  /// 401 Fournisseurs                      C 20 000
  /// ```
  Future<void> pourAchat({
    required String reference,
    required DateTime date,
    required String mode,
    required double total,
    required double paye,
    required Map<String, double> ventilation,
  }) async {
    if (total <= 0) return;

    final lignes = <LigneAEcrire>[];

    ventilation.forEach((compte, montant) {
      if (montant <= 0) return;
      lignes.add(
        LigneAEcrire(
          numeroCompte: compte,
          debit: montant,
          credit: 0,
          libelle: 'Achat $reference',
        ),
      );
    });

    final resteDu = (total - paye).clamp(0.0, total);
    if (paye > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: ComptesAutomatiques.tresoreriePour(mode),
          debit: 0,
          credit: paye,
          libelle: 'Règlement achat $reference',
        ),
      );
    }
    if (resteDu > 0) {
      lignes.add(
        LigneAEcrire(
          numeroCompte: ComptesAutomatiques.fournisseurs,
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

    final tresorerie = ComptesAutomatiques.tresoreriePour(mode);
    final tiers = estEncaissement
        ? ComptesAutomatiques.clients
        : ComptesAutomatiques.fournisseurs;

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
