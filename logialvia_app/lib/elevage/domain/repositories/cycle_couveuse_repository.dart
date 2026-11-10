import '../entities/cycle_incubation.dart';

/// Résultat d'une éclosion : le lot clôturé, et le sous-lot créé pour combler
/// la place s'il y a eu remplacement.
class ResultatEclosion {
  const ResultatEclosion({required this.lot, this.sousLot});

  final CycleIncubation lot;
  final CycleIncubation? sousLot;

  bool get aEteRemplace => sousLot != null;
}

/// Dépôt des lots de couveuse — table `CYCLE_COUVEUSE` (Doc D1), étendue en
/// v21 pour le suivi multi-âges.
abstract class CycleCouveuseRepository {
  Future<List<CycleIncubation>> chargerTous();

  /// Les incubateurs référencés.
  Future<List<MachineIncubateur>> chargerMachines();

  Future<MachineIncubateur> creerMachine({
    required String code,
    required String libelle,
    int? capaciteOeufs,
  });

  /// Crée un lot et retourne le code généré.
  Future<CycleIncubation> creer({
    required EspeceCouvable espece,
    required DateTime dateChargement,
    required int oeufsCharges,
    String? machineId,

    /// Lot remplacé, si celui-ci prend sa place dans la machine.
    String? lotParentId,
  });

  /// Saisit un mirage — `B_i(7)` ou `M_i(14)` selon [jour].
  ///
  /// Séparé de l'éclosion : les mirages se font en cours d'incubation, sur un
  /// lot toujours actif, et chacun retire réellement des œufs de la machine.
  Future<void> enregistrerMirage({
    required String cycleId,
    required int jour,
    required int oeufsRetires,
  });

  /// Enregistre l'éclosion et clôture le lot.
  ///
  /// Si [oeufsRemplacement] est fourni, un **sous-lot** est créé dans la même
  /// transaction pour combler la place libérée : le lot d'origine passe alors
  /// en « Remplacé » plutôt qu'en « Éclosion Effectuée ».
  Future<ResultatEclosion> enregistrerEclosion({
    required String cycleId,
    required int poussinsEclos,
    required int oeufsPerdus,
    int? oeufsRemplacement,
    EspeceCouvable? especeRemplacement,
    DateTime? dateRemplacement,
  });

  /// Modifie un lot **en cours**. Le code n'est jamais modifiable : il est la
  /// référence portée par le journal d'élevage et les rapports.
  Future<void> modifier({
    required String cycleId,
    required EspeceCouvable espece,
    required DateTime dateChargement,
    required int oeufsCharges,
    String? machineId,
  });

  /// Supprime un lot. Un lot éclos ne se supprime pas : ses poussins sont déjà
  /// entrés dans les effectifs (Doc F3).
  Future<void> supprimer(
    String cycleId, {
    String? utilisateurId,
    String? utilisateurNom,
  });

  /// Prochain numéro de séquence pour le code `C-AAAA-NNN`.
  Future<int> prochainNumero(int annee);
}
