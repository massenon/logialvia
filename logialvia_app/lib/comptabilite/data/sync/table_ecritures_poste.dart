import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';

/// `ecriture_comptable` — les écritures sont des **FAITS IMMUABLES** (`46d_` §2, §3).
///
/// ## Une pièce voyage entière
///
/// L'unité n'est pas la ligne mais la **pièce** (partie double) : ses lignes partent
/// dans un même corps (`lignes: [...]`) et arrivent de même. Le serveur vérifie
/// qu'elle est équilibrée (débit = crédit) et l'accepte ou la refuse **tout entière**.
///
/// ## Ce qu'absorber la pièce d'un autre poste ne fait PAS
///
/// Aucune écriture locale n'est générée : la vente ou l'achat d'un autre poste est
/// **connu** ici (`ventes`, `achats`) mais n'a aucun effet comptable local ; son écriture
/// à lui arrive comme son propre fait, avec son `origine`. Le grand livre et la balance
/// de chaque poste sont donc la somme de TOUS les faits : ni double comptage, ni trou.
///
/// Une pièce ne change jamais après acceptation : rejouée, elle est acceptée sans rien
/// changer. Se corriger, c'est passer la pièce inverse (`contrepasse_de`).
class TableEcrituresPoste implements TablePoste {
  const TableEcrituresPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const _journaux = {'VT', 'AC', 'CA', 'OD'};
  static const double _tolerance = 0.01;

  @override
  String get nom => 'ecriture_comptable';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.ecritureComptable))
      .map((_) {});

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  static bool _uuidValide(Object? v) => v is String && _uuid.hasMatch(v);

  /// Une pièce reçue est-elle cohérente ? Partie double stricte, comptes valides.
  bool _valide(Map<String, dynamic> p) {
    final lignes = p['lignes'];
    if (!_uuidValide(p['id']) ||
        p['date_ecriture'] is! String ||
        DateTime.tryParse(p['date_ecriture'] as String) == null ||
        p['updated_at'] is! String ||
        DateTime.tryParse(p['updated_at'] as String) == null ||
        p['exercice_annee'] is! int ||
        !_journaux.contains(p['journal_code']) ||
        (p['contrepasse_de'] != null && !_uuidValide(p['contrepasse_de'])) ||
        lignes is! List ||
        lignes.length < 2) {
      return false;
    }
    var debit = 0.0;
    var credit = 0.0;
    for (final x in lignes) {
      if (x is! Map ||
          !_uuidValide(x['id']) ||
          _texte(x['numero_compte']) == null ||
          _texte(x['libelle']) == null ||
          x['debit'] is! num ||
          x['credit'] is! num) {
        return false;
      }
      final d = (x['debit'] as num).toDouble();
      final c = (x['credit'] as num).toDouble();
      // Partie double : exactement un des deux est strictement positif.
      if (d < 0 || c < 0 || (d > 0) == (c > 0)) return false;
      debit += d;
      credit += c;
    }
    return (debit - credit).abs() <= _tolerance;
  }

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;

      for (final p in lignes) {
        if (!_valide(p)) {
          refusees++;
          continue;
        }
        final pieceId = p['id'] as String;
        final annee = p['exercice_annee'] as int;
        final lignesPiece = (p['lignes'] as List).cast<Map<String, dynamic>>();

        final connue =
            await (_db.select(_db.ecritureComptable)
                  ..where((e) => e.pieceId.equals(pieceId))
                  ..limit(1))
                .getSingleOrNull();
        if (connue != null) {
          // Notre propre pièce qui revient : le serveur la connaît.
          if (connue.origine == null && connue.syncStatus != 'synced') {
            await marquerSynchronise(pieceId, '');
          }
          continue;
        }

        // Les exercices et le plan arrivent AVANT les écritures : un exercice ou un
        // compte toujours inconnu rend la pièce inexploitable ici.
        final exercice = await (_db.select(
          _db.exerciceComptable,
        )..where((e) => e.annee.equals(annee))).getSingleOrNull();
        var comptesConnus = exercice != null;
        for (final x in lignesPiece) {
          final c =
              await (_db.select(_db.planComptable)..where(
                    (c) => c.numeroCompte.equals(x['numero_compte'] as String),
                  ))
                  .getSingleOrNull();
          if (c == null) comptesConnus = false;
        }
        if (!comptesConnus) {
          refusees++;
          continue;
        }

        final origine = _texte(p['device_id']) ?? 'autre-poste';
        final date = DateTime.parse(p['date_ecriture'] as String).toLocal();
        for (final x in lignesPiece) {
          await _db
              .into(_db.ecritureComptable)
              .insert(
                EcritureComptableCompanion.insert(
                  id: Value(x['id'] as String),
                  pieceId: Value(pieceId),
                  exerciceAnnee: annee,
                  numeroCompte: x['numero_compte'] as String,
                  dateEcriture: date,
                  debit: Value((x['debit'] as num).toDouble()),
                  credit: Value((x['credit'] as num).toDouble()),
                  libelle: (x['libelle'] as String).trim(),
                  journalCode: Value(p['journal_code'] as String),
                  numeroPiece: Value(_texte(p['numero_piece'])),
                  venteRef: Value(_texte(p['vente_ref'])),
                  achatRef: Value(_texte(p['achat_ref'])),
                  axeAnalytique: Value(_texte(x['axe_analytique'])),
                  contrepasseDe: Value(_texte(p['contrepasse_de'])),
                  isLocked: Value(exercice!.isCloture),
                  // La pièce d'un autre poste : de l'historique partagé, aucune
                  // écriture locale n'en découle.
                  origine: Value(origine),
                  syncStatus: const Value('synced'),
                  updatedAt: Value(
                    DateTime.parse(
                      p['updated_at'] as String,
                    ).toUtc().toIso8601String(),
                  ),
                ),
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
        await (_db.select(_db.ecritureComptable)
              ..where(
                (e) => e.syncStatus.equals('pending') & e.origine.isNull(),
              )
              ..orderBy([
                (e) => OrderingTerm.asc(e.updatedAt),
                (e) => OrderingTerm.asc(e.pieceId),
                (e) => OrderingTerm.asc(e.id),
              ]))
            .get();

    final pieces = <String, List<EcritureRow>>{};
    for (final l in lignes) {
      pieces.putIfAbsent(l.pieceId, () => []).add(l);
    }

    return [
      for (final entree in pieces.entries)
        LigneAEnvoyer(
          id: entree.key,
          instantSaisie: entree.value.first.updatedAt,
          corps: {
            'id': entree.key,
            'numero_piece': entree.value.first.numeroPiece,
            'date_ecriture': entree.value.first.dateEcriture
                .toUtc()
                .toIso8601String(),
            'exercice_annee': entree.value.first.exerciceAnnee,
            'journal_code': entree.value.first.journalCode,
            'vente_ref': entree.value.first.venteRef,
            'achat_ref': entree.value.first.achatRef,
            'contrepasse_de': entree.value.first.contrepasseDe,
            'updated_at': entree.value.first.updatedAt,
            'lignes': [
              for (final x in entree.value)
                {
                  'id': x.id,
                  'numero_compte': x.numeroCompte,
                  'debit': x.debit,
                  'credit': x.credit,
                  'libelle': x.libelle,
                  'axe_analytique': x.axeAnalytique,
                },
            ],
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    // Immuable : l'instant ne sert qu'à ne pas écraser une pièce REMPLACÉE entre-temps
    // (une pièce refusée puis corrigée garde son identité, pas son instant).
    final requete = _db.update(_db.ecritureComptable)
      ..where(
        (e) =>
            e.pieceId.equals(id) &
            (instantEnvoye.isEmpty
                ? const Constant(true)
                : e.updatedAt.equals(instantEnvoye)),
      );
    await requete.write(
      const EcritureComptableCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(
      _db.ecritureComptable,
    )..where((e) => e.pieceId.equals(id))).write(
      EcritureComptableCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur : les écritures (de ce poste comme des autres) partent
  /// avec lui ; celles de ce poste non acceptées sont comptées comme perdues.
  @override
  Future<int> purger() async {
    final nonEnvoyees =
        await (_db.select(_db.ecritureComptable)..where(
              (e) => e.syncStatus.isNotValue('synced') & e.origine.isNull(),
            ))
            .get();
    await _db.delete(_db.ecritureComptable).go();
    return nonEnvoyees.map((e) => e.pieceId).toSet().length;
  }
}
