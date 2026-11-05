import 'package:drift/drift.dart';

/// Préférences **de ce poste**, pas de l'entreprise.
///
/// Le prototype en garde deux dans `localStorage` :
///
/// | Clé web | Ce qu'elle retient |
/// |---|---|
/// | `logialvia_sidebar_hidden` | barre latérale repliée ou non (`common.js` l.25) |
/// | — | « Se souvenir de moi » n'écrit **rien** (`login.html` l.101) |
///
/// Aucune des deux ne survivait au redémarrage côté Flutter. La seconde était
/// même une case à cocher qui ne pilotait qu'elle-même — exactement la
/// « fonctionnalité décorative » que le Cahier des Charges §2.3 interdit.
///
/// Table clé/valeur volontairement minuscule, et **séparée de
/// `PARAMETRES_ENTREPRISE`** : celle-ci décrit ALLMANY et suivrait la base si
/// elle était copiée sur un autre ordinateur, alors qu'un identifiant mémorisé
/// ou une barre repliée n'ont de sens que sur la machine où on les a réglés.
///
/// Pas de `shared_preferences` : la base est déjà locale au poste
/// (`getApplicationSupportDirectory`), une dépendance de plus n'apporterait
/// rien qu'une seconde source de vérité.
@DataClassName('PreferencePosteRow')
class PreferencesPoste extends Table {
  TextColumn get cle => text()();
  TextColumn get valeur => text()();

  @override
  Set<Column> get primaryKey => {cle};
}
