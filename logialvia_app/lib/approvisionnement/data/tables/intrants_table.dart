import 'package:drift/drift.dart';

/// Table `INTRANTS` — Doc D1 §2.
///
/// Contexte Approvisionnement : provende et veterinaire, jamais vendus au
/// comptoir (Doc C1 §2).
@DataClassName('IntrantRow')
class Intrants extends Table {
  /// Identifiant metier, ex. 'INT-001'.
  TextColumn get code => text()();

  TextColumn get name => text()();

  /// 'Intrants Provende', 'Marchandises', 'Vétérinaire'
  TextColumn get cat => text()();

  IntColumn get stock => integer()();
  TextColumn get unit => text()();
  IntColumn get threshold => integer()();

  /// Prix Moyen Pondere, en FCFA.
  IntColumn get pmp => integer()();

  @override
  Set<Column> get primaryKey => {code};
}
