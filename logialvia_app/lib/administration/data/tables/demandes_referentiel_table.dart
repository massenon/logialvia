import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// File des **demandes de modification d'un référentiel** faites au poste
/// (`46_` §4.3).
///
/// Un référentiel appartient au serveur : le poste ne l'envoie jamais, il le
/// **propose**. Chaque modification locale des modules actifs ou des paramètres
/// de l'entreprise dépose ici une demande ; le moteur l'envoie à
/// `POST /api/sync/demandes`, le serveur décide, et le résultat redescend au
/// tirage suivant.
///
/// Une seule demande en attente par clé (`type` + `cle`) : une seconde
/// modification avant l'envoi **remplace** la première (la dernière saisie
/// gagne, comme partout).
@DataClassName('DemandeReferentielRow')
class DemandesReferentiel extends Table {
  /// UUID de la demande : le serveur la rend idempotente par cet identifiant.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  /// `module_actif` ou `parametres_entreprise`.
  TextColumn get type => text()();

  /// `module_id`, ou `parametres` (ligne unique).
  TextColumn get cle => text()();

  /// Corps JSON de la demande.
  TextColumn get donnees => text()();

  /// Instant de SAISIE (UTC, ISO 8601, microsecondes).
  TextColumn get saisiLe => text().clientDefault(instantSaisie)();

  /// `pending` · `synced` · `conflict` (refusée, voir `syncMotif`).
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  TextColumn get syncMotif => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
