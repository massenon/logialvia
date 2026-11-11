import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Peuplement initial de `MODULES_ACTIFS` — Doc I2 §2 et §5.
///
/// **Seuls les 5 modules reellement basculables ont une ligne**, et ils sont
/// **desactives par defaut**. Goliaths et Pintades n'en ont volontairement
/// aucune : ils ne sont jamais desactivables (`checked disabled` dans
/// `parametres-generaux.html`), donc leur donner une ligne modifiable
/// suggererait a tort le contraire.
///
/// Les identifiants techniques sont ceux des attributs `data-module` reels de
/// `sidebar.js` et `elevage-dashboard.html` — jamais un nom d'espece.
class ModulesActifsSeeder {
  const ModulesActifsSeeder(this._db);

  final AppDatabase _db;

  static const String pisciculture = 'pisciculture';
  static const String cuniculture = 'cuniculture';
  static const String avicultureClassique = 'aviculture_classique';
  static const String heliciculture = 'heliciculture';
  static const String ovins = 'ovins';

  /// Correspondance module basculable -> espece de la fiche associee.
  static const Map<String, String> especeParModule = {
    pisciculture: 'poissons-chats',
    cuniculture: 'lapins',
    avicultureClassique: 'poulets',
    heliciculture: 'escargots',
    ovins: 'ovins',
  };

  /// Migration v27 : ajoute les modules manquants (heliciculture, ovins) a
  /// une base en service, **desactives** comme les autres. Un module deja
  /// present est laisse tel quel : son etat est un choix de la Gerante.
  static Future<void> ajouterModulesManquants(AppDatabase db) async {
    final presents = (await db.select(db.modulesActifs).get())
        .map((m) => m.moduleId)
        .toSet();
    for (final entree in especeParModule.entries) {
      if (presents.contains(entree.key)) continue;
      await db
          .into(db.modulesActifs)
          .insert(
            ModulesActifsCompanion.insert(
              moduleId: entree.key,
              isActif: const Value(false),
              espece: Value(entree.value),
            ),
          );
    }
  }

  Future<bool> executer() async {
    if (await _contientDejaDesLignes()) return false;

    await _db.batch((batch) {
      batch.insertAll(
        _db.modulesActifs,
        especeParModule.entries.map(
          (e) => ModulesActifsCompanion.insert(
            moduleId: e.key,
            isActif: const Value(false), // desactive par defaut (Doc I2 §2)
            espece: Value(e.value),
          ),
        ),
      );
    });
    return true;
  }

  /// `LIMIT 1` plutot qu'un `COUNT(*)` : on veut seulement savoir si la table
  /// est vide, pas combien elle contient de lignes.
  Future<bool> _contientDejaDesLignes() async {
    final premiere = await (_db.select(
      _db.modulesActifs,
    )..limit(1)).getSingleOrNull();
    return premiere != null;
  }
}
