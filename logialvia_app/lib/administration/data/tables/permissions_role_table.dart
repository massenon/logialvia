import 'package:drift/drift.dart';

import 'roles_table.dart';

/// Table `PERMISSIONS_ROLE` — Doc D1 §2, regle metier BR-ADM-001.
/// Une ligne par route autorisee pour un role.
@DataClassName('PermissionRoleRow')
class PermissionsRole extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get roleId => text().references(Roles, #id)();
  TextColumn get route => text()();
}
