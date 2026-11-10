import 'package:flutter/foundation.dart';

import '../../../administration/data/repositories/parametres_repository_drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/resultat/resultat.dart';
import '../../data/repositories/devis_repository_drift.dart';
import '../../domain/entities/client.dart';
import '../../domain/entities/devis_emis.dart';
import '../../domain/entities/produit_vendable.dart';
import '../../domain/entities/livraison.dart';
import '../../domain/entities/vente.dart';
import '../../domain/repositories/ventes_repository.dart';

// Le devis vit dans le domaine (`47a2_`) ; ré-exporté pour les écrans existants.
export '../../domain/entities/devis_emis.dart';

/// Écran Ventes — Doc F4 Écran 1 et Doc H1 (4 onglets).
class VentesViewModel extends ChangeNotifier {
  VentesViewModel(this._repository, this._db);

  final VentesRepository _repository;
  final AppDatabase _db;

  bool _chargement = true;
  bool get chargement => _chargement;

  List<ProduitVendable> _catalogue = const [];
  List<Vente> _ventes = const [];
  List<DevisEmis> _devis = const [];

  List<Vente> get ventes => _ventes;
  List<DevisEmis> get devis => _devis;

  // ------------------------------------------------------- grille de produits

  String _recherche = '';
  String? _filtreCategorie;
  String get recherche => _recherche;
  String? get filtreCategorie => _filtreCategorie;

  List<ProduitVendable> get produitsFiltres {
    final terme = _recherche.trim().toLowerCase();
    return _catalogue.where((p) {
      if (_filtreCategorie != null && p.categorie != _filtreCategorie) {
        return false;
      }
      if (terme.isEmpty) return true;
      return p.nom.toLowerCase().contains(terme);
    }).toList();
  }

  /// Catégories réellement présentes dans le catalogue.
  List<String> get categories =>
      (_catalogue.map((p) => p.categorie).toSet().toList()..sort());

  void definirRecherche(String valeur) {
    _recherche = valeur;
    notifyListeners();
  }

  void definirCategorie(String? valeur) {
    _filtreCategorie = valeur;
    notifyListeners();
  }

  // -------------------------------------------------------------------- panier

  final List<LignePanier> _panier = [];
  List<LignePanier> get panier => List.unmodifiable(_panier);

  /// Total des lignes du panier, **hors** frais de livraison.
  double get totalLignes => _panier.fold(0, (s, l) => s + l.total);

  /// Total encaissé : lignes + frais d'une livraison facturée séparément.
  double get totalPanier => totalLignes + (_livraison?.supplementFacture ?? 0);

  // ------------------------------------------------------------- Livraison

  /// `#modal-livraison` — voir [Livraison] pour ce que le prototype n'en fait
  /// pas.
  Livraison? _livraison;
  Livraison? get livraison => _livraison;

  bool get livraisonConcernee => _livraison != null;

  /// Retourne un message d'erreur, ou `null` si la livraison est valide.
  /// Passer `null` retire la livraison de la vente.
  String? definirLivraison(Livraison? livraison) {
    if (livraison != null) {
      final erreur = livraison.valider();
      if (erreur != null) return erreur;
    }
    _livraison = livraison;
    notifyListeners();
    return null;
  }

  bool get panierVide => _panier.isEmpty;

  String _client = '';
  String get client => _client;

  /// Le client CHOISI dans la liste, quand il y en a un. Dès que le texte est
  /// retouché à la main, le choix est oublié : on ne garde pas l'identifiant d'un
  /// client dont le nom n'est plus celui qui est affiché.
  String? _clientId;
  String? get clientId => _clientId;
  set client(String valeur) {
    _client = valeur;
    if (_clientId != null && !_clients.any((c) => c.id == _clientId && c.nom == valeur)) {
      _clientId = null;
    }
    notifyListeners();
  }

  List<ClientChoix> _clients = const [];

  /// Les clients dont le nom contient [saisie] (casse ignorée), 8 au plus.
  List<ClientChoix> suggestionsClients(String saisie) {
    final cherche = saisie.trim().toLowerCase();
    if (cherche.isEmpty) return const [];
    return _clients
        .where((c) => c.nom.toLowerCase().contains(cherche))
        .take(8)
        .toList();
  }

  void choisirClient(ClientChoix client) {
    _client = client.nom;
    _clientId = client.id;
    notifyListeners();
  }

  /// Plusieurs clients portent exactement ce nom ET aucun n'est choisi : la vente
  /// serait rattachée à personne. L'écran invite alors à choisir dans la liste.
  bool get clientAmbigu {
    if (_clientId != null) return false;
    final nom = _client.trim().toLowerCase();
    if (nom.isEmpty) return false;
    return _clients.where((c) => c.nom.trim().toLowerCase() == nom).length > 1;
  }

  String _mode = ModeReglement.especes;
  String get mode => _mode;
  set mode(String valeur) {
    _mode = valeur;
    notifyListeners();
  }

  /// Condition de paiement — independante du mode depuis l'arbitrage de la
  /// Gerante. Voir [ConditionPaiement].
  String _condition = ConditionPaiement.comptant;
  String get condition => _condition;
  set condition(String valeur) {
    _condition = valeur;
    // Repasser en comptant apres avoir saisi une avance laisserait un montant
    // recu partiel qui bloquerait la validation sans dire pourquoi.
    if (valeur == ConditionPaiement.comptant) {
      _montantRecu = 0;
      _echeance = null;
    } else {
      // Le delai des Parametres Generaux pre-remplit le champ ; la caissiere
      // peut l'ecraser. S'il n'est pas configure, rien n'est propose : on
      // n'invente pas d'echeance.
      final delai = _delaiPaiementParDefaut;
      _echeance ??= delai == null
          ? null
          : DateTime.now().add(Duration(days: delai));
    }
    notifyListeners();
  }

  bool get estAvance => _condition == ConditionPaiement.avance;

  // ----------------------------------------------------- echeance de paiement
  //
  // Absente du prototype. Ses rapports affichent pourtant une colonne
  // « Echeance » qu'ils remplissent avec la date de vente : toute creance nee
  // la veille etait declaree « En Retard », et la lettre de relance imprimee
  // depuis ce tableau reclamait un paiement non echu.

  DateTime? _echeance;

  /// Date d'exigibilite convenue, `null` si aucun delai n'a ete fixe.
  ///
  /// N'a de sens que sur une vente a credit : une vente comptant est soldee a
  /// l'encaissement, il n'y a rien a echoir.
  DateTime? get echeance => estAvance ? _echeance : null;

  set echeance(DateTime? valeur) {
    _echeance = valeur;
    notifyListeners();
  }

  /// Delai par defaut des Parametres Generaux, en jours. `null` tant que la
  /// Gerante ne l'a pas fixe — aucune valeur n'est supposee.
  int? _delaiPaiementParDefaut;
  int? get delaiPaiementParDefaut => _delaiPaiementParDefaut;

  /// Vrai quand une vente a credit est enregistree sans echeance : la creance
  /// restera « Sans echeance » et ne sera jamais reclamee. Ce n'est pas une
  /// erreur — c'est un fait que l'ecran doit enoncer.
  bool get echeanceNonFixee => estAvance && _echeance == null;

  double _montantRecu = 0;
  double get montantRecu => _montantRecu;
  set montantRecu(double valeur) {
    _montantRecu = valeur;
    notifyListeners();
  }

  /// Ajoute une ligne **à montant négocié** — `confirmWeightAdd()` du prototype.
  ///
  /// La quantité **et** le montant global sont saisis dans la modale « Vente à
  /// la Pièce ». Le montant n'est jamais déduit d'un prix unitaire multiplié :
  /// c'est le total convenu avec le client. Voir [LignePanier].
  ///
  /// Un même produit peut être ajouté **plusieurs fois** avec des montants
  /// différents — deux clients ne négocient pas au même prix. Le prototype
  /// empile les lignes (`cart.push`) au lieu de les fusionner ; ce
  /// comportement est conservé.
  String? ajouterAuPanier(
    ProduitVendable produit, {
    required double quantite,
    required double montantGlobal,
  }) {
    if (produit.estEpuise) {
      return '${produit.nom} est en rupture de stock.';
    }
    if (quantite <= 0 || montantGlobal <= 0) {
      return 'Veuillez saisir une quantité et un montant valides.';
    }

    // Le stock reste une borne : la somme des quantites deja au panier pour ce
    // produit ne peut pas depasser ce qui existe (FRS-VTE-02).
    final dejaAuPanier = _panier
        .where((l) => l.produitId == produit.id)
        .fold<double>(0, (s, l) => s + l.quantite);
    if (dejaAuPanier + quantite > produit.stock) {
      return 'Stock insuffisant (${produit.stock} disponible, '
          '${dejaAuPanier.toInt()} déjà au panier).';
    }

    _panier.add(
      LignePanier(
        produitId: produit.id,
        nom: produit.nom,
        montantGlobal: montantGlobal,
        quantite: quantite,
        stockDisponible: produit.stock,
        prixIndicatif: produit.prix,
        prixIndicatifMax: produit.prixMax,
        espece: produit.espece,
        unite: produit.unite,
      ),
    );
    notifyListeners();
    return null;
  }

  /// Modifie une ligne existante — `editWeightLine()` puis `confirmWeightAdd()`.
  ///
  /// L'index est utilise plutot que `produitId` : un meme produit peut occuper
  /// plusieurs lignes a des montants differents.
  String? modifierLigne(
    int index, {
    required double quantite,
    required double montantGlobal,
  }) {
    if (index < 0 || index >= _panier.length) return null;
    if (quantite <= 0 || montantGlobal <= 0) {
      return 'Veuillez saisir une quantité et un montant valides.';
    }

    final ligne = _panier[index];
    final autresLignes = _panier
        .asMap()
        .entries
        .where((e) => e.key != index && e.value.produitId == ligne.produitId)
        .fold<double>(0, (s, e) => s + e.value.quantite);
    if (autresLignes + quantite > ligne.stockDisponible) {
      return 'Stock insuffisant (${ligne.stockDisponible} disponible).';
    }

    _panier[index] = ligne.copyWith(
      quantite: quantite,
      montantGlobal: montantGlobal,
    );
    notifyListeners();
    return null;
  }

  void retirerLigne(int index) {
    if (index < 0 || index >= _panier.length) return;
    _panier.removeAt(index);
    notifyListeners();
  }

  void retirerDuPanier(String produitId) {
    _panier.removeWhere((l) => l.produitId == produitId);
    notifyListeners();
  }

  void viderPanier() {
    _panier.clear();
    _client = '';
    _clientId = null;
    _montantRecu = 0;
    _mode = ModeReglement.especes;
    _condition = ConditionPaiement.comptant;
    _echeance = null;
    _livraison = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------- KPI
  // Doc F4 : KPI globaux, persistants au-dessus des onglets.

  List<Vente> get _ventesDuJour {
    final aujourdhui = DateTime.now();
    return _ventes
        .where(
          (v) =>
              !v.estAnnulee &&
              v.date.year == aujourdhui.year &&
              v.date.month == aujourdhui.month &&
              v.date.day == aujourdhui.day,
        )
        .toList();
  }

  double get chiffreAffairesDuJour =>
      _ventesDuJour.fold(0, (s, v) => s + v.total);

  /// `null` — et non 0 — s'il n'y a eu aucune vente : une moyenne sur zéro
  /// vente n'existe pas.
  double? get panierMoyen {
    final ventes = _ventesDuJour;
    if (ventes.isEmpty) return null;
    return chiffreAffairesDuJour / ventes.length;
  }

  int get ventesEnAttente => _ventes.where((v) => v.estEnAvance).length;

  // ------------------------------------------------------------- chargement

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    await _rafraichir();
    _chargement = false;
    notifyListeners();
  }

  Future<void> _rafraichir() async {
    _catalogue = await _repository.chargerCatalogue();
    _clients = await _repository.chargerClientsChoix();
    _ventes = await _repository.chargerVentes();
    _devis = await _chargerDevis();
    _ligneMobileMoney = await _chargerLigneMobileMoney();
    _delaiPaiementParDefaut = await _chargerDelaiPaiement();
  }

  Future<int?> _chargerDelaiPaiement() async {
    final parametres = await ParametresRepositoryDrift(_db).charger();
    final delai = parametres.delaiPaiementJours;
    return (delai == null || delai <= 0) ? null : delai;
  }

  // ------------------------------------------------------- ligne Mobile Money
  //
  // `ventes.html` l.388 code en dur `MOBILE_MONEY_ACCOUNTS = [{ id:'momo1',
  // label:'Mobile Money — +229 97 00 00 00 (Gerante)' }]`, puis ouvre une
  // modale « Choisir la ligne Mobile Money » pour faire choisir parmi... une
  // seule option, et `validateSale()` ne conserve pas le choix.
  //
  // Le numero code en dur est **exactement** le « Telephone Principal » de
  // `parametres-generaux.html` l.147. Ce n'est donc pas une donnee du point de
  // vente : c'est une donnee d'entreprise, deja administrable. Elle est lue la,
  // affichee en clair dans le panier, et copiee sur la vente.

  String? _ligneMobileMoney;

  /// La ligne creditee quand le reglement est en Mobile Money, `null` sinon.
  String? get ligneMobileMoney =>
      _mode == ModeReglement.mobileMoney ? _ligneMobileMoney : null;

  /// Vrai quand le mode Mobile Money est choisi alors qu'aucun numero n'est
  /// renseigne dans Parametres Generaux.
  bool get ligneMobileMoneyManquante =>
      _mode == ModeReglement.mobileMoney && _ligneMobileMoney == null;

  Future<String?> _chargerLigneMobileMoney() async {
    // On passe par le repository des parametres, pas par une requete directe :
    // c'est lui qui porte les valeurs par defaut de `parametres-generaux.html`
    // tant que la Gerante n'a rien enregistre. Interroger la table en direct
    // renverrait `null` sur une base neuve alors que l'ecran Parametres, lui,
    // affiche bien un numero — deux verites pour une meme donnee.
    final parametres = await ParametresRepositoryDrift(_db).charger();
    final telephone = parametres.telephone?.trim();
    return (telephone == null || telephone.isEmpty) ? null : telephone;
  }

  // ------------------------------------------------------------ encaissement

  /// Validation avant encaissement — Doc E6 §4, `PosValidator`.
  String? validerAvantEncaissement() {
    if (_panier.isEmpty) return 'Le panier est vide.';
    if (ligneMobileMoneyManquante) {
      // Le prototype refuse la vente tant que la ligne n'est pas choisie ; il
      // en propose une, codee en dur. Ici le refus subsiste mais dit ou aller
      // la renseigner, au lieu d'imposer un numero que personne n'a saisi.
      return 'Aucun numéro Mobile Money n\'est enregistré. Renseignez le '
          'Téléphone Principal dans Paramètres Généraux avant d\'encaisser '
          'par Mobile Money.';
    }
    if (estAvance && _montantRecu <= 0) {
      return 'Veuillez saisir le montant reçu pour une vente à crédit.';
    }
    if (estAvance && _montantRecu >= totalPanier) {
      // Sinon la vente serait enregistree « Avance » avec un reste du nul :
      // elle apparaitrait en creance dans Clients sans rien a recouvrer.
      return 'Le montant reçu solde la vente : choisissez « Comptant ».';
    }
    if (!estAvance && _montantRecu < totalPanier) {
      return 'Le montant reçu est inférieur au total de la vente.';
    }
    return null;
  }

  Future<Resultat<Vente>> encaisser() async {
    final erreur = validerAvantEncaissement();
    if (erreur != null) return Echec(erreur);

    final enAvance = estAvance;
    try {
      final resultat = await _repository.enregistrerVente(
        client: _client.trim().isEmpty ? 'Client Comptant' : _client.trim(),
        clientId: _clientId,
        mode: _mode,
        statut: enAvance ? StatutVente.avance : StatutVente.payee,
        // Une vente comptant est soldée : `paye` vaut le total, pas le montant
        // remis en main (qui peut inclure la monnaie à rendre).
        montantPaye: enAvance ? _montantRecu : totalPanier,
        panier: List.of(_panier),
        livraison: _livraison,
        ligneMobileMoney: ligneMobileMoney,
        echeance: echeance,
      );
      viderPanier();
      await _rafraichir();
      notifyListeners();
      return Succes(resultat.vente);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec encaissement: $e');
      return const Echec(
        'La vente n\'a pas pu être enregistrée. Aucune modification n\'a été '
        'appliquée au stock.',
      );
    }
  }

  Future<Resultat<void>> annuler({
    required String reference,
    required String? motif,
  }) async {
    if (motif == null || motif.trim().isEmpty) {
      return const Echec('Le motif d\'annulation est obligatoire.');
    }
    try {
      await _repository.annulerVente(reference: reference, motif: motif);
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec annulation: $e');
      return const Echec('Cette vente n\'a pas pu être annulée.');
    }
  }

  Future<Resultat<void>> enregistrerPaiement({
    required String reference,
    required double montant,
  }) async {
    if (montant <= 0) return const Echec('Le montant doit être supérieur à 0.');
    try {
      await _repository.enregistrerPaiement(
        reference: reference,
        montant: montant,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec paiement: $e');
      return const Echec('Le paiement n\'a pas pu être enregistré.');
    }
  }

  // ------------------------------------------------------------------- devis

  late final DevisRepositoryDrift _devisRepository = DevisRepositoryDrift(_db);

  Future<List<DevisEmis>> _chargerDevis() => _devisRepository.tous();

  Future<Resultat<DevisEmis>> genererDevis({
    required String client,
    required String objet,
    required double? montant,
    required int? validiteJours,
  }) => _apresDevis(
    _devisRepository.creer(
      client: client,
      objet: objet,
      montant: montant,
      validiteJours: validiteJours,
    ),
  );

  /// Modifie un devis ÉMIS (un devis accepté ou refusé ne se modifie plus).
  Future<Resultat<DevisEmis>> modifierDevis({
    required String id,
    required String client,
    required String objet,
    required double? montant,
    required int? validiteJours,
  }) => _apresDevis(
    _devisRepository.modifier(
      id: id,
      client: client,
      objet: objet,
      montant: montant,
      validiteJours: validiteJours,
    ),
  );

  Future<Resultat<DevisEmis>> changerStatutDevis(
    String id,
    StatutDevis statut,
  ) => _apresDevis(_devisRepository.changerStatut(id, statut));

  /// Un nouveau devis (nouveau numéro) au contenu de celui-ci.
  Future<Resultat<DevisEmis>> dupliquerDevis(String id) =>
      _apresDevis(_devisRepository.dupliquer(id));

  /// Pierre tombale ; un devis accepté ne se supprime pas.
  Future<Resultat<void>> supprimerDevis(String id) async {
    final resultat = await _devisRepository.supprimer(id);
    _devis = await _chargerDevis();
    notifyListeners();
    return resultat;
  }

  Future<Resultat<DevisEmis>> _apresDevis(
    Future<Resultat<DevisEmis>> operation,
  ) async {
    final resultat = await operation;
    _devis = await _chargerDevis();
    notifyListeners();
    return resultat;
  }

  // -------------------------------------------------------------- historique

  String _rechercheHistorique = '';
  String? _filtreStatut;
  String get rechercheHistorique => _rechercheHistorique;
  String? get filtreStatut => _filtreStatut;

  void definirRechercheHistorique(String valeur) {
    _rechercheHistorique = valeur;
    notifyListeners();
  }

  void definirFiltreStatut(String? valeur) {
    _filtreStatut = valeur;
    notifyListeners();
  }

  List<Vente> get historiqueFiltre {
    final terme = _rechercheHistorique.trim().toLowerCase();
    return _ventes.where((v) {
      if (_filtreStatut != null && v.statut != _filtreStatut) return false;
      if (terme.isEmpty) return true;
      return v.reference.toLowerCase().contains(terme) ||
          v.client.toLowerCase().contains(terme);
    }).toList();
  }

  /// Onglet 4 — vue de consultation pure des ventes annulées (Doc H1).
  List<Vente> get retours => _ventes.where((v) => v.estAnnulee).toList();

  /// Ventes en avance non soldées — alimente l'écran Clients & Créances.
  List<Vente> get creances => _ventes.where((v) => v.estEnAvance).toList();
}
