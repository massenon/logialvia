import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/effets_stock_poste.dart';
import '../../../core/sync/table_poste.dart';

/// `mouvements_produit` — journal des corrections de stock des produits vendables,
/// fait **immuable** (palier 6).
///
/// Décision du client : « stock propre à chaque poste + journal partagé ». Absorber
/// la correction d'un autre poste **ne change pas le stock de CE poste** : la ligne est
/// stockée avec son `origine`, comme un historique. Rejoué, un mouvement est accepté
/// sans rien changer. Le produit doit exister ici (il arrive AVANT, référentiel).
///
/// ## Exception à la règle d'or (`47s_`)
///
/// Une correction saisie au web peut porter `poste_cible` : le poste désigné — et lui
/// seul — ajoute la variation à SON stock, **une fois** (plancher à 0 et avertissement tracé).
/// Pour tous les autres postes, la ligne reste de l'historique pur.
class TableMouvementsProduitPoste implements TablePoste {
  const TableMouvementsProduitPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  String get nom => 'mouvements_produit';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.mouvementsProduit))
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
        final produitId = l['produit_id'];
        final horodatage = l['horodatage'] is String
            ? DateTime.tryParse(l['horodatage'] as String)
            : null;
        final quantite = l['quantite'];
        // Strict : un mouvement incohérent est refusé, jamais lissé.
        if (id is! String ||
            !_uuid.hasMatch(id) ||
            produitId is! String ||
            !_uuid.hasMatch(produitId) ||
            horodatage == null ||
            _texte(l['article']) == null ||
            _texte(l['motif']) == null ||
            quantite is! num ||
            quantite == 0 ||
            (l['poste_cible'] != null &&
                (l['poste_cible'] is! String ||
                    !_uuid.hasMatch(l['poste_cible'] as String)))) {
          refusees++;
          continue;
        }

        final connu = await (_db.select(
          _db.mouvementsProduit,
        )..where((m) => m.id.equals(id))).getSingleOrNull();
        if (connu != null) {
          // Notre propre mouvement qui revient : il est connu du serveur.
          if (connu.syncStatus != 'synced' && connu.origine == null) {
            await marquerSynchronise(id, '');
          }
          continue;
        }

        final produit = await (_db.select(
          _db.produitsVendables,
        )..where((p) => p.id.equals(produitId))).getSingleOrNull();
        if (produit == null) {
          refusees++;
          continue;
        }

        await _db
            .into(_db.mouvementsProduit)
            .insert(
              MouvementsProduitCompanion.insert(
                id: Value(id),
                horodatage: horodatage.toLocal(),
                produitId: produitId,
                article: (l['article'] as String).trim(),
                motif: (l['motif'] as String).trim(),
                quantite: quantite.toDouble(),
                // Historique d'un autre poste : AUCUNE écriture dans le stock.
                origine: Value(_texte(l['device_id']) ?? 'autre-poste'),
                posteCible: Value(_texte(l['poste_cible'])),
                syncStatus: const Value('synced'),
              ),
            );
        // Sauf si CE poste est le poste désigné : alors, et alors seulement, la
        // variation s'applique à son stock (une fois : journal `effets_appliques`).
        final effets = EffetsStockPoste(_db);
        if (await effets.estCible(_texte(l['poste_cible']))) {
          await effets.appliquerCorrection(
            mouvementId: id,
            produitId: produitId,
            article: (l['article'] as String).trim(),
            motif: (l['motif'] as String).trim(),
            variation: quantite.toDouble(),
          );
        }
        absorbees++;
      }
      return ResultatAbsorption(absorbees: absorbees, refusees: refusees);
    });
  }

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final lignes =
        await (_db.select(_db.mouvementsProduit)
              ..where(
                (m) => m.syncStatus.equals('pending') & m.origine.isNull(),
              )
              ..orderBy([(m) => OrderingTerm.asc(m.horodatage)]))
            .get();
    return [
      for (final m in lignes)
        LigneAEnvoyer(
          id: m.id,
          instantSaisie: '',
          corps: {
            'id': m.id,
            'horodatage': m.horodatage.toUtc().toIso8601String(),
            'produit_id': m.produitId,
            'article': m.article,
            'motif': m.motif,
            'quantite': m.quantite,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.mouvementsProduit,
    )..where((m) => m.id.equals(id))).write(
      const MouvementsProduitCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(
      _db.mouvementsProduit,
    )..where((m) => m.id.equals(id))).write(
      MouvementsProduitCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur : le journal part (celui des autres aussi) ; les
  /// corrections non envoyées de ce poste sont comptées comme perdues. ⚠️ Le stock du
  /// poste n'est pas touché : il lui est propre.
  @override
  Future<int> purger() async {
    final nonEnvoyes =
        await (_db.select(_db.mouvementsProduit)..where(
              (m) => m.syncStatus.isNotValue('synced') & m.origine.isNull(),
            ))
            .get();
    await _db.delete(_db.mouvementsProduit).go();
    return nonEnvoyes.length;
  }
}
