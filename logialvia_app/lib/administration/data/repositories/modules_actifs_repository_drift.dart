import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../sync/depot_demandes_referentiel.dart';
import '../../domain/repositories/modules_actifs_repository.dart';

class ModulesActifsRepositoryDrift implements ModulesActifsRepository {
  const ModulesActifsRepositoryDrift(this._db);

  final AppDatabase _db;

  /// Identifiant du module de conformite fiscale, tel que la barre laterale
  /// l'interroge.
  static const String moduleMecef = 'mecef';

  @override
  Future<Map<String, bool>> chargerEtats() async {
    final lignes = await _db.select(_db.modulesActifs).get();
    final etats = {for (final ligne in lignes) ligne.moduleId: ligne.isActif};

    // MeCeF n'est pas une filiere : son interrupteur vit dans
    // PARAMETRES_ENTREPRISE, parce que BR-ADM-004 le lie a l'IFU et au RCCM.
    // Le recopier dans MODULES_ACTIFS creerait une seconde verite qui
    // divergerait au premier oubli. Il est donc **lu** ici, jamais duplique :
    // une seule source, deux lecteurs.
    final parametres = await _db
        .select(_db.parametresEntreprise)
        .getSingleOrNull();
    etats[moduleMecef] = parametres?.mecefActif ?? false;

    return etats;
  }

  @override
  Future<void> definirEtat(String moduleId, {required bool actif}) async {
    if (moduleId == moduleMecef) {
      // L'ecran Parametres Generaux ecrit deja `mecefActif` en respectant
      // BR-ADM-004 (IFU et RCCM requis). Doubler l'ecriture ici contournerait
      // ce controle.
      throw StateError(
        'Le module MeCeF s\'active depuis Paramètres Général › Modules '
        'Actifs, qui vérifie que l\'IFU et le RCCM sont renseignés.',
      );
    }
    await (_db.update(_db.modulesActifs)
          ..where((m) => m.moduleId.equals(moduleId)))
        .write(ModulesActifsCompanion(isActif: Value(actif)));
    // Un referentiel appartient au serveur : le poste le PROPOSE (`46_` §4.3).
    await DepotDemandesReferentiel(_db).proposerModule(moduleId, actif: actif);
  }
}
