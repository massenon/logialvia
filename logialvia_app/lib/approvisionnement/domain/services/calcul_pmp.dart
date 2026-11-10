/// Prix moyen pondéré (PMP) d'un intrant — **formule unique** du poste.
///
/// Elle est utilisée par la réception saisie au poste (`ApprovisionnementRepositoryDrift`)
/// ET par l'effet d'une réception saisie au web, appliqué à ce poste (`47s_`) : une seule
/// définition, donc le même PMP quelle que soit l'origine de la commande.
class CalculPmp {
  const CalculPmp._();

  /// Réception de [quantite] à [prixUnitaire] sur un stock de [stock] valorisé à [pmp] :
  /// `PMP' = (stock × PMP + qté × prix) ÷ (stock + qté)`, arrondi à l'entier (FCFA).
  /// Stock résultant nul ou négatif : PMP inchangé.
  static int apresReception({
    required int stock,
    required int pmp,
    required int quantite,
    required double prixUnitaire,
  }) {
    final nouveauStock = stock + quantite;
    if (nouveauStock <= 0) return pmp;
    return ((stock * pmp + quantite * prixUnitaire) / nouveauStock).round();
  }

  /// **Inverse** de la réception, pour l'annulation d'une commande livrée (`47s_` §3) :
  /// la marchandise repart au prix auquel elle était entrée,
  /// `PMP' = (stock × PMP − qté × prix) ÷ (stock − qté)`.
  ///
  /// Le PMP n'est recalculé que si le stock couvre la quantité retirée et en laisse :
  /// sinon (stock insuffisant, plancher à 0, ou stock vidé) il reste inchangé — on ne
  /// fabrique pas un PMP négatif ou indéfini. Jamais négatif.
  static int apresRetrait({
    required int stock,
    required int pmp,
    required int quantite,
    required double prixUnitaire,
  }) {
    final reste = stock - quantite;
    // Un stock qui ne couvre pas la quantité (ou qu'elle vide) laisse le PMP inchangé : `reste <= 0`.
    if (reste <= 0) return pmp;
    final nouveau = ((stock * pmp - quantite * prixUnitaire) / reste).round();
    return nouveau < 0 ? 0 : nouveau;
  }
}
