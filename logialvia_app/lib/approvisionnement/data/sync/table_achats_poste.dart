import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../../../commercial/domain/entities/vente.dart';
import '../../domain/entities/approvisionnement.dart';

/// `achats` + `lignes_achat` — **faits** saisis au poste, jamais fusionnés
/// (`46_` §2.3). Mêmes règles que les ventes :
///
/// - un achat et ses lignes ne se séparent jamais (un seul corps, une seule
///   transaction) ;
/// - absorber l'achat d'un autre poste ne produit **aucun effet** : ni entrée de
///   stock, ni recalcul du PMP, ni mouvement journalisé, ni écriture comptable (la
///   réception appartient au poste qui a reçu la marchandise) ;
/// - les lignes sont **immuables** ; l'entête (statut, montant payé) suit « dernier
///   écrivain gagne » ; la référence ne change jamais.
class TableAchatsPoste implements TablePoste {
  const TableAchatsPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final RegExp _reference = RegExp(r'^ACH-(P\d+-)?\d{4}-\d{3,}$');

  @override
  String get nom => 'achats';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications =>
      _db.tableUpdates(TableUpdateQuery.onTable(_db.achats)).map((_) {});

  static const _statuts = {
    StatutAchat.commande,
    StatutAchat.livre,
    StatutAchat.annule,
  };
  static const _modes = {
    ModeReglement.especes,
    ModeReglement.mobileMoney,
    ModeReglement.nonPrecise,
  };

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  bool _valide(Map<String, dynamic> l) {
    final lignes = l['lignes'];
    if (l['id'] is! String ||
        !_uuid.hasMatch(l['id'] as String) ||
        l['reference'] is! String ||
        !_reference.hasMatch(l['reference'] as String) ||
        l['fournisseur_id'] is! String ||
        !_uuid.hasMatch(l['fournisseur_id'] as String) ||
        l['date_achat'] is! String ||
        DateTime.tryParse(l['date_achat'] as String) == null ||
        l['updated_at'] is! String ||
        DateTime.tryParse(l['updated_at'] as String) == null ||
        !_statuts.contains(l['statut']) ||
        (l['mode'] != null && !_modes.contains(l['mode'])) ||
        l['total'] is! num ||
        (l['total'] as num) < 0 ||
        l['paye'] is! num ||
        (l['paye'] as num) < 0 ||
        (l['paye'] as num) > (l['total'] as num) + 0.005 ||
        lignes is! List ||
        lignes.isEmpty) {
      return false;
    }
    for (final x in lignes) {
      if (x is! Map ||
          x['id'] is! String ||
          !_uuid.hasMatch(x['id'] as String) ||
          _texte(x['intrant_code']) == null ||
          _texte(x['nom']) == null ||
          x['qte'] is! num ||
          (x['qte'] as num) <= 0 ||
          x['pu_achat'] is! num ||
          (x['pu_achat'] as num) < 0) {
        return false;
      }
    }
    return true;
  }

  DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        if (!_valide(l)) {
          refusees++;
          continue;
        }
        final id = l['id'] as String;
        final reference = l['reference'] as String;
        final instant = DateTime.parse(l['updated_at'] as String);
        final lignesAchat = (l['lignes'] as List).cast<Map<String, dynamic>>();

        final locale = await (_db.select(
          _db.achats,
        )..where((a) => a.id.equals(id))).getSingleOrNull();

        if (locale == null) {
          // Le fournisseur arrive AVANT l'achat ; chaque intrant doit exister ici
          // (la clé étrangère de la ligne le exige).
          final fournisseur =
              await (_db.select(_db.fournisseurs)
                    ..where((f) => f.id.equals(l['fournisseur_id'] as String)))
                  .getSingleOrNull();
          var intrantsConnus = true;
          for (final x in lignesAchat) {
            final i =
                await (_db.select(
                      _db.intrants,
                    )..where((i) => i.code.equals(x['intrant_code'] as String)))
                    .getSingleOrNull();
            if (i == null) intrantsConnus = false;
          }
          // `ref` est la clé primaire locale : une ancienne référence sans code déjà
          // prise par une AUTRE vente de ce poste ne peut pas coexister ici.
          final prise = await (_db.select(
            _db.achats,
          )..where((a) => a.ref.equals(reference))).getSingleOrNull();
          if (fournisseur == null || !intrantsConnus || prise != null) {
            refusees++;
            continue;
          }

          await _db
              .into(_db.achats)
              .insert(
                AchatsCompanion.insert(
                  id: Value(id),
                  ref: reference,
                  fournisseurId: l['fournisseur_id'] as String,
                  dateAchat: DateTime.parse(
                    l['date_achat'] as String,
                  ).toLocal(),
                  statut: l['statut'] as String,
                  total: (l['total'] as num).toDouble(),
                  paye: Value((l['paye'] as num).toDouble()),
                  mode: Value(_texte(l['mode'])),
                  echeance: Value(_date(l['echeance'])),
                  syncStatus: const Value('synced'),
                  updatedAt: Value(instant.toUtc().toIso8601String()),
                ),
              );
          for (final x in lignesAchat) {
            await _db
                .into(_db.lignesAchat)
                .insert(
                  LignesAchatCompanion.insert(
                    id: Value(x['id'] as String),
                    achatRef: reference,
                    intrantCode: x['intrant_code'] as String,
                    nom: (x['nom'] as String).trim(),
                    qte: (x['qte'] as num).toDouble(),
                    puAchat: (x['pu_achat'] as num).toDouble(),
                  ),
                );
          }
          absorbees++;
          continue;
        }

        // Achat déjà connu : règle du plus récent, comme le serveur.
        if (locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++;
            continue;
          }
          supplantees++;
        }
        final identique =
            locale.statut == l['statut'] &&
            locale.paye == (l['paye'] as num).toDouble() &&
            locale.total == (l['total'] as num).toDouble() &&
            locale.syncStatus == 'synced';
        if (identique) continue;

        await (_db.update(_db.achats)..where((a) => a.id.equals(id))).write(
          AchatsCompanion(
            statut: Value(l['statut'] as String),
            total: Value((l['total'] as num).toDouble()),
            paye: Value((l['paye'] as num).toDouble()),
            mode: Value(_texte(l['mode'])),
            echeance: Value(_date(l['echeance'])),
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
    final achats =
        await (_db.select(_db.achats)
              ..where((a) => a.syncStatus.equals('pending'))
              ..orderBy([(a) => OrderingTerm.asc(a.updatedAt)]))
            .get();
    final envoi = <LigneAEnvoyer>[];
    for (final a in achats) {
      final lignes = await (_db.select(
        _db.lignesAchat,
      )..where((x) => x.achatRef.equals(a.ref))).get();
      envoi.add(
        LigneAEnvoyer(
          id: a.id,
          instantSaisie: a.updatedAt,
          corps: {
            'id': a.id,
            'reference': a.ref,
            'fournisseur_id': a.fournisseurId,
            'date_achat': a.dateAchat.toUtc().toIso8601String(),
            'statut': a.statut,
            'total': a.total,
            'paye': a.paye,
            'mode': a.mode,
            'echeance': a.echeance?.toUtc().toIso8601String(),
            'updated_at': a.updatedAt,
            'lignes': [
              for (final x in lignes)
                {
                  'id': x.id,
                  'intrant_code': x.intrantCode,
                  'nom': x.nom,
                  'qte': x.qte,
                  'pu_achat': x.puAchat,
                },
            ],
          },
        ),
      );
    }
    return envoi;
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.achats,
    )..where((a) => a.id.equals(id) & a.updatedAt.equals(instantEnvoye))).write(
      const AchatsCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(_db.achats)..where((a) => a.id.equals(id))).write(
      AchatsCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur : les achats (et leurs lignes) partent avec lui.
  /// ⚠️ Stock, PMP, mouvements et écritures du poste restent (autres paliers).
  @override
  Future<int> purger() async {
    final nonEnvoyes = await (_db.select(
      _db.achats,
    )..where((a) => a.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.lignesAchat).go();
    await _db.delete(_db.achats).go();
    return nonEnvoyes.length;
  }
}
