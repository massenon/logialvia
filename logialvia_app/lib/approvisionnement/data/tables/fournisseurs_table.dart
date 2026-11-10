import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Table `FOURNISSEURS` — Doc D1 §2.
@DataClassName('FournisseurRow')
class Fournisseurs extends Table {
  /// UUID genere au poste (DV-19) : un fournisseur cree sur deux postes ne peut pas
  /// porter le meme entier. Les anciens recoivent le leur a la migration v35.
  TextColumn get id => text().clientDefault(nouvelUuid)();
  TextColumn get nom => text()();

  /// Doc D1 nomme cette colonne `contact` ; le tableau reel (`fournisseurs.html`
  /// l.135) l'intitule « Téléphone ». Meme donnee, nom aligne sur l'interface.
  TextColumn get telephone => text().nullable()();

  TextColumn get adresse => text().nullable()();

  /// ⚠️ AJOUTEE — colonne « Fournit » du tableau reel (l.136) : ce que le
  /// fournisseur approvisionne. Absente de Doc D1.
  TextColumn get fournit => text().nullable()();

  // --- Synchronisation (`46_` §1) ---

  /// `pending` · `synced` · `conflict`.
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get syncMotif => text().nullable()();

  /// Instant de SAISIE (UTC, ISO 8601, microsecondes).
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {id};
}
