/// Une espèce couvable, avec sa durée d'incubation.
///
/// ⚠️ **Doc F3 énonçait « Éclosion attendue = Date Incubation + 21 jours »
/// comme une règle unique. C'est faux** : la modale réelle de création de cycle
/// propose deux espèces avec des durées distinctes
/// (`cycle-couveuse.html` l.232-233).
///
/// ⚠️ **La pintade incube 28 jours, pas 27.** Le prototype écrit
/// `data-duree="27"` ; la Gérante a corrigé cette valeur. 27 avancerait
/// l'éclosion prévue d'un jour, donc l'alerte de mirage et la relève des
/// poussins — sur un couvoir en continu, l'erreur se répète à chaque lot.
enum EspeceCouvable {
  goliath(identifiant: 'goliath', libelle: 'Goliath', dureeIncubationJours: 21),
  pintade(identifiant: 'pintade', libelle: 'Pintade', dureeIncubationJours: 28);

  const EspeceCouvable({
    required this.identifiant,
    required this.libelle,
    required this.dureeIncubationJours,
  });

  final String identifiant;
  final String libelle;
  final int dureeIncubationJours;

  /// Jour du **premier mirage** — retrait des œufs clairs (« blancs »).
  /// Identique pour les deux espèces.
  static const int jourMirage1 = 7;

  /// Jour du **second mirage** — retrait des œufs gâtés.
  static const int jourMirage2 = 14;

  static EspeceCouvable? depuisIdentifiant(String valeur) {
    for (final espece in values) {
      if (espece.identifiant == valeur) return espece;
    }
    return null;
  }

  /// Durée d'une espèce inconnue : on retombe sur Goliath (21 j) plutôt que de
  /// planter, mais c'est un cas qui ne doit pas exister — les seules valeurs
  /// persistées viennent de cet enum.
  static int dureeJours(String identifiantEspece) =>
      depuisIdentifiant(identifiantEspece)?.dureeIncubationJours ??
      goliath.dureeIncubationJours;
}

/// Statuts d'un lot d'incubation.
///
/// Trois valeurs, conformément au suivi multi-âges : un lot est en incubation,
/// puis clôturé par son éclosion, et **remplacé** si un sous-lot a été inséré
/// dans la machine pour combler le vide qu'il laisse.
///
/// « Remplacé » n'efface pas l'éclosion : les poussins nés, les pertes et le
/// TER restent lisibles sur le lot. Le statut dit seulement que sa place dans
/// la machine est reprise.
class StatutCycle {
  StatutCycle._();

  static const String enIncubation = 'En Incubation';
  static const String eclosionEffectuee = 'Éclosion Effectuée';
  static const String remplace = 'Remplacé';

  static const List<String> tous = [
    enIncubation,
    eclosionEffectuee,
    remplace,
  ];
}

/// Une échéance du calendrier d'incubation.
enum TypeEcheance {
  mirage1('Mirage 1', 'Retrait des œufs clairs'),
  mirage2('Mirage 2', 'Retrait des œufs gâtés'),
  eclosion('Éclosion', 'Relève des poussins');

  const TypeEcheance(this.libelle, this.detail);

  final String libelle;
  final String detail;
}

/// Une alerte du couvoir : une échéance atteinte ou dépassée sur un lot.
class AlerteIncubation {
  const AlerteIncubation({
    required this.lot,
    required this.type,
    required this.dateEcheance,
    required this.joursDecart,
  });

  final CycleIncubation lot;
  final TypeEcheance type;
  final DateTime dateEcheance;

  /// Négatif si l'échéance est à venir, 0 le jour même, positif si dépassée.
  final int joursDecart;

  bool get estAujourdhui => joursDecart == 0;
  bool get estEnRetard => joursDecart > 0;
}

/// Un lot d'incubation — ou un **sous-lot**, s'il en remplace un autre.
///
/// ## Suivi multi-âges
///
/// La couveuse tourne en continu : plusieurs lots d'âges différents y
/// cohabitent, et chaque lot suit **son propre calendrier** à partir de sa date
/// d'insertion. Un sous-lot n'hérite donc d'aucune date de son parent — il
/// n'hérite que du lien de traçabilité.
class CycleIncubation {
  const CycleIncubation({
    required this.id,
    required this.code,
    required this.espece,
    required this.dateChargement,
    required this.oeufsCharges,
    required this.statut,
    this.poussinsEclos,
    this.oeufsPerdus,
    this.machineId,
    this.machineCode,
    this.oeufsBlancsJ7,
    this.oeufsGatesJ14,
    this.lotParentId,
    this.lotParentCode,
  });

  final String id;
  final String code;
  final EspeceCouvable espece;

  /// Jour 0 — date d'insertion des œufs dans la machine.
  final DateTime dateChargement;

  /// `E_i(0)` de la formule du TER : quantité initiale du lot.
  final int oeufsCharges;

  final String statut;

  /// `E_i(21/28)` : œufs éclos, `null` tant que l'éclosion n'est pas saisie.
  final int? poussinsEclos;

  /// Pertes constatées **à l'éclosion**, hors mirages : œufs non éclos ou
  /// cassés. Distinctes des blancs et des gâtés, retirés bien plus tôt.
  final int? oeufsPerdus;

  /// Incubateur occupé — plusieurs machines peuvent tourner en parallèle.
  final String? machineId;
  final String? machineCode;

  /// `B_i(7)` : œufs clairs retirés au premier mirage.
  final int? oeufsBlancsJ7;

  /// `M_i(14)` : œufs gâtés retirés au second mirage.
  final int? oeufsGatesJ14;

  /// Lot d'origine si celui-ci le remplace. `null` pour un lot racine.
  final String? lotParentId;
  final String? lotParentCode;

  bool get estEnCours => statut == StatutCycle.enIncubation;
  bool get estEclos => !estEnCours;
  bool get estRemplace => statut == StatutCycle.remplace;
  bool get estSousLot => lotParentId != null;

  /// Pour un sous-lot, sa date d'insertion **est** la date de remplacement du
  /// lot parent. Elle n'est pas stockée deux fois : deux copies finiraient par
  /// diverger.
  DateTime? get dateRemplacement => estSousLot ? dateChargement : null;

  /// De même, la quantité initiale d'un sous-lot **est** la quantité remplacée.
  int? get quantiteRemplacee => estSousLot ? oeufsCharges : null;

  // ------------------------------------------------------ calendrier du lot

  /// Date du premier mirage — J+7.
  DateTime get dateMirage1 =>
      dateChargement.add(const Duration(days: EspeceCouvable.jourMirage1));

  /// Date du second mirage — J+14.
  DateTime get dateMirage2 =>
      dateChargement.add(const Duration(days: EspeceCouvable.jourMirage2));

  /// Date d'éclosion prévisionnelle — J+21 (Goliath) ou J+28 (Pintade).
  /// **Calculée à l'affichage, jamais saisie** (Doc F3, règle métier).
  DateTime get dateEclosionPrevue =>
      dateChargement.add(Duration(days: espece.dureeIncubationJours));

  /// Tolérance de la date d'éclosion, en jours.
  ///
  /// Une éclosion ne tombe pas au jour dit : la température, l'hygrométrie et
  /// l'âge des reproducteurs l'avancent ou la retardent. La Gérante suit une
  /// fenêtre de **deux jours de part et d'autre** — c'est elle qui a donné ce
  /// chiffre, il n'est pas déduit d'une moyenne.
  ///
  /// Annoncer une date au jour près ferait passer une éclosion parfaitement
  /// normale à J−1 pour une avance anormale.
  static const int toleranceEclosionJours = 2;

  /// Début de la fenêtre d'éclosion — `dateEclosionPrevue − 2 jours`.
  DateTime get eclosionAuPlusTot => dateEclosionPrevue.subtract(
    const Duration(days: toleranceEclosionJours),
  );

  /// Fin de la fenêtre d'éclosion — `dateEclosionPrevue + 2 jours`.
  DateTime get eclosionAuPlusTard => dateEclosionPrevue.add(
    const Duration(days: toleranceEclosionJours),
  );

  /// Âge du lot en jours à la date [maintenant].
  int ageJours(DateTime maintenant) =>
      _minuit(maintenant).difference(_minuit(dateChargement)).inDays;

  /// Jours restants avant l'éclosion prévue. Négatif si la date est dépassée.
  int joursAvantEclosion(DateTime maintenant) =>
      dateEclosionPrevue.difference(_minuit(maintenant)).inDays;

  /// Progression de l'incubation, bornée à 1. Un lot au-delà de son terme
  /// affiche 100 %, pas 110 %.
  double avancement(DateTime maintenant) {
    final age = ageJours(maintenant);
    if (age <= 0) return 0;
    return (age / espece.dureeIncubationJours).clamp(0, 1);
  }

  // --------------------------------------------------------- effectif retenu

  /// Œufs encore en incubation après les deux mirages —
  /// `E_i(0) − [B_i(7) + M_i(14)]`, dénominateur du TER.
  ///
  /// C'est le nombre d'œufs **réellement fertiles et viables** confiés à la
  /// machine : c'est sur eux que la performance du couvoir se juge, pas sur la
  /// quantité de départ qui contient des œufs clairs dès le premier jour.
  int get oeufsRetenusApresMirages =>
      oeufsCharges - (oeufsBlancsJ7 ?? 0) - (oeufsGatesJ14 ?? 0);

  /// Total retiré aux deux mirages.
  int get oeufsRetiresAuxMirages => (oeufsBlancsJ7 ?? 0) + (oeufsGatesJ14 ?? 0);

  // ------------------------------------------------------------------- taux

  /// **Taux d'Éclosion Réel** (TER), en pourcentage.
  ///
  /// ```
  /// TER = E_i(21/28) / (E_i(0) − [B_i(7) + M_i(14)]) × 100
  /// ```
  ///
  /// `null` tant que l'éclosion n'est pas saisie, et `null` aussi si le
  /// dénominateur est nul ou négatif — un lot entièrement vidé aux mirages n'a
  /// pas de taux, il n'a plus d'œufs. Afficher 0 % laisserait croire à un
  /// échec d'incubation là où il n'y a jamais rien eu à faire éclore.
  double? get tauxEclosionReel {
    final eclos = poussinsEclos;
    if (eclos == null) return null;
    final retenus = oeufsRetenusApresMirages;
    if (retenus <= 0) return null;
    return eclos / retenus * 100;
  }

  /// Taux d'éclosion **brut**, rapporté à la quantité initiale.
  ///
  /// Conservé parce que c'est ce que le prototype affichait, et qu'il reste
  /// utile pour juger d'un lot de reproducteurs : un fort écart entre brut et
  /// réel signale beaucoup d'œufs clairs, donc un problème de fécondation et
  /// non d'incubation.
  double? get tauxEclosionBrut {
    if (poussinsEclos == null || oeufsCharges <= 0) return null;
    return poussinsEclos! / oeufsCharges * 100;
  }

  /// Ancien nom, conservé pour ne pas casser les écrans qui l'utilisent —
  /// pointe sur le taux **brut**, comme avant.
  double? get tauxEclosion => tauxEclosionBrut;

  double? get tauxPerte {
    final taux = tauxEclosionBrut;
    return taux == null ? null : 100 - taux;
  }

  /// Part d'œufs clairs sur la quantité initiale — indicateur de fécondation.
  double? get tauxOeufsClairs {
    if (oeufsBlancsJ7 == null || oeufsCharges <= 0) return null;
    return oeufsBlancsJ7! / oeufsCharges * 100;
  }

  // ------------------------------------------------------------------ export

  /// Contrat JSON du lot.
  ///
  /// C'est **exactement** la charge utile qu'une API REST renverrait pour ce
  /// lot. Elle est produite ici plutôt que par un serveur : LogiALVIA est une
  /// application desktop hors-ligne, il n'y a ni backend à interroger ni
  /// consommateur distant. Le contrat existe pour qu'un backend puisse s'y
  /// brancher plus tard sans rien réécrire côté domaine.
  Map<String, Object?> versJson(DateTime maintenant) => {
    'lotId': id,
    'code': code,
    'espece': espece.identifiant,
    'dureeIncubationJours': espece.dureeIncubationJours,
    'machineId': machineId,
    'machineCode': machineCode,
    'dateInsertion': dateChargement.toIso8601String(),
    'quantiteInitiale': oeufsCharges,
    'oeufsBlancsJ7': oeufsBlancsJ7,
    'oeufsGatesJ14': oeufsGatesJ14,
    'oeufsEclos': poussinsEclos,
    'oeufsPerdus': oeufsPerdus,
    'dateMirage1': dateMirage1.toIso8601String(),
    'dateMirage2': dateMirage2.toIso8601String(),
    'dateEclosionPrevue': dateEclosionPrevue.toIso8601String(),
    'statut': statut,
    'lotParentId': lotParentId,
    'lotParentCode': lotParentCode,
    'dateRemplacement': dateRemplacement?.toIso8601String(),
    'quantiteRemplacee': quantiteRemplacee,
    'ageJours': ageJours(maintenant),
    'oeufsRetenusApresMirages': oeufsRetenusApresMirages,
    'tauxEclosionReel': tauxEclosionReel,
    'tauxEclosionBrut': tauxEclosionBrut,
  };

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Un incubateur physique. Le couvoir peut en compter plusieurs.
class MachineIncubateur {
  const MachineIncubateur({
    required this.id,
    required this.code,
    required this.libelle,
    this.capaciteOeufs,
    this.active = true,
  });

  final String id;
  final String code;
  final String libelle;

  /// Capacité annoncée, `null` si inconnue. Sert à signaler une surcharge, pas
  /// à la bloquer : la Gérante sait ce que sa machine encaisse.
  final int? capaciteOeufs;

  final bool active;

  Map<String, Object?> versJson() => {
    'machineId': id,
    'code': code,
    'libelle': libelle,
    'capaciteOeufs': capaciteOeufs,
    'active': active,
  };
}
