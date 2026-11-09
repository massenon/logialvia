import '../entities/journee_elevage.dart';

/// Une semaine du tableau « Vue Hebdomadaire ».
class SemaineElevage {
  const SemaineElevage({
    required this.numero,
    required this.premierJour,
    required this.dernierJour,
    required this.cumulAchats,
    required this.cumulNaissances,
    required this.cumulMorts,
    required this.cumulVentes,
    required this.effectifDebut,
    required this.effectifFin,
    required this.aDesJourneesSaisies,
  });

  final int numero;
  final int premierJour;
  final int dernierJour;

  final int cumulAchats;
  final int cumulNaissances;
  final int cumulMorts;
  final int cumulVentes;

  /// Effectif au soir de la veille du premier jour de la semaine.
  final int effectifDebut;

  /// Effectif au soir du dernier jour **saisi** de la semaine.
  final int effectifFin;

  /// Faux quand aucune journée de la semaine n'a été enregistrée : la ligne
  /// existe — la semaine fait partie du mois — mais elle ne porte aucun chiffre.
  final bool aDesJourneesSaisies;

  /// Mortalité de la semaine rapportée à l'effectif de départ.
  ///
  /// `null` — et non 0 — si l'effectif de départ est nul : sans effectif, il n'y
  /// a pas de taux à calculer, et afficher « 0,0 % » laisserait croire à une
  /// semaine sans perte.
  ///
  /// Le dénominateur est l'effectif **exposé** au risque : effectif de départ + entrées
  /// de la semaine (`47e_`). Avec le seul effectif de départ, une bande arrivée en cours
  /// de semaine n'avait aucun taux (« — »), ou un taux supérieur à 100 %.
  double? get tauxMortalite {
    final expose = effectifDebut + cumulAchats + cumulNaissances;
    return expose <= 0 ? null : cumulMorts / expose * 100;
  }
}

/// Agrégation hebdomadaire du tableau mensuel — `renderWeeklyGrid()` de
/// `fiche-goliaths.html` l.794.
///
/// ## Deux corrections par rapport au prototype
///
/// 1. **Les découpes de semaines n'étaient pas calculées.** Le prototype code
///    `[[1,7],[8,14],[15,21],[22,31]]` en dur et étiquette « 22-31 **août** »,
///    le mois étant lui-même figé. En février, la 4ᵉ ligne annoncerait des
///    jours qui n'existent pas. Les bornes sont ici dérivées du mois affiché :
///    trois semaines de 7 jours, la dernière absorbant le reliquat (7 à 10
///    jours selon le mois).
/// 2. **La colonne « Traitements & Prophylaxie » n'est pas reprise d'ici.**
///    Le prototype la remplit avec `PROPHYLAXIE_MULTI_CALENDAR[jourDuMois]`,
///    or ce calendrier est indexé sur le **jour du cycle** (voir
///    `ProphylaxieDuJour`). L'écran affiche à la place les observations de
///    traitement réellement saisies sur les journées de la semaine.
class AgregationHebdomadaire {
  const AgregationHebdomadaire();

  /// Découpe le mois en 4 semaines, comme le prototype, mais en tenant compte
  /// de sa longueur réelle.
  List<SemaineElevage> calculer({
    required int nombreJoursDuMois,
    required Map<int, JourneeElevage> journees,
    required int effectifInitial,
  }) {
    final bornes = decouper(nombreJoursDuMois);
    final semaines = <SemaineElevage>[];

    for (var i = 0; i < bornes.length; i++) {
      final (debut, fin) = bornes[i];

      // Effectif de depart : celui du soir de la veille. Pour la premiere
      // semaine, c'est l'effectif de report du mois precedent.
      // Dernier effectif CONNU avant la semaine : une veille non saisie ne ramene pas a
      // l'effectif de debut de mois (`47e_`), elle laisse l'effectif de la derniere
      // journee saisie (sinon la semaine suivante partirait d'un effectif perime).
      var effectifDebut = effectifInitial;
      for (var j = 1; j < debut; j++) {
        final precedente = journees[j];
        if (precedente != null && precedente.isRecorded) {
          effectifDebut = precedente.effectif;
        }
      }

      var achats = 0;
      var naissances = 0;
      var morts = 0;
      var ventes = 0;
      var effectifFin = effectifDebut;
      var saisie = false;

      for (var jour = debut; jour <= fin; jour++) {
        final journee = journees[jour];
        if (journee == null || !journee.isRecorded) continue;
        saisie = true;
        achats += journee.achat;
        naissances += journee.ne;
        morts += journee.totalMorts;
        ventes += journee.vente;
        effectifFin = journee.effectif;
      }

      semaines.add(
        SemaineElevage(
          numero: i + 1,
          premierJour: debut,
          dernierJour: fin,
          cumulAchats: achats,
          cumulNaissances: naissances,
          cumulMorts: morts,
          cumulVentes: ventes,
          effectifDebut: effectifDebut,
          effectifFin: effectifFin,
          aDesJourneesSaisies: saisie,
        ),
      );
    }

    return semaines;
  }

  /// Les 4 découpes du mois. Trois semaines pleines, la dernière prend le
  /// reste — 7 jours en février, 10 en juillet.
  List<(int, int)> decouper(int nombreJoursDuMois) => [
    (1, 7),
    (8, 14),
    (15, 21),
    (22, nombreJoursDuMois),
  ];
}
