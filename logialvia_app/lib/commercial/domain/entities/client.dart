/// Un client, avec ses agrégats calculés depuis `VENTES`.
class Client {
  const Client({
    required this.id,
    required this.nom,
    this.telephone,
    this.dateNaissance,
    this.dernierContact,
    this.totalAchats = 0,
    this.soldeActuel = 0,
  });

  /// UUID (DV-19).
  final String id;
  final String nom;
  final String? telephone;
  final DateTime? dateNaissance;
  final DateTime? dernierContact;

  /// Somme des ventes non annulées de ce client — **recalculée**, jamais lue
  /// depuis une colonne de cumul.
  final double totalAchats;

  /// Somme des restes dus sur ses ventes en avance.
  final double soldeActuel;

  bool get aUneCreance => soldeActuel > 0;

  /// Jours avant le prochain anniversaire. `null` si la date de naissance
  /// n'est pas renseignée.
  int? joursAvantAnniversaire(DateTime maintenant) {
    final naissance = dateNaissance;
    if (naissance == null) return null;

    final aujourdhui = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
    );
    var prochain = DateTime(aujourdhui.year, naissance.month, naissance.day);
    if (prochain.isBefore(aujourdhui)) {
      prochain = DateTime(aujourdhui.year + 1, naissance.month, naissance.day);
    }
    return prochain.difference(aujourdhui).inDays;
  }
}

/// Une créance ouverte — une vente en avance non soldée.
class Creance {
  const Creance({
    required this.client,
    required this.referenceVente,
    required this.montantTotal,
    required this.dejaRegle,
    required this.dateVente,
  });

  final String client;
  final String referenceVente;
  final double montantTotal;
  final double dejaRegle;
  final DateTime dateVente;

  double get soldeRestantDu =>
      (montantTotal - dejaRegle).clamp(0, double.infinity);

  /// « Ancienneté » du tableau des créances, en jours.
  int ancienneteJours(DateTime maintenant) =>
      maintenant.difference(dateVente).inDays;

  /// Seuil « Soldes Anciens » du KPI de l'écran (> 10 jours).
  bool estAncienne(DateTime maintenant) => ancienneteJours(maintenant) > 10;
}

/// Un événement CRM à venir — dérivé de la date de naissance du client.
class EvenementCrm {
  const EvenementCrm({
    required this.client,
    required this.type,
    required this.date,
    required this.joursRestants,
    this.dernierContact,
  });

  final String client;
  final String type;
  final DateTime date;
  final int joursRestants;
  final DateTime? dernierContact;

  static const String anniversaire = 'Anniversaire';
}
