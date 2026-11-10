import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Table `FICHE_VENTES_JOUR` — Doc D1 §2.
///
/// Equivalent Flutter de `logialvia_fiche_ventes_jour` du prototype : compteur
/// de ventes du jour par espece, alimente par le POS (Doc C1 §4,
/// `VenteValideeEvent`).
///
/// ## Synchronisation (schema v38, DV-19, `46a_`) — une ligne par POSTE
///
/// Le compteur etait cumulatif et unique par (espece, date) : avec plusieurs
/// postes, deux caisses se seraient ecrase l'une l'autre, ou comptees deux fois.
/// Chaque poste tient donc **son propre** compteur (`origine` vide = CE poste) ;
/// les compteurs des autres postes arrivent avec leur `origine` et la lecture
/// **somme** toutes les lignes du jour. Absorber la vente d'un autre poste ne
/// touche jamais ce compteur (aucun effet de bord) : il arrive par sa propre ligne.
///
/// `id` est deterministe : (espece, date, identifiant du poste). Un poste qui
/// renvoie sa ligne ne peut donc jamais la dupliquer.
@DataClassName('FicheVenteJourRow')
class FicheVentesJour extends Table {
  TextColumn get id => text().clientDefault(nouvelUuid)();
  TextColumn get espece => text()();

  /// Normalisee a minuit.
  DateTimeColumn get date => dateTime()();

  IntColumn get qte => integer().withDefault(const Constant(0))();

  /// Identifiant du poste qui a vendu. `NULL` = CE poste (son compteur propre).
  TextColumn get origine => text().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  TextColumn get syncMotif => text().nullable()();

  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {id};
}
