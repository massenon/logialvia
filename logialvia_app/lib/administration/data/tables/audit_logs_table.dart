import 'package:drift/drift.dart';

/// Table `AUDIT_LOGS` — Doc D1 §2, Doc I3 §6.
/// Actions journalisees : suppression, modification, cloture, decloture, connexion.
@DataClassName('AuditLogRow')
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get horodatage => dateTime()();
  TextColumn get utilisateurId => text()();
  TextColumn get action => text()();
  TextColumn get entiteConcernee => text()();
  TextColumn get entiteId => text()();

  /// JSON des valeurs avant/apres si pertinent.
  TextColumn get details => text().nullable()();
}
