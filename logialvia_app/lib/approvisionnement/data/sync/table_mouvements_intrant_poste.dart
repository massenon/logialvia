import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../../domain/entities/approvisionnement.dart';

/// `mouvements_intrant` — le **journal** des mouvements, fait **immuable**.
///
/// ## Décision du client : « stock propre à chaque poste + journal partagé »
///
/// Le journal est un **historique** que tous les postes se partagent. Il n'est
/// appliqué à **aucun stock** :
/// - envoyer un mouvement ne change rien au stock du serveur (il n'en a pas) ;
/// - **absorber le mouvement d'un autre poste ne change pas le stock de CE poste** :
///   il est stocké avec son `origine` (l'identifiant du poste qui l'a saisi) pour
///   qu'aucun calcul local — inventaire, valorisation — ne le prenne pour le sien.
///
/// Un mouvement ne se modifie jamais : rejoué, il est accepté sans rien changer.
class TableMouvementsIntrantPoste implements TablePoste {
  const TableMouvementsIntrantPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const _types = {
    TypeMouvement.entree,
    TypeMouvement.sortie,
    TypeMouvement.ajustement,
  };

  @override
  String get nom => 'mouvements_intrant';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.mouvementsIntrant))
      .map((_) {});

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;

      for (final l in lignes) {
        final id = l['id'];
        final horodatage = l['horodatage'] is String
            ? DateTime.tryParse(l['horodatage'] as String)
            : null;
        final quantite = l['quantite'];
        // Strict : un mouvement incohérent est refusé, jamais lissé.
        if (id is! String ||
            !_uuid.hasMatch(id) ||
            horodatage == null ||
            _texte(l['intrant_code']) == null ||
            _texte(l['article']) == null ||
            !_types.contains(l['type']) ||
            _texte(l['motif']) == null ||
            quantite is! num ||
            quantite == 0) {
          refusees++;
          continue;
        }

        final connu = await (_db.select(
          _db.mouvementsIntrant,
        )..where((m) => m.id.equals(id))).getSingleOrNull();
        if (connu != null) {
          // Notre propre mouvement qui revient : il est connu du serveur.
          if (connu.syncStatus != 'synced' && connu.origine == null) {
            await marquerSynchronise(id, '');
          }
          continue;
        }

        // L'intrant doit exister ici (clé étrangère) : les intrants arrivent AVANT.
        final intrant =
            await (_db.select(_db.intrants)
                  ..where((i) => i.code.equals(l['intrant_code'] as String)))
                .getSingleOrNull();
        if (intrant == null) {
          refusees++;
          continue;
        }

        await _db
            .into(_db.mouvementsIntrant)
            .insert(
              MouvementsIntrantCompanion.insert(
                id: Value(id),
                horodatage: horodatage.toLocal(),
                intrantCode: l['intrant_code'] as String,
                article: (l['article'] as String).trim(),
                type: l['type'] as String,
                motif: (l['motif'] as String).trim(),
                quantite: quantite.toDouble(),
                reference: Value(_texte(l['reference'])),
                // Le mouvement d'un autre poste : de l'historique, pas du stock.
                origine: Value(_texte(l['device_id']) ?? 'autre-poste'),
                syncStatus: const Value('synced'),
              ),
            );
        // Volontairement : AUCUNE écriture dans `intrants` (stock, PMP).
        absorbees++;
      }
      return ResultatAbsorption(absorbees: absorbees, refusees: refusees);
    });
  }

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final lignes =
        await (_db.select(_db.mouvementsIntrant)
              ..where(
                (m) => m.syncStatus.equals('pending') & m.origine.isNull(),
              )
              ..orderBy([(m) => OrderingTerm.asc(m.horodatage)]))
            .get();
    return [
      for (final m in lignes)
        LigneAEnvoyer(
          id: m.id,
          // Immuable : l'identifiant suffit à l'accusé.
          instantSaisie: '',
          corps: {
            'id': m.id,
            'horodatage': m.horodatage.toUtc().toIso8601String(),
            'intrant_code': m.intrantCode,
            'article': m.article,
            'type': m.type,
            'motif': m.motif,
            'quantite': m.quantite,
            'reference': m.reference,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.mouvementsIntrant,
    )..where((m) => m.id.equals(id))).write(
      const MouvementsIntrantCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(
      _db.mouvementsIntrant,
    )..where((m) => m.id.equals(id))).write(
      MouvementsIntrantCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur : les mouvements d'AUTRES postes partent avec lui ; les
  /// siens (non envoyés) sont comptés comme perdus. ⚠️ Le stock du poste, lui, n'est pas
  /// touché : il est propre à ce poste.
  @override
  Future<int> purger() async {
    final nonEnvoyes =
        await (_db.select(_db.mouvementsIntrant)..where(
              (m) => m.syncStatus.isNotValue('synced') & m.origine.isNull(),
            ))
            .get();
    await _db.delete(_db.mouvementsIntrant).go();
    return nonEnvoyes.length;
  }
}
