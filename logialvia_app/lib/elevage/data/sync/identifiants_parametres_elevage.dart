import '../../../core/sync/identifiant_poste.dart';

/// Identifiants **déterministes** des paramètres d'élevage (DV-19, `46c_`).
///
/// Les barèmes, taux et échéances SEMÉS sont identiques sur tous les postes : deux
/// postes installés du même programme doivent donner le MÊME UUID à la ration
/// « goliaths — poussin », sinon le serveur la verrait en double. La clé est le
/// couple que la base déclare déjà unique (barèmes, taux) ; pour une échéance, qui n'a
/// pas de clé unique, c'est (espèce, jour, traitement, produit).
class IdentifiantsParametresElevage {
  IdentifiantsParametresElevage._();

  static String bareme(String espece, String stade) =>
      uuidDeterministe('bareme_ration:$espece|$stade');

  static String taux(String espece, int poidsMinG) =>
      uuidDeterministe('taux_ration_poids:$espece|$poidsMinG');

  static String echeance(
    String espece,
    int jourCycle,
    String traitement,
    String produit,
  ) => uuidDeterministe(
    'echeance_prophylaxie:$espece|$jourCycle|$traitement|$produit',
  );
}
