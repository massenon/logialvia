import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../domain/entities/comptabilite.dart';

/// Une ligne à écrire (partie double).
class LigneAEcrire {
  const LigneAEcrire({
    required this.numeroCompte,
    required this.debit,
    required this.credit,
    required this.libelle,
    this.axeAnalytique,
  });

  final String numeroCompte;
  final double debit;
  final double credit;
  final String libelle;

  /// Centre analytique d'imputation — « Goliaths », « Commerce Annexe »…
  /// `null` si la ligne n'est pas imputée. Voir `ECRITURE_COMPTABLE`.
  final String? axeAnalytique;
}

abstract class ComptabiliteRepository {
  Future<List<CompteComptable>> chargerPlanComptable();
  Future<List<Ecriture>> chargerEcritures({int? exerciceAnnee});
  Future<List<int>> chargerExercices();
  Future<bool> exerciceEstCloture(int annee);
  Future<Map<int, bool>> chargerCloturesPeriodiques(int annee);
  Future<List<NoteAnnexe>> chargerNotes(int exerciceAnnee);

  Future<void> creerCompte(CompteComptable compte);

  /// Le libellé et la classe sont modifiables ; **le numéro ne l'est pas** —
  /// il est référencé par `ECRITURE_COMPTABLE.numeroCompte` et le renommer
  /// orphelinerait tout l'historique.
  Future<void> modifierCompte({
    required String numero,
    required String libelle,
    required String classe,
  });

  Future<void> archiverCompte(String numero, {required bool archive});

  /// Nombre d'écritures portées par un compte — un compte mouvementé ne peut
  /// pas changer de classe sans fausser rétroactivement les états financiers.
  Future<int> nombreEcrituresDuCompte(String numero);

  /// Enregistre une pièce comptable équilibrée. Vérifie le **double
  /// verrouillage** (Doc F6 §9) avant toute écriture.
  Future<void> enregistrerPiece({
    required DateTime date,
    required String journalCode,
    required String? numeroPiece,
    required List<LigneAEcrire> lignes,
    String? venteRef,
    String? achatRef,
  });

  Future<void> supprimerEcriture(int id);

  /// Supprime **toutes** les lignes d'une pièce. Une dépense ou une opération
  /// diverse est équilibrée sur 2 lignes : n'en supprimer qu'une casserait la
  /// partie double et déséquilibrerait la balance.
  Future<void> supprimerPiece({
    required int exerciceAnnee,
    required String numeroPiece,
  });

  /// Réécrit une pièce **sous son propre numéro**, en une seule transaction.
  ///
  /// Modifier une dépense, ce n'est pas modifier une ligne : c'est remplacer
  /// les deux lignes de sa pièce. Enchaîner une suppression puis une écriture
  /// laisserait, si la seconde échoue, une pièce disparue et une charge
  /// évaporée du Compte de Résultat. Ici les deux sont indissociables.
  ///
  /// Le numéro de pièce est **conservé** : il figure sur le reçu papier que la
  /// Gérante a classé. Le renuméroter à chaque correction rendrait le
  /// rapprochement impossible.
  Future<void> remplacerPiece({
    required int exerciceAnnee,
    required String numeroPiece,
    required DateTime date,
    required String journalCode,
    required List<LigneAEcrire> lignes,
  });

  Future<void> cloturerMois({required int annee, required int mois});
  Future<void> decloturerMois({
    required int annee,
    required int mois,
    required String utilisateurId,
  });

  Future<void> cloturerExercice(int annee);
  Future<void> enregistrerNote(int exerciceAnnee, NoteAnnexe note);
}

class ComptabiliteRepositoryDrift implements ComptabiliteRepository {
  const ComptabiliteRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Future<List<CompteComptable>> chargerPlanComptable() async {
    final lignes =
        await (_db.select(_db.planComptable)
              ..orderBy([(p) => OrderingTerm.asc(p.numeroCompte)]))
            .get();
    return [
      for (final c in lignes)
        CompteComptable(
          numero: c.numeroCompte,
          libelle: c.libelle,
          classe: c.classe,
          archive: c.archive,
        ),
    ];
  }

  @override
  Future<List<Ecriture>> chargerEcritures({int? exerciceAnnee}) async {
    final requete = _db.select(_db.ecritureComptable)
      ..orderBy([(e) => OrderingTerm.desc(e.dateEcriture)]);
    if (exerciceAnnee != null) {
      requete.where((e) => e.exerciceAnnee.equals(exerciceAnnee));
    }

    return [
      for (final e in await requete.get())
        Ecriture(
          id: e.id,
          exerciceAnnee: e.exerciceAnnee,
          numeroCompte: e.numeroCompte,
          date: e.dateEcriture,
          debit: e.debit,
          credit: e.credit,
          libelle: e.libelle,
          journalCode: e.journalCode,
          numeroPiece: e.numeroPiece,
          venteRef: e.venteRef,
          achatRef: e.achatRef,
          isLocked: e.isLocked,
          axeAnalytique: e.axeAnalytique,
        ),
    ];
  }

  @override
  Future<List<int>> chargerExercices() async {
    final lignes =
        await (_db.select(_db.exerciceComptable)
              ..orderBy([(e) => OrderingTerm.desc(e.annee)]))
            .get();
    return lignes.map((e) => e.annee).toList();
  }

  @override
  Future<bool> exerciceEstCloture(int annee) async {
    final exercice = await (_db.select(
      _db.exerciceComptable,
    )..where((e) => e.annee.equals(annee))).getSingleOrNull();
    return exercice?.isCloture ?? false;
  }

  @override
  Future<Map<int, bool>> chargerCloturesPeriodiques(int annee) async {
    final lignes = await (_db.select(
      _db.cloturesPeriodiques,
    )..where((c) => c.annee.equals(annee))).get();
    return {for (final c in lignes) c.mois: c.isCloture};
  }

  @override
  Future<List<NoteAnnexe>> chargerNotes(int exerciceAnnee) async {
    final lignes =
        await (_db.select(_db.notesAnnexes)
              ..where((n) => n.exerciceAnnee.equals(exerciceAnnee))
              ..orderBy([(n) => OrderingTerm.asc(n.numeroNote)]))
            .get();
    return [
      for (final n in lignes)
        NoteAnnexe(numero: n.numeroNote, titre: n.titre, contenu: n.contenu),
    ];
  }

  @override
  Future<void> creerCompte(CompteComptable compte) async {
    await _db
        .into(_db.planComptable)
        .insert(
          PlanComptableCompanion.insert(
            numeroCompte: compte.numero,
            libelle: compte.libelle,
            classe: compte.classe,
          ),
        );
  }

  @override
  Future<void> modifierCompte({
    required String numero,
    required String libelle,
    required String classe,
  }) async {
    await (_db.update(
      _db.planComptable,
    )..where((p) => p.numeroCompte.equals(numero))).write(
      PlanComptableCompanion(
        libelle: Value(libelle),
        classe: Value(classe),
      ),
    );
  }

  @override
  Future<int> nombreEcrituresDuCompte(String numero) async {
    final compte = _db.ecritureComptable.id.count();
    final requete = _db.selectOnly(_db.ecritureComptable)
      ..addColumns([compte])
      ..where(_db.ecritureComptable.numeroCompte.equals(numero));
    final ligne = await requete.getSingle();
    return ligne.read(compte) ?? 0;
  }

  @override
  Future<void> archiverCompte(String numero, {required bool archive}) async {
    await (_db.update(
      _db.planComptable,
    )..where((p) => p.numeroCompte.equals(numero))).write(
      PlanComptableCompanion(archive: Value(archive)),
    );
  }

  /// ## Double verrouillage — Doc F6 §9
  ///
  /// « Toute écriture sur `ECRITURE_COMPTABLE` doit vérifier
  /// `EXERCICE_COMPTABLE.isCloture` (BR-CPT-001) **et** `CLOTURES_PERIODIQUES`
  /// du mois concerné (BR-CPT-006) avant d'être acceptée. »
  ///
  /// La vérification est faite **ici**, dans la couche de persistance, et pas
  /// seulement dans l'interface : une écriture automatique générée par une
  /// vente passe par le même chemin et doit obéir à la même règle.
  Future<void> _verifierVerrouillage(DateTime date) async {
    final exercice = await (_db.select(
      _db.exerciceComptable,
    )..where((e) => e.annee.equals(date.year))).getSingleOrNull();

    if (exercice == null) {
      throw StateError(
        'Aucun exercice comptable ouvert pour ${date.year}.',
      );
    }
    if (exercice.isCloture) {
      throw StateError(
        'L\'exercice ${date.year} est clôturé : aucune écriture ne peut y être '
        'ajoutée ni modifiée (BR-CPT-001).',
      );
    }

    final cloture = await (_db.select(_db.cloturesPeriodiques)..where(
          (c) => c.annee.equals(date.year) & c.mois.equals(date.month),
        ))
        .getSingleOrNull();
    if (cloture?.isCloture ?? false) {
      throw StateError(
        'Le mois ${date.month}/${date.year} est clôturé. Une administratrice '
        'peut le déclôturer pour correction (BR-CPT-006).',
      );
    }
  }

  @override
  Future<void> enregistrerPiece({
    required DateTime date,
    required String journalCode,
    required String? numeroPiece,
    required List<LigneAEcrire> lignes,
    String? venteRef,
    String? achatRef,
  }) async {
    await _db.transaction(() async {
      await _verifierVerrouillage(date);

      for (final ligne in lignes) {
        await _db
            .into(_db.ecritureComptable)
            .insert(
              EcritureComptableCompanion.insert(
                exerciceAnnee: date.year,
                numeroCompte: ligne.numeroCompte,
                dateEcriture: date,
                debit: Value(ligne.debit),
                credit: Value(ligne.credit),
                libelle: ligne.libelle,
                journalCode: Value(journalCode),
                numeroPiece: Value(numeroPiece),
                venteRef: Value(venteRef),
                achatRef: Value(achatRef),
                axeAnalytique: Value(ligne.axeAnalytique),
              ),
            );
      }
    });
  }

  @override
  Future<void> supprimerEcriture(int id) async {
    await _db.transaction(() async {
      final ecriture = await (_db.select(
        _db.ecritureComptable,
      )..where((e) => e.id.equals(id))).getSingleOrNull();
      if (ecriture == null) return;

      await _verifierVerrouillage(ecriture.dateEcriture);

      if (ecriture.venteRef != null || ecriture.achatRef != null) {
        throw StateError(
          'Cette écriture est générée automatiquement par '
          '${ecriture.venteRef ?? ecriture.achatRef}. Annulez l\'opération '
          'd\'origine plutôt que l\'écriture.',
        );
      }

      await (_db.delete(
        _db.ecritureComptable,
      )..where((e) => e.id.equals(id))).go();
    });
  }

  @override
  Future<void> supprimerPiece({
    required int exerciceAnnee,
    required String numeroPiece,
  }) async {
    await _db.transaction(() async {
      final lignes =
          await (_db.select(_db.ecritureComptable)..where(
                (e) =>
                    e.exerciceAnnee.equals(exerciceAnnee) &
                    e.numeroPiece.equals(numeroPiece),
              ))
              .get();
      if (lignes.isEmpty) return;

      await _verifierVerrouillage(lignes.first.dateEcriture);

      for (final ligne in lignes) {
        if (ligne.venteRef != null || ligne.achatRef != null) {
          throw StateError(
            'La pièce $numeroPiece est générée automatiquement par '
            '${ligne.venteRef ?? ligne.achatRef}. Annulez l\'opération '
            'd\'origine plutôt que l\'écriture.',
          );
        }
      }

      await (_db.delete(_db.ecritureComptable)..where(
            (e) =>
                e.exerciceAnnee.equals(exerciceAnnee) &
                e.numeroPiece.equals(numeroPiece),
          ))
          .go();
    });
  }

  @override
  Future<void> remplacerPiece({
    required int exerciceAnnee,
    required String numeroPiece,
    required DateTime date,
    required String journalCode,
    required List<LigneAEcrire> lignes,
  }) async {
    await _db.transaction(() async {
      final anciennes =
          await (_db.select(_db.ecritureComptable)..where(
                (e) =>
                    e.exerciceAnnee.equals(exerciceAnnee) &
                    e.numeroPiece.equals(numeroPiece),
              ))
              .get();

      if (anciennes.isEmpty) {
        throw StateError('La pièce $numeroPiece est introuvable.');
      }

      // Les deux dates comptent : l'ancienne parce qu'on retire une ecriture
      // de sa periode, la nouvelle parce qu'on en depose une. Si l'une des
      // deux est verrouillee, la modification est refusee.
      await _verifierVerrouillage(anciennes.first.dateEcriture);
      await _verifierVerrouillage(date);

      for (final ligne in anciennes) {
        if (ligne.venteRef != null || ligne.achatRef != null) {
          throw StateError(
            'La pièce $numeroPiece est générée automatiquement par '
            '${ligne.venteRef ?? ligne.achatRef}. Corrigez l\'opération '
            'd\'origine plutôt que l\'écriture.',
          );
        }
      }

      await (_db.delete(_db.ecritureComptable)..where(
            (e) =>
                e.exerciceAnnee.equals(exerciceAnnee) &
                e.numeroPiece.equals(numeroPiece),
          ))
          .go();

      for (final ligne in lignes) {
        await _db
            .into(_db.ecritureComptable)
            .insert(
              EcritureComptableCompanion.insert(
                exerciceAnnee: date.year,
                numeroCompte: ligne.numeroCompte,
                dateEcriture: date,
                debit: Value(ligne.debit),
                credit: Value(ligne.credit),
                libelle: ligne.libelle,
                journalCode: Value(journalCode),
                numeroPiece: Value(numeroPiece),
                axeAnalytique: Value(ligne.axeAnalytique),
              ),
            );
      }
    });
  }

  @override
  Future<void> cloturerMois({required int annee, required int mois}) async {
    await _db
        .into(_db.cloturesPeriodiques)
        .insertOnConflictUpdate(
          CloturesPeriodiquesCompanion.insert(
            annee: annee,
            mois: mois,
            isCloture: const Value(true),
            dateCloture: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<void> decloturerMois({
    required int annee,
    required int mois,
    required String utilisateurId,
  }) async {
    await _db
        .into(_db.cloturesPeriodiques)
        .insertOnConflictUpdate(
          CloturesPeriodiquesCompanion.insert(
            annee: annee,
            mois: mois,
            isCloture: const Value(false),
            // BR-ADM-003 : tracabilite du deblocage exceptionnel.
            declotureParUtilisateurId: Value(utilisateurId),
          ),
        );

    await _db
        .into(_db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            horodatage: DateTime.now(),
            utilisateurId: utilisateurId,
            action: 'decloture',
            entiteConcernee: 'CloturePeriodique',
            entiteId: '$mois/$annee',
          ),
        );
  }

  @override
  Future<void> cloturerExercice(int annee) async {
    await _db.transaction(() async {
      await (_db.update(_db.exerciceComptable)
            ..where((e) => e.annee.equals(annee)))
          .write(
            ExerciceComptableCompanion(
              isCloture: const Value(true),
              dateCloture: Value(DateTime.now()),
            ),
          );

      // Verrouille toutes les ecritures de l'exercice.
      await (_db.update(_db.ecritureComptable)
            ..where((e) => e.exerciceAnnee.equals(annee)))
          .write(const EcritureComptableCompanion(isLocked: Value(true)));

      // Ouvre l'exercice suivant s'il n'existe pas.
      final suivant = await (_db.select(
        _db.exerciceComptable,
      )..where((e) => e.annee.equals(annee + 1))).getSingleOrNull();
      if (suivant == null) {
        await _db
            .into(_db.exerciceComptable)
            .insert(
              ExerciceComptableCompanion.insert(annee: Value(annee + 1)),
            );
      }
    });
  }

  @override
  Future<void> enregistrerNote(int exerciceAnnee, NoteAnnexe note) async {
    final companion = NotesAnnexesCompanion.insert(
      exerciceAnnee: exerciceAnnee,
      numeroNote: note.numero,
      titre: note.titre,
      contenu: note.contenu,
    );

    // `UNIQUE(exerciceAnnee, numeroNote)` — cible explicite, jamais la cle
    // primaire auto-incrementee (Doc K3 §6-TER).
    await _db
        .into(_db.notesAnnexes)
        .insert(
          companion,
          onConflict: DoUpdate(
            (_) => companion,
            target: [
              _db.notesAnnexes.exerciceAnnee,
              _db.notesAnnexes.numeroNote,
            ],
          ),
        );
  }
}
