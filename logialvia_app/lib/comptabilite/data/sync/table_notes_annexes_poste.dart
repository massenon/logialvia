import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../../core/sync/table_poste.dart';

/// `notes_annexes` — les 5 notes obligatoires de l'exercice (`46d_` §2).
///
/// **Dernier écrivain gagne**, par la clé naturelle (exercice, numéro) : l'identifiant
/// est déterministe, deux postes qui rédigent la note 1 de 2026 la désignent par le
/// même UUID. Rien n'est fusionné : la version la plus récente remplace l'autre, à
/// l'instant de SAISIE, strictement (même règle que le serveur).
class TableNotesAnnexesPoste implements TablePoste {
  const TableNotesAnnexesPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  String get nom => 'notes_annexes';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications =>
      _db.tableUpdates(TableUpdateQuery.onTable(_db.notesAnnexes)).map((_) {});

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        final annee = l['exercice_annee'];
        final numero = l['numero_note'];
        final instant = l['updated_at'] is String
            ? DateTime.tryParse(l['updated_at'] as String)
            : null;
        final titre = l['titre'];
        // Strict : une note incohérente est refusée, jamais lissée.
        if (l['id'] is! String ||
            !_uuid.hasMatch(l['id'] as String) ||
            annee is! int ||
            numero is! int ||
            numero < 1 ||
            numero > 5 ||
            titre is! String ||
            titre.trim().isEmpty ||
            l['contenu'] is! String ||
            instant == null) {
          refusees++;
          continue;
        }

        final exercice = await (_db.select(
          _db.exerciceComptable,
        )..where((e) => e.annee.equals(annee))).getSingleOrNull();
        if (exercice == null) {
          refusees++;
          continue;
        }

        final locale =
            await (_db.select(_db.notesAnnexes)..where(
                  (n) =>
                      n.exerciceAnnee.equals(annee) &
                      n.numeroNote.equals(numero),
                ))
                .getSingleOrNull();

        if (locale == null) {
          await _db
              .into(_db.notesAnnexes)
              .insert(
                NotesAnnexesCompanion.insert(
                  id: Value(l['id'] as String),
                  exerciceAnnee: annee,
                  numeroNote: numero,
                  titre: titre.trim(),
                  contenu: l['contenu'] as String,
                  syncStatus: const Value('synced'),
                  updatedAt: Value(instant.toUtc().toIso8601String()),
                ),
              );
          absorbees++;
          continue;
        }

        // Règle du plus récent, comme le serveur.
        if (locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++; // la saisie locale est plus récente : elle partira
            continue;
          }
          supplantees++;
        }
        final identique =
            locale.titre == titre.trim() &&
            locale.contenu == l['contenu'] &&
            locale.syncStatus == 'synced';
        if (identique) continue;

        await (_db.update(
          _db.notesAnnexes,
        )..where((n) => n.id.equals(locale.id))).write(
          NotesAnnexesCompanion(
            titre: Value(titre.trim()),
            contenu: Value(l['contenu'] as String),
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
    final notes =
        await (_db.select(_db.notesAnnexes)
              ..where((n) => n.syncStatus.equals('pending'))
              ..orderBy([(n) => OrderingTerm.asc(n.updatedAt)]))
            .get();
    return [
      for (final n in notes)
        LigneAEnvoyer(
          // L'identifiant du fil est celui de la clé naturelle : un poste dont la
          // note porte encore un ancien UUID envoie quand même la bonne identité.
          id: n.id,
          instantSaisie: n.updatedAt,
          corps: {
            'id': n.id,
            'exercice_annee': n.exerciceAnnee,
            'numero_note': n.numeroNote,
            'titre': n.titre,
            'contenu': n.contenu,
            'updated_at': n.updatedAt,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.notesAnnexes,
    )..where((n) => n.id.equals(id) & n.updatedAt.equals(instantEnvoye))).write(
      const NotesAnnexesCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(_db.notesAnnexes)..where((n) => n.id.equals(id))).write(
      NotesAnnexesCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  @override
  Future<int> purger() async {
    final nonEnvoyees = await (_db.select(
      _db.notesAnnexes,
    )..where((n) => n.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.notesAnnexes).go();
    return nonEnvoyees.length;
  }
}

/// Identifiant du fil d'une note : déterministe, partagé par tous les postes.
String idNoteAnnexe(int exerciceAnnee, int numero) =>
    uuidDeterministe('note:$exerciceAnnee-$numero');
