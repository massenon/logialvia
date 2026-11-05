import '../entities/cycle_incubation.dart';

/// Ce qu'un lot apprend sur la qualité des œufs et la conduite de la machine.
class StatistiquesLot {
  const StatistiquesLot({required this.lot});

  final CycleIncubation lot;

  int get charges => lot.oeufsCharges;

  /// Œufs clairs retirés au premier mirage — **jamais fécondés**.
  int? get clairs => lot.oeufsBlancsJ7;

  /// Œufs gâtés retirés au second mirage — embryon démarré puis **arrêté**.
  int? get gates => lot.oeufsGatesJ14;

  int get retenus => lot.oeufsRetenusApresMirages;
  int? get eclos => lot.poussinsEclos;

  bool get mirage1Fait => clairs != null;
  bool get mirage2Fait => gates != null;
  bool get miragesComplets => mirage1Fait && mirage2Fait;

  /// Taux d'infertilité — clairs ÷ chargés.
  ///
  /// Il ne juge **pas** la couveuse : un œuf clair n'a jamais été fécondé, la
  /// machine n'y est pour rien. C'est le troupeau de reproducteurs qu'il met en
  /// cause — un coq trop vieux, un ratio mâle/femelle déréglé.
  double? get tauxInfertilite =>
      clairs == null || charges <= 0 ? null : clairs! / charges * 100;

  /// Mortalité embryonnaire — gâtés ÷ œufs encore présents au second mirage.
  ///
  /// Rapportée aux œufs **restants après le premier mirage**, pas aux œufs
  /// chargés : les clairs ne sont pas morts, ils n'ont jamais vécu. Les inclure
  /// au dénominateur diluerait le taux et masquerait un vrai problème de
  /// conduite (température, hygrométrie, retournement).
  double? get mortaliteEmbryonnaire {
    if (gates == null) return null;
    final presents = charges - (clairs ?? 0);
    if (presents <= 0) return null;
    return gates! / presents * 100;
  }

  /// Taux d'éclosion réel — éclos ÷ œufs retenus après les deux mirages.
  double? get ter => lot.tauxEclosionReel;

  /// Taux d'éclosion brut — éclos ÷ œufs chargés.
  double? get tauxBrut =>
      eclos == null || charges <= 0 ? null : eclos! / charges * 100;

  /// Œufs perdus en tout : clairs, gâtés, et ceux qui n'ont pas éclos.
  int? get pertes {
    if (eclos == null) return null;
    return charges - eclos!;
  }

  double? get tauxPerte =>
      pertes == null || charges <= 0 ? null : pertes! / charges * 100;
}

/// Agrégat des mirages sur un ensemble de lots.
///
/// ## Pourquoi cet écran existe
///
/// Le TER seul ne dit pas **d'où vient** une mauvaise éclosion. Trois causes
/// distinctes se cachent derrière un même chiffre décevant :
///
/// | Constat | Cause | Responsable |
/// |---|---|---|
/// | Beaucoup de clairs au J+7 | œufs non fécondés | le troupeau reproducteur |
/// | Beaucoup de gâtés au J+14 | embryons arrêtés | la conduite de la machine |
/// | Peu d'éclos sur les retenus | éclosion ratée | la fin d'incubation |
///
/// Séparer les trois est tout l'intérêt des mirages. Les additionner dans un
/// « taux de perte » unique reviendrait à jeter l'information au moment où elle
/// devient utile.
class StatistiquesMirages {
  const StatistiquesMirages(this.lots);

  final List<CycleIncubation> lots;

  List<StatistiquesLot> get parLot =>
      [for (final l in lots) StatistiquesLot(lot: l)];

  int get nombreLots => lots.length;

  int get chargesTotal =>
      lots.fold<int>(0, (s, l) => s + l.oeufsCharges);

  /// Somme des clairs, sur les seuls lots dont le mirage 1 est fait.
  int get clairsTotal =>
      lots.fold<int>(0, (s, l) => s + (l.oeufsBlancsJ7 ?? 0));

  int get gatesTotal =>
      lots.fold<int>(0, (s, l) => s + (l.oeufsGatesJ14 ?? 0));

  int get retenusTotal =>
      lots.fold<int>(0, (s, l) => s + l.oeufsRetenusApresMirages);

  /// Éclos, sur les seuls lots ayant réellement éclos.
  int get eclosTotal =>
      lots.fold<int>(0, (s, l) => s + (l.poussinsEclos ?? 0));

  /// Base de calcul des taux de mirage : les lots dont le mirage est fait.
  ///
  /// Rapporter les clairs à **tous** les œufs chargés, mirages faits ou non,
  /// donnerait un taux d'autant plus bas que des mirages manquent — la
  /// négligence ressemblerait à un bon résultat.
  int get chargesAvecMirage1 => lots
      .where((l) => l.oeufsBlancsJ7 != null)
      .fold<int>(0, (s, l) => s + l.oeufsCharges);

  int get presentsAvecMirage2 => lots
      .where((l) => l.oeufsGatesJ14 != null)
      .fold<int>(0, (s, l) => s + l.oeufsCharges - (l.oeufsBlancsJ7 ?? 0));

  /// Œufs retenus des seuls lots ayant éclos — dénominateur du TER.
  int get retenusDesLotsEclos => lots
      .where((l) => l.poussinsEclos != null)
      .fold<int>(0, (s, l) => s + l.oeufsRetenusApresMirages);

  double? get tauxInfertilite => chargesAvecMirage1 <= 0
      ? null
      : clairsTotal / chargesAvecMirage1 * 100;

  double? get mortaliteEmbryonnaire => presentsAvecMirage2 <= 0
      ? null
      : gatesTotal / presentsAvecMirage2 * 100;

  double? get ter =>
      retenusDesLotsEclos <= 0 ? null : eclosTotal / retenusDesLotsEclos * 100;

  /// Perte totale sur les lots clôturés — la seule population où « perdu » a
  /// un sens : un lot encore en machine n'a rien perdu, il n'a pas fini.
  double? get tauxPerte {
    final closes = lots.where((l) => l.poussinsEclos != null);
    final charges = closes.fold<int>(0, (s, l) => s + l.oeufsCharges);
    if (charges <= 0) return null;
    final eclos = closes.fold<int>(0, (s, l) => s + l.poussinsEclos!);
    return (charges - eclos) / charges * 100;
  }

  /// Lots en cours dont un mirage est déjà dû mais n'a pas été saisi.
  ///
  /// C'est le trou qui fausse tout le reste : un mirage oublié gonfle le
  /// dénominateur du TER et fait passer une bonne couvée pour une mauvaise.
  List<CycleIncubation> miragesManquants(DateTime t) {
    final jour = DateTime(t.year, t.month, t.day);
    return lots.where((l) {
      if (!l.estEnCours) return false;
      final m1Du = !jour.isBefore(_minuit(l.dateMirage1)) &&
          l.oeufsBlancsJ7 == null;
      final m2Du = !jour.isBefore(_minuit(l.dateMirage2)) &&
          l.oeufsGatesJ14 == null;
      return m1Du || m2Du;
    }).toList();
  }

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);
}
