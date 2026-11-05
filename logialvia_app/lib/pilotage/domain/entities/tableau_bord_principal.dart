/// Severite d'une alerte, qui determine sa couleur (Doc E7 §4).
enum SeveriteAlerte { critique, avertissement }

/// Une ligne du panneau « Alertes Critiques » (dashboard.html l.196-204).
class AlerteCritique {
  const AlerteCritique({
    required this.message,
    required this.severite,
    required this.icone,
    required this.route,
  });

  final String message;
  final SeveriteAlerte severite;

  /// Nom d'icone Material Symbols.
  final String icone;

  /// Route ouverte au clic — jamais un lien mort (Doc E3 §5).
  final String route;
}

/// Un indicateur du bandeau KPI.
class IndicateurCle {
  const IndicateurCle({
    required this.libelle,
    required this.valeur,
    required this.unite,
    required this.detail,
    required this.icone,
    required this.accent,
    this.calculable = true,
  });

  final String libelle;

  /// Toujours une chaine, jamais nulle — un KPI a zero affiche « 0 »
  /// (Doc E7 §1, regle non negociable).
  final String valeur;

  /// Suffixe en petit a droite de la valeur : « FCFA », « têtes », « cycles »…
  final String unite;

  /// Ligne de detail sous la valeur.
  final String detail;

  final String icone;
  final AccentKpi accent;

  /// `false` quand la source de donnee n'existe pas encore dans
  /// l'application — la carte reste affichee (Doc E7 §1) mais son detail le dit
  /// explicitement, au lieu de laisser croire a un vrai zero metier.
  final bool calculable;
}

/// Couleur d'accent semantique de la bordure gauche (Doc E7 §4).
enum AccentKpi { navy, info, or, succes, erreur }

/// Recensement d'une filiere d'elevage (cartes du bas de dashboard.html
/// et cartes principales de elevage-dashboard.html).
class RecensementFiliere {
  const RecensementFiliere({
    required this.espece,
    required this.libelle,
    required this.icone,
    required this.route,
    required this.effectif,
    required this.effectifMatures,
    required this.libelleJeunes,
    required this.effectifJeunes,
    required this.tauxMortalite,
    required this.aDesDonnees,
  });

  final String espece;
  final String libelle;
  final String icone;
  final String route;
  final int effectif;
  final int effectifMatures;

  /// « Goliathaux », « Pintadaux »… — libelle propre a l'espece.
  final String libelleJeunes;
  final int effectifJeunes;

  /// En pourcentage, 1 decimale a l'affichage.
  final double tauxMortalite;

  /// `false` si aucune journee n'a encore ete saisie pour cette filiere.
  final bool aDesDonnees;
}

/// Bloc « Couveuse » des cartes de recensement.
class RecensementCouveuse {
  const RecensementCouveuse({
    required this.cyclesEnCours,
    required this.oeufsCharges,
    required this.tauxEclosionMoyen,
    required this.poussinsAttendus,
  });

  final int cyclesEnCours;
  final int oeufsCharges;

  /// En pourcentage. `null` si aucune eclosion n'a encore ete enregistree —
  /// une moyenne calculee sur zero echantillon n'a pas de sens (Doc E7 §1 :
  /// afficher « — », jamais un 0 trompeur).
  final double? tauxEclosionMoyen;

  final int poussinsAttendus;

  double? get tauxPerteMoyen =>
      tauxEclosionMoyen == null ? null : 100 - tauxEclosionMoyen!;
}

/// Une ligne du tableau « Meilleures Ventes du Mois ».
class MeilleureVente {
  const MeilleureVente({
    required this.produit,
    required this.quantite,
    required this.chiffreAffaires,
    required this.activite,
  });

  final String produit;
  final double quantite;
  final double chiffreAffaires;

  /// « Avicole » ou « Commerce » — colonne Activite du prototype.
  final String activite;
}

/// Une ligne du fil « Activités du Jour ».
class ActiviteJournal {
  const ActiviteJournal({
    required this.libelle,
    required this.horodatage,
    required this.auteur,
    required this.accent,
  });

  final String libelle;
  final DateTime horodatage;
  final String auteur;
  final AccentKpi accent;
}

/// Une transaction recente (onglets Vente / Achat / Dépenses).
class TransactionRecente {
  const TransactionRecente({
    required this.libelle,
    required this.montant,
    required this.enAvance,
  });

  final String libelle;
  final double montant;

  /// Vrai si la vente est en statut 'Avance' — affichee en or, suffixee
  /// « (avance) » comme dans dashboard.html l.279.
  final bool enAvance;
}

/// Point mensuel du graphique « CA vs Dépenses — 6 derniers mois ».
class PointMensuel {
  const PointMensuel({
    required this.libelleMois,
    required this.chiffreAffaires,
    required this.depenses,
  });

  final String libelleMois;
  final double chiffreAffaires;
  final double depenses;
}

/// Point journalier des barres « Statistiques de Ventes ».
class PointJournalier {
  const PointJournalier({
    required this.libelleJour,
    required this.recettes,
    required this.depenses,
  });

  final String libelleJour;
  final double recettes;
  final double depenses;
}
