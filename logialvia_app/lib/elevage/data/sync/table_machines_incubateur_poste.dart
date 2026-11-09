import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';

/// `machines_incubateur` — les incubateurs du couvoir : un FAIT saisi au poste,
/// dernier écrivain gagne par UUID (`46b_`, décision à valider).
///
/// Le contrat (`46_` §2.2) les rangeait parmi les référentiels « le serveur
/// gagne » ; on les traite en **faits** parce que seul le poste sait en déclarer
/// (le serveur n'a aucune règle propre à leur appliquer) et qu'une demande de
/// référentiel aurait touché le code partagé des demandes. Le **code** est
/// l'identité métier : l'UUID en est dérivé (deux postes qui déclarent « INC-01 »
/// désignent le même incubateur).
///
/// Absorber l'incubateur d'un autre poste n'a **aucun** effet de bord.
class TableMachinesIncubateurPoste implements TablePoste {
  const TableMachinesIncubateurPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  String get nom => 'machines_incubateur';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.machinesIncubateur))
      .map((_) {});

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        final id = l['id'];
        final code = l['code'];
        final libelle = l['libelle'];
        final capacite = l['capacite_oeufs'];
        final actif = l['active'];
        final instant = l['updated_at'] is String
            ? DateTime.tryParse(l['updated_at'] as String)
            : null;
        // Strict : une ligne incohérente est refusée, jamais lissée.
        if (id is! String ||
            !_uuid.hasMatch(id) ||
            code is! String ||
            code.trim().isEmpty ||
            libelle is! String ||
            libelle.trim().isEmpty ||
            (capacite != null && (capacite is! int || capacite < 1)) ||
            actif is! bool ||
            instant == null ||
            l['supprime_le'] != null) {
          refusees++;
          continue;
        }

        final locale = await (_db.select(
          _db.machinesIncubateur,
        )..where((m) => m.id.equals(id))).getSingleOrNull();

        // Un AUTRE incubateur porte déjà ce code ici : jamais fusionné en silence.
        final homonyme =
            await (_db.select(_db.machinesIncubateur)..where(
                  (m) => m.code.equals(code.trim()) & m.id.isNotValue(id),
                ))
                .getSingleOrNull();
        if (homonyme != null) {
          refusees++;
          continue;
        }

        if (locale != null && locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++; // la saisie locale est plus récente : elle gagnera
            continue;
          }
          supplantees++;
        }

        await _db
            .into(_db.machinesIncubateur)
            .insertOnConflictUpdate(
              MachinesIncubateurCompanion(
                id: Value(id),
                code: Value(code.trim()),
                libelle: Value(libelle.trim()),
                capaciteOeufs: Value(capacite as int?),
                active: Value(actif),
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
        await (_db.select(_db.machinesIncubateur)
              ..where((m) => m.syncStatus.equals('pending'))
              ..orderBy([(m) => OrderingTerm.asc(m.updatedAt)]))
            .get();
    return [
      for (final m in lignes)
        LigneAEnvoyer(
          id: m.id,
          instantSaisie: m.updatedAt,
          corps: {
            'id': m.id,
            'code': m.code,
            'libelle': m.libelle,
            'capacite_oeufs': m.capaciteOeufs,
            'active': m.active,
            'updated_at': m.updatedAt,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.machinesIncubateur,
    )..where((m) => m.id.equals(id) & m.updatedAt.equals(instantEnvoye))).write(
      const MachinesIncubateurCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(
      _db.machinesIncubateur,
    )..where((m) => m.id.equals(id))).write(
      MachinesIncubateurCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur : vide les incubateurs (les lots sont purgés AVANT,
  /// le moteur purge dans l'ordre inverse des dépendances). Renvoie le nombre
  /// d'incubateurs non envoyés perdus.
  @override
  Future<int> purger() async {
    final nonEnvoyes = await (_db.select(
      _db.machinesIncubateur,
    )..where((m) => m.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.machinesIncubateur).go();
    return nonEnvoyes.length;
  }
}
