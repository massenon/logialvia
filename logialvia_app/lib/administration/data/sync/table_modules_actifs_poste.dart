import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../seed/modules_actifs_seeder.dart';
import 'depot_demandes_referentiel.dart';
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

  DepotDemandesReferentiel get depot => DepotDemandesReferentiel(_db);

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
      var supplantees = 0;

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

        final decide = serveurADecide(l);
        final demande = await depot.enAttente(
          DepotDemandesReferentiel.typeModule,
          id,
        );
        final aAppliquer = locale == null
            ? true
            : demande != null
            // Une demande du poste est en attente : même règle que le serveur,
            // la version la plus récente gagne. Le serveur ne l'emporte que s'il
            // a décidé APRÈS la saisie du poste ; sinon la demande partira.
            ? decide &&
                  (decisionDuServeur(
                        l,
                      )?.isAfter(DateTime.parse(demande.saisiLe)) ??
                      false)
            : decide;

        if (!aAppliquer) {
          // Valeur de semis (ou saisie locale plus récente) : le choix local
          // reste. Si le serveur n'a jamais décidé et diffère du poste, le poste
          // lui PROPOSE son choix (adoption initiale).
          if (demande == null && locale.isActif != actif) {
            await depot.proposerModule(id, actif: locale.isActif);
          }
          conservees++;
          continue;
        }

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
          if (demande != null) supplantees++;
        }
        if (demande != null) await depot.abandonner(demande.id);
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
  Future<List<LigneAEnvoyer>> aEnvoyer() async => const [];

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {}

  @override
  Future<void> marquerConflit(String id, String motif) async {}

  /// Une remise à zéro préserve les référentiels (blueprint §6).
  @override
  Future<int> purger() async => 0;
}
