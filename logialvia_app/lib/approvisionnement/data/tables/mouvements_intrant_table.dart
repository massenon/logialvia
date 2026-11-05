import 'package:drift/drift.dart';

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
  IntColumn get id => integer().autoIncrement()();

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
}
