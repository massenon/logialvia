import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../repositories/comptabilite_repository_drift.dart';

/// `exercice_comptable` — référentiel **reçu seulement** (`46d_` §2, §4).
///
/// - **Clé naturelle** : l'année. Deux postes qui ouvrent 2026 ouvrent le MÊME exercice.
/// - Le poste n'envoie jamais un exercice : sa **clôture** part comme un fait lourd
///   distinct (`TableCloturesExercicePoste`, `clotures_exercice`), APRÈS les écritures
///   (le serveur verrouille l'exercice : il doit d'abord connaître toutes les pièces).
/// - **Aucune déclôture** (BR-CPT-001) : une clôture venue du serveur s'applique ici
///   (exercice fermé, écritures verrouillées) ; un serveur qui dit « ouvert » ne rouvre
///   jamais un exercice que ce poste a fermé. Seule la **remise à zéro** du serveur
///   rouvre les exercices (leurs écritures sont alors purgées avec).
class TableExercicesPoste implements TablePoste {
  const TableExercicesPoste(this._db);

  final AppDatabase _db;

  @override
  String get nom => 'exercice_comptable';

  @override
  bool get referentiel => true;

  @override
  Stream<void> get modifications => const Stream<void>.empty();

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;

      for (final l in lignes) {
        final annee = l['annee'];
        final cloture = l['is_cloture'];
        final dateCloture = l['date_cloture'] is String
            ? DateTime.tryParse(l['date_cloture'] as String)
            : null;
        // Strict : une année absurde ou une clôture sans date est refusée.
        if (annee is! int ||
            annee < 2000 ||
            annee > 2100 ||
            cloture is! bool ||
            (cloture && dateCloture == null)) {
          refusees++;
          continue;
        }

        final locale = await (_db.select(
          _db.exerciceComptable,
        )..where((e) => e.annee.equals(annee))).getSingleOrNull();

        if (locale == null) {
          await _db
              .into(_db.exerciceComptable)
              .insert(
                ExerciceComptableCompanion.insert(
                  annee: Value(annee),
                  isCloture: Value(cloture),
                  dateCloture: Value(dateCloture?.toLocal()),
                  syncStatus: const Value('synced'),
                ),
              );
          if (cloture) await _verrouiller(annee);
          absorbees++;
          continue;
        }

        if (cloture && !locale.isCloture) {
          await (_db.update(
            _db.exerciceComptable,
          )..where((e) => e.annee.equals(annee))).write(
            ExerciceComptableCompanion(
              isCloture: const Value(true),
              dateCloture: Value(dateCloture?.toLocal()),
              syncStatus: const Value('synced'),
              syncMotif: const Value(null),
            ),
          );
          await _verrouiller(annee);
          absorbees++;
        } else if (cloture &&
            locale.isCloture &&
            locale.syncStatus == 'pending') {
          // Notre propre clôture, acceptée entre-temps : le serveur la connaît.
          await (_db.update(
            _db.exerciceComptable,
          )..where((e) => e.annee.equals(annee))).write(
            const ExerciceComptableCompanion(
              syncStatus: Value('synced'),
              syncMotif: Value(null),
            ),
          );
        }
        // Serveur « ouvert », poste « clos » : jamais de déclôture ici… sauf RÉOUVERTURE
        // explicite du serveur (`rouvert_le`, droit close-fiscal-year, écran Clôture du web) :
        // c'est alors un fait nouveau, que ce poste suit — son exercice, dont la clôture avait
        // été acceptée, retrouve ses écritures déverrouillées, sans écritures de clôture ni
        // à-nouveaux (le serveur les a retirés).
        else if (!cloture &&
            locale.isCloture &&
            locale.syncStatus == 'synced' &&
            l['rouvert_le'] is String &&
            DateTime.tryParse(l['rouvert_le'] as String) != null) {
          await ComptabiliteRepositoryDrift.rouvrirLocalement(_db, annee);
          absorbees++;
        }
        // Sinon, serveur « ouvert » et poste « clos » : jamais de déclôture ici.
      }
      return ResultatAbsorption(absorbees: absorbees, refusees: refusees);
    });
  }

  Future<void> _verrouiller(int annee) =>
      (_db.update(_db.ecritureComptable)
            ..where((e) => e.exerciceAnnee.equals(annee)))
          .write(const EcritureComptableCompanion(isLocked: Value(true)));

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async => const [];

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {}

  @override
  Future<void> marquerConflit(String id, String motif) async {}

  /// Remise à zéro du serveur : les exercices redeviennent OUVERTS (leurs écritures
  /// sont purgées avec) ; ils ne sont pas supprimés, c'est un référentiel.
  @override
  Future<int> purger() async {
    // Une clôture non acceptée est une saisie perdue : le poste le dit.
    final perdues = await (_db.select(
      _db.exerciceComptable,
    )..where((e) => e.syncStatus.equals('pending'))).get();
    await _db
        .update(_db.exerciceComptable)
        .write(
          ExerciceComptableCompanion(
            isCloture: const Value(false),
            dateCloture: const Value(null),
            syncStatus: const Value('synced'),
            syncMotif: const Value(null),
            updatedAt: Value(DateTime.now().toUtc().toIso8601String()),
          ),
        );
    return perdues.length;
  }
}
