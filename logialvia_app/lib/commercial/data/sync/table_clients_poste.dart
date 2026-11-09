import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';

/// `clients` — fait saisi au poste, dernier écrivain gagne (`46_` §2.3).
///
/// `solde_creance` est une donnée **dérivée** (ventes) : jamais envoyée, jamais
/// absorbée — le poste recalcule le solde depuis ses ventes.
class TableClientsPoste implements TablePoste {
  const TableClientsPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  String get nom => 'clients';

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final ligne in lignes) {
        final id = ligne['id'];
        final nomClient = ligne['nom'];
        final instant = ligne['updated_at'] is String
            ? DateTime.tryParse(ligne['updated_at'] as String)
            : null;
        // Strict : une ligne sans UUID, sans nom ou sans instant n'est pas lissée.
        if (id is! String ||
            !_uuid.hasMatch(id) ||
            nomClient is! String ||
            nomClient.trim().isEmpty ||
            instant == null) {
          refusees++;
          continue;
        }

        final locale = await (_db.select(
          _db.clients,
        )..where((c) => c.id.equals(id))).getSingleOrNull();
        var supplantee = false;
        if (locale != null && locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++; // la saisie locale est plus récente : elle gagnera
            continue;
          }
          supplantee =
              true; // le serveur a une version strictement plus récente
        }
        if (supplantee) supplantees++;

        // Pierre tombale : le serveur a supprimé ce client.
        if (ligne['supprime_le'] != null) {
          if (locale != null) {
            await (_db.delete(_db.clients)..where((c) => c.id.equals(id))).go();
            absorbees++;
          }
          continue;
        }

        final contact = _instant(ligne['dernier_contact']);
        await _db
            .into(_db.clients)
            .insertOnConflictUpdate(
              ClientsCompanion(
                id: Value(id),
                nom: Value(nomClient.trim()),
                telephone: Value(_texteOuNull(ligne['telephone'])),
                dateNaissance: Value(_jour(ligne['date_naissance'])),
                dernierContact: Value(contact),
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
        await (_db.select(_db.clients)
              ..where((c) => c.syncStatus.equals('pending'))
              ..orderBy([(c) => OrderingTerm.asc(c.updatedAt)]))
            .get();
    return [
      for (final c in lignes)
        LigneAEnvoyer(
          id: c.id,
          instantSaisie: c.updatedAt,
          corps: {
            'id': c.id,
            'nom': c.nom,
            'telephone': c.telephone,
            // Date civile : envoyée telle quelle, sans fuseau (sinon une
            // naissance à minuit local reculerait d'un jour en UTC).
            'date_naissance': c.dateNaissance == null
                ? null
                : _formatJour(c.dateNaissance!),
            'dernier_contact': c.dernierContact?.toUtc().toIso8601String(),
            'updated_at': c.updatedAt,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.clients,
    )..where((c) => c.id.equals(id) & c.updatedAt.equals(instantEnvoye))).write(
      const ClientsCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(_db.clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  @override
  Future<int> purger() async {
    final nonEnvoyees = await (_db.select(
      _db.clients,
    )..where((c) => c.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.clients).go();
    return nonEnvoyees.length;
  }

  // ------------------------------------------------------------------ Outils

  String? _texteOuNull(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  DateTime? _instant(Object? v) => v is String ? DateTime.tryParse(v) : null;

  /// `2026-01-31` ou `2026-01-31T00:00:00.000000Z` -> 31 janvier, minuit LOCAL.
  DateTime? _jour(Object? v) {
    if (v is! String || v.length < 10) return null;
    final a = int.tryParse(v.substring(0, 4));
    final m = int.tryParse(v.substring(5, 7));
    final j = int.tryParse(v.substring(8, 10));
    if (a == null || m == null || j == null) return null;
    return DateTime(a, m, j);
  }

  String _formatJour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
