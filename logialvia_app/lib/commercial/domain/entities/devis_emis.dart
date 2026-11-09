/// Un devis de prestations (Doc H1 §Onglet 2, `47a2_`).
///
/// Un devis n'est pas une vente : il ne décrémente aucun stock, ne génère aucune
/// écriture comptable et n'entre dans aucun chiffre d'affaires.
library;

/// Cycle de vie d'un devis. « Expiré » n'en fait pas partie : il se déduit de la
/// date (voir [DevisEmis.estExpire]), pour qu'aucun poste n'ait à « passer » un
/// devis à expiré.
enum StatutDevis {
  /// Remis au client, sans réponse. Seul état où le devis se modifie.
  emis('emis', 'Émis'),

  /// Accepté par le client : figé, ni modifiable ni supprimable.
  accepte('accepte', 'Accepté'),

  /// Refusé par le client.
  refuse('refuse', 'Refusé');

  const StatutDevis(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutDevis depuis(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => StatutDevis.emis);
}

/// Un devis émis.
class DevisEmis {
  const DevisEmis({
    required this.reference,
    required this.client,
    required this.objet,
    required this.montant,
    required this.validiteJours,
    required this.dateEmission,
    this.id = '',
    this.statut = StatutDevis.emis,
  });

  /// UUID du devis (DV-19). Vide pour un devis tout juste construit en mémoire.
  final String id;
  final String reference;
  final String client;
  final String objet;
  final double montant;
  final int validiteJours;
  final DateTime dateEmission;
  final StatutDevis statut;

  DateTime get dateExpiration =>
      dateEmission.add(Duration(days: validiteJours));

  /// Sans réponse du client et hors délai de validité. Un devis accepté ou
  /// refusé n'« expire » pas : sa réponse a déjà été donnée.
  bool estExpire([DateTime? maintenant]) =>
      statut == StatutDevis.emis &&
      (maintenant ?? DateTime.now()).isAfter(dateExpiration);

  /// Le libellé affiché : « Expiré » l'emporte sur « Émis ».
  String libelleStatut([DateTime? maintenant]) =>
      estExpire(maintenant) ? 'Expiré' : statut.libelle;

  /// Seul un devis « émis » se modifie (le client n'a pas encore répondu).
  bool get modifiable => statut == StatutDevis.emis;

  /// Un devis accepté engage l'entreprise : il ne se supprime pas.
  bool get supprimable => statut != StatutDevis.accepte;
}
