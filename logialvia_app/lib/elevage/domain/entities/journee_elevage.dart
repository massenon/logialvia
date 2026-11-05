/// Une journée d'une fiche d'élevage — projection de `FICHE_JOURNEE` (Doc D1).
class JourneeElevage {
  const JourneeElevage({
    required this.espece,
    required this.date,
    required this.achat,
    required this.ne,
    required this.vente,
    required this.mortsParCategorie,
    required this.donsParCategorie,
    required this.effectif,
    required this.effectifsParCategorie,
    required this.isRecorded,
    this.poidsGeneralG,
    this.traitementObs,
    this.traitementValide = false,
    this.srh,
    this.totalStock,
    this.stockFinalOeufs,
    this.oeufsPondus,
    this.oeufsCasses,
    this.sortiesPlateaux,
  });

  /// Journée vierge, non saisie — utilisée pour compléter les jours d'un mois
  /// sans enregistrement.
  factory JourneeElevage.vierge({
    required String espece,
    required DateTime date,
    required int nombreCategories,
  }) {
    return JourneeElevage(
      espece: espece,
      date: date,
      achat: 0,
      ne: 0,
      vente: 0,
      mortsParCategorie: List<int>.filled(nombreCategories, 0),
      donsParCategorie: List<int>.filled(nombreCategories, 0),
      effectif: 0,
      effectifsParCategorie: List<int>.filled(nombreCategories, 0),
      isRecorded: false,
    );
  }

  final String espece;
  final DateTime date;
  final int achat;
  final int ne;
  final int vente;
  final List<int> mortsParCategorie;
  final List<int> donsParCategorie;

  /// Calculé, jamais saisi (BR-ELV-007, Doc 05 §6).
  final int effectif;
  final List<int> effectifsParCategorie;

  final bool isRecorded;
  final int? poidsGeneralG;
  final String? traitementObs;
  final bool traitementValide;

  /// Pondeuses uniquement (Doc 05 §4) — **résultats calculés**.
  final int? srh;
  final int? totalStock;
  final int? stockFinalOeufs;

  /// Pondeuses uniquement — **saisies** dont dérivent les 3 valeurs ci-dessus.
  final int? oeufsPondus;
  final int? oeufsCasses;
  final int? sortiesPlateaux;

  int get totalMorts => mortsParCategorie.fold(0, (s, v) => s + v);
  int get totalDons => donsParCategorie.fold(0, (s, v) => s + v);

  JourneeElevage copyWith({
    int? achat,
    int? ne,
    int? vente,
    List<int>? mortsParCategorie,
    List<int>? donsParCategorie,
    int? effectif,
    List<int>? effectifsParCategorie,
    bool? isRecorded,
    int? poidsGeneralG,
    String? traitementObs,
    bool? traitementValide,
    int? srh,
    int? totalStock,
    int? stockFinalOeufs,
    int? oeufsPondus,
    int? oeufsCasses,
    int? sortiesPlateaux,
  }) {
    return JourneeElevage(
      espece: espece,
      date: date,
      achat: achat ?? this.achat,
      ne: ne ?? this.ne,
      vente: vente ?? this.vente,
      mortsParCategorie: mortsParCategorie ?? this.mortsParCategorie,
      donsParCategorie: donsParCategorie ?? this.donsParCategorie,
      effectif: effectif ?? this.effectif,
      effectifsParCategorie:
          effectifsParCategorie ?? this.effectifsParCategorie,
      isRecorded: isRecorded ?? this.isRecorded,
      poidsGeneralG: poidsGeneralG ?? this.poidsGeneralG,
      traitementObs: traitementObs ?? this.traitementObs,
      traitementValide: traitementValide ?? this.traitementValide,
      srh: srh ?? this.srh,
      totalStock: totalStock ?? this.totalStock,
      stockFinalOeufs: stockFinalOeufs ?? this.stockFinalOeufs,
      oeufsPondus: oeufsPondus ?? this.oeufsPondus,
      oeufsCasses: oeufsCasses ?? this.oeufsCasses,
      sortiesPlateaux: sortiesPlateaux ?? this.sortiesPlateaux,
    );
  }
}
