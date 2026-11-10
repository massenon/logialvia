import 'package:drift/drift.dart';

import '../../administration/data/repositories/preferences_poste_repository.dart';
import '../../approvisionnement/domain/services/calcul_pmp.dart';
import '../database/app_database.dart';
import 'identifiant_poste.dart';

/// Une ligne de réception / d'annulation de réception à appliquer au stock d'intrants.
class LigneEffetIntrant {
  const LigneEffetIntrant({
    required this.code,
    required this.nom,
    required this.quantite,
    required this.prixUnitaire,
  });

  final String code;
  final String nom;
  final double quantite;
  final double prixUnitaire;
}

/// Une ligne de vente / d'annulation de vente à appliquer au stock de produits.
class LigneEffetProduit {
  const LigneEffetProduit({
    required this.produitId,
    required this.nom,
    required this.quantite,
  });

  final String produitId;
  final String nom;
  final double quantite;
}

/// Applique au stock de **CE poste** l'effet d'une opération saisie au web qui le désigne
/// (`docs/logialvia/47s_STOCK_CIBLE.md`) — l'**exception documentée** à la règle d'or
/// « absorber le fait d'un autre poste n'a aucun effet local ».
///
/// ## Garanties
/// - **Une seule fois** : chaque effet est identifié par (fait, nature) ; la table
///   `effets_appliques` est consultée avant toute écriture et sa clé est unique. Un rejeu,
///   un tirage complet, « renvoyer vers ce poste » ne produisent jamais un second effet.
/// - **Atomique** : à appeler dans la transaction de l'absorbeur ; effet et trace
///   s'écrivent ensemble ou pas du tout.
/// - **Aucun stock négatif silencieux** : plancher à 0 (comme `_decrementerStock` du poste)
///   ET avertissement tracé (« Stock insuffisant au poste P2 : … »), visible au poste et
///   au web (la trace est synchronisée).
/// - **Local** : ni écriture dans le journal partagé (les mouvements du web y sont déjà),
///   ni mouvement de stock vers un autre poste.
class EffetsStockPoste {
  EffetsStockPoste(this._db);

  final AppDatabase _db;

  static const String faitAchat = 'achat';
  static const String faitVente = 'vente';
  static const String faitCorrection = 'mouvement_produit';

  static const String reception = 'reception';
  static const String annulationReception = 'annulation_reception';
  static const String vente = 'vente';
  static const String annulationVente = 'annulation_vente';
  static const String correction = 'correction';

  static const String etatApplique = 'applique';
  static const String etatAvertissement = 'avertissement';
  static const String etatIgnore = 'ignore';

  /// Identifiant déterministe de l'effet (`fait`, `nature`) : le même sur tous les postes.
  static String idEffet(String faitId, String nature) =>
      uuidDeterministe('effet:$nature:$faitId');

  Future<String> identifiantLocal() =>
      PreferencesPosteRepository(_db).identifiantPoste();

  /// Ce poste est-il celui que désigne [posteCible] ?
  Future<bool> estCible(String? posteCible) async =>
      posteCible != null && posteCible == await identifiantLocal();

  /// Libellé du poste pour les messages (`P2`, sinon « ce poste »).
  Future<String> _nomPoste() async =>
      await PreferencesPosteRepository(_db).codePoste() ?? 'ce poste';

  /// L'effet de ce (fait, nature), **produit par ce poste**, s'il existe.
  Future<EffetAppliqueRow?> effet(String faitId, String nature) =>
      (_db.select(_db.effetsAppliques)
            ..where((e) => e.faitId.equals(faitId) & e.nature.equals(nature)))
          .getSingleOrNull();

  Future<bool> dejaApplique(String faitId, String nature) async =>
      await effet(faitId, nature) != null;

  /// Vrai si l'effet existe ET a réellement touché le stock (pas `ignore`).
  Future<bool> aToucheLeStock(String faitId, String nature) async {
    final e = await effet(faitId, nature);
    return e != null && e.etat != etatIgnore;
  }

  Future<void> _tracer({
    required String faitType,
    required String faitId,
    required String nature,
    required String? reference,
    required String libelle,
    required List<String> avertissements,
    bool ignore = false,
  }) async {
    await _db
        .into(_db.effetsAppliques)
        .insert(
          EffetsAppliquesCompanion.insert(
            id: idEffet(faitId, nature),
            faitType: faitType,
            faitId: faitId,
            nature: nature,
            reference: Value(reference),
            libelle: libelle,
            etat: ignore
                ? etatIgnore
                : avertissements.isEmpty
                ? etatApplique
                : etatAvertissement,
            avertissement: Value(
              avertissements.isEmpty ? null : avertissements.join(' ; '),
            ),
            appliqueLe: Value(instantSaisie()),
          ),
        );
  }

  /// Enregistre que l'effet n'a PAS été appliqué (et pourquoi), une fois : le web voit
  /// « non appliqué » au lieu d'attendre indéfiniment.
  Future<void> ignorer({
    required String faitType,
    required String faitId,
    required String nature,
    required String? reference,
    required String motif,
  }) async {
    if (await dejaApplique(faitId, nature)) return;
    await _tracer(
      faitType: faitType,
      faitId: faitId,
      nature: nature,
      reference: reference,
      libelle: 'Non appliqué : $motif',
      avertissements: [motif],
      ignore: true,
    );
  }

  // ------------------------------------------------------------------ achats

  /// Réception d'une commande saisie au web : **entrée** des quantités et **PMP recalculé**
  /// (`CalculPmp`, la formule du poste). `false` si l'effet existait déjà.
  Future<bool> appliquerReception({
    required String achatId,
    required String reference,
    required List<LigneEffetIntrant> lignes,
  }) async {
    if (await dejaApplique(achatId, reception)) return false;
    final details = <String>[];
    final avertissements = <String>[];
    for (final l in lignes) {
      final intrant = await (_db.select(
        _db.intrants,
      )..where((i) => i.code.equals(l.code))).getSingleOrNull();
      if (intrant == null) {
        avertissements.add(
          'Intrant inconnu « ${l.nom} » : ligne non appliquée',
        );
        continue;
      }
      final quantite = l.quantite.round();
      final stock = intrant.stock + quantite;
      final pmp = CalculPmp.apresReception(
        stock: intrant.stock,
        pmp: intrant.pmp,
        quantite: quantite,
        prixUnitaire: l.prixUnitaire,
      );
      await (_db.update(_db.intrants)..where((i) => i.code.equals(l.code)))
          .write(IntrantsCompanion(stock: Value(stock), pmp: Value(pmp)));
      details.add(
        '${l.nom} +$quantite (stock $stock, PMP ${intrant.pmp} → $pmp)',
      );
    }
    await _tracer(
      faitType: faitAchat,
      faitId: achatId,
      nature: reception,
      reference: reference,
      libelle: 'Réception $reference reçue du web : ${details.join(' ; ')}',
      avertissements: avertissements,
    );
    return true;
  }

  /// Annulation d'une commande **déjà appliquée** à ce poste : **sortie** inverse, plancher
  /// à 0 avec avertissement, PMP rendu par l'inverse de la formule (`CalculPmp.apresRetrait`).
  /// Sans réception appliquée ici, rien n'est fait (rien n'était entré).
  Future<bool> annulerReception({
    required String achatId,
    required String reference,
    required List<LigneEffetIntrant> lignes,
  }) async {
    if (await dejaApplique(achatId, annulationReception)) return false;
    if (!await aToucheLeStock(achatId, reception)) return false;
    final poste = await _nomPoste();
    final details = <String>[];
    final avertissements = <String>[];
    for (final l in lignes) {
      final intrant = await (_db.select(
        _db.intrants,
      )..where((i) => i.code.equals(l.code))).getSingleOrNull();
      if (intrant == null) {
        avertissements.add(
          'Intrant inconnu « ${l.nom} » : ligne non appliquée',
        );
        continue;
      }
      final quantite = l.quantite.round();
      final stock = intrant.stock - quantite < 0 ? 0 : intrant.stock - quantite;
      if (intrant.stock < quantite) {
        avertissements.add(
          'Stock insuffisant au poste $poste : « ${l.nom} » — $quantite à '
          'retirer, ${intrant.stock} disponibles ; stock ramené à 0',
        );
      }
      final pmp = CalculPmp.apresRetrait(
        stock: intrant.stock,
        pmp: intrant.pmp,
        quantite: quantite,
        prixUnitaire: l.prixUnitaire,
      );
      await (_db.update(_db.intrants)..where((i) => i.code.equals(l.code)))
          .write(IntrantsCompanion(stock: Value(stock), pmp: Value(pmp)));
      details.add(
        '${l.nom} −$quantite (stock $stock, PMP ${intrant.pmp} → $pmp)',
      );
    }
    await _tracer(
      faitType: faitAchat,
      faitId: achatId,
      nature: annulationReception,
      reference: reference,
      libelle: 'Annulation $reference reçue du web : ${details.join(' ; ')}',
      avertissements: avertissements,
    );
    return true;
  }

  // ------------------------------------------------------------------ ventes

  /// Vente saisie au web : **décrément** du stock des produits, borné à 0
  /// (`_decrementerStock` du poste) avec avertissement si le stock manquait.
  Future<bool> appliquerVente({
    required String venteId,
    required String reference,
    required List<LigneEffetProduit> lignes,
  }) async {
    if (await dejaApplique(venteId, vente)) return false;
    final poste = await _nomPoste();
    final details = <String>[];
    final avertissements = <String>[];
    for (final l in lignes) {
      final produit = await (_db.select(
        _db.produitsVendables,
      )..where((p) => p.id.equals(l.produitId))).getSingleOrNull();
      if (produit == null) {
        avertissements.add(
          'Produit inconnu « ${l.nom} » : ligne non appliquée',
        );
        continue;
      }
      final quantite = l.quantite.round();
      final stock = (produit.stock - quantite).clamp(0, 1 << 30);
      if (produit.stock < quantite) {
        avertissements.add(
          'Stock insuffisant au poste $poste : « ${l.nom} » — $quantite '
          'demandés, ${produit.stock} disponibles ; stock ramené à 0',
        );
      }
      await (_db.update(_db.produitsVendables)
            ..where((p) => p.id.equals(l.produitId)))
          .write(ProduitsVendablesCompanion(stock: Value(stock)));
      details.add('${l.nom} −$quantite (stock $stock)');
    }
    await _tracer(
      faitType: faitVente,
      faitId: venteId,
      nature: vente,
      reference: reference,
      libelle: 'Vente $reference reçue du web : ${details.join(' ; ')}',
      avertissements: avertissements,
    );
    return true;
  }

  /// Annulation d'une vente **déjà appliquée** à ce poste : **réintégration** des quantités
  /// (`_incrementerStock` du poste : sans plafond).
  Future<bool> annulerVente({
    required String venteId,
    required String reference,
    required List<LigneEffetProduit> lignes,
  }) async {
    if (await dejaApplique(venteId, annulationVente)) return false;
    if (!await aToucheLeStock(venteId, vente)) return false;
    final details = <String>[];
    final avertissements = <String>[];
    for (final l in lignes) {
      final produit = await (_db.select(
        _db.produitsVendables,
      )..where((p) => p.id.equals(l.produitId))).getSingleOrNull();
      if (produit == null) {
        avertissements.add(
          'Produit inconnu « ${l.nom} » : ligne non appliquée',
        );
        continue;
      }
      final quantite = l.quantite.round();
      final stock = produit.stock + quantite;
      await (_db.update(_db.produitsVendables)
            ..where((p) => p.id.equals(l.produitId)))
          .write(ProduitsVendablesCompanion(stock: Value(stock)));
      details.add('${l.nom} +$quantite (stock $stock)');
    }
    await _tracer(
      faitType: faitVente,
      faitId: venteId,
      nature: annulationVente,
      reference: reference,
      libelle: 'Annulation $reference reçue du web : ${details.join(' ; ')}',
      avertissements: avertissements,
    );
    return true;
  }

  // ------------------------------------------------------------ corrections

  /// Correction de stock d'un produit saisie au web : variation **signée** ajoutée au stock
  /// de ce poste, plancher à 0 avec avertissement.
  Future<bool> appliquerCorrection({
    required String mouvementId,
    required String produitId,
    required String article,
    required String motif,
    required double variation,
  }) async {
    if (await dejaApplique(mouvementId, correction)) return false;
    final poste = await _nomPoste();
    final produit = await (_db.select(
      _db.produitsVendables,
    )..where((p) => p.id.equals(produitId))).getSingleOrNull();
    if (produit == null) {
      await ignorer(
        faitType: faitCorrection,
        faitId: mouvementId,
        nature: correction,
        reference: null,
        motif: 'Produit inconnu « $article » : correction non appliquée',
      );
      return false;
    }
    final delta = variation.round();
    final brut = produit.stock + delta;
    final stock = brut < 0 ? 0 : brut;
    await (_db.update(_db.produitsVendables)
          ..where((p) => p.id.equals(produitId)))
        .write(ProduitsVendablesCompanion(stock: Value(stock)));
    await _tracer(
      faitType: faitCorrection,
      faitId: mouvementId,
      nature: correction,
      reference: null,
      libelle:
          'Correction reçue du web : $article ${delta >= 0 ? '+' : '−'}${delta.abs()} '
          '(stock $stock) — $motif',
      avertissements: brut < 0
          ? [
              'Stock insuffisant au poste $poste : « $article » — ${delta.abs()} à '
                  'retirer, ${produit.stock} disponibles ; stock ramené à 0',
            ]
          : const [],
    );
    return true;
  }
}
