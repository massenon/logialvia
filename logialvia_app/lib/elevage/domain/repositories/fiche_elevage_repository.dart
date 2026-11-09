import '../entities/journee_elevage.dart';

/// Dépôt des fiches d'élevage — table `FICHE_JOURNEE` (Doc D1).
abstract class FicheElevageRepository {
  /// Les journées réellement enregistrées d'un mois donné.
  Future<List<JourneeElevage>> chargerMois({
    required String espece,
    required int annee,
    required int mois,
  });

  Future<JourneeElevage?> chargerJour({
    required String espece,
    required DateTime date,
  });

  /// Dernière journée saisie **strictement avant** [date], quel que soit le
  /// mois — la continuité d'un mois à l'autre ne doit pas être rompue
  /// (BR-ELV-006).
  Future<JourneeElevage?> chargerJourneePrecedente({
    required String espece,
    required DateTime date,
  });

  /// Journées saisies **après** [date], dans l'ordre chronologique, jusqu'au
  /// premier trou — cible de la cascade (Doc 05 §5).
  Future<List<JourneeElevage>> chargerJourneesSuivantes({
    required String espece,
    required DateTime date,
  });

  Future<void> enregistrerJour(JourneeElevage journee);

  /// TOUTES les journées saisies de la filière, dans l'ordre chronologique (chaîne
  /// d'effectifs, `47e_`).
  Future<List<JourneeElevage>> chargerJoursSaisis(String espece);

  /// Les versions en présence quand la fiche du jour est « modifiée ailleurs » : la
  /// courante d'abord, puis les autres. Liste vide sans divergence.
  Future<List<VersionJournee>> versionsEnDivergence({
    required String espece,
    required DateTime date,
  });

  /// Marque la fiche du jour comme **résolue** : les variantes sont effacées et la
  /// prochaine écriture envoyée le dit au serveur. À appeler APRÈS avoir réécrit la
  /// version choisie (`enregistrerJour`).
  Future<void> marquerDivergenceResolue({
    required String espece,
    required DateTime date,
  });

  /// Ventes du jour issues du POS pour cette espèce (`FICHE_VENTES_JOUR`).
  Future<int> venteDuJour({required String espece, required DateTime date});
}
