import 'package:drift/drift.dart';

import '../../../administration/data/repositories/preferences_poste_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import 'identifiants_elevage.dart';
import 'outils_sync_elevage.dart';

/// `fiche_ventes_jour` — le compteur de ventes du jour, **une ligne par poste**
/// (`46a_`).
///
/// ## Pourquoi une ligne par poste
///
/// Le compteur est cumulatif (la caisse l'incrémente, une annulation le décrémente).
/// À plusieurs postes, une ligne unique par (espèce, date) se serait écrasée d'un poste
/// à l'autre (dernier écrivain gagne : des ventes perdues) ou comptée deux fois. Chaque
/// poste tient **son** compteur ; la lecture (`venteDuJour`) **somme** toutes les lignes
/// du jour. Aucun double comptage : la vente d'un autre poste (table `ventes`) n'a
/// jamais d'effet local, son compteur arrive par sa propre ligne.
///
/// ## Qui est « moi »
///
/// Le serveur sert `device_id` (le poste qui a vendu). Si c'est CE poste (cas d'une
/// resynchronisation complète sur une base vide, d'une restauration), la ligne reprend
/// `origine` vide : sinon mon propre compteur serait pris pour celui d'un autre, et
/// mes prochaines ventes ouvriraient une seconde ligne — comptées deux fois.
class TableVentesJourPoste implements TablePoste {
  const TableVentesJourPoste(this._db);

  final AppDatabase _db;

  @override
  String get nom => 'fiche_ventes_jour';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.ficheVentesJour))
      .map((_) {});

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;
      final moi = await PreferencesPosteRepository(_db).identifiantPoste();

      for (final l in lignes) {
        final jour = OutilsSyncElevage.jour(l['date']);
        final instant = OutilsSyncElevage.instant(l['updated_at']);
        final espece = l['espece'];
        final poste = OutilsSyncElevage.texte(l['device_id']);

        // Strict. Le compteur d'un poste ne peut porter que l'identifiant calculé de
        // (espèce, date, poste) : sinon deux lignes d'un même poste se sommeraient.
        if (!OutilsSyncElevage.estUuid(l['id']) ||
            !OutilsSyncElevage.especeConnue(espece) ||
            jour == null ||
            instant == null ||
            poste == null ||
            !OutilsSyncElevage.entierPositif(l['qte']) ||
            l['id'] != identifiantVentesJour(espece as String, jour, poste)) {
          refusees++;
          continue;
        }
        final id = l['id'] as String;

        final locale = await (_db.select(
          _db.ficheVentesJour,
        )..where((f) => f.id.equals(id))).getSingleOrNull();

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

        final origine = poste == moi ? null : poste;
        await _db
            .into(_db.ficheVentesJour)
            .insertOnConflictUpdate(
              FicheVentesJourCompanion(
                id: Value(id),
                espece: Value(espece),
                date: Value(jour),
                qte: Value(l['qte'] as int),
                origine: Value(origine),
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

  /// Seulement MON compteur : celui des autres postes n'est jamais renvoyé.
  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final lignes =
        await (_db.select(_db.ficheVentesJour)
              ..where(
                (f) => f.syncStatus.equals('pending') & f.origine.isNull(),
              )
              ..orderBy([(f) => OrderingTerm.asc(f.updatedAt)]))
            .get();
    return [
      for (final f in lignes)
        LigneAEnvoyer(
          id: f.id,
          instantSaisie: f.updatedAt,
          corps: {
            'id': f.id,
            'espece': f.espece,
            'date': jourCivil(f.date),
            'qte': f.qte,
            'updated_at': f.updatedAt,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.ficheVentesJour,
    )..where((f) => f.id.equals(id) & f.updatedAt.equals(instantEnvoye))).write(
      const FicheVentesJourCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(
      _db.ficheVentesJour,
    )..where((f) => f.id.equals(id))).write(
      FicheVentesJourCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur : tous les compteurs partent (le mien comme ceux des
  /// autres) ; seuls les miens, non envoyés, sont comptés comme perdus.
  @override
  Future<int> purger() async {
    final nonEnvoyes =
        await (_db.select(_db.ficheVentesJour)..where(
              (f) => f.syncStatus.isNotValue('synced') & f.origine.isNull(),
            ))
            .get();
    await _db.delete(_db.ficheVentesJour).go();
    return nonEnvoyes.length;
  }
}
