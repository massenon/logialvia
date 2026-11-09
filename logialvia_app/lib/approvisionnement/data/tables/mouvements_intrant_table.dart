import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

import 'intrants_table.dart';

/// Table `MOUVEMENTS_INTRANT`.
///
/// ⚠️ **Présente dans l'ERD de Doc D1** (`INTRANTS ||--o{ MOUVEMENTS_INTRANT :
/// "trace"`) mais **jamais définie dans le dictionnaire de données** — aucune
/// colonne n'y était spécifiée.
///
/// Elle alimente pourtant le 2ᵉ tableau de `gestion-stocks.html` (l.170-175 :
/// Date/Heure · Référence · Article · Type · Motif · Quantité) et le KPI
/// « Mouvements (7j) ». Sans elle, ni l'un ni l'autre n'existent.
@DataClassName('MouvementIntrantRow')
class MouvementsIntrant extends Table {
  /// UUID (DV-19) : un mouvement est un fait synchronise, jamais renumerote.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  DateTimeColumn get horodatage => dateTime()();

  TextColumn get intrantCode => text().references(Intrants, #code)();

  /// Nom de l'intrant au moment du mouvement — l'historique doit rester lisible
  /// même si l'intrant est renommé.
  TextColumn get article => text()();

  /// 'Entrée', 'Sortie', 'Ajustement'
  TextColumn get type => text()();

  /// Ex. « Réception commande ACH-2026-001 », « Inventaire physique ».
  TextColumn get motif => text()();

  /// Signée : positive pour une entrée, négative pour une sortie.
  RealColumn get quantite => real()();

  /// Référence de l'opération d'origine (achat, ajustement), si elle existe.
  TextColumn get reference => text().nullable()();

  /// D'ou vient ce mouvement : `null` = CE poste ; sinon l'identifiant du poste qui
  /// l'a saisi. Un mouvement d'un autre poste est une ligne d'HISTORIQUE : il
  /// n'entre dans aucun calcul de stock ni d'inventaire de ce poste (decision du
  /// client : « stock propre a chaque poste + journal partage »).
  TextColumn get origine => text().nullable()();

  // --- Synchronisation (`46_` §1) ---

  /// `pending` · `synced` · `conflict`. Un mouvement est IMMUABLE : pas d'`updated_at`.
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get syncMotif => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
