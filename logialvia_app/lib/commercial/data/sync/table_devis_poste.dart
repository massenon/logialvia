import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../../domain/entities/devis_emis.dart';

/// `devis` — fait saisi au poste (ou au web), dernier écrivain gagne par UUID
/// (`46_` §2.3, `47a2_`).
///
/// - La **référence** est le numéro officiel : jamais renumérotée, jamais modifiée.
///   `DV-P2-2026-001` (poste), `DV-2026-001` (poste jamais appairé), `DV-WEB-2026-001`
///   (web). Une ligne dont la référence est déjà prise par un AUTRE devis du poste est
///   refusée (jamais écrasée).
/// - Un devis **accepté** est figé : un contenu différent reçu pour un devis accepté
///   est refusé (seul son statut, ou sa suppression, peut évoluer).
/// - Une pierre tombale (`supprime_le`) CACHE le devis (la ligne reste, pour que le
///   numéro ne soit jamais réutilisé) ; un devis accepté localement ne se laisse pas
///   supprimer par une pierre tombale reçue.
/// - Aucun effet de bord local : ni écriture comptable, ni vente, ni stock.
class TableDevisPoste implements TablePoste {
  const TableDevisPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final RegExp _reference = RegExp(r'^DV-((P\d+|WEB)-)?\d{4}-\d{3,}$');
  static const _statuts = {'emis', 'accepte', 'refuse'};

  @override
  String get nom => 'devis';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications =>
      _db.tableUpdates(TableUpdateQuery.onTable(_db.devis)).map((_) {});

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  /// Strict : une ligne incohérente est refusée, jamais lissée.
  bool _valide(Map<String, dynamic> l) {
    final reference = l['reference'];
    final statut = l['statut'];
    final validite = l['validite_jours'];
    final montant = l['montant_estime'];
    return l['id'] is String &&
        _uuid.hasMatch(l['id'] as String) &&
        reference is String &&
        _reference.hasMatch(reference) &&
        _texte(l['client']) != null &&
        _texte(l['objet']) != null &&
        montant is num &&
        montant > 0 &&
        validite is int &&
        validite >= 1 &&
        l['date_emission'] is String &&
        DateTime.tryParse(l['date_emission'] as String) != null &&
        statut is String &&
        _statuts.contains(statut) &&
        l['updated_at'] is String &&
        DateTime.tryParse(l['updated_at'] as String) != null &&
        (l['supprime_le'] == null ||
            (l['supprime_le'] is String &&
                DateTime.tryParse(l['supprime_le'] as String) != null));
  }

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

        final locale = await (_db.select(
          _db.devis,
        )..where((d) => d.id.equals(id))).getSingleOrNull();

        if (locale == null) {
          final prise = await (_db.select(
            _db.devis,
          )..where((d) => d.reference.equals(reference))).getSingleOrNull();
          if (prise != null) {
            refusees++; // jamais écrasée : le numéro appartient à un autre devis
            continue;
          }
          await _db.into(_db.devis).insert(_companion(l, instant));
          absorbees++;
          continue;
        }

        // La référence ne change JAMAIS pour un même UUID : une anomalie.
        if (locale.reference != reference) {
          refusees++;
          continue;
        }

        var supplantee = false;
        if (locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++; // la saisie locale est plus récente : elle partira
            continue;
          }
          supplantee = true;
        } else {
          // Déjà au même instant ou plus récent : rien à reprendre.
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && instant.isBefore(saisieLocale)) continue;
        }

        final accepteLocalement =
            StatutDevis.depuis(locale.statut) == StatutDevis.accepte;
        final contenuDifferent =
            locale.client != (l['client'] as String).trim() ||
            locale.objet != (l['objet'] as String).trim() ||
            (locale.montantEstime - (l['montant_estime'] as num)).abs() >
                0.0001 ||
            locale.validiteJours != l['validite_jours'];
        // Un devis accepté est figé : ni contenu différent, ni pierre tombale.
        if (accepteLocalement &&
            (contenuDifferent || l['supprime_le'] != null)) {
          refusees++;
          continue;
        }

        await (_db.update(_db.devis)..where((d) => d.id.equals(id))).write(
          DevisCompanion(
            client: Value((l['client'] as String).trim()),
            objet: Value((l['objet'] as String).trim()),
            montantEstime: Value((l['montant_estime'] as num).toDouble()),
            validiteJours: Value(l['validite_jours'] as int),
            dateEmission: Value(DateTime.parse(l['date_emission'] as String)),
            statut: Value(l['statut'] as String),
            supprimeLe: Value(_texte(l['supprime_le'])),
            syncStatus: const Value('synced'),
            syncMotif: const Value(null),
            updatedAt: Value(instant.toUtc().toIso8601String()),
          ),
        );
        absorbees++;
        if (supplantee) supplantees++;
      }
      return ResultatAbsorption(
        absorbees: absorbees,
        refusees: refusees,
        conservees: conservees,
        supplantees: supplantees,
      );
    });
  }

  DevisCompanion _companion(Map<String, dynamic> l, DateTime instant) =>
      DevisCompanion.insert(
        id: Value(l['id'] as String),
        reference: l['reference'] as String,
        client: (l['client'] as String).trim(),
        objet: (l['objet'] as String).trim(),
        montantEstime: (l['montant_estime'] as num).toDouble(),
        validiteJours: Value(l['validite_jours'] as int),
        dateEmission: DateTime.parse(l['date_emission'] as String),
        statut: Value(l['statut'] as String),
        supprimeLe: Value(_texte(l['supprime_le'])),
        syncStatus: const Value('synced'),
        updatedAt: Value(instant.toUtc().toIso8601String()),
      );

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final lignes =
        await (_db.select(_db.devis)
              ..where((d) => d.syncStatus.equals('pending'))
              ..orderBy([(d) => OrderingTerm.asc(d.updatedAt)]))
            .get();
    return [
      for (final d in lignes)
        LigneAEnvoyer(
          id: d.id,
          instantSaisie: d.updatedAt,
          corps: {
            'id': d.id,
            'reference': d.reference,
            'client': d.client,
            'objet': d.objet,
            'montant_estime': d.montantEstime,
            'validite_jours': d.validiteJours,
            'date_emission': d.dateEmission.toUtc().toIso8601String(),
            'statut': d.statut,
            'supprime_le': d.supprimeLe,
            'updated_at': d.updatedAt,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.devis,
    )..where((d) => d.id.equals(id) & d.updatedAt.equals(instantEnvoye))).write(
      const DevisCompanion(syncStatus: Value('synced'), syncMotif: Value(null)),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(_db.devis)..where((d) => d.id.equals(id))).write(
      DevisCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur : les devis sont des faits, ils partent avec lui.
  @override
  Future<int> purger() async {
    final nonEnvoyes = await (_db.select(
      _db.devis,
    )..where((d) => d.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.devis).go();
    return nonEnvoyes.length;
  }
}
