import '../../../administration/domain/services/service_archivage.dart';
import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../domain/entities/cycle_incubation.dart';
import '../../domain/repositories/cycle_couveuse_repository.dart';
import '../../domain/services/suivi_incubation.dart';

/// Écran Cycle Couveuse — Doc F3.
class CycleCouveuseViewModel extends ChangeNotifier {
  CycleCouveuseViewModel(this._repository);

  final CycleCouveuseRepository _repository;

  bool _chargement = true;
  bool get chargement => _chargement;

  static const SuiviIncubation _suivi = SuiviIncubation();

  List<CycleIncubation> _cycles = const [];
  List<MachineIncubateur> _machines = const [];

  /// Date de référence de tous les calculs — âge, alertes, TER.
  ///
  /// Injectable pour que les tests soient déterministes ; vaut « maintenant »
  /// dans l'application.
  DateTime _reference = DateTime.now();
  DateTime get reference => _reference;

  void definirReference(DateTime date) {
    _reference = date;
    notifyListeners();
  }

  List<MachineIncubateur> get machines => _machines;

  /// Filtre par machine — un couvoir a plusieurs incubateurs.
  int? _filtreMachine;
  int? get filtreMachine => _filtreMachine;

  void definirFiltreMachine(int? machineId) {
    _filtreMachine = machineId;
    notifyListeners();
  }

  /// Filtres de la barre d'outils (`cycle-couveuse.html` l.135-142).
  String? _filtreStatut;
  String? _filtreEspece;
  String? get filtreStatut => _filtreStatut;
  String? get filtreEspece => _filtreEspece;

  List<CycleIncubation> get cycles {
    return _cycles.where((c) {
      if (_filtreStatut == 'en_cours' && !c.estEnCours) return false;
      if (_filtreStatut == 'eclos' && c.estEnCours) return false;
      if (_filtreEspece != null && c.espece.identifiant != _filtreEspece) {
        return false;
      }
      if (_filtreMachine != null && c.machineId != _filtreMachine) return false;
      return true;
    }).toList();
  }

  /// Tous les lots, filtres non appliqués — les KPI décrivent le couvoir
  /// entier, la table en montre une partie.
  List<CycleIncubation> get tousLesLots => _cycles;

  void definirFiltreStatut(String? statut) {
    _filtreStatut = statut;
    notifyListeners();
  }

  void definirFiltreEspece(String? espece) {
    _filtreEspece = espece;
    notifyListeners();
  }

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    _cycles = await _repository.chargerTous();
    _machines = await _repository.chargerMachines();
    _chargement = false;
    notifyListeners();
  }

  // ------------------------------------------------- suivi multi-ages (v21)

  /// Échéances atteintes ou dépassées — mirages et éclosions.
  List<AlerteIncubation> get alertes => _suivi.alertes(_cycles, _reference);

  /// Échéances des 3 prochains jours.
  List<AlerteIncubation> get echeancesAVenir =>
      _suivi.echeancesAVenir(_cycles, _reference);

  /// **TER moyen** à la date de référence, pondéré par les œufs retenus.
  double? get tauxEclosionReelMoyen =>
      _suivi.terMoyenA(_cycles, _reference);

  /// Œufs actuellement en incubation, tous lots actifs confondus.
  int get oeufsEnIncubation => _cycles
      .where((c) => c.estEnCours)
      .fold<int>(0, (s, c) => s + c.oeufsRetenusApresMirages);

  int occupation(int machineId) => _suivi.occupation(_cycles, machineId);

  List<CycleIncubation> lignee(int lotRacineId) =>
      _suivi.lignee(_cycles, lotRacineId);

  CycleIncubation? racineDe(CycleIncubation lot) =>
      _suivi.racineDe(_cycles, lot);

  /// TER de toute une lignée de remplacements, à la date de référence.
  ///
  /// C'est la productivité d'un **emplacement** sur la durée : le TER d'un seul
  /// lot ne dit rien de la rotation qui l'a suivi.
  double? terDeLaLignee(int lotRacineId) =>
      _suivi.terDeLaLignee(_cycles, lotRacineId, _reference);

  /// Capacité totale déclarée du parc, `null` si aucune machine ne l'annonce.
  int? get capaciteTotale {
    final connues = _machines
        .where((m) => m.capaciteOeufs != null)
        .map((m) => m.capaciteOeufs!);
    if (connues.isEmpty) return null;
    return connues.reduce((a, b) => a + b);
  }

  /// Contrat JSON du suivi — voir `SuiviIncubation.versJson`.
  Map<String, Object?> versJson() =>
      _suivi.versJson(_cycles, _machines, _reference);

  // ------------------------------------------------------------------- KPIs
  // Les 4 KPI reels de `cycle-couveuse.html` l.105-120 — ⚠️ differents de ceux
  // que listait Doc F3 (« Lots en Incubation, Œufs Couvés, Taux d'Éclosion
  // Moyen, Éclosions cette Semaine »).

  int get cyclesEnCours => _cycles.where((c) => c.estEnCours).length;

  /// Projection des poussins attendus sur les cycles en cours, à partir du taux
  /// d'éclosion historique. Sans historique, aucune projection n'est possible.
  int get poussinsAttendus {
    final taux = tauxEclosionMoyen;
    if (taux == null) return 0;
    final oeufs = _cycles
        .where((c) => c.estEnCours)
        .fold<int>(0, (s, c) => s + c.oeufsCharges);
    return (oeufs * taux / 100).round();
  }

  /// `null` — et non 0 — tant qu'aucune éclosion n'a été enregistrée.
  double? get tauxEclosionMoyen {
    final eclos = _cycles
        .where((c) => c.tauxEclosion != null)
        .map((c) => c.tauxEclosion!)
        .toList();
    if (eclos.isEmpty) return null;
    return eclos.reduce((a, b) => a + b) / eclos.length;
  }

  double? get tauxPerteMoyen {
    final taux = tauxEclosionMoyen;
    return taux == null ? null : 100 - taux;
  }

  Future<Resultat<CycleIncubation>> creerCycle({
    required EspeceCouvable? espece,
    required DateTime? dateChargement,
    required int? oeufsCharges,
    int? machineId,
  }) async {
    // Validations de la modale (`data-required`, cycle-couveuse.html l.229-246).
    if (espece == null) return const Echec('L\'espèce est obligatoire.');
    if (dateChargement == null) return const Echec('La date est obligatoire.');
    if (oeufsCharges == null || oeufsCharges < 1) {
      return const Echec('Le nombre d\'œufs est obligatoire.');
    }

    try {
      final cycle = await _repository.creer(
        espece: espece,
        dateChargement: dateChargement,
        oeufsCharges: oeufsCharges,
        machineId: machineId,
      );
      await charger();
      return Succes(cycle);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec creation cycle: $e');
      return const Echec('Impossible de créer le cycle. Réessayez.');
    }
  }

  /// Modifie un cycle **encore en incubation**.
  ///
  /// Un cycle éclos n'est plus modifiable : son taux d'éclosion est déjà entré
  /// dans les statistiques de la couveuse et ses poussins dans les effectifs.
  /// Changer rétroactivement le nombre d'œufs chargés fausserait un taux déjà
  /// publié.
  Future<Resultat<void>> modifierCycle({
    required CycleIncubation cycle,
    required EspeceCouvable? espece,
    required DateTime? dateChargement,
    required int? oeufsCharges,
    int? machineId,
  }) async {
    if (!cycle.estEnCours) {
      return const Echec(
        'Un cycle éclos ne peut plus être modifié : son taux d\'éclosion est '
        'déjà entré dans les statistiques.',
      );
    }
    if (espece == null) return const Echec('L\'espèce est obligatoire.');
    if (dateChargement == null) return const Echec('La date est obligatoire.');
    if (oeufsCharges == null || oeufsCharges < 1) {
      return const Echec('Le nombre d\'œufs est obligatoire.');
    }

    try {
      await _repository.modifier(
        cycleId: cycle.id,
        espece: espece,
        dateChargement: dateChargement,
        oeufsCharges: oeufsCharges,
        machineId: machineId ?? cycle.machineId,
      );
      await charger();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec modification cycle: $e');
      return const Echec('Impossible de modifier ce cycle. Réessayez.');
    }
  }

  /// Supprime un cycle **encore en incubation**.
  Future<Resultat<void>> supprimerCycle(
    CycleIncubation cycle, {
    AuteurArchivage? auteur,
  }) async {
    if (!cycle.estEnCours) {
      return const Echec(
        'Un cycle éclos ne peut pas être supprimé : ses poussins sont déjà '
        'entrés dans les effectifs de la filière.',
      );
    }

    try {
      await _repository.supprimer(
        cycle.id,
        utilisateurId: auteur?.id,
        utilisateurNom: auteur?.nom,
      );
      await charger();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec suppression cycle: $e');
      return const Echec('Impossible de supprimer ce cycle. Réessayez.');
    }
  }

  /// Saisit un mirage — J+7 (oeufs clairs) ou J+14 (oeufs gates).
  Future<Resultat<void>> enregistrerMirage({
    required CycleIncubation lot,
    required int jour,
    required int? oeufsRetires,
  }) async {
    if (!lot.estEnCours) {
      return const Echec(
        'Ce lot est clôturé : ses mirages ne peuvent plus être saisis.',
      );
    }
    if (jour != EspeceCouvable.jourMirage1 &&
        jour != EspeceCouvable.jourMirage2) {
      return const Echec('Le mirage se fait à J+7 ou à J+14.');
    }
    final retires = oeufsRetires ?? -1;
    if (retires < 0) {
      return const Echec('Le nombre d\'œufs retirés est obligatoire.');
    }

    // Un mirage ne peut pas retirer plus d'oeufs qu'il n'en reste dans la
    // machine, sinon le denominateur du TER deviendrait negatif.
    final dejaRetires = jour == EspeceCouvable.jourMirage1
        ? (lot.oeufsGatesJ14 ?? 0)
        : (lot.oeufsBlancsJ7 ?? 0);
    if (retires + dejaRetires > lot.oeufsCharges) {
      return Echec(
        'Ce lot ne contient que ${lot.oeufsCharges} œufs, dont $dejaRetires '
        'déjà retirés : impossible d\'en retirer $retires de plus.',
      );
    }

    try {
      await _repository.enregistrerMirage(
        cycleId: lot.id,
        jour: jour,
        oeufsRetires: retires,
      );
      await charger();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec mirage: $e');
      return const Echec('Impossible d\'enregistrer ce mirage. Réessayez.');
    }
  }

  /// Enregistre l'éclosion, et crée le **sous-lot de remplacement** si des
  /// œufs sont réinsérés dans la place libérée.
  Future<Resultat<ResultatEclosion>> enregistrerEclosion({
    required CycleIncubation cycle,
    required int? poussinsEclos,
    required int? oeufsPerdus,
    int? oeufsRemplacement,
    EspeceCouvable? especeRemplacement,
    DateTime? dateRemplacement,
  }) async {
    final eclos = poussinsEclos ?? 0;
    final perdus = oeufsPerdus ?? 0;

    if (eclos < 0 || perdus < 0) {
      return const Echec('Les quantités ne peuvent être négatives.');
    }

    // Invariant : on ne peut pas faire eclore plus d'oeufs qu'il n'en RESTE
    // apres les mirages — et non plus qu'il n'y en avait au depart. Un lot de
    // 100 oeufs dont 30 ont ete retires ne peut pas rendre 80 poussins.
    final retenus = cycle.oeufsRetenusApresMirages;
    if (eclos + perdus > retenus) {
      return Echec(
        'Poussins éclos + œufs perdus (${eclos + perdus}) dépasse les '
        '$retenus œufs encore en incubation après les mirages.',
      );
    }

    if (oeufsRemplacement != null && oeufsRemplacement < 0) {
      return const Echec('La quantité de remplacement ne peut être négative.');
    }

    try {
      final resultat = await _repository.enregistrerEclosion(
        cycleId: cycle.id,
        poussinsEclos: eclos,
        oeufsPerdus: perdus,
        oeufsRemplacement: oeufsRemplacement,
        especeRemplacement: especeRemplacement,
        dateRemplacement: dateRemplacement,
      );
      await charger();
      return Succes(resultat);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec enregistrement eclosion: $e');
      return const Echec('Impossible d\'enregistrer l\'éclosion. Réessayez.');
    }
  }

  /// Déclare un nouvel incubateur.
  Future<Resultat<MachineIncubateur>> creerMachine({
    required String code,
    required String libelle,
    int? capaciteOeufs,
  }) async {
    final codePropre = code.trim();
    final libellePropre = libelle.trim();

    if (codePropre.isEmpty) return const Echec('Le code est obligatoire.');
    if (libellePropre.isEmpty) {
      return const Echec('Le libellé est obligatoire.');
    }
    if (_machines.any(
      (m) => m.code.toLowerCase() == codePropre.toLowerCase(),
    )) {
      return Echec('Un incubateur porte déjà le code $codePropre.');
    }
    if (capaciteOeufs != null && capaciteOeufs <= 0) {
      return const Echec('La capacité doit être supérieure à 0.');
    }

    try {
      final machine = await _repository.creerMachine(
        code: codePropre,
        libelle: libellePropre,
        capaciteOeufs: capaciteOeufs,
      );
      await charger();
      return Succes(machine);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec creation machine: $e');
      return const Echec('Impossible de créer cet incubateur.');
    }
  }
}
