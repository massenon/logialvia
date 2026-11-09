/// Une table du poste branchée à la synchronisation (`46_`).
///
/// Chaque palier de la migration UUID (DV-19) branche une table de plus : le
/// moteur ne connaît que cette interface, jamais les tables elles-mêmes.
abstract class TablePoste {
  /// Nom de la table **côté serveur** (clé de `tables` dans pull et push).
  String get nom;

  /// Absorbe une page tirée du serveur, dans UNE transaction locale.
  ///
  /// **Absorbeur strict** : une ligne incohérente est REFUSÉE, jamais lissée.
  ///
  /// Une ligne locale `pending` ou `conflict` (saisie que le serveur n'a pas
  /// encore) n'est écrasée **que si la version du serveur est strictement plus
  /// récente** : c'est la règle « dernier écrivain gagne » du serveur, appliquée
  /// ici aussi. Sans cela le poste garderait une saisie que le serveur a
  /// ignorée comme trop ancienne, la croirait synchronisée, et ne convergerait
  /// jamais (le curseur est déjà passé). Une saisie locale plus récente (ou
  /// égale) est conservée et partira à l'envoi.
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes);

  /// Lignes `pending`, dans l'ordre d'envoi.
  Future<List<LigneAEnvoyer>> aEnvoyer();

  /// Accusé du serveur. Ne marque `synced` que si la ligne n'a pas été
  /// modifiée depuis l'envoi (`updated_at` inchangé) : une saisie faite pendant
  /// que le réseau répondait doit repartir au prochain envoi.
  Future<void> marquerSynchronise(String id, String instantEnvoye);

  /// Refus du serveur : la ligne devient `conflict`, avec son motif.
  Future<void> marquerConflit(String id, String motif);

  /// Remise à zéro côté serveur : vide cette table. Renvoie le nombre de lignes
  /// **non envoyées** perdues (le poste le dit).
  Future<int> purger();
}

class LigneAEnvoyer {
  const LigneAEnvoyer({
    required this.id,
    required this.instantSaisie,
    required this.corps,
  });

  final String id;

  /// `updated_at` tel qu'envoyé, pour l'accusé.
  final String instantSaisie;
  final Map<String, dynamic> corps;
}

class ResultatAbsorption {
  const ResultatAbsorption({
    this.absorbees = 0,
    this.refusees = 0,
    this.conservees = 0,
    this.supplantees = 0,
  });

  /// Lignes écrites (ou supprimées) localement.
  final int absorbees;

  /// Lignes incohérentes, refusées.
  final int refusees;

  /// Lignes ignorées car le poste a une saisie locale non envoyée plus récente.
  final int conservees;

  /// Saisies locales non envoyées remplacées par une version plus récente du
  /// serveur (comptées dans [absorbees] : le poste le dit à l'utilisatrice).
  final int supplantees;
}
