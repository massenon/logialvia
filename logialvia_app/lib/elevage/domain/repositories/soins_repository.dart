import '../entities/soin.dart';

/// Dépôt du calendrier de soins et de l'infirmerie.
abstract class SoinsRepository {
  Future<List<Soin>> chargerSoins();

  Future<Soin> enregistrerSoin({
    required String espece,
    required DateTime date,
    required String typeSoin,
    required String statut,
    String? produit,
    String? dose,
    int remanenceJours = 0,
    String? veterinaire,
    String? symptomes,
    int coutFcfa = 0,
    String? bandeId,
    int? echeanceProphylaxieId,
  });

  /// Passe un soin planifié en « Effectué » — « Confirmer Administration »
  /// du volet de détail.
  Future<void> confirmerAdministration(int soinId);

  Future<List<EntreeInfirmerie>> chargerInfirmerie();

  Future<EntreeInfirmerie> enregistrerEntreeInfirmerie({
    required String sujet,
    required String motif,
    required String niveauIsolement,
    required DateTime dateEntree,
    String? espece,
  });

  /// Clôture une entrée d'infirmerie (réintégration ou décès).
  Future<void> cloturerEntree({
    required int entreeId,
    required String statut,
    required DateTime dateSortie,
  });

  /// Marque un décès comme **porté** sur la fiche d'élevage, dans la catégorie
  /// d'effectif [categorieMortalite].
  ///
  /// Appelé après le report, jamais avant : une entrée marquée alors que la
  /// fiche n'a pas bougé ferait disparaître la perte du taux de mortalité sans
  /// que rien ne le signale.
  Future<void> marquerDecesReporte({
    required int entreeId,
    required int categorieMortalite,
  });
}
