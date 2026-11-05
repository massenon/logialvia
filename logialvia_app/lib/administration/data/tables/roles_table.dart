import 'package:drift/drift.dart';

/// Table `ROLES` — Doc D1 §2.
/// Referentiel des 3 roles reels : admin / caissier / animalier
/// (Doc I1 §1, corrige suite a Doc K4 §8 — aucun role `comptable` distinct).
@DataClassName('RoleRow')
class Roles extends Table {
  TextColumn get id => text()();
  TextColumn get libelle => text()();

  @override
  Set<Column> get primaryKey => {id};
}
