import 'package:drift/drift.dart';

import 'identifiant_poste.dart';

/// Table `EFFETS_APPLIQUES` — journal des **effets de stock appliqués à CE poste** parce
/// qu'une opération saisie au web le désignait (`docs/logialvia/47s_STOCK_CIBLE.md`).
///
/// Elle sert à deux choses :
/// 1. l'**idempotence** : un effet est identifié par (fait, nature) ; l'identifiant est
///    déterministe, la clé (`fait_id`, `nature`) est unique. Rejeu, tirage complet ou
///    « renvoyer vers ce poste » n'appliquent jamais deux fois le même effet ;
/// 2. la **trace** visible au poste (journal, badge, avertissement) et au web : elle part
///    au serveur (`effets_stock`), qui la redistribue aux autres postes comme historique.
///
/// Un effet est un fait **immuable**. Un effet d'un autre poste (`origine` non nulle) est
/// de l'historique : il n'entre dans aucun calcul d'idempotence de ce poste.
@DataClassName('EffetAppliqueRow')
class EffetsAppliques extends Table {
  /// UUID v5 de `effet:<nature>:<fait_id>`.
  TextColumn get id => text()();

  /// `achat` · `vente` · `mouvement_produit`.
  TextColumn get faitType => text()();

  /// Identifiant (UUID) du fait web qui a produit l'effet.
  TextColumn get faitId => text()();

  /// `reception` · `annulation_reception` · `vente` · `annulation_vente` · `correction`.
  TextColumn get nature => text()();

  /// Référence lisible du fait (`ACH-WEB-2026-001`, `V-WEB-2026-004`), si elle existe.
  TextColumn get reference => text().nullable()();

  /// Résumé en français de ce qui a été fait au stock.
  TextColumn get libelle => text()();

  /// `applique` · `avertissement` (appliqué avec plancher à 0) · `ignore` (non appliqué).
  TextColumn get etat => text()();

  /// Motif de l'avertissement ou de l'abstention (« Stock insuffisant au poste… »).
  TextColumn get avertissement => text().nullable()();

  /// Instant (UTC, ISO 8601) où ce poste a appliqué l'effet.
  TextColumn get appliqueLe => text().clientDefault(instantSaisie)();

  /// `null` = CE poste ; sinon le poste qui a appliqué l'effet (historique).
  TextColumn get origine => text().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get syncMotif => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {faitId, nature},
  ];
}
