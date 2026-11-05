import '../entities/cycle_incubation.dart';

/// Suivi d'un couvoir en **incubation continue** — lots d'âges différents
/// cohabitant dans une ou plusieurs machines.
///
/// Tout est calculé à partir d'une date de référence injectée, jamais de
/// `DateTime.now()` : c'est ce qui rend « le TER à une date précise t » du
/// cahier des charges vérifiable, et les tests déterministes.
class SuiviIncubation {
  const SuiviIncubation();

  // ------------------------------------------------------------- échéances

  /// Les échéances **atteintes ou dépassées** à la date [t], pour les lots
  /// encore en incubation.
  ///
  /// Une échéance est retenue tant que l'information qu'elle réclame n'a pas
  /// été saisie : un mirage 1 sans œufs clairs renseignés reste dû, même une
  /// semaine après. Un couvoir en continu se rate justement par les mirages
  /// oubliés, pas par les éclosions — celles-là, les poussins les signalent.
  List<AlerteIncubation> alertes(List<CycleIncubation> lots, DateTime t) {
    final jour = _minuit(t);
    final alertes = <AlerteIncubation>[];

    for (final lot in lots) {
      if (!lot.estEnCours) continue;

      if (lot.oeufsBlancsJ7 == null && !jour.isBefore(_minuit(lot.dateMirage1))) {
        alertes.add(
          AlerteIncubation(
            lot: lot,
            type: TypeEcheance.mirage1,
            dateEcheance: lot.dateMirage1,
            joursDecart: jour.difference(_minuit(lot.dateMirage1)).inDays,
          ),
        );
      }

      if (lot.oeufsGatesJ14 == null && !jour.isBefore(_minuit(lot.dateMirage2))) {
        alertes.add(
          AlerteIncubation(
            lot: lot,
            type: TypeEcheance.mirage2,
            dateEcheance: lot.dateMirage2,
            joursDecart: jour.difference(_minuit(lot.dateMirage2)).inDays,
          ),
        );
      }

      if (!jour.isBefore(_minuit(lot.dateEclosionPrevue))) {
        alertes.add(
          AlerteIncubation(
            lot: lot,
            type: TypeEcheance.eclosion,
            dateEcheance: lot.dateEclosionPrevue,
            joursDecart: jour.difference(_minuit(lot.dateEclosionPrevue)).inDays,
          ),
        );
      }
    }

    // Le plus en retard d'abord : c'est l'ordre dans lequel il faut agir.
    alertes.sort((a, b) => b.joursDecart.compareTo(a.joursDecart));
    return alertes;
  }

  /// Échéances **à venir** dans les [jours] prochains — pour préparer, pas
  /// pour rattraper.
  List<AlerteIncubation> echeancesAVenir(
    List<CycleIncubation> lots,
    DateTime t, {
    int jours = 3,
  }) {
    final jour = _minuit(t);
    final limite = jour.add(Duration(days: jours));
    final aVenir = <AlerteIncubation>[];

    void ajouter(CycleIncubation lot, TypeEcheance type, DateTime date) {
      final echeance = _minuit(date);
      if (echeance.isAfter(jour) && !echeance.isAfter(limite)) {
        aVenir.add(
          AlerteIncubation(
            lot: lot,
            type: type,
            dateEcheance: date,
            joursDecart: jour.difference(echeance).inDays,
          ),
        );
      }
    }

    for (final lot in lots) {
      if (!lot.estEnCours) continue;
      if (lot.oeufsBlancsJ7 == null) {
        ajouter(lot, TypeEcheance.mirage1, lot.dateMirage1);
      }
      if (lot.oeufsGatesJ14 == null) {
        ajouter(lot, TypeEcheance.mirage2, lot.dateMirage2);
      }
      ajouter(lot, TypeEcheance.eclosion, lot.dateEclosionPrevue);
    }

    aVenir.sort((a, b) => a.dateEcheance.compareTo(b.dateEcheance));
    return aVenir;
  }

  // ------------------------------------------------------------------- TER

  /// **TER moyen à la date [t]**, sur les lots dont l'éclosion est enregistrée
  /// au plus tard à cette date.
  ///
  /// Moyenne **pondérée par les œufs retenus**, pas moyenne des taux : un lot
  /// de 300 œufs et un lot de 12 ne pèsent pas pareil dans la performance d'un
  /// couvoir. Faire la moyenne arithmétique des pourcentages laisserait un
  /// petit lot raté effondrer un chiffre par ailleurs bon.
  ///
  /// `null` si aucun lot n'a encore éclos — une moyenne sur zéro échantillon
  /// n'existe pas.
  double? terMoyenA(List<CycleIncubation> lots, DateTime t) {
    final jour = _minuit(t);
    var eclos = 0;
    var retenus = 0;

    for (final lot in lots) {
      if (lot.poussinsEclos == null) continue;
      if (_minuit(lot.dateEclosionPrevue).isAfter(jour)) continue;
      if (lot.oeufsRetenusApresMirages <= 0) continue;
      eclos += lot.poussinsEclos!;
      retenus += lot.oeufsRetenusApresMirages;
    }

    if (retenus <= 0) return null;
    return eclos / retenus * 100;
  }

  /// TER d'un lot **et de toute sa descendance** — la chaîne de remplacements
  /// occupant successivement la même place dans la machine.
  ///
  /// C'est ce qui mesure la productivité d'un emplacement sur la durée, là où
  /// le TER d'un seul lot ne dit rien de la rotation.
  double? terDeLaLignee(
    List<CycleIncubation> lots,
    int lotRacineId,
    DateTime t,
  ) => terMoyenA(lignee(lots, lotRacineId), t);

  /// Le lot racine et tous ses descendants, dans l'ordre chronologique.
  List<CycleIncubation> lignee(List<CycleIncubation> lots, int lotRacineId) {
    final parIdentifiant = {for (final l in lots) l.id: l};
    final racine = parIdentifiant[lotRacineId];
    if (racine == null) return const [];

    final resultat = <CycleIncubation>[racine];
    final aExplorer = <int>[lotRacineId];

    while (aExplorer.isNotEmpty) {
      final courant = aExplorer.removeLast();
      for (final lot in lots) {
        if (lot.lotParentId == courant) {
          resultat.add(lot);
          aExplorer.add(lot.id);
        }
      }
    }

    resultat.sort((a, b) => a.dateChargement.compareTo(b.dateChargement));
    return resultat;
  }

  /// Remonte jusqu'au lot d'origine d'une chaîne de remplacements.
  CycleIncubation? racineDe(List<CycleIncubation> lots, CycleIncubation lot) {
    final parIdentifiant = {for (final l in lots) l.id: l};
    var courant = lot;
    // Garde-fou : une reference circulaire en base ferait boucler a l'infini.
    final vus = <int>{courant.id};
    while (courant.lotParentId != null) {
      final parent = parIdentifiant[courant.lotParentId];
      if (parent == null || !vus.add(parent.id)) break;
      courant = parent;
    }
    return courant;
  }

  // --------------------------------------------------------------- machines

  /// Œufs actuellement en incubation dans une machine à la date [t].
  int occupation(List<CycleIncubation> lots, int machineId) => lots
      .where((l) => l.machineId == machineId && l.estEnCours)
      .fold<int>(0, (s, l) => s + l.oeufsRetenusApresMirages);

  /// Contrat JSON du suivi complet — voir `CycleIncubation.versJson`.
  ///
  /// LogiALVIA est une application desktop **hors-ligne** : aucun serveur HTTP
  /// n'est embarqué, il n'y aurait ni consommateur distant à servir ni raison
  /// d'ouvrir un port sur le poste de la Gérante. Ce document est la charge
  /// utile exacte qu'une API REST renverrait, produite localement pour que
  /// l'écran s'en nourrisse — et pour qu'un backend futur reprenne le contrat
  /// tel quel.
  Map<String, Object?> versJson(
    List<CycleIncubation> lots,
    List<MachineIncubateur> machines,
    DateTime t,
  ) {
    final alertesCourantes = alertes(lots, t);
    return {
      'genereLe': t.toIso8601String(),
      'terMoyen': terMoyenA(lots, t),
      'machines': [for (final m in machines) m.versJson()],
      'lots': [for (final l in lots) l.versJson(t)],
      'alertes': [
        for (final a in alertesCourantes)
          {
            'lotId': a.lot.id,
            'lotCode': a.lot.code,
            'type': a.type.name,
            'libelle': a.type.libelle,
            'dateEcheance': a.dateEcheance.toIso8601String(),
            'joursDecart': a.joursDecart,
            'enRetard': a.estEnRetard,
          },
      ],
    };
  }

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);
}
