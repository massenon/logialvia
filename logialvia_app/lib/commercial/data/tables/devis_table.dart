import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

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
  /// UUID genere au poste (DV-19, v43) : l'identite SYNCHRONISEE du devis. Les
  /// anciens devis (entier auto-incremente) recoivent le leur a la migration.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  /// Numero OFFICIEL, jamais renumerote : `DV-P2-2026-001` (poste appaire),
  /// `DV-2026-001` (poste jamais appaire), `DV-WEB-2026-001` (emis au web).
  TextColumn get reference => text().unique()();

  TextColumn get client => text()();

  /// Objet / prestation proposée.
  TextColumn get objet => text()();

  RealColumn get montantEstime => real()();

  /// Durée de validité en jours — 15 par défaut (Doc H1).
  IntColumn get validiteJours => integer().withDefault(const Constant(15))();

  DateTimeColumn get dateEmission => dateTime()();

  /// Cycle de vie : `emis` (a la signature du client) puis `accepte` ou `refuse`.
  /// « Expire » n'est PAS stocke : il se deduit de la date d'expiration.
  /// Un devis `accepte` ne se modifie plus et ne se supprime pas (v43).
  TextColumn get statut => text().withDefault(const Constant('emis'))();

  /// Pierre tombale (instant de suppression, ISO UTC) : la ligne reste, cachee,
  /// pour que la suppression se propage et que le numero ne soit jamais reutilise.
  TextColumn get supprimeLe => text().nullable()();

  // ------------------------------------------------------- Synchronisation
  //
  // Colonnes communes a toute table synchronisee (`46_` §1).

  /// `pending` (a envoyer) · `synced` · `conflict` (refuse, voir `syncMotif`).
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  /// Motif du refus du serveur, en francais ; `null` hors conflit.
  TextColumn get syncMotif => text().nullable()();

  /// Instant de SAISIE (UTC, ISO 8601, microsecondes).
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {id};
}
