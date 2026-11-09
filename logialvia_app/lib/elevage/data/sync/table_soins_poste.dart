import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../../domain/entities/soin.dart';

/// `soins_calendrier` — **fait** saisi au poste, dernier écrivain gagne (`46_` §2.3,
/// `46c_`).
///
/// - **Absorbeur strict** : UUID, instant, espèce, date, type d'action (texte LIBRE :
///   « Planifier une Intervention » le saisit tel quel, hors des 4 types du registre),
///   statut, rémanence et coût sont vérifiés ; une ligne incohérente est REFUSÉE et comptée,
///   jamais lissée.
/// - **Aucun effet de bord** : absorber le soin d'un autre poste n'écrit que la ligne
///   (ni stock, ni compteur de fiche, ni écriture comptable, ni événement) — ce que
///   fait `confirmerAdministration` est une simple écriture de statut.
/// - **`bande_id` ne voyage pas** : les bandes ne sont pas encore synchronisées, un
///   entier de bande n'aurait aucun sens sur un autre poste. Le soin reçu arrive sans
///   bande ; le lien local d'une ligne déjà connue n'est JAMAIS effacé.
/// - Un soin n'est jamais supprimé au poste (pas de pierre tombale).
class TableSoinsPoste implements TablePoste {
  const TableSoinsPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  String get nom => 'soins_calendrier';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.soinsCalendrier))
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
        final instant = l['updated_at'] is String
            ? DateTime.tryParse(l['updated_at'] as String)
            : null;
        final espece = _texte(l['espece']);
        final jour = _jour(l['date_prevue']);
        final type = _texte(l['type_soin']);
        final statut = _texte(l['statut']);
        final remanence = l['remanence_jours'];
        final cout = l['cout_fcfa'];
        final echeance = l['echeance_prophylaxie_id'];
        // Strict : une ligne incohérente est refusée, jamais lissée.
        if (id is! String ||
            !_uuid.hasMatch(id) ||
            instant == null ||
            espece == null ||
            jour == null ||
            type == null ||
            statut == null ||
            !StatutSoin.tous.contains(statut) ||
            (remanence != null && (remanence is! int || remanence < 0)) ||
            (cout != null && (cout is! int || cout < 0)) ||
            (echeance != null &&
                (echeance is! String || !_uuid.hasMatch(echeance)))) {
          refusees++;
          continue;
        }

        final locale = await (_db.select(
          _db.soinsCalendrier,
        )..where((s) => s.id.equals(id))).getSingleOrNull();
        if (locale != null && locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++; // la saisie locale est plus récente : elle gagnera
            continue;
          }
          supplantees++; // le serveur a une version strictement plus récente
        }

        await _db
            .into(_db.soinsCalendrier)
            .insertOnConflictUpdate(
              SoinsCalendrierCompanion(
                id: Value(id),
                espece: Value(espece),
                datePrevue: Value(jour),
                typeSoin: Value(type),
                statut: Value(statut),
                observations: Value(_texte(l['observations'])),
                produit: Value(_texte(l['produit'])),
                dose: Value(_texte(l['dose'])),
                remanenceJours: Value(remanence as int? ?? 0),
                veterinaire: Value(_texte(l['veterinaire'])),
                symptomes: Value(_texte(l['symptomes'])),
                coutFcfa: Value(cout as int? ?? 0),
                echeanceProphylaxieId: Value(echeance as String?),
                // `bandeId` : volontairement absent — local à ce poste.
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
        await (_db.select(_db.soinsCalendrier)
              ..where((s) => s.syncStatus.equals('pending'))
              ..orderBy([(s) => OrderingTerm.asc(s.updatedAt)]))
            .get();
    return [
      for (final s in lignes)
        LigneAEnvoyer(
          id: s.id,
          instantSaisie: s.updatedAt,
          corps: {
            'id': s.id,
            'espece': s.espece,
            // Date civile : envoyée telle quelle, sans fuseau.
            'date_prevue': formatJour(s.datePrevue),
            'type_soin': s.typeSoin,
            'statut': s.statut,
            'observations': s.observations,
            'produit': s.produit,
            'dose': s.dose,
            'remanence_jours': s.remanenceJours,
            'veterinaire': s.veterinaire,
            'symptomes': s.symptomes,
            'cout_fcfa': s.coutFcfa,
            'echeance_prophylaxie_id': s.echeanceProphylaxieId,
            'updated_at': s.updatedAt,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.soinsCalendrier,
    )..where((s) => s.id.equals(id) & s.updatedAt.equals(instantEnvoye))).write(
      const SoinsCalendrierCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(
      _db.soinsCalendrier,
    )..where((s) => s.id.equals(id))).write(
      SoinsCalendrierCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  @override
  Future<int> purger() async {
    final nonEnvoyes = await (_db.select(
      _db.soinsCalendrier,
    )..where((s) => s.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.soinsCalendrier).go();
    return nonEnvoyes.length;
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

  /// Date civile `AAAA-MM-JJ`.
  static String formatJour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
