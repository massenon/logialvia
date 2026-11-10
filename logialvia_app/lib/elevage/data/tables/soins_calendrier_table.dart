import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Table `SOINS_CALENDRIER` — Doc D1 §2.
@DataClassName('SoinCalendrierRow')
class SoinsCalendrier extends Table {
  /// UUID genere au poste (DV-19, `46c_`) : un soin saisi sur deux postes ne
  /// peut pas porter le meme entier. Les anciens soins recoivent le leur a la
  /// migration v40.
  TextColumn get id => text().clientDefault(nouvelUuid)();
  TextColumn get espece => text()();
  DateTimeColumn get datePrevue => dateTime()();
  TextColumn get typeSoin => text()();

  /// 'Planifié', 'Effectué', 'En retard', 'Traitement en cours'
  TextColumn get statut => text()();

  TextColumn get observations => text().nullable()();

  // ⚠️ COLONNES AJOUTEES — la modale « Nouveau Soin » saisit 9 champs
  // (soins-calendrier.html l.264-291) alors que Doc D1 n'en modelisait que 5.
  // Sans elles, le registre reel et le KPI « Coût Vétérinaire (Mois) » sont
  // impossibles a alimenter.

  /// Produit utilise, ex. « Antcox ».
  TextColumn get produit => text().nullable()();

  /// Dose, saisie en texte libre : ex. « 1C/20L d'eau ».
  TextColumn get dose => text().nullable()();

  /// Delai d'attente / remanence, en jours — periode pendant laquelle les
  /// produits de l'animal ne sont pas commercialisables.
  IntColumn get remanenceJours => integer().withDefault(const Constant(0))();

  TextColumn get veterinaire => text().nullable()();
  TextColumn get symptomes => text().nullable()();

  /// Cout en FCFA, alimente le KPI « Coût Vétérinaire (Mois) ».
  IntColumn get coutFcfa => integer().withDefault(const Constant(0))();

  // ⚠️ COLONNES AJOUTEES EN v25 — tracabilite de l'injection du calendrier de
  // prophylaxie. Elles n'ont de valeur QUE sur un soin injecte ; un soin saisi
  // a la main les laisse a NULL.

  /// Bande dont ce soin decoule (`BANDES.id`).
  /// UUID de la bande (schema v38 : `bandes.id` est desormais un UUID).
  TextColumn get bandeId => text().nullable()();

  /// Echeance du calendrier dont ce soin decoule
  /// (`CALENDRIER_PROPHYLAXIE.id`).
  ///
  /// Le couple (`bandeId`, `echeanceId`) est ce qui rend l'injection
  /// **idempotente** : la relancer ne cree pas un second rappel Newcastle. Une
  /// simple comparaison (espece, date, traitement) ne suffirait pas — deux
  /// bandes mises en place le meme jour partagent exactement ces trois
  /// valeurs.
  ///
  /// Texte (UUID de l'echeance) depuis la v40 : le calendrier de prophylaxie
  /// est synchronise, ses identifiants sont des UUID.
  TextColumn get echeanceProphylaxieId => text().nullable()();

  // ------------------------------------------------------- Synchronisation
  //
  // Colonnes communes a toute table synchronisee (`46_` §1). Un soin est un FAIT :
  // dernier ecrivain gagne, par UUID. `bandeId` reste LOCAL (les bandes ne sont pas
  // encore synchronisees) : il ne voyage pas, voir `46c_`.

  /// `pending` (a envoyer) · `synced` · `conflict` (refuse, voir `syncMotif`).
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  /// Motif du refus du serveur, en francais ; `null` hors conflit.
  TextColumn get syncMotif => text().nullable()();

  /// Instant de SAISIE (UTC, ISO 8601, microsecondes) — voir [instantSaisie].
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {id};
}
