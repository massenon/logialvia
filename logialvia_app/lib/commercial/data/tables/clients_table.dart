import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Table `CLIENTS` — Doc D1 §2.
@DataClassName('ClientRow')
class Clients extends Table {
  /// UUID genere au poste (DV-19, `46_`) : jamais un entier auto-incremente,
  /// que deux postes attribueraient chacun de leur cote. Les anciennes lignes
  /// recoivent le leur a la migration v31.
  TextColumn get id => text().clientDefault(nouvelUuid)();
  TextColumn get nom => text()();
  TextColumn get telephone => text().nullable()();

  /// Somme des ventes en statut 'Avance' non soldees.
  ///
  /// NOTE : cette colonne est conservee pour rester conforme a Doc D1, mais le
  /// solde affiche est **recalcule depuis `VENTES`** a chaque lecture. Stocker
  /// un cumul dérivé, c'est accepter qu'il diverge de sa source — le genre
  /// d'incoherence silencieuse que ce projet a deja connue.
  RealColumn get soldeCreance => real().withDefault(const Constant(0))();

  /// ⚠️ AJOUTEE — colonne « Date de Naissance » du tableau et du formulaire
  /// client (`relances-clients.html` l.144 et l.329), absente de Doc D1.
  /// C'est la source des « Événements CRM (7j) » et de l'alerte
  /// « Anniversaire client demain » du tableau de bord.
  DateTimeColumn get dateNaissance => dateTime().nullable()();

  /// ⚠️ AJOUTEE — colonne « Dernier Contact » du tableau CRM (l.251).
  DateTimeColumn get dernierContact => dateTime().nullable()();

  // ------------------------------------------------------- Synchronisation
  //
  // Colonnes communes a toute table synchronisee (`46_` §1). L'identifiant du
  // poste (`device_id`) n'est PAS stocke : le serveur le deduit du jeton.

  /// `pending` (a envoyer) · `synced` · `conflict` (refuse, voir `syncMotif`).
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  /// Motif du refus du serveur, en francais ; `null` hors conflit.
  TextColumn get syncMotif => text().nullable()();

  /// Instant de SAISIE (UTC, ISO 8601, microsecondes) — voir [instantSaisie].
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {id};
}
