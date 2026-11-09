import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Table `INFIRMERIE` — **entierement absente de Doc D1**.
///
/// `soins-calendrier.html` comporte un onglet « Suivi » avec son propre
/// tableau (l.236-243 : Date d'Entrée, Lot/Sujet, Motif, Niveau d'Isolement,
/// Statut, Actions), sa modale de creation (l.300-319) et sa modale de
/// declaration de deces (l.321-332). Rien de tout cela n'apparait ni dans
/// Doc F3 ni dans le modele de donnees.
///
/// C'est aussi la source du KPI « En Quarantaine / Traitement ».
@DataClassName('InfirmerieRow')
class Infirmerie extends Table {
  /// UUID genere au poste (DV-19, `46c_`). Les anciennes entrees recoivent le leur
  /// a la migration v40.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  DateTimeColumn get dateEntree => dateTime()();

  /// Texte libre — le prototype accepte un lot ou un sujet identifie,
  /// ex. « Goliath #G-014 ».
  TextColumn get sujet => text()();

  /// Ex. « Suspicion Newcastle ».
  TextColumn get motif => text()();

  /// 'Simple surveillance', 'Infirmerie', 'Quarantaine stricte'
  TextColumn get niveauIsolement => text()();

  /// 'En cours', 'Réintégré', 'Décédé' — valeurs du filtre de statut
  /// (l.220-223).
  TextColumn get statut => text()();

  /// Renseignee a la reintegration ou au deces.
  DateTimeColumn get dateSortie => dateTime().nullable()();

  /// Espece concernee, pour rattacher un deces a la fiche d'elevage
  /// correspondante (voir la note de la modale de deces, l.326).
  TextColumn get espece => text().nullable()();

  /// Categorie d'effectif ou le deces a ete reporte — index dans
  /// `ConfigurationEspece.categories`. `null` s'il ne l'a pas ete.
  ///
  /// Sans elle, un deces pourrait etre reporte deux fois : une a la cloture,
  /// une a la main sur la fiche. La colonne rend le report VERIFIABLE.
  IntColumn get categorieMortalite => integer().nullable()();

  // ------------------------------------------------------- Synchronisation
  //
  // Une entree d'infirmerie est un FAIT : dernier ecrivain gagne, par UUID.

  /// `pending` (a envoyer) · `synced` · `conflict` (refuse, voir `syncMotif`).
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  /// Motif du refus du serveur, en francais ; `null` hors conflit.
  TextColumn get syncMotif => text().nullable()();

  /// Instant de SAISIE (UTC, ISO 8601, microsecondes) — voir [instantSaisie].
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {id};
}
