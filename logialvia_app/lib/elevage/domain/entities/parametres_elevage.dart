/// Un barème de rationnement — `parametres-elevage.html` Onglet 1.
class BaremeRation {
  const BaremeRation({
    required this.id,
    required this.espece,
    required this.stade,
    required this.rationGrammesParJour,
    required this.confirme,
  });

  final String id;
  final String espece;
  final String stade;
  final int rationGrammesParJour;

  /// Le prototype distingue deux natures de barème :
  /// « Confirmé (Référence Cuniculture) » et « Générique (Aviculture, à
  /// confirmer) ». Ce n'est pas cosmétique : un barème générique signale à la
  /// Gérante une valeur qu'elle doit encore valider.
  final bool confirme;

  /// Filières ajoutées après le prototype (DV-16, DV-17) : leurs barèmes ne
  /// sont pas une reprise de l'aviculture, ce sont des repères à valider.
  static const Set<String> _especesAjoutees = {'escargots', 'bovins'};

  String get badge {
    // Le libelle du prototype ne vaut que pour les lapins, seuls barèmes qu'il
    // portait comme confirmés ; un barème validé depuis l'écran est « Validé ».
    if (confirme) {
      return espece == 'lapins' ? 'Confirmé (Référence Cuniculture)' : 'Validé';
    }
    if (_especesAjoutees.contains(espece)) return 'Repère à valider';
    return 'Générique (Aviculture, à confirmer)';
  }
}

/// Une classe de poids vif et son taux de ration — DV-17.
///
/// La classe couvre `[poidsMinG, poidsMaxG[` (borne haute exclue, `null` =
/// ouverte vers le haut). Les poids sont en grammes, comme la pesée de la
/// fiche journalière ; [libelleClasse] les affiche en kilos.
class TauxRationPoids {
  const TauxRationPoids({
    required this.id,
    required this.espece,
    required this.poidsMinG,
    required this.poidsMaxG,
    required this.tauxPourcent,
    required this.confirme,
  });

  final String id;
  final String espece;
  final int poidsMinG;
  final int? poidsMaxG;

  /// Pourcentage du poids vif par jour, en matière sèche.
  final double tauxPourcent;
  final bool confirme;

  /// Vrai si [poidsMoyenG] tombe dans la classe.
  bool contient(double poidsMoyenG) =>
      poidsMoyenG >= poidsMinG &&
      (poidsMaxG == null || poidsMoyenG < poidsMaxG!);

  /// « 150 » ou « 0,5 » — nombre sans unité, virgule décimale.
  static String _nombre(double valeur) => valeur == valeur.roundToDouble()
      ? valeur.round().toString()
      : valeur.toStringAsFixed(1).replaceAll('.', ',');

  /// Un poids avec son unité : en grammes sous 1 kg, en kilos au-delà.
  static ({String nombre, String unite}) _poids(int grammes) => grammes < 1000
      ? (nombre: grammes.toString(), unite: 'g')
      : (nombre: _nombre(grammes / 1000), unite: 'kg');

  /// « Moins de 150 kg », « De 5 à moins de 20 g », « 500 g et plus » : l'unité
  /// n'est répétée que si les deux bornes n'ont pas la même.
  String get libelleClasse {
    final max = poidsMaxG;
    final bas = _poids(poidsMinG);
    if (poidsMinG <= 0 && max != null) {
      final haut = _poids(max);
      return 'Moins de ${haut.nombre} ${haut.unite}';
    }
    if (max == null) return '${bas.nombre} ${bas.unite} et plus';
    final haut = _poids(max);
    return bas.unite == haut.unite
        ? 'De ${bas.nombre} à moins de ${haut.nombre} ${haut.unite}'
        : 'De ${bas.nombre} ${bas.unite} à moins de ${haut.nombre} ${haut.unite}';
  }

  String get libelleTaux => '${tauxPourcent.toString().replaceAll('.', ',')} %';
}

/// Une échéance du calendrier de prophylaxie — Onglet 2.
class EcheanceProphylaxie {
  const EcheanceProphylaxie({
    required this.id,
    required this.espece,
    required this.jourCycle,
    required this.traitement,
    required this.produit,
    required this.remanenceJours,
    this.dose,
  });

  final String id;
  final String espece;
  final int jourCycle;
  final String traitement;
  final String produit;
  final int remanenceJours;

  /// Dose, texte libre ; `null` tant que l'animalier ne l'a pas renseignee.
  final String? dose;

  String get libelleJour => 'J$jourCycle';
}

/// Formats de numérotation des bandes et sujets — Onglet 4.
class FormatsNumerotation {
  const FormatsNumerotation({
    this.enclos = 'E',
    this.cage = 'C',
    this.bande = 'B',
    this.bassin = 'B',
    this.bac = 'BAC',
    this.parc = 'PARC',
  });

  final String enclos;
  final String cage;
  final String bande;
  final String bassin;

  /// Bacs des escargots (DV-16) et parcs des bovins (DV-17).
  final String bac;
  final String parc;

  /// Aperçus en temps réel, repris tels quels de `updateNumerotationPreviews()`.
  String get apercuEnclos => '${enclos}1, ${enclos}2, ${enclos}3';
  String get apercuCage => '${cage}1, ${cage}2, ${cage}5, ${cage}12';
  String get apercuBande => '${bande}1, ${bande}2';
  String get apercuBassin => '${bassin}1, ${bassin}2, ${bassin}3';
  String get apercuBac => '${bac}1, ${bac}2, ${bac}3';
  String get apercuParc => '${parc}1, ${parc}2, ${parc}3';

  FormatsNumerotation copyWith({
    String? enclos,
    String? cage,
    String? bande,
    String? bassin,
    String? bac,
    String? parc,
  }) => FormatsNumerotation(
    enclos: enclos ?? this.enclos,
    cage: cage ?? this.cage,
    bande: bande ?? this.bande,
    bassin: bassin ?? this.bassin,
    bac: bac ?? this.bac,
    parc: parc ?? this.parc,
  );
}

/// Un intrant de provende, tel qu'affiché dans l'onglet du même nom.
///
/// ## ÉCART_DELIBERE — l'onglet n'est plus en lecture seule
///
/// `parametres-elevage.html` intitule ce tableau « Types de Provende » et le
/// déclare en lecture seule : « Le stock de ces 5 intrants se gère
/// exclusivement depuis Gestion Stocks / Fabrication de Provende — lecture
/// seule ici. »
///
/// À la demande de la Gérante, l'onglet devient administrable : ajout, édition
/// et suppression d'un intrant de provende s'y font directement, et le libellé
/// devient « **Intrants de Provende** » — ce sont bien des intrants nommés, pas
/// des types abstraits.
///
/// **Ce qui reste vrai de la note d'origine** : la *quantité* en stock ne se
/// saisit toujours pas ici. Elle ne bouge que par une réception de commande,
/// une fabrication de provende ou un ajustement d'inventaire — chacun laissant
/// sa trace dans `MOUVEMENTS_INTRANT`. Permettre de la retoucher à la main
/// depuis un écran de paramétrage contournerait précisément la traçabilité que
/// le Cahier des Charges Technique §6.2 impose.
class TypeProvende {
  const TypeProvende({
    required this.code,
    required this.nom,
    required this.stock,
    required this.unite,
    required this.prixIndicatif,
    required this.seuil,
  });

  /// Code de l'intrant dans `INTRANTS` — « INT-001 ». Nécessaire pour éditer
  /// ou supprimer la ligne depuis cet écran.
  final String code;

  final String nom;
  final double stock;
  final String unite;
  final double prixIndicatif;
  final double seuil;

  /// Stock sous le seuil d'alerte — affiché en rouge, comme dans le prototype
  /// où seul le Maïs (18 kg) porte `text-error-deep`.
  bool get critique => stock <= seuil;
}

/// Les 6 espèces proposées par les filtres et le sélecteur de prophylaxie
/// (les 4 d'origine, plus escargots et bovins).
class EspecesParametrables {
  EspecesParametrables._();

  /// (identifiant technique, libellé affiché, emoji du sélecteur de
  /// prophylaxie) — `parametres-elevage.html` l.60-64.
  static const List<({String id, String libelle, String emoji})> toutes = [
    (id: 'goliaths', libelle: 'Goliaths', emoji: '🐔'),
    (id: 'pintades', libelle: 'Pintades', emoji: '🦃'),
    (id: 'lapins', libelle: 'Lapins', emoji: '🐰'),
    (id: 'poissons-chats', libelle: 'Poissons-Chats', emoji: '🐟'),
    (id: 'escargots', libelle: 'Escargots', emoji: '🐌'),
    (id: 'bovins', libelle: 'Bovins', emoji: '🐄'),
  ];

  static String libelle(String identifiant) {
    for (final e in toutes) {
      if (e.id == identifiant) return e.libelle;
    }
    return identifiant;
  }
}
