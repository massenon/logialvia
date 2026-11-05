import 'package:drift/drift.dart';

/// Table `SECURITY_LOGS` — Doc D1 §2, Doc I3 §6.
/// Types d'evenement : echec_connexion, acces_route_non_autorise,
/// tentative_modification_verrouillee.
@DataClassName('SecurityLogRow')
class SecurityLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get horodatage => dateTime()();
  TextColumn get typeEvenement => text()();
  TextColumn get identifiantTente => text().nullable()();
  TextColumn get detail => text().nullable()();
}
