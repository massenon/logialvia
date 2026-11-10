import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../../domain/entities/cycle_incubation.dart';

/// `cycle_couveuse` — les lots d'incubation et leurs mirages : un FAIT saisi au
/// poste, **dernier écrivain gagne** par UUID (`46_` §2.3, `46b_`).
///
/// Les mirages ne sont pas une table : ce sont deux colonnes du lot
/// (`oeufs_blancs_j7`, `oeufs_gates_j14`), saisies dans le temps. Une saisie de
/// mirage est donc une MODIFICATION du lot, avec son nouvel instant de saisie.
///
/// ## Règle d'or : absorber le fait d'un autre poste n'a AUCUN effet de bord
///
/// Un lot reçu est de l'historique : aucun poussin n'entre dans une fiche d'élevage
/// (`fiche_journee` n'est jamais touchée), aucun stock, aucune écriture, aucun
/// événement. Les naissances d'un lot sont portées par les faits de la filière
/// (autre tranche), pas par le lot.
///
/// ## Suppression
///
/// Supprimer un lot au poste le range en corbeille. La suppression voyage comme une
/// **pierre tombale** : l'instantané de la corbeille (qui porte l'instant de la
/// suppression) repart au serveur avec `supprime_le`. Restaurer le lot lève la pierre
/// tombale (il repart, daté de maintenant). Une corbeille vidée avant l'envoi perd la
/// pierre tombale (limite documentée).
class TableCyclesCouveusePoste implements TablePoste {
  const TableCyclesCouveusePoste(this._db);

  final AppDatabase _db;

  static const String _tableArchivee = 'cycle_couveuse';

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  String get nom => 'cycle_couveuse';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([_db.cycleCouveuse, _db.corbeille]),
      )
      .map((_) {});

  // ------------------------------------------------------------- Absorption

  /// Vrai si les compteurs du lot se contredisent. Mêmes règles que l'écran
  /// (`CycleCouveuseViewModel`) et que le serveur : un mirage ne retire pas plus
  /// d'œufs qu'il n'y en a, et éclos + perdus ne dépassent pas les œufs retenus.
  static bool compteursIncoherents({
    required int charges,
    int? blancs,
    int? gates,
    int? eclos,
    int? perdus,
  }) {
    if (charges < 1) return true;
    if ((blancs ?? 0) < 0 || (gates ?? 0) < 0) return true;
    if ((eclos ?? 0) < 0 || (perdus ?? 0) < 0) return true;
    final retenus = charges - (blancs ?? 0) - (gates ?? 0);
    if (retenus < 0) return true;
    if (eclos != null && eclos + (perdus ?? 0) > retenus) return true;
    return false;
  }

  /// Un entier JSON, ou `null` s'il manque. [invalide] est appelé si la valeur est là
  /// mais n'est pas un entier.
  static int? _entier(Object? v, void Function() invalide) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double && v == v.truncateToDouble()) return v.toInt();
    invalide();
    return null;
  }

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        var valide = true;
        void invalide() => valide = false;

        final id = l['id'];
        final code = l['code_incubation'];
        final espece = l['espece'];
        final statut = l['statut'];
        final jour = _jour(l['date_incubation']);
        final instant = l['updated_at'] is String
            ? DateTime.tryParse(l['updated_at'] as String)
            : null;
        final charges = _entier(l['oeufs_couves'], invalide);
        final eclos = _entier(l['poussins_nes'], invalide);
        final perdus = _entier(l['oeufs_perdus'], invalide);
        final blancs = _entier(l['oeufs_blancs_j7'], invalide);
        final gates = _entier(l['oeufs_gates_j14'], invalide);
        final machine = l['machine_id'];
        final parent = l['lot_parent_id'];

        // Strict : un lot incohérent est REFUSÉ, jamais lissé.
        if (!valide ||
            id is! String ||
            !_uuid.hasMatch(id) ||
            code is! String ||
            code.trim().isEmpty ||
            espece is! String ||
            EspeceCouvable.depuisIdentifiant(espece) == null ||
            statut is! String ||
            !StatutCycle.tous.contains(statut) ||
            jour == null ||
            instant == null ||
            charges == null ||
            compteursIncoherents(
              charges: charges,
              blancs: blancs,
              gates: gates,
              eclos: eclos,
              perdus: perdus,
            ) ||
            (machine != null &&
                (machine is! String || !_uuid.hasMatch(machine))) ||
            (parent != null &&
                (parent is! String ||
                    !_uuid.hasMatch(parent) ||
                    parent == id))) {
          refusees++;
          continue;
        }

        final locale = await (_db.select(
          _db.cycleCouveuse,
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

        // Pierre tombale : le serveur a supprimé ce lot.
        if (l['supprime_le'] != null) {
          if (supplantee) supplantees++;
          if (locale != null) {
            await (_db.delete(
              _db.cycleCouveuse,
            )..where((c) => c.id.equals(id))).go();
            absorbees++;
          }
          continue;
        }

        // Un lot SUPPRIMÉ ici (corbeille) n'est pas ressuscité par l'écho du serveur : son
        // propre envoi lui revient au tirage suivant, avant que la pierre tombale
        // soit partie. Seule une version STRICTEMENT plus récente (un autre poste l'a
        // modifié après la suppression) le fait revenir ; la pierre tombale est alors
        // caduque.
        if (locale == null) {
          final archive = await _archiveDe(id);
          if (archive != null) {
            final saisieArchive = archive.donnees['updated_at'] is String
                ? DateTime.tryParse(archive.donnees['updated_at'] as String)
                : null;
            if (saisieArchive != null && !instant.isAfter(saisieArchive)) {
              conservees++;
              continue;
            }
            if (archive.donnees['sync_status'] != 'synced') supplantees++;
            await _marquerArchive(id, null, 'synced', null);
          }
        }

        // L'incubateur doit exister ici (clé étrangère) : il arrive AVANT les lots.
        if (machine != null) {
          final connue = await (_db.select(
            _db.machinesIncubateur,
          )..where((m) => m.id.equals(machine as String))).getSingleOrNull();
          if (connue == null) {
            refusees++;
            continue;
          }
        }

        // Le code est unique ici : un AUTRE lot qui le porte déjà est signalé, jamais
        // écrasé (deux postes sans code de poste ont pu créer `C-2026-001`).
        final homonyme =
            await (_db.select(_db.cycleCouveuse)..where(
                  (c) =>
                      c.codeIncubation.equals(code.trim()) &
                      c.id.isNotValue(id),
                ))
                .getSingleOrNull();
        if (homonyme != null) {
          refusees++;
          continue;
        }

        if (supplantee) supplantees++;
        await _db
            .into(_db.cycleCouveuse)
            .insertOnConflictUpdate(
              CycleCouveuseCompanion(
                id: Value(id),
                codeIncubation: Value(code.trim()),
                espece: Value(espece),
                dateIncubation: Value(jour),
                oeufsCouves: Value(charges),
                poussinsNes: Value(eclos),
                oeufsPerdus: Value(perdus),
                statut: Value(statut),
                machineId: Value(machine as String?),
                oeufsBlancsJ7: Value(blancs),
                oeufsGatesJ14: Value(gates),
                lotParentId: Value(parent as String?),
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

  // ------------------------------------------------------------------ Envoi

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final lignes = await (_db.select(
      _db.cycleCouveuse,
    )..where((c) => c.syncStatus.equals('pending'))).get();

    final envois = <LigneAEnvoyer>[
      for (final c in lignes)
        LigneAEnvoyer(
          id: c.id,
          instantSaisie: c.updatedAt,
          corps: {
            'id': c.id,
            'code_incubation': c.codeIncubation,
            'espece': c.espece,
            'date_incubation': _formatJour(c.dateIncubation),
            'oeufs_couves': c.oeufsCouves,
            'poussins_nes': c.poussinsNes,
            'oeufs_perdus': c.oeufsPerdus,
            'statut': c.statut,
            'machine_id': c.machineId,
            'oeufs_blancs_j7': c.oeufsBlancsJ7,
            'oeufs_gates_j14': c.oeufsGatesJ14,
            'lot_parent_id': c.lotParentId,
            'supprime_le': null,
            'updated_at': c.updatedAt,
          },
        ),
    ];

    // Pierres tombales : les lots supprimés dont la suppression n'est pas partie.
    for (final archive in await _archives()) {
      final donnees = archive.donnees;
      if (donnees['sync_status'] != 'pending') continue;
      final id = donnees['id'];
      final saisie = donnees['updated_at'];
      final jour = donnees['date_incubation'];
      if (id is! String ||
          saisie is! String ||
          jour is! int ||
          !_uuid.hasMatch(id)) {
        continue;
      }
      envois.add(
        LigneAEnvoyer(
          id: id,
          instantSaisie: saisie,
          corps: {
            'id': id,
            'code_incubation': donnees['code_incubation'],
            'espece': donnees['espece'],
            'date_incubation': _formatJour(
              DateTime.fromMillisecondsSinceEpoch(jour * 1000),
            ),
            'oeufs_couves': donnees['oeufs_couves'],
            'poussins_nes': donnees['poussins_nes'],
            'oeufs_perdus': donnees['oeufs_perdus'],
            'statut': donnees['statut'],
            'machine_id': donnees['machine_id'],
            'oeufs_blancs_j7': donnees['oeufs_blancs_j7'],
            'oeufs_gates_j14': donnees['oeufs_gates_j14'],
            'lot_parent_id': donnees['lot_parent_id'],
            'supprime_le': saisie,
            'updated_at': saisie,
          },
        ),
      );
    }

    envois.sort((a, b) {
      final c = DateTime.parse(
        a.instantSaisie,
      ).compareTo(DateTime.parse(b.instantSaisie));
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return envois;
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    final ecrites =
        await (_db.update(_db.cycleCouveuse)..where(
              (c) => c.id.equals(id) & c.updatedAt.equals(instantEnvoye),
            ))
            .write(
              const CycleCouveuseCompanion(
                syncStatus: Value('synced'),
                syncMotif: Value(null),
              ),
            );
    if (ecrites == 0) {
      await _marquerArchive(id, instantEnvoye, 'synced', null);
    }
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    final ecrites =
        await (_db.update(
          _db.cycleCouveuse,
        )..where((c) => c.id.equals(id))).write(
          CycleCouveuseCompanion(
            syncStatus: const Value('conflict'),
            syncMotif: Value(motif),
          ),
        );
    if (ecrites == 0) {
      await _marquerArchive(id, null, 'conflict', motif);
    }
  }

  /// Remise à zéro du serveur : vide les lots. La corbeille n'est pas touchée (elle
  /// appartient à l'utilisatrice) ; les saisies non envoyées sont comptées.
  @override
  Future<int> purger() async {
    final nonEnvoyes = await (_db.select(
      _db.cycleCouveuse,
    )..where((c) => c.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.cycleCouveuse).go();
    return nonEnvoyes.length;
  }

  // ------------------------------------------------------------------ Outils

  Future<List<_Archive>> _archives() async {
    final lignes = await (_db.select(
      _db.corbeille,
    )..where((c) => c.nomTable.equals(_tableArchivee))).get();
    final archives = <_Archive>[];
    for (final ligne in lignes) {
      try {
        final donnees = jsonDecode(ligne.donneesJson);
        if (donnees is Map<String, Object?>) {
          archives.add(_Archive(ligne.id, donnees));
        }
      } on FormatException {
        // Instantané illisible : il ne part pas, il ne bloque rien.
      }
    }
    return archives;
  }

  /// L'instantané de corbeille le plus récent de ce lot, s'il en existe un.
  Future<_Archive?> _archiveDe(String id) async {
    _Archive? plusRecente;
    for (final archive in await _archives()) {
      if (archive.donnees['id'] != id) continue;
      if (plusRecente == null ||
          archive.idCorbeille > plusRecente.idCorbeille) {
        plusRecente = archive;
      }
    }
    return plusRecente;
  }

  /// Marque l'instantané d'un lot supprimé (accusé de sa pierre tombale, ou refus).
  /// [instant] non nul : ne touche que si l'instantané n'a pas changé depuis l'envoi.
  Future<void> _marquerArchive(
    String id,
    String? instant,
    String statut,
    String? motif,
  ) async {
    for (final archive in await _archives()) {
      if (archive.donnees['id'] != id) continue;
      if (instant != null && archive.donnees['updated_at'] != instant) continue;
      final donnees = {
        ...archive.donnees,
        'sync_status': statut,
        'sync_motif': motif,
      };
      await (_db.update(_db.corbeille)
            ..where((c) => c.id.equals(archive.idCorbeille)))
          .write(CorbeilleCompanion(donneesJson: Value(jsonEncode(donnees))));
    }
  }

  /// `2026-08-01` ou `2026-08-01T00:00:00.000000Z` -> 1er août, minuit LOCAL.
  DateTime? _jour(Object? v) {
    if (v is! String || v.length < 10) return null;
    final a = int.tryParse(v.substring(0, 4));
    final m = int.tryParse(v.substring(5, 7));
    final j = int.tryParse(v.substring(8, 10));
    if (a == null || m == null || j == null) return null;
    if (m < 1 || m > 12 || j < 1 || j > 31) return null;
    return DateTime(a, m, j);
  }

  String _formatJour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _Archive {
  const _Archive(this.idCorbeille, this.donnees);

  final int idCorbeille;
  final Map<String, Object?> donnees;
}
