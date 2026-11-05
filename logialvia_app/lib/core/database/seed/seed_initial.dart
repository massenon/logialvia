import '../../../administration/data/seed/admin_seeder.dart';
import '../../../administration/data/seed/modules_actifs_seeder.dart';
import '../../../approvisionnement/data/seed/intrants_seeder.dart';
import '../../../commercial/data/seed/catalogue_seeder.dart';
import '../../../commercial/data/seed/groupes_taxe_seeder.dart';
import '../../../comptabilite/data/seed/plan_comptable_seeder.dart';
import '../../../elevage/data/seed/parametres_elevage_seeder.dart';
import '../app_database.dart';

/// Resultat du peuplement initial.
class ResultatSeed {
  const ResultatSeed({required this.compteAdminCree});

  /// `true` si le compte administrateur vient d'etre cree — donc tout premier
  /// lancement sur ce poste (Doc F1 Ecran 1).
  final bool compteAdminCree;
}

/// Orchestre l'ensemble des peuplements initiaux — `_seedInitialData()` de
/// Doc D1 §3.
///
/// Chaque seeder est independamment idempotent : supprimer manuellement le
/// catalogue sans toucher aux comptes le fera repeupler au prochain lancement,
/// sans toucher au reste.
///
/// **Ce qui n'est PAS seede, et pourquoi** : Doc D1 §3 mentionne un
/// `DEFAULT_VENTES`. Verification faite dans `logialvia-store.js`, **il
/// n'existe pas** — `getVentes()` retourne `[]` par defaut, l'historique des
/// ventes demarre vide dans le prototype. Aucune vente de demonstration n'est
/// donc creee ici : elles seraient une invention, pas une donnee extraite
/// (Strict Avoid §10).
class SeedInitial {
  const SeedInitial(this._db);

  final AppDatabase _db;

  Future<ResultatSeed> executer() async {
    final compteAdminCree = await AdminSeeder(_db).executer();
    await ModulesActifsSeeder(_db).executer();
    await CatalogueSeeder(_db).executer();
    await GroupesTaxeSeeder(_db).executer();
    await IntrantsSeeder(_db).executer();
    await ParametresElevageSeeder(_db).executer();

    // Plan comptable + exercice courant. `garantirExerciceCourant` est appelé
    // a chaque demarrage et pas seulement au premier : sans exercice ouvert
    // pour l'annee en cours, aucune ecriture ne peut etre enregistree.
    final planComptable = PlanComptableSeeder(_db);
    await planComptable.executer();
    await planComptable.garantirExerciceCourant();

    return ResultatSeed(compteAdminCree: compteAdminCree);
  }
}
