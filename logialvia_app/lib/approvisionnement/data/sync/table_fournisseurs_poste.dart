import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';

/// `fournisseurs` — fait saisi au poste, dernier écrivain gagne (`46_` §2.3).
///
/// Deux fournisseurs de même nom restent **deux** fournisseurs (jamais fusionnés).
/// Le poste ne supprime pas de fournisseur : une pierre tombale du serveur est
/// ignorée (un achat peut s'y rattacher).
class TableFournisseursPoste implements TablePoste {
  const TableFournisseursPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  String get nom => 'fournisseurs';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications =>
      _db.tableUpdates(TableUpdateQuery.onTable(_db.fournisseurs)).map((_) {});

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        final id = l['id'];
        final nomF = _texte(l['nom']);
        final instant = l['updated_at'] is String
            ? DateTime.tryParse(l['updated_at'] as String)
            : null;
        // Strict : une ligne sans UUID, sans nom ou sans instant n'est pas lissée.
        if (id is! String ||
            !_uuid.hasMatch(id) ||
            nomF == null ||
            instant == null) {
          refusees++;
          continue;
        }

        final locale = await (_db.select(
          _db.fournisseurs,
        )..where((f) => f.id.equals(id))).getSingleOrNull();
        if (locale != null && locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++; // la saisie locale est plus récente : elle gagnera
            continue;
          }
          supplantees++; // le serveur a une version strictement plus récente
        }
        if (l['supprime_le'] != null) {
          conservees++; // le poste ne supprime jamais un fournisseur
          continue;
        }

        await _db
            .into(_db.fournisseurs)
            .insertOnConflictUpdate(
              FournisseursCompanion(
                id: Value(id),
                nom: Value(nomF.trim()),
                telephone: Value(_texte(l['telephone'])),
                adresse: Value(_texte(l['adresse'])),
                fournit: Value(_texte(l['fournit'])),
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
        await (_db.select(_db.fournisseurs)
              ..where((f) => f.syncStatus.equals('pending'))
              ..orderBy([(f) => OrderingTerm.asc(f.updatedAt)]))
            .get();
    return [
      for (final f in lignes)
        LigneAEnvoyer(
          id: f.id,
          instantSaisie: f.updatedAt,
          corps: {
            'id': f.id,
            'nom': f.nom,
            'telephone': f.telephone,
            'adresse': f.adresse,
            'fournit': f.fournit,
            'updated_at': f.updatedAt,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.fournisseurs,
    )..where((f) => f.id.equals(id) & f.updatedAt.equals(instantEnvoye))).write(
      const FournisseursCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(_db.fournisseurs)..where((f) => f.id.equals(id))).write(
      FournisseursCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro : les achats d'abord (ils référencent leur fournisseur) — le
  /// moteur purge dans l'ordre INVERSE des dépendances.
  @override
  Future<int> purger() async {
    final nonEnvoyes = await (_db.select(
      _db.fournisseurs,
    )..where((f) => f.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.fournisseurs).go();
    return nonEnvoyes.length;
  }
}
