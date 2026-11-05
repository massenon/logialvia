import 'package:drift/drift.dart';

/// Table `MODULES_ACTIFS` — Doc D1 §2, regle metier BR-ADM-002, Doc I2.
///
/// Doc I2 (point 4 de l'index maitre) : Goliaths et Pintades ne sont **jamais**
/// desactivables ; les 3 filieres reellement desactivables (pisciculture,
/// cuniculture, aviculture_classique) sont **desactivees par defaut**.
@DataClassName('ModuleActifRow')
class ModulesActifs extends Table {
  TextColumn get moduleId => text()();
  BoolColumn get isActif => boolean().withDefault(const Constant(true))();

  /// Espece concernee si le module correspond a une filiere d'elevage.
  TextColumn get espece => text().nullable()();

  @override
  Set<Column> get primaryKey => {moduleId};
}
