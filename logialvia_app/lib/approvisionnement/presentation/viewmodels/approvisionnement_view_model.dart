import '../../../administration/domain/services/service_archivage.dart';
import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../data/repositories/approvisionnement_repository_drift.dart';
import '../../domain/entities/approvisionnement.dart';
import '../../domain/entities/fabrication_provende.dart';

/// État partagé du contexte Approvisionnement — Doc F5.
///
/// Un seul ViewModel pour les 3 écrans (Stocks, Achats, Fournisseurs) : ils
/// lisent les mêmes tables et une commande réceptionnée depuis l'écran Achats
/// doit se voir immédiatement dans les Stocks. Trois ViewModels séparés
/// auraient chacun leur copie, et donc leur propre version de la vérité.
class ApprovisionnementViewModel extends ChangeNotifier {
  ApprovisionnementViewModel(this._repository);

  final ApprovisionnementRepository _repository;

  /// Fenêtre du KPI « Mouvements (7j) ».
  static const int fenetreMouvementsJours = 7;

  bool _chargement = true;
  bool get chargement => _chargement;

  List<Intrant> _intrants = const [];
  List<MouvementIntrant> _mouvements = const [];
  List<Fournisseur> _fournisseurs = const [];
  List<Achat> _achats = const [];

  List<MouvementIntrant> get mouvements => _mouvements;
  List<Fournisseur> get fournisseurs => _fournisseurs;
  List<Achat> get achats => _achats;

  String _recherche = '';
  String? _filtreCategorie;
  String get recherche => _recherche;
  String? get filtreCategorie => _filtreCategorie;

  List<Intrant> get intrants {
    final terme = _recherche.trim().toLowerCase();
    return _intrants.where((i) {
      if (_filtreCategorie != null && i.categorie != _filtreCategorie) {
        return false;
      }
      if (terme.isEmpty) return true;
      return i.nom.toLowerCase().contains(terme) ||
          i.code.toLowerCase().contains(terme);
    }).toList();
  }

  List<Intrant> get tousLesIntrants => _intrants;

  void definirRecherche(String valeur) {
    _recherche = valeur;
    notifyListeners();
  }

  void definirCategorie(String? valeur) {
    _filtreCategorie = valeur;
    notifyListeners();
  }

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    await _rafraichir();
    _chargement = false;
    notifyListeners();
  }

  Future<void> _rafraichir() async {
    _intrants = await _repository.chargerIntrants();
    _mouvements = await _repository.chargerMouvements();
    _fournisseurs = await _repository.chargerFournisseurs();
    _achats = await _repository.chargerAchats();
  }

  // -------------------------------------------------- KPI Gestion des Stocks
  // Libellés réels de `gestion-stocks.html` l.102-114.

  double get valeurTotaleStock =>
      _intrants.fold(0, (s, i) => s + i.valeur);

  int get intrantsSousSeuil => _intrants.where((i) => i.estCritique).length;

  int get articlesSuivis => _intrants.length;

  /// « Mouvements (7j) » — ⚠️ Doc F5 annonçait « Dernier Mouvement ».
  int get mouvements7Jours {
    final limite = DateTime.now().subtract(
      const Duration(days: fenetreMouvementsJours),
    );
    return _mouvements.where((m) => m.horodatage.isAfter(limite)).length;
  }

  // ------------------------------------------------------ KPI Fournisseurs
  // Libellés réels de `fournisseurs.html` l.105-117.

  int get fournisseursActifs => _fournisseurs.length;

  double get detteTotale => _fournisseurs.fold(0, (s, f) => s + f.soldeDu);

  /// « Achats Cumulés (Mois) »
  double get achatsCumulesMois {
    final maintenant = DateTime.now();
    final debutMois = DateTime(maintenant.year, maintenant.month);
    return _achats
        .where((a) => !a.estAnnule && !a.date.isBefore(debutMois))
        .fold(0, (s, a) => s + a.total);
  }

  /// « Dettes Soldées (Mois) » — commandes du mois entièrement réglées.
  int get dettesSoldeesMois {
    final maintenant = DateTime.now();
    final debutMois = DateTime(maintenant.year, maintenant.month);
    return _achats
        .where(
          (a) =>
              !a.estAnnule &&
              !a.date.isBefore(debutMois) &&
              a.soldeDu <= 0 &&
              a.total > 0,
        )
        .length;
  }

  /// Commandes non soldées — tableau des dettes.
  List<Achat> get dettes =>
      _achats.where((a) => !a.estAnnule && a.soldeDu > 0).toList();

  // ---------------------------------------------------------- KPI Achats
  // Doc F5 Écran 2.

  int get commandesEnCours =>
      _achats.where((a) => a.statut == StatutAchat.commande).length;

  double get montantTotalEngage => _achats
      .where((a) => a.statut == StatutAchat.commande)
      .fold(0, (s, a) => s + a.total);

  // ------------------------------------------------------------------ panier

  final List<LignePanierAchat> _panier = [];
  List<LignePanierAchat> get panier => List.unmodifiable(_panier);

  double get totalPanier => _panier.fold(0, (s, l) => s + l.total);
  bool get panierVide => _panier.isEmpty;

  int? _fournisseurSelectionne;
  int? get fournisseurSelectionne => _fournisseurSelectionne;
  set fournisseurSelectionne(int? valeur) {
    _fournisseurSelectionne = valeur;
    notifyListeners();
  }

  String _modeAchat = 'Espèces';
  String get modeAchat => _modeAchat;
  set modeAchat(String valeur) {
    _modeAchat = valeur;
    notifyListeners();
  }

  double _montantRegle = 0;
  double get montantRegle => _montantRegle;
  set montantRegle(double valeur) {
    _montantRegle = valeur;
    notifyListeners();
  }

  bool _livreeImmediatement = true;
  bool get livreeImmediatement => _livreeImmediatement;
  set livreeImmediatement(bool valeur) {
    _livreeImmediatement = valeur;
    notifyListeners();
  }

  void ajouterAuPanier(Intrant intrant) {
    final index = _panier.indexWhere((l) => l.intrantCode == intrant.code);
    if (index == -1) {
      _panier.add(
        LignePanierAchat(
          intrantCode: intrant.code,
          nom: intrant.nom,
          quantite: 1,
          // Le PMP actuel sert de prix propose, pas de prix impose.
          prixUnitaire: intrant.pmp.toDouble(),
          unite: intrant.unite,
        ),
      );
    } else {
      _panier[index] = _panier[index].copyWith(
        quantite: _panier[index].quantite + 1,
      );
    }
    notifyListeners();
  }

  void changerLignePanier(
    String code, {
    double? quantite,
    double? prixUnitaire,
  }) {
    final index = _panier.indexWhere((l) => l.intrantCode == code);
    if (index == -1) return;
    if (quantite != null && quantite <= 0) {
      _panier.removeAt(index);
      notifyListeners();
      return;
    }
    _panier[index] = _panier[index].copyWith(
      quantite: quantite,
      prixUnitaire: prixUnitaire,
    );
    notifyListeners();
  }

  void retirerDuPanier(String code) {
    _panier.removeWhere((l) => l.intrantCode == code);
    notifyListeners();
  }

  void viderPanier() {
    _panier.clear();
    _fournisseurSelectionne = null;
    _montantRegle = 0;
    _modeAchat = 'Espèces';
    _livreeImmediatement = true;
    notifyListeners();
  }

  // ------------------------------------------------------------------ actions

  Future<Resultat<Achat>> validerCommande() async {
    if (_panier.isEmpty) return const Echec('Le panier d\'achat est vide.');
    if (_fournisseurSelectionne == null) {
      return const Echec('Sélectionnez un fournisseur.');
    }
    if (_montantRegle < 0) {
      return const Echec('Le montant réglé ne peut être négatif.');
    }
    if (_panier.any((l) => l.prixUnitaire <= 0)) {
      return const Echec('Chaque ligne doit avoir un prix unitaire positif.');
    }

    try {
      final achat = await _repository.enregistrerAchat(
        fournisseurId: _fournisseurSelectionne!,
        mode: _modeAchat,
        montantPaye: _montantRegle.clamp(0, totalPanier),
        panier: List.of(_panier),
        livree: _livreeImmediatement,
      );
      viderPanier();
      await _rafraichir();
      notifyListeners();
      return Succes(achat);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec commande: $e');
      return const Echec(
        'La commande n\'a pas pu être enregistrée. Aucun stock n\'a été '
        'modifié.',
      );
    }
  }

  Future<Resultat<void>> receptionner(Achat achat) async {
    try {
      await _repository.receptionnerAchat(achat.reference);
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec reception: $e');
      return const Echec('Cette commande n\'a pas pu être réceptionnée.');
    }
  }

  Future<Resultat<void>> reglerDette({
    required String reference,
    required double? montant,
  }) async {
    if (montant == null || montant <= 0) {
      return const Echec('Le montant doit être supérieur à 0.');
    }
    try {
      await _repository.reglerAchat(reference: reference, montant: montant);
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec reglement: $e');
      return const Echec('Le règlement n\'a pas pu être enregistré.');
    }
  }

  Future<Resultat<void>> enregistrerIntrant({
    String? code,
    required String nom,
    required String? categorie,
    required int? stock,
    required String unite,
    required int? seuil,
    required int? pmp,
  }) async {
    if (nom.trim().isEmpty) {
      return const Echec('La désignation est obligatoire.');
    }
    if (categorie == null) return const Echec('La catégorie est obligatoire.');
    if ((stock ?? 0) < 0) return const Echec('Le stock ne peut être négatif.');
    if ((seuil ?? 0) < 0) return const Echec('Le seuil ne peut être négatif.');
    if ((pmp ?? 0) < 0) return const Echec('Le prix ne peut être négatif.');

    try {
      await _repository.enregistrerIntrant(
        Intrant(
          code: code ?? _prochainCode(),
          nom: nom.trim(),
          categorie: categorie,
          stock: stock ?? 0,
          unite: unite.trim().isEmpty ? 'u' : unite.trim(),
          seuil: seuil ?? 0,
          pmp: pmp ?? 0,
        ),
        creation: code == null,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec enregistrement intrant: $e');
      return const Echec('Impossible d\'enregistrer cet intrant.');
    }
  }

  Future<Resultat<void>> supprimerIntrant(
    Intrant intrant, {
    AuteurArchivage? auteur,
  }) async {
    try {
      await _repository.supprimerIntrant(
        intrant.code,
        utilisateurId: auteur?.id,
        utilisateurNom: auteur?.nom,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec suppression intrant: $e');
      return const Echec(
        'Cet intrant ne peut pas être supprimé : il figure dans des commandes '
        'ou des mouvements déjà enregistrés.',
      );
    }
  }

  // ------------------------------------------- Fabrication de provende

  /// Les 5 intrants de provende, seuls candidats à une fabrication.
  List<Intrant> get intrantsDeProvende => _intrants
      .where((i) => i.categorie == 'Intrants Provende')
      .toList();

  /// Lance une fabrication. Voir [FabricationProvende] pour ce que le prototype
  /// annonce sans le faire.
  Future<Resultat<String>> fabriquerProvende(
    Map<String, double> quantites,
  ) async {
    final fabrication = FabricationProvende(quantites);
    final erreur = fabrication.valider(intrantsDeProvende);
    if (erreur != null) return Echec(erreur);

    try {
      final reference = await _repository.fabriquerProvende(fabrication);
      await _rafraichir();
      notifyListeners();
      return Succes(reference);
    } on StateError catch (e) {
      // Message metier du controle de stock — il doit remonter tel quel.
      return Echec(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec fabrication: $e');
      return const Echec(
        'La fabrication n\'a pas pu être enregistrée. Aucun stock n\'a été '
        'modifié.',
      );
    }
  }

  Future<Resultat<void>> ajusterInventaire({
    required Intrant intrant,
    required int? stockPhysique,
    required String motif,
  }) async {
    if (stockPhysique == null || stockPhysique < 0) {
      return const Echec('Le stock physique constaté est invalide.');
    }
    if (motif.trim().isEmpty) {
      return const Echec('Le motif de l\'ajustement est obligatoire.');
    }

    try {
      await _repository.ajusterInventaire(
        code: intrant.code,
        stockPhysique: stockPhysique,
        motif: motif.trim(),
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec ajustement: $e');
      return const Echec('L\'ajustement n\'a pas pu être enregistré.');
    }
  }

  Future<Resultat<Fournisseur>> creerFournisseur({
    required String nom,
    String? telephone,
    String? adresse,
    String? fournit,
  }) async {
    if (nom.trim().isEmpty) return const Echec('Le nom est obligatoire.');
    if (_fournisseurs.any(
      (f) => f.nom.toLowerCase() == nom.trim().toLowerCase(),
    )) {
      return const Echec('Un fournisseur porte déjà ce nom.');
    }

    try {
      final fournisseur = await _repository.creerFournisseur(
        nom: nom.trim(),
        telephone: telephone?.trim().isEmpty ?? true ? null : telephone!.trim(),
        adresse: adresse?.trim().isEmpty ?? true ? null : adresse!.trim(),
        fournit: fournit?.trim().isEmpty ?? true ? null : fournit!.trim(),
      );
      await _rafraichir();
      notifyListeners();
      return Succes(fournisseur);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec creation fournisseur: $e');
      return const Echec('Impossible d\'enregistrer ce fournisseur.');
    }
  }

  /// Code métier séquentiel `INT-NNN`, cohérent avec les 6 intrants seedés.
  String _prochainCode() {
    var maximum = 0;
    for (final intrant in _intrants) {
      if (!intrant.code.startsWith('INT-')) continue;
      final numero = int.tryParse(intrant.code.substring(4));
      if (numero != null && numero > maximum) maximum = numero;
    }
    return 'INT-${(maximum + 1).toString().padLeft(3, '0')}';
  }
}
