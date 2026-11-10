import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../domain/plan_syscohada.dart';

/// Peuplement du plan comptable et de l'exercice courant.
///
/// ## Plan SYSCOHADA révisé (`47p_`)
///
/// Le plan hérité du prototype (24 comptes, numérotation non conforme : 601/602 inversés,
/// caisse en 531…) est **remplacé** par le sous-ensemble utile du plan SYSCOHADA révisé, voir
/// `PlanSyscohada.comptes` (numéros et libellés officiels). La renumérotation de l'historique
/// d'une base existante est faite par la migration v48 (`MigrationPlanSyscohada`), pas ici : ce
/// semis ne fait qu'**ajouter** les comptes absents.
class PlanComptableSeeder {
  const PlanComptableSeeder(this._db);

  final AppDatabase _db;

  /// Le socle semé : le plan applicable de la ferme (`PlanSyscohada.comptes`).
  static List<({String numero, String libelle, String classe})> get tous =>
      PlanSyscohada.comptes;

  /// Retourne `true` si le plan vient d'être peuplé pour la première fois.
  Future<bool> executer() async {
    final premier = await (_db.select(
      _db.planComptable,
    )..limit(1)).getSingleOrNull();
    final planVierge = premier == null;

    await completerComptesManquants();

    // Ouvre l'exercice courant : sans exercice ouvert, aucune écriture ne peut
    // être enregistrée (contrainte de clé étrangère).
    await _ouvrirExerciceSiNecessaire(DateTime.now().year);
    return planVierge;
  }

  /// Insère les comptes du socle absents de la base — **jamais** de mise à jour
  /// ni de suppression.
  ///
  /// Un simple « si la table est vide, la remplir » ne suffit pas : une base
  /// créée avant l'ajout des comptes de dépenses a déjà un plan non vide, et
  /// resterait indéfiniment sans les comptes 613/616/624/628 que l'écran de
  /// saisie des dépenses exige. Un compte renommé ou archivé par la Gérante
  /// n'est pas touché — seuls les numéros absents sont ajoutés.
  Future<void> completerComptesManquants() async {
    final existants = (await _db.select(_db.planComptable).get())
        .map((c) => c.numeroCompte)
        .toSet();

    final manquants = tous
        .where((c) => !existants.contains(c.numero))
        .toList();
    if (manquants.isEmpty) return;

    await _db.batch((batch) {
      batch.insertAll(
        _db.planComptable,
        manquants.map(
          (c) => PlanComptableCompanion.insert(
            numeroCompte: c.numero,
            libelle: c.libelle,
            classe: c.classe,
          ),
        ),
      );
    });
  }

  /// Idempotent — utilisé aussi au changement d'année civile.
  Future<void> _ouvrirExerciceSiNecessaire(int annee) async {
    final existant = await (_db.select(
      _db.exerciceComptable,
    )..where((e) => e.annee.equals(annee))).getSingleOrNull();
    if (existant != null) return;

    await _db
        .into(_db.exerciceComptable)
        // `annee` est un INTEGER PRIMARY KEY, donc alias de rowid cote SQLite :
        // Drift l'expose en `Value<int>` optionnel, il faut l'envelopper.
        .insert(ExerciceComptableCompanion.insert(annee: Value(annee)));
  }

  /// Appelé au démarrage : garantit qu'un exercice existe pour l'année en
  /// cours, même si l'application n'a pas été lancée depuis le 31 décembre.
  Future<void> garantirExerciceCourant() =>
      _ouvrirExerciceSiNecessaire(DateTime.now().year);
}
