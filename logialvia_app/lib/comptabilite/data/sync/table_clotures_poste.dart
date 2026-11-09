import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../../core/sync/table_poste.dart';

/// `clotures_periodiques` — clôture (et déclôture) d'un MOIS (`46d_` §4).
///
/// Clé naturelle (année, mois) ; l'identifiant du fil est dérivé
/// (`uuidDeterministe('cloture-periodique:AAAA-M')`) : deux postes qui clôturent mars
/// 2026 parlent du même fait. **Dernier écrivain gagne**, à l'instant de saisie,
/// strictement. Verrouiller un mois ici n'efface rien : il refuse les nouvelles
/// écritures datées de ce mois, ici comme au serveur.
class TableCloturesPeriodiquesPoste implements TablePoste {
  const TableCloturesPeriodiquesPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  String get nom => 'clotures_periodiques';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.cloturesPeriodiques))
      .map((_) {});

  /// Identifiant du fil d'un mois.
  static String idDuMois(int annee, int mois) =>
      uuidDeterministe('cloture-periodique:$annee-$mois');

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        final annee = l['annee'];
        final mois = l['mois'];
        final cloture = l['is_cloture'];
        final instant = l['updated_at'] is String
            ? DateTime.tryParse(l['updated_at'] as String)
            : null;
        final date = l['date_cloture'] is String
            ? DateTime.tryParse(l['date_cloture'] as String)
            : null;
        // Strict : un mois hors 1-12, une clôture sans date, un identifiant qui ne
        // désigne pas ce mois : refusés, jamais devinés.
        if (annee is! int ||
            mois is! int ||
            mois < 1 ||
            mois > 12 ||
            cloture is! bool ||
            (cloture && date == null) ||
            instant == null ||
            l['id'] is! String ||
            !_uuid.hasMatch(l['id'] as String) ||
            l['id'] != idDuMois(annee, mois)) {
          refusees++;
          continue;
        }

        final exercice = await (_db.select(
          _db.exerciceComptable,
        )..where((e) => e.annee.equals(annee))).getSingleOrNull();
        if (exercice == null) {
          refusees++;
          continue;
        }

        final locale =
            await (_db.select(_db.cloturesPeriodiques)
                  ..where((c) => c.annee.equals(annee) & c.mois.equals(mois)))
                .getSingleOrNull();

        if (locale != null && locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++; // la saisie locale est plus récente : elle partira
            continue;
          }
          supplantees++;
        }
        if (locale != null &&
            locale.syncStatus == 'synced' &&
            locale.isCloture == cloture) {
          continue; // identique
        }

        await _db
            .into(_db.cloturesPeriodiques)
            .insertOnConflictUpdate(
              CloturesPeriodiquesCompanion.insert(
                annee: annee,
                mois: mois,
                isCloture: Value(cloture),
                dateCloture: Value(date?.toLocal()),
                declotureParUtilisateurId: Value(
                  l['decloture_par'] is String
                      ? l['decloture_par'] as String
                      : null,
                ),
                syncStatus: const Value('synced'),
                syncMotif: const Value(null),
                updatedAt: Value(instant.toUtc().toIso8601String()),
              ),
            );
        absorbees++;
      }
      return ResultatAbsorption(
        absorbees: absorbees,
        refusees: refusees,
        conservees: conservees,
        supplantees: supplantees,
      );
    });
  }

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final lignes =
        await (_db.select(_db.cloturesPeriodiques)
              ..where((c) => c.syncStatus.equals('pending'))
              ..orderBy([(c) => OrderingTerm.asc(c.updatedAt)]))
            .get();
    return [
      for (final c in lignes)
        LigneAEnvoyer(
          id: idDuMois(c.annee, c.mois),
          instantSaisie: c.updatedAt,
          corps: {
            'id': idDuMois(c.annee, c.mois),
            'annee': c.annee,
            'mois': c.mois,
            'is_cloture': c.isCloture,
            'date_cloture': c.dateCloture?.toUtc().toIso8601String(),
            'decloture_par': c.declotureParUtilisateurId,
            'updated_at': c.updatedAt,
          },
        ),
    ];
  }

  Future<CloturePeriodiqueRow?> _trouver(String id) async {
    for (final c in await _db.select(_db.cloturesPeriodiques).get()) {
      if (idDuMois(c.annee, c.mois) == id) return c;
    }
    return null;
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    final c = await _trouver(id);
    if (c == null) return;
    await (_db.update(_db.cloturesPeriodiques)..where(
          (x) =>
              x.annee.equals(c.annee) &
              x.mois.equals(c.mois) &
              x.updatedAt.equals(instantEnvoye),
        ))
        .write(
          const CloturesPeriodiquesCompanion(
            syncStatus: Value('synced'),
            syncMotif: Value(null),
          ),
        );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    final c = await _trouver(id);
    if (c == null) return;
    await (_db.update(
      _db.cloturesPeriodiques,
    )..where((x) => x.annee.equals(c.annee) & x.mois.equals(c.mois))).write(
      CloturesPeriodiquesCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  @override
  Future<int> purger() async {
    final nonEnvoyees = await (_db.select(
      _db.cloturesPeriodiques,
    )..where((c) => c.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.cloturesPeriodiques).go();
    return nonEnvoyees.length;
  }
}

/// `clotures_exercice` — la clôture ANNUELLE, un **fait lourd**, envoyé seulement
/// (`46d_` §4).
///
/// Le serveur ne la sert jamais : l'exercice fermé redescend par `exercice_comptable`.
/// Ce fait part APRÈS les écritures (ordre du moteur) : le serveur verrouille
/// l'exercice, il doit donc connaître toutes les pièces d'abord. Il n'accepte que
/// l'administratrice (`close-fiscal-year`), sur une balance équilibrée.
///
/// **Refusée**, la clôture n'a pas eu lieu : l'exercice est rouvert ici (écritures
/// déverrouillées), le motif est conservé et affiché sur l'écran de clôture. Ce n'est
/// pas une déclôture (BR-CPT-001) : le serveur, qui fait foi, n'a jamais clos.
class TableCloturesExercicePoste implements TablePoste {
  const TableCloturesExercicePoste(this._db);

  final AppDatabase _db;

  @override
  String get nom => 'clotures_exercice';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.exerciceComptable))
      .map((_) {});

  static String idDeLExercice(int annee) =>
      uuidDeterministe('cloture-exercice:$annee');

  /// Le serveur ne sert jamais ce fait : rien à absorber.
  @override
  Future<ResultatAbsorption> absorber(
    List<Map<String, dynamic>> lignes,
  ) async => const ResultatAbsorption();

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final lignes =
        await (_db.select(_db.exerciceComptable)
              ..where(
                (e) =>
                    e.syncStatus.equals('pending') & e.isCloture.equals(true),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.annee)]))
            .get();
    return [
      for (final e in lignes)
        LigneAEnvoyer(
          id: idDeLExercice(e.annee),
          instantSaisie: e.updatedAt,
          corps: {
            'id': idDeLExercice(e.annee),
            'annee': e.annee,
            'date_cloture': (e.dateCloture ?? DateTime.now())
                .toUtc()
                .toIso8601String(),
            'updated_at': e.updatedAt,
          },
        ),
    ];
  }

  Future<int?> _annee(String id) async {
    for (final e in await _db.select(_db.exerciceComptable).get()) {
      if (idDeLExercice(e.annee) == id) return e.annee;
    }
    return null;
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    final annee = await _annee(id);
    if (annee == null) return;
    await (_db.update(_db.exerciceComptable)..where(
          (e) => e.annee.equals(annee) & e.updatedAt.equals(instantEnvoye),
        ))
        .write(
          const ExerciceComptableCompanion(
            syncStatus: Value('synced'),
            syncMotif: Value(null),
          ),
        );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    final annee = await _annee(id);
    if (annee == null) return;
    await _db.transaction(() async {
      await (_db.update(
        _db.exerciceComptable,
      )..where((e) => e.annee.equals(annee))).write(
        ExerciceComptableCompanion(
          isCloture: const Value(false),
          dateCloture: const Value(null),
          syncStatus: const Value('conflict'),
          syncMotif: Value(motif),
        ),
      );
      await (_db.update(_db.ecritureComptable)
            ..where((e) => e.exerciceAnnee.equals(annee)))
          .write(const EcritureComptableCompanion(isLocked: Value(false)));
    });
  }

  @override
  Future<int> purger() async => 0;
}
