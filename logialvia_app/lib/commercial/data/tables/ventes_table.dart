import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Table `VENTES` — Doc D1 §2.
@DataClassName('VenteRow')
class Ventes extends Table {
  /// UUID de la vente (DV-19) : l'identite SYNCHRONISEE. La cle primaire reste
  /// [ref] (les lignes, les ecritures et les factures s'y rattachent par texte) ;
  /// `ref` est le numero OFFICIEL remis au client (`V-P2-2026-001`, DV-21), jamais
  /// renumerote.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  /// Le client, quand il est identifiable. `null` si la vente porte un nom libre
  /// (« Client Comptant ») ou si le nom designe PLUSIEURS clients (homonymes) :
  /// on ne devine pas qui a achete.
  TextColumn get clientId => text().nullable()();

  // --- Synchronisation (`46_` §1) ---

  /// `pending` · `synced` · `conflict`.
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get syncMotif => text().nullable()();

  /// Instant de SAISIE (UTC, ISO 8601, microsecondes).
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  /// Reference unique, format 'V-AAAA-NNN'.
  TextColumn get ref => text()();

  /// Nom du client, ou 'Client Comptant'.
  TextColumn get client => text()();

  DateTimeColumn get dateVente => dateTime()();

  /// Instrument de paiement : 'Espèces' ou 'Mobile Money' — et 'Non précisé'
  /// pour les ventes antérieures à la migration v15.
  ///
  /// ⚠️ Ne contient plus 'Avance (Solde Restant Dû)' : la condition de paiement
  /// se lit sur [status]. Voir `ModeReglement` et `ConditionPaiement`.
  TextColumn get mode => text()();

  /// 'Payée', 'Avance', 'Annulée'
  TextColumn get status => text()();

  RealColumn get total => real()();

  /// Montant effectivement encaisse.
  RealColumn get paye => real()();

  /// Obligatoire si `status = 'Annulée'` (BR-VTE-004).
  TextColumn get motifAnnulation => text().nullable()();

  // --- Livraison (`#modal-livraison` de ventes.html) ---
  //
  // ⚠️ Le prototype affiche cette modale mais `validateSale()` **ne lit aucun
  // de ses champs** : ni le mode, ni les frais, ni l'adresse ne survivent au
  // clic sur « Valider ». C'est le meme anti-patron que `validateSale()`
  // lui-meme designe (Master Prompt §2.3). Ces 4 colonnes le corrigent.

  /// `null` si la vente ne concerne pas de livraison. Sinon : `gratuite`,
  /// `client`, `incluse` ou `facturee` — les 4 options du selecteur.
  TextColumn get livraisonMode => text().nullable()();

  /// Frais de livraison, **uniquement** en mode `facturee`. Ils s'ajoutent au
  /// total : c'est la seule lecture coherente de « facturee separement », que
  /// le prototype n'applique pas.
  RealColumn get livraisonFrais => real().nullable()();

  TextColumn get livraisonAdresse => text().nullable()();
  TextColumn get livraisonContact => text().nullable()();

  /// Date d'exigibilité d'une vente à crédit — « Payable le ».
  ///
  /// ⚠️ Absente du prototype, et c'est un défaut qui coûte cher : les rapports
  /// affichent une colonne « Échéance » qu'ils remplissent avec la **date de
  /// vente**, si bien que toute créance née hier est déclarée « En Retard »
  /// avec un compteur de jours qui est en réalité son âge. La lettre de
  /// relance branchée sur ce tableau réclamerait donc un paiement non échu.
  ///
  /// `null` = aucun délai convenu. La créance reste « À échoir » sans date et
  /// **n'est jamais en retard** : mieux vaut ne rien affirmer que de supposer
  /// un délai que personne n'a fixé.
  DateTimeColumn get echeance => dateTime().nullable()();

  /// Ligne Mobile Money créditée — `#modal-account-select` de `ventes.html`.
  ///
  /// ⚠️ Même anti-patron que la livraison : le prototype **exige** ce choix
  /// (`validateSale()` refuse la vente sans lui) mais ne l'écrit nulle part.
  /// Une obligation dont le résultat est jeté.
  ///
  /// Dénormalisée volontairement, comme `LIGNES_VENTE.nom` : le numéro est
  /// copié au moment de la vente. Si la Gérante change de ligne l'an prochain,
  /// les encaissements passés doivent continuer de nommer celle qui les a
  /// réellement reçus, sans quoi le rapprochement du compte 512 devient faux
  /// rétroactivement.
  ///
  /// `null` pour tout règlement en espèces.
  TextColumn get ligneMobileMoney => text().nullable()();

  @override
  Set<Column> get primaryKey => {ref};

  @override
  List<Set<Column>> get uniqueKeys => [
    {id},
  ];
}
