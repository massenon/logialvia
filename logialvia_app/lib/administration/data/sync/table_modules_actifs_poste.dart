import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../seed/modules_actifs_seeder.dart';
import 'regle_referentiel.dart';

/// `modules_actifs` — référentiel : le serveur gagne (`46_` §2.2).
///
/// Seuls les modules **basculables** que le poste connaît sont absorbés ; un
/// identifiant inconnu est refusé (le routeur ne sait rien en faire). Une ligne
/// de semis du serveur n'écrase pas le choix de la Gérante : voir
/// [serveurADecide]. Le poste ne l'envoie jamais.
class TableModulesActifsPoste implements TablePoste {
  const TableModulesActifsPoste(this._db);

  final AppDatabase _db;

  @override
  String get nom => 'modules_actifs';

  @override
  bool get referentiel => true;

  @override
  Stream<void> get modifications => const Stream<void>.empty();

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;

      for (final l in lignes) {
        final id = l['module_id'];
        final actif = lireBool(l['is_actif']);
        final espece = l['espece'];
        if (id is! String ||
            !ModulesActifsSeeder.especeParModule.containsKey(id) ||
            actif == null ||
            (espece != null && espece is! String)) {
          refusees++;
          continue;
        }

        final locale = await (_db.select(
          _db.modulesActifs,
        )..where((m) => m.moduleId.equals(id))).getSingleOrNull();

        if (locale == null) {
          await _db
              .into(_db.modulesActifs)
              .insert(
                ModulesActifsCompanion.insert(
                  moduleId: id,
                  isActif: Value(actif),
                  espece: Value(espece as String?),
                ),
              );
          absorbees++;
        } else if (!serveurADecide(l)) {
          conservees++; // valeur de semis : le choix local est gardé
        } else if (locale.isActif != actif ||
            (espece != null && locale.espece != espece)) {
          await (_db.update(
            _db.modulesActifs,
          )..where((m) => m.moduleId.equals(id))).write(
            ModulesActifsCompanion(
              isActif: Value(actif),
              espece: espece == null
                  ? const Value.absent()
                  : Value(espece as String),
            ),
          );
          absorbees++;
        }
      }
      return ResultatAbsorption(
        absorbees: absorbees,
        refusees: refusees,
        conservees: conservees,
      );
    });
  }

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async => const [];

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {}

  @override
  Future<void> marquerConflit(String id, String motif) async {}

  /// Une remise à zéro préserve les référentiels (blueprint §6).
  @override
  Future<int> purger() async => 0;
}
