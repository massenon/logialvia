import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'effets_stock_poste.dart';
import 'table_poste.dart';

/// `effets_stock` (table locale `effets_appliques`) — la **trace** des effets de stock qu'un
/// poste a appliqués parce que le web le désignait (`47s_`). Fait **immuable**.
///
/// Elle remonte au serveur pour que le web sache, pour chaque commande, vente ou correction,
/// si son poste de stock l'a **appliquée** (et avec quel avertissement) ou si elle **attend**
/// encore la prochaine synchronisation de ce poste.
///
/// Un effet reçu d'un autre poste est de l'**historique** : stocké avec son `origine`, il
/// ne touche aucun stock. Un effet qui porte l'identifiant DE CE POSTE (tirage complet sur
/// une base restaurée) redevient le sien : il prouve que l'effet a déjà été appliqué ici.
class TableEffetsStockPoste implements TablePoste {
  const TableEffetsStockPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const _faits = {
    EffetsStockPoste.faitAchat,
    EffetsStockPoste.faitVente,
    EffetsStockPoste.faitCorrection,
  };
  static const _natures = {
    EffetsStockPoste.reception,
    EffetsStockPoste.annulationReception,
    EffetsStockPoste.vente,
    EffetsStockPoste.annulationVente,
    EffetsStockPoste.correction,
  };
  static const _etats = {
    EffetsStockPoste.etatApplique,
    EffetsStockPoste.etatAvertissement,
    EffetsStockPoste.etatIgnore,
  };

  @override
  String get nom => 'effets_stock';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.effetsAppliques))
      .map((_) {});

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      final moi = await EffetsStockPoste(_db).identifiantLocal();

      for (final l in lignes) {
        final id = l['id'];
        final faitId = l['fait_id'];
        final nature = l['nature'];
        // Strict : un effet incohérent est refusé, jamais lissé. L'identifiant doit être
        // celui qu'on calcule de (fait, nature) : un autre poste ne peut pas en forger.
        if (id is! String ||
            !_uuid.hasMatch(id) ||
            faitId is! String ||
            !_uuid.hasMatch(faitId) ||
            !_faits.contains(l['fait_type']) ||
            !_natures.contains(nature) ||
            id != EffetsStockPoste.idEffet(faitId, nature as String) ||
            !_etats.contains(l['etat']) ||
            _texte(l['libelle']) == null ||
            l['applique_le'] is! String ||
            DateTime.tryParse(l['applique_le'] as String) == null) {
          refusees++;
          continue;
        }

        final connu = await (_db.select(
          _db.effetsAppliques,
        )..where((e) => e.id.equals(id))).getSingleOrNull();
        if (connu != null) {
          // Notre propre effet qui revient : il est connu du serveur.
          if (connu.syncStatus != 'synced' && connu.origine == null) {
            await marquerSynchronise(id, '');
          }
          continue;
        }

        final emetteur = _texte(l['device_id']);
        final estLeMien = emetteur != null && emetteur == moi;
        await _db
            .into(_db.effetsAppliques)
            .insert(
              EffetsAppliquesCompanion.insert(
                id: id,
                faitType: l['fait_type'] as String,
                faitId: faitId,
                nature: nature,
                reference: Value(_texte(l['reference'])),
                libelle: (l['libelle'] as String).trim(),
                etat: l['etat'] as String,
                avertissement: Value(_texte(l['avertissement'])),
                appliqueLe: Value(l['applique_le'] as String),
                // Historique d'un autre poste : AUCUNE écriture dans le stock.
                origine: Value(estLeMien ? null : (emetteur ?? 'autre-poste')),
                syncStatus: const Value('synced'),
              ),
            );
        absorbees++;
      }
      return ResultatAbsorption(absorbees: absorbees, refusees: refusees);
    });
  }

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final lignes =
        await (_db.select(_db.effetsAppliques)
              ..where(
                (e) => e.syncStatus.equals('pending') & e.origine.isNull(),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.appliqueLe)]))
            .get();
    return [
      for (final e in lignes)
        LigneAEnvoyer(
          id: e.id,
          // Immuable : l'identifiant suffit à l'accusé.
          instantSaisie: '',
          corps: {
            'id': e.id,
            'fait_type': e.faitType,
            'fait_id': e.faitId,
            'nature': e.nature,
            'reference': e.reference,
            'libelle': e.libelle,
            'etat': e.etat,
            'avertissement': e.avertissement,
            'applique_le': e.appliqueLe,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.effetsAppliques,
    )..where((e) => e.id.equals(id))).write(
      const EffetsAppliquesCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(
      _db.effetsAppliques,
    )..where((e) => e.id.equals(id))).write(
      EffetsAppliquesCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur : les faits du web partent avec lui, leur trace aussi. ⚠️ Le
  /// stock du poste, lui, n'est pas touché : il est propre à ce poste.
  @override
  Future<int> purger() async {
    final nonEnvoyes =
        await (_db.select(_db.effetsAppliques)..where(
              (e) => e.syncStatus.isNotValue('synced') & e.origine.isNull(),
            ))
            .get();
    await _db.delete(_db.effetsAppliques).go();
    return nonEnvoyes.length;
  }
}
