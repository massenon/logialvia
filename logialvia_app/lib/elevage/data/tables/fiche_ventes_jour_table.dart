import 'package:drift/drift.dart';

/// Table `FICHE_VENTES_JOUR` — Doc D1 §2.
///
/// Equivalent Flutter de `logialvia_fiche_ventes_jour` du prototype : compteur
/// de ventes du jour par espece, alimente par le POS (Doc C1 §4,
/// `VenteValideeEvent`).
@DataClassName('FicheVenteJourRow')
class FicheVentesJour extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get espece => text()();

  /// Normalisee a minuit.
  DateTimeColumn get date => dateTime()();

  IntColumn get qte => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {espece, date},
  ];
}
