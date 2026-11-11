import 'adresse_serveur.dart';

/// Environnement de CE logiciel : fixé à la construction (`build_windows.bat
/// --env dev|recette|production`, transmis par `--dart-define=LOGIALVIA_ENV`).
///
/// Il ne sert qu'à **proposer** une adresse de serveur à l'appairage : le poste
/// ne se connecte jamais tout seul, et l'adresse reste modifiable (réseau
/// local, serveur de recette). Sans `--dart-define` (flutter run, tests) :
/// `dev`, aucune adresse proposée.
class Environnement {
  const Environnement._(this.code, this.libelle, this.adresseParDefaut);

  /// `dev`, `recette` ou `production`.
  final String code;
  final String libelle;

  /// Adresse proposée à l'appairage ; `null` : à saisir.
  final String? adresseParDefaut;

  /// Serveur de production d'ALLMANY ET COMPAGNIE.
  static const String adresseProduction = 'https://logialvia.digitonpro.com';

  static const Environnement dev = Environnement._(
    'dev',
    'Développement',
    null,
  );
  static const Environnement recette = Environnement._(
    'recette',
    'Recette (essais)',
    null,
  );
  static const Environnement production = Environnement._(
    'production',
    'Production',
    adresseProduction,
  );

  /// L'environnement de cette construction.
  static Environnement get courant =>
      depuisCode(const String.fromEnvironment('LOGIALVIA_ENV'));

  /// Inconnu ou vide : `dev` (jamais une adresse de production par erreur).
  static Environnement depuisCode(String? code) => switch (code?.trim()) {
    'production' => production,
    'recette' => recette,
    _ => dev,
  };

  /// Adresse à proposer, normalisée (même règle que la saisie).
  String? get adresseProposee => adresseParDefaut == null
      ? null
      : normaliserAdresseServeur(adresseParDefaut!);
}
