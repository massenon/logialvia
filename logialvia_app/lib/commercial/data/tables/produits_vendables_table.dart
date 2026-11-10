import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Table `PRODUITS_VENDABLES` — Doc D1 §2.
///
/// Contexte Commercial. Ne pas confondre avec `INTRANTS` (contexte
/// Approvisionnement) : Doc C1 §2 impose explicitement que ces deux notions de
/// « stock » restent deux entites distinctes, malgre leur ressemblance
/// structurelle.
@DataClassName('ProduitVendableRow')
class ProduitsVendables extends Table {
  /// UUID genere au poste (DV-19, `46_`) : un produit cree sur deux postes ne
  /// peut pas porter le meme entier. Les anciens produits recoivent le leur a la
  /// migration v33.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  /// ⚠️ AJOUTEE — colonne « SKU », 1ʳᵉ du tableau de `catalogue-produits.html`
  /// (l.126) et absente de Doc D1. Genere sous la forme 'PRD-001' faute de
  /// regle de codification documentee.
  TextColumn get sku => text().nullable()();

  TextColumn get name => text()();

  /// 'Avicole', 'Commerce Annexe', 'Cuniculture', 'Pisciculture'
  /// (valeurs reellement presentes dans `logialvia-store.js`, plus larges que
  /// les 2 valeurs listees par Doc D1 — voir note du seeder).
  TextColumn get cat => text()();

  RealColumn get price => real()();

  /// Prix haut de la fourchette de negociation, si le produit en a une.
  RealColumn get priceMax => real().nullable()();

  TextColumn get unit => text()();

  /// Nom d'icone Material Symbols, tel quel depuis le prototype.
  TextColumn get icon => text()();

  /// Coût de revient unitaire — ce que le produit a coûté, pas ce qu'il se
  /// vend.
  ///
  /// ⚠️ Le prototype ne le connaît pas et le confond avec le prix : sa colonne
  /// « CMUP » du Rapport de Stocks reprend **exactement** le prix de vente du
  /// catalogue (`price:6000` / `cmup:6000` pour le Goliath mature). Valoriser
  /// un stock à son prix de vente le surévalue et anticipe une marge non
  /// réalisée — un goliath encore dans l'enclos n'a pas rapporté 6 000 F.
  ///
  /// `null` = non renseigné. Le stock de ce produit n'est alors **pas
  /// valorisé** ; le prix de vente ne lui est jamais substitué.
  RealColumn get coutRevient => real().nullable()();

  /// Groupe de taxe de la grille MeCeF — la lettre imprimee en face de chaque
  /// ligne d'une facture normalisee.
  ///
  /// Defaut `'A'`, exonere : ALLMANY vend d'abord des produits d'elevage non
  /// transformes. Taxer par defaut aurait ete le pire choix -- une facture qui
  /// reclame une TVA non due engage l'entreprise, et personne ne verifie un
  /// champ qui parait deja rempli correctement.
  TextColumn get groupeTaxe => text().withDefault(const Constant('A'))();

  IntColumn get stock => integer()();
  IntColumn get threshold => integer()();

  /// Renseigne si le produit est un animal vivant issu d'une filiere.
  TextColumn get espece => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
