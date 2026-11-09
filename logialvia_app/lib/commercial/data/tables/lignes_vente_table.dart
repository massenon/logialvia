import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

import 'produits_vendables_table.dart';
import 'ventes_table.dart';

/// Table `LIGNES_VENTE` — Doc D1 §2.
@DataClassName('LigneVenteRow')
class LignesVente extends Table {
  /// UUID (DV-19) : une ligne de vente est un fait synchronise.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  TextColumn get venteRef =>
      text().references(Ventes, #ref, onDelete: KeyAction.cascade)();

  TextColumn get produitId => text().references(ProduitsVendables, #id)();

  /// Nom du produit **au moment de la vente** — denormalise volontairement,
  /// pour que l'historique reste fidele si le produit est renomme plus tard.
  TextColumn get name => text()();

  RealColumn get qte => real()();
  RealColumn get pu => real()();

  /// Espece concernee si le produit est un animal (declenche BR-ELV-010).
  TextColumn get espece => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
