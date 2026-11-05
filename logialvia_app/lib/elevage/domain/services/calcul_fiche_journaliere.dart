import '../entities/configuration_espece.dart';

/// Mouvements saisis pour une journee.
class MouvementsJour {
  const MouvementsJour({
    this.achat = 0,
    this.ne = 0,
    this.vente = 0,
    this.mortsParCategorie = const [],
    this.donsParCategorie = const [],
  });

  final int achat;
  final int ne;
  final int vente;

  /// Indexes alignes sur [ConfigurationEspece.categories].
  final List<int> mortsParCategorie;
  final List<int> donsParCategorie;

  int get totalMorts => mortsParCategorie.fold(0, (s, v) => s + v);
  int get totalDons => donsParCategorie.fold(0, (s, v) => s + v);

  int mortsCategorie(int index) =>
      index < mortsParCategorie.length ? mortsParCategorie[index] : 0;

  int donsCategorie(int index) =>
      index < donsParCategorie.length ? donsParCategorie[index] : 0;
}

/// Effectifs calcules d'une journee.
class EffectifsJour {
  const EffectifsJour({
    required this.effectifTotal,
    required this.parCategorie,
    required this.tauxMortalite,
  });

  final int effectifTotal;

  /// Indexes alignes sur [ConfigurationEspece.categories].
  final List<int> parCategorie;

  /// En pourcentage.
  final double tauxMortalite;

  int categorie(int index) =>
      index < parCategorie.length ? parCategorie[index] : 0;
}

/// Traduction Dart de Doc 05 — **le document le plus critique du projet**.
///
/// ## Le bug historique a ne JAMAIS reintroduire (Doc 05 §1)
///
/// Les fiches utilisaient une repartition en pourcentage fixe, deconnectee des
/// saisies :
/// ```dart
/// final effCat1 = (effectifFinal * 0.35).round(); // ❌ INTERDIT
/// ```
/// Une mortalite saisie sur une categorie precise faisait alors bouger **toutes**
/// les categories proportionnellement. La regle correcte, appliquee ici :
/// **chaque categorie ne perd QUE ses propres morts et dons saisis**.
///
/// Verifie ligne a ligne contre le JS reel de `fiche-goliaths.html` l.633-642.
class CalculFicheJournaliere {
  const CalculFicheJournaliere(
    this.configuration, {
    this.rationsConfigurees = const {},
  });

  final ConfigurationEspece configuration;

  /// Rations issues de l'écran **Paramètres Élevage**, indexées par libellé de
  /// stade — `parametres-elevage.html` Onglet 1.
  ///
  /// Le prototype affirme que cet écran « est la CONFIGURATION » des barèmes
  /// « utilisés pour le calcul automatique dans les fiches journalières ». Sans
  /// cette injection, modifier une ration dans les paramètres n'aurait aucun
  /// effet sur la provende calculée : l'écran serait décoratif (Master Prompt
  /// §2.3) et il existerait deux vérités pour une même donnée.
  ///
  /// La valeur de [ConfigurationEspece] reste la référence par défaut : elle
  /// s'applique tant qu'aucun barème n'a été enregistré pour ce stade.
  final Map<String, int> rationsConfigurees;

  /// Ration effective d'une catégorie, en g/tête/jour.
  int rationCategorie(int index) {
    if (index < 0 || index >= configuration.categories.length) return 0;
    final categorie = configuration.categories[index];
    return rationsConfigurees[categorie.libelle] ??
        categorie.rationGrammesParJour;
  }

  /// Garde-fou de Doc 05 : aucun effectif ne peut devenir negatif (BR-ELV-001).
  static const int _plafond = 999999;

  /// Calcule les effectifs d'une journee a partir de ceux de la veille.
  ///
  /// [effectifsVeille] : sous-effectifs par categorie au jour precedent.
  /// Pour le tout premier jour, passer [repartitionInitiale].
  EffectifsJour calculerJour({
    required List<int> effectifsVeille,
    required int effectifTotalVeille,
    required MouvementsJour mouvements,
  }) {
    final resultat = <int>[];

    for (var i = 0; i < configuration.categories.length; i++) {
      final categorie = configuration.categories[i];
      final precedent = i < effectifsVeille.length ? effectifsVeille[i] : 0;

      var valeur = precedent;
      // Achats et naissances alimentent TOUJOURS la categorie la plus jeune.
      if (categorie.recoitAchatEtNaissances) {
        valeur += mouvements.achat + mouvements.ne;
      }
      // La vente est TOUJOURS deduite de la seule categorie commercialisee.
      // Pour Goliaths c'est « Goliathau », PAS « Mature » — malgre le libelle
      // « Mature — Éligible à la Vente » du bandeau de cycle, qui decrit
      // l'eligibilite commerciale et non la categorie decrementee
      // (verifie sur fiche-goliaths.html l.638).
      if (categorie.deduiteDesVentes) {
        valeur -= mouvements.vente;
      }
      valeur -= mouvements.mortsCategorie(i) + mouvements.donsCategorie(i);

      resultat.add(valeur.clamp(0, _plafond));
    }

    final effectifTotal =
        (effectifTotalVeille +
                mouvements.achat +
                mouvements.ne -
                mouvements.totalMorts -
                mouvements.vente -
                mouvements.totalDons)
            .clamp(0, _plafond);

    return EffectifsJour(
      effectifTotal: effectifTotal,
      parCategorie: resultat,
      tauxMortalite: tauxMortaliteJour(
        mouvements.totalMorts,
        effectifTotalVeille,
      ),
    );
  }

  /// (Morts du jour ÷ Effectif J-1) × 100 — Doc 05 §3.
  static double tauxMortaliteJour(int totalMorts, int effectifVeille) =>
      effectifVeille > 0 ? (totalMorts / effectifVeille) * 100 : 0.0;

  /// Repartition du tout premier jour, sans historique — Doc 05 §2.
  ///
  /// Ratio 35 % / 35 % / reste, **explicitement signale comme une donnee de
  /// demonstration et non une regle metier reelle de la ferme** (Doc 05 §2).
  /// Conserve tel quel pour rester fidele au prototype ; sans effectif de
  /// depart (cas d'une base neuve), il produit naturellement des zeros et la
  /// question du ratio ne se pose pas.
  List<int> repartitionInitiale(int effectifDeBase) {
    final nombre = configuration.categories.length;
    if (nombre == 0 || effectifDeBase <= 0) {
      return List<int>.filled(nombre, 0);
    }

    final jeune = (effectifDeBase * 0.35).round();
    final commercialisee = (effectifDeBase * 0.35).round();
    final reste = (effectifDeBase - jeune - commercialisee).clamp(0, _plafond);

    final resultat = List<int>.filled(nombre, 0);
    final indexJeune = configuration.indexCategorieJeune;
    final indexCommercialisee = configuration.indexCategorieCommercialisee;

    if (indexJeune >= 0) resultat[indexJeune] = jeune;
    if (indexCommercialisee >= 0) resultat[indexCommercialisee] = commercialisee;

    // Le reste va a la premiere categorie qui n'est ni jeune ni commercialisee.
    final indexReste = List.generate(
      nombre,
      (i) => i,
    ).firstWhere((i) => i != indexJeune && i != indexCommercialisee, orElse: () => -1);
    if (indexReste >= 0) resultat[indexReste] = reste;

    return resultat;
  }

  /// Provende totale du jour, en grammes.
  ///
  /// Bug historique corrige (Doc 05 §4) : le total ne sommait autrefois que la
  /// categorie commercialisee. Il somme ici **toutes** les categories.
  int provendeTotaleGrammes(List<int> effectifsParCategorie) {
    var total = 0;
    for (var i = 0; i < configuration.categories.length; i++) {
      final effectif = i < effectifsParCategorie.length
          ? effectifsParCategorie[i]
          : 0;
      total += effectif * rationCategorie(i);
    }
    return total;
  }

  /// Poids moyen d'un sujet, en grammes (fiche-goliaths.html l.671-676).
  static int poidsMoyenGrammes({
    required int poidsTotalGrammes,
    required int effectif,
  }) {
    if (effectif <= 0) return 0;
    return (poidsTotalGrammes / effectif).round();
  }
}

/// Suivi du stock d'oeufs des Pondeuses — Doc 05 §4.
///
/// ## Le bug le plus grave trouve sur ce projet
///
/// > SRH du jour J+1 = **Stock Final** du jour J — et **non** Total Stock (TS)
/// > du jour J. Les deux ne coincident que les jours sans sortie de plateaux.
///
/// Le piege d'implementation d'origine reassignait l'accumulateur AVANT de
/// l'avoir stocke comme ouverture du jour : chaque jour affichait alors son
/// propre stock final au lieu du stock herite de la veille. Ce piege est evite
/// structurellement ici en recevant `srhOuverture` comme parametre distinct,
/// capture avant tout calcul.
class CalculStockOeufs {
  const CalculStockOeufs._();

  /// Un plateau contient 30 oeufs.
  static const int oeufsParPlateau = 30;

  static ResultatStockOeufs calculerJour({
    required int srhOuverture,
    required int oeufsPondus,
    required int oeufsCasses,
    required int sortiesPlateaux,
  }) {
    final commercialisables = (oeufsPondus - oeufsCasses).clamp(0, 999999);
    final totalStock = commercialisables + srhOuverture;
    final sortiesOeufs = sortiesPlateaux * oeufsParPlateau;
    final stockFinal = (totalStock - sortiesOeufs).clamp(0, 999999);

    return ResultatStockOeufs(
      srh: srhOuverture,
      totalStock: totalStock,
      sortiesOeufs: sortiesOeufs,
      stockFinal: stockFinal,
    );
  }
}

class ResultatStockOeufs {
  const ResultatStockOeufs({
    required this.srh,
    required this.totalStock,
    required this.sortiesOeufs,
    required this.stockFinal,
  });

  /// Stock Restant Hier — ouverture du jour.
  final int srh;

  /// Total Stock du jour.
  final int totalStock;

  final int sortiesOeufs;

  /// Stock Final — c'est **cette** valeur qui devient le SRH du lendemain.
  final int stockFinal;
}
