import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../../domain/entities/soin.dart';
import 'table_soins_poste.dart';

/// `infirmerie` — **fait** saisi au poste, dernier écrivain gagne (`46_` §2.3, `46c_`).
///
/// - **Absorbeur strict** : une ligne incohérente (statut inconnu, sortie avant
///   l'entrée, marque de mortalité sur un sujet non décédé…) est REFUSÉE et comptée.
/// - **Aucun effet de bord** : absorber un décès venu d'un autre poste ne le REPORTE
///   PAS dans la fiche d'élevage d'ici (c'est l'effet du poste qui a déclaré le
///   décès). Sa marque `categorie_mortalite` est en revanche absorbée telle quelle :
///   elle dit « ce décès est déjà compté », ce qui empêche ce poste de le reporter une
///   seconde fois à la main.
class TableInfirmeriePoste implements TablePoste {
  const TableInfirmeriePoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static const List<String> _statuts = [
    StatutInfirmerie.enCours,
    StatutInfirmerie.reintegre,
    StatutInfirmerie.decede,
  ];

  @override
  String get nom => 'infirmerie';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications =>
      _db.tableUpdates(TableUpdateQuery.onTable(_db.infirmerie)).map((_) {});

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        final id = l['id'];
        final instant = l['updated_at'] is String
            ? DateTime.tryParse(l['updated_at'] as String)
            : null;
        final entree = _jour(l['date_entree']);
        final sortie = l['date_sortie'] == null
            ? null
            : _jour(l['date_sortie']);
        final sujet = _texte(l['sujet']);
        final motif = _texte(l['motif']);
        final niveau = _texte(l['niveau_isolement']);
        final statut = _texte(l['statut']);
        final categorie = l['categorie_mortalite'];
        // Strict : une ligne incohérente est refusée, jamais lissée.
        if (id is! String ||
            !_uuid.hasMatch(id) ||
            instant == null ||
            entree == null ||
            (l['date_sortie'] != null && sortie == null) ||
            sujet == null ||
            motif == null ||
            niveau == null ||
            !NiveauIsolement.tous.contains(niveau) ||
            statut == null ||
            !_statuts.contains(statut) ||
            (sortie != null && sortie.isBefore(entree)) ||
            (statut != StatutInfirmerie.enCours && sortie == null) ||
            (statut == StatutInfirmerie.enCours && sortie != null) ||
            (categorie != null &&
                (categorie is! int ||
                    categorie < 0 ||
                    statut != StatutInfirmerie.decede))) {
          refusees++;
          continue;
        }

        final locale = await (_db.select(
          _db.infirmerie,
        )..where((i) => i.id.equals(id))).getSingleOrNull();
        if (locale != null && locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++; // la saisie locale est plus récente : elle gagnera
            continue;
          }
          supplantees++; // le serveur a une version strictement plus récente
        }

        await _db
            .into(_db.infirmerie)
            .insertOnConflictUpdate(
              InfirmerieCompanion(
                id: Value(id),
                dateEntree: Value(entree),
                sujet: Value(sujet),
                motif: Value(motif),
                niveauIsolement: Value(niveau),
                statut: Value(statut),
                dateSortie: Value(sortie),
                espece: Value(_texte(l['espece'])),
                categorieMortalite: Value(categorie as int?),
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
        await (_db.select(_db.infirmerie)
              ..where((i) => i.syncStatus.equals('pending'))
              ..orderBy([(i) => OrderingTerm.asc(i.updatedAt)]))
            .get();
    return [
      for (final i in lignes)
        LigneAEnvoyer(
          id: i.id,
          instantSaisie: i.updatedAt,
          corps: {
            'id': i.id,
            'date_entree': TableSoinsPoste.formatJour(i.dateEntree),
            'sujet': i.sujet,
            'motif': i.motif,
            'niveau_isolement': i.niveauIsolement,
            'statut': i.statut,
            'date_sortie': i.dateSortie == null
                ? null
                : TableSoinsPoste.formatJour(i.dateSortie!),
            'espece': i.espece,
            'categorie_mortalite': i.categorieMortalite,
            'updated_at': i.updatedAt,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.infirmerie,
    )..where((i) => i.id.equals(id) & i.updatedAt.equals(instantEnvoye))).write(
      const InfirmerieCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(_db.infirmerie)..where((i) => i.id.equals(id))).write(
      InfirmerieCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  @override
  Future<int> purger() async {
    final nonEnvoyees = await (_db.select(
      _db.infirmerie,
    )..where((i) => i.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.infirmerie).go();
    return nonEnvoyees.length;
  }

  // ------------------------------------------------------------------ Outils

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  /// `2026-01-31` ou `2026-01-31T00:00:00.000000Z` -> 31 janvier, minuit LOCAL.
  static DateTime? _jour(Object? v) {
    if (v is! String || v.length < 10) return null;
    final a = int.tryParse(v.substring(0, 4));
    final m = int.tryParse(v.substring(5, 7));
    final j = int.tryParse(v.substring(8, 10));
    if (a == null || m == null || j == null) return null;
    if (m < 1 || m > 12 || j < 1 || j > 31) return null;
    return DateTime(a, m, j);
  }
}
