import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';
import 'produits_vendables_table.dart';

/// Table `MOUVEMENTS_PRODUIT` — journal des **corrections de stock** d'un produit
/// vendable (palier 6).
///
/// Les ventes et leurs annulations voyagent déjà avec leurs lignes (`ventes`) : elles
/// ne sont pas recopiées ici. Seule la correction manuelle du catalogue, qui n'avait
/// aucune trace, est journalisée. Un fait **immuable**, jamais appliqué à un stock :
/// décision du client « stock propre à chaque poste + journal partagé ».
@DataClassName('MouvementProduitRow')
class MouvementsProduit extends Table {
  TextColumn get id => text().clientDefault(nouvelUuid)();

  DateTimeColumn get horodatage => dateTime()();

  TextColumn get produitId => text().references(ProduitsVendables, #id)();

  /// Nom du produit au moment de la correction (l'historique reste lisible).
  TextColumn get article => text()();

  TextColumn get motif => text()();

  /// Variation SIGNÉE du stock de CE poste ; jamais nulle.
  RealColumn get quantite => real()();

  /// `null` = CE poste ; sinon l'identifiant du poste d'origine (historique pur).
  TextColumn get origine => text().nullable()();


  /// Poste de stock désigné par une opération saisie au web (`47s_`) : l'identifiant du
  /// poste dont le stock (et le PMP) subit l'effet. `null` = aucun. Sur une
  /// correction saisie au web, le poste désigné applique la variation à SON stock (une fois). Posé à la création, **immuable** ensuite (le fait est lié à ce poste).
  TextColumn get posteCible => text().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get syncMotif => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
