import '../entities/client.dart';
import '../entities/produit_vendable.dart';
import '../entities/livraison.dart';
import '../entities/vente.dart';

/// Résultat d'un encaissement.
class ResultatEncaissement {
  const ResultatEncaissement({required this.vente});

  final Vente vente;
}

/// Dépôt du contexte Commercial — ventes, lignes, catalogue, clients.
abstract class VentesRepository {
  Future<List<ProduitVendable>> chargerCatalogue();

  /// Les clients proposes a la saisie d'une vente, par ordre alphabetique.
  Future<List<ClientChoix>> chargerClientsChoix();

  Future<List<Vente>> chargerVentes({int limite = 200});

  Future<Vente?> chargerVente(String reference);

  /// Enregistre une vente **de façon atomique** (BR-VTE-002) : vente, lignes,
  /// décrément du stock et compteur de la fiche d'élevage dans une seule
  /// transaction Drift. Un échec à n'importe quelle étape n'écrit rien.
  Future<ResultatEncaissement> enregistrerVente({
    required String client,
    required String mode,
    required String statut,
    required double montantPaye,
    required List<LignePanier> panier,

    /// Le client CHOISI dans la liste (lève l'ambiguité des homonymes). `null` : le
    /// depot cherche un client unique portant ce nom.
    String? clientId,

    /// `null` si la vente ne concerne pas de livraison. Les frais d'une
    /// livraison **facturee separement** s'ajoutent au total.
    Livraison? livraison,

    /// Ligne Mobile Money creditee, denormalisee sur la vente. `null` en
    /// especes. Voir `VENTES.ligneMobileMoney`.
    String? ligneMobileMoney,

    /// Date de la vente. `null` vaut « maintenant », le cas du point de vente.
    ///
    /// Injectable pour que les tests soient deterministes et pour qu'un
    /// peuplement de demonstration puisse produire un mois d'historique :
    /// sans elle, toutes les ventes porteraient la date du jour et aucun
    /// ecran date ne serait eprouve.
    DateTime? date,

    /// Date d'exigibilite convenue. `null` = aucun delai fixe, la creance ne
    /// sera jamais declaree en retard. Voir `VENTES.echeance`.
    DateTime? echeance,
  });

  /// Annule une vente : statut `Annulée`, motif obligatoire, **restitution du
  /// stock** et décrément du compteur de la fiche d'élevage — le tout dans une
  /// seule transaction (FRS-VTE-05).
  Future<void> annulerVente({required String reference, required String motif});

  /// Enregistre un paiement partiel ou total sur une vente en avance
  /// (Doc F4 Écran 3). Passe le statut à `Payée` si le solde est atteint.
  Future<void> enregistrerPaiement({
    required String reference,
    required double montant,
  });

  Future<ProduitVendable> creerProduit(ProduitVendable produit);

  /// [motifCorrection] : pourquoi le stock change (journal partagé, palier 6).
  Future<void> mettreAJourProduit(
    ProduitVendable produit, {
    String? motifCorrection,
  });

  Future<void> supprimerProduit(
    String produitId, {
    String? utilisateurId,
    String? utilisateurNom,
  });
}
