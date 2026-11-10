import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import 'identifiants_elevage.dart';
import 'outils_sync_elevage.dart';

/// `bandes` — fait saisi au poste, dernier écrivain gagne par UUID (`46_` §2.3, `46a_`).
///
/// ## Ce qui voyage, et ce qui ne voyage jamais
///
/// Voyage : la **déclaration** (espèce, code, date de mise en place, effectif mis en
/// place, date de clôture, observations). `effectif_initial` est **indicatif** : il
/// documente la mise en place, il n'alimente aucun calcul.
///
/// Ne voyage JAMAIS : un effectif « réel » de la bande. Il n'existe pas comme donnée
/// stockée (la fiche journalière est tenue par filière, pas par bande) ; il se recalcule
/// des fiches. Cette table n'a d'ailleurs aucune colonne pour le porter.
///
/// ## Le code est unique par filière
///
/// `UNIQUE(espece, code)`. Deux postes qui déclarent chacun « B2 » pour la même filière
/// (hors ligne) créent deux bandes de UUID différents : la seconde reçue est **refusée**
/// et comptée (jamais fusionnée, jamais écrasée : deux dates de mise en place ne se
/// moyennent pas). Voir `46a_` §« Décisions à valider ».
class TableBandesPoste implements TablePoste {
  const TableBandesPoste(this._db);

  final AppDatabase _db;

  @override
  String get nom => 'bandes';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications =>
      _db.tableUpdates(TableUpdateQuery.onTable(_db.bandes)).map((_) {});

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        final miseEnBande = OutilsSyncElevage.jour(l['date_mise_en_bande']);
        final cloture = l['date_cloture'] == null
            ? null
            : OutilsSyncElevage.jour(l['date_cloture']);
        final instant = OutilsSyncElevage.instant(l['updated_at']);
        final code = OutilsSyncElevage.texte(l['code']);

        // Strict : refusée, jamais lissée. Une clôture antérieure à la mise en place
        // est la même incohérence que celle que refuse le formulaire du poste.
        if (!OutilsSyncElevage.estUuid(l['id']) ||
            !OutilsSyncElevage.especeConnue(l['espece']) ||
            code == null ||
            miseEnBande == null ||
            (l['date_cloture'] != null && cloture == null) ||
            (cloture != null && cloture.isBefore(miseEnBande)) ||
            instant == null ||
            !OutilsSyncElevage.entierOuNull(l['effectif_initial']) ||
            (l['observations'] != null && l['observations'] is! String)) {
          refusees++;
          continue;
        }
        final id = l['id'] as String;
        final espece = l['espece'] as String;

        // Le code est l'identité métier d'une bande dans une filière.
        final homonyme =
            await (_db.select(_db.bandes)..where(
                  (b) =>
                      b.espece.equals(espece) &
                      b.code.equals(code.trim()) &
                      b.id.equals(id).not(),
                ))
                .getSingleOrNull();
        if (homonyme != null) {
          refusees++;
          continue;
        }

        final locale = await (_db.select(
          _db.bandes,
        )..where((b) => b.id.equals(id))).getSingleOrNull();
        var supplantee = false;
        if (locale != null && locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++;
            continue;
          }
          supplantee = true;
        }
        if (supplantee) supplantees++;

        await _db
            .into(_db.bandes)
            .insertOnConflictUpdate(
              BandesCompanion(
                id: Value(id),
                espece: Value(espece),
                code: Value(code.trim()),
                dateMiseEnBande: Value(miseEnBande),
                effectifInitial: Value(l['effectif_initial'] as int?),
                dateCloture: Value(cloture),
                observations: Value(OutilsSyncElevage.texte(l['observations'])),
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
        await (_db.select(_db.bandes)
              ..where((b) => b.syncStatus.equals('pending'))
              ..orderBy([(b) => OrderingTerm.asc(b.updatedAt)]))
            .get();
    return [
      for (final b in lignes)
        LigneAEnvoyer(
          id: b.id,
          instantSaisie: b.updatedAt,
          corps: {
            'id': b.id,
            'espece': b.espece,
            'code': b.code,
            'date_mise_en_bande': jourCivil(b.dateMiseEnBande),
            'effectif_initial': b.effectifInitial,
            'date_cloture': b.dateCloture == null
                ? null
                : jourCivil(b.dateCloture!),
            'observations': b.observations,
            'updated_at': b.updatedAt,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.bandes,
    )..where((b) => b.id.equals(id) & b.updatedAt.equals(instantEnvoye))).write(
      const BandesCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(_db.bandes)..where((b) => b.id.equals(id))).write(
      BandesCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  @override
  Future<int> purger() async {
    final nonEnvoyees = await (_db.select(
      _db.bandes,
    )..where((b) => b.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.bandes).go();
    return nonEnvoyees.length;
  }
}
