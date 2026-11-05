import 'package:drift/drift.dart';

import 'produits_vendables_table.dart';
import 'ventes_table.dart';

/// Table `LIGNES_VENTE` — Doc D1 §2.
@DataClassName('LigneVenteRow')
class LignesVente extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get venteRef =>
      text().references(Ventes, #ref, onDelete: KeyAction.cascade)();

  IntColumn get produitId => integer().references(ProduitsVendables, #id)();

  /// Nom du produit **au moment de la vente** — denormalise volontairement,
  /// pour que l'historique reste fidele si le produit est renomme plus tard.
  TextColumn get name => text()();

  RealColumn get qte => real()();
  RealColumn get pu => real()();

  /// Espece concernee si le produit est un animal (declenche BR-ELV-010).
  TextColumn get espece => text().nullable()();
}
