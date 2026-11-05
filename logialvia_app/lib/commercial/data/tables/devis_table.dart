import 'package:drift/drift.dart';

/// Table `DEVIS` — **absente de Doc D1**, signalée comme telle par Doc H1
/// §Onglet 2 : *« table à ajouter si le module Devis doit dépasser le stade
/// prototype, actuellement stocké séparément de `VENTES` côté web »*.
///
/// Sans elle, l'onglet « Devis Prestations » afficherait un formulaire dont le
/// bouton « Générer le Devis » ne persisterait rien — exactement le pattern
/// interdit par le Master Prompt §2.3.
///
/// Volontairement **séparée de `VENTES`** : un devis n'est pas une vente, il
/// ne décrémente aucun stock, ne génère aucune écriture comptable et n'entre
/// dans aucun KPI de chiffre d'affaires.
@DataClassName('DevisRow')
class Devis extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Format 'DV-AAAA-NNN'.
  TextColumn get reference => text().unique()();

  TextColumn get client => text()();

  /// Objet / prestation proposée.
  TextColumn get objet => text()();

  RealColumn get montantEstime => real()();

  /// Durée de validité en jours — 15 par défaut (Doc H1).
  IntColumn get validiteJours => integer().withDefault(const Constant(15))();

  DateTimeColumn get dateEmission => dateTime()();
}
