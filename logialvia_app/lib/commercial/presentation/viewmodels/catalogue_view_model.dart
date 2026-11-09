import '../../../administration/domain/services/service_archivage.dart';
import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../domain/entities/produit_vendable.dart';
import '../../domain/repositories/ventes_repository.dart';

/// Catalogue & Seuils — Doc F4 Écran 2, fidèle à `catalogue-produits.html`.
///
/// ⚠️ L'écran réel comporte **2 tableaux** — le catalogue (SKU, Désignation,
/// Catégorie, Stock, Tarif, Actions) et les seuils d'alerte (Désignation,
/// Stock Actuel, Seuil d'Alerte, Statut, Action). C'est d'ailleurs le nom que
/// lui donne la barre latérale : « Catalogue & Seuils ».
class CatalogueViewModel extends ChangeNotifier {
  CatalogueViewModel(this._repository);

  final VentesRepository _repository;

  bool _chargement = true;
  bool get chargement => _chargement;

  List<ProduitVendable> _produits = const [];

  String _recherche = '';
  String? _filtreCategorie;
  String get recherche => _recherche;
  String? get filtreCategorie => _filtreCategorie;

  List<ProduitVendable> get produits {
    final terme = _recherche.trim().toLowerCase();
    return _produits.where((p) {
      if (_filtreCategorie != null && p.categorie != _filtreCategorie) {
        return false;
      }
      if (terme.isEmpty) return true;
      return p.nom.toLowerCase().contains(terme) ||
          (p.sku?.toLowerCase().contains(terme) ?? false);
    }).toList();
  }

  /// 2ᵉ tableau — uniquement les produits sous leur seuil.
  List<ProduitVendable> get produitsSousSeuil =>
      _produits.where((p) => p.estCritique).toList();

  List<String> get categories =>
      (_produits.map((p) => p.categorie).toSet().toList()..sort());

  void definirRecherche(String valeur) {
    _recherche = valeur;
    notifyListeners();
  }

  void definirCategorie(String? valeur) {
    _filtreCategorie = valeur;
    notifyListeners();
  }

  // ------------------------------------------------------------------- KPI
  // Doc F4 Écran 2.

  int get produitsActifs => _produits.length;

  /// Somme stock × **prix de vente** — ce que le catalogue vaut à la vente.
  double get valeurCatalogue => _produits.fold(0, (s, p) => s + p.valeurStock);

  /// Somme stock × **coût de revient**, sur les seuls produits qui en ont un.
  ///
  /// Distincte de [valeurCatalogue] : l'une dit ce que la ferme espère
  /// encaisser, l'autre ce qu'elle a dépensé. Le prototype ne connaît que la
  /// première et l'appelle « CMUP » dans le Rapport de Stocks.
  double get valeurCatalogueAuCout =>
      _produits.fold(0, (s, p) => s + (p.valeurStockAuCout ?? 0));

  /// Produits dont le coût de revient n'est pas renseigné : leur stock n'entre
  /// dans aucune valorisation au coût.
  List<ProduitVendable> get produitsSansCout =>
      _produits.where((p) => p.coutRevient == null).toList();

  int get produitsCritiques => produitsSousSeuil.length;

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    _produits = await _repository.chargerCatalogue();
    _chargement = false;
    notifyListeners();
  }

  /// Génère le prochain SKU. Aucune règle de codification n'étant documentée,
  /// le format `PRD-NNN` est un choix explicite, signalé comme tel.
  String _prochainSku() {
    var maximum = 0;
    for (final produit in _produits) {
      final sku = produit.sku;
      if (sku == null || !sku.startsWith('PRD-')) continue;
      final numero = int.tryParse(sku.substring(4));
      if (numero != null && numero > maximum) maximum = numero;
    }
    return 'PRD-${(maximum + 1).toString().padLeft(3, '0')}';
  }

  Future<Resultat<ProduitVendable>> enregistrer({
    String? id,
    required String nom,
    required String? categorie,
    required double? prix,
    double? prixMax,
    required String unite,
    required int? stock,
    required int? seuil,
    String? espece,
    String? icone,
    double? coutRevient,
  }) async {
    if (nom.trim().isEmpty) {
      return const Echec('La désignation est obligatoire.');
    }
    if (categorie == null) return const Echec('La catégorie est obligatoire.');
    if (prix == null || prix <= 0) {
      return const Echec('Le tarif indicatif doit être supérieur à 0.');
    }
    if (prixMax != null && prixMax < prix) {
      return const Echec(
        'Le prix haut de fourchette ne peut être inférieur au prix bas.',
      );
    }
    if ((stock ?? 0) < 0) {
      return const Echec('Le stock ne peut être négatif.');
    }
    if ((seuil ?? 0) < 0) {
      return const Echec('Le seuil d\'alerte ne peut être négatif.');
    }
    if (coutRevient != null && coutRevient < 0) {
      return const Echec('Le coût de revient ne peut être négatif.');
    }
    if (coutRevient != null && coutRevient > prix) {
      // Refus et non avertissement : un cout superieur au prix signifie que
      // chaque vente perd de l'argent. Si c'est vrai, c'est le prix qu'il faut
      // corriger, pas le cout qu'il faut accepter en silence.
      return const Echec(
        'Le coût de revient dépasse le tarif indicatif : chaque vente serait '
        'à perte. Vérifiez l\'un ou l\'autre.',
      );
    }

    final produit = ProduitVendable(
      // Vide = nouveau produit : le depot lui donne son UUID a la creation.
      id: id ?? '',
      sku: id == null ? _prochainSku() : null,
      nom: nom.trim(),
      categorie: categorie,
      prix: prix,
      prixMax: prixMax,
      unite: unite.trim().isEmpty ? 'u' : unite.trim(),
      icone: icone ?? 'category',
      stock: stock ?? 0,
      seuil: seuil ?? 0,
      espece: espece,
      coutRevient: coutRevient,
    );

    try {
      if (id == null) {
        await _repository.creerProduit(produit);
      } else {
        // Le SKU d'un produit existant n'est jamais reecrit.
        final existant = _produits.firstWhere((p) => p.id == id);
        await _repository.mettreAJourProduit(
          ProduitVendable(
            id: id,
            sku: existant.sku,
            nom: produit.nom,
            categorie: produit.categorie,
            prix: produit.prix,
            prixMax: produit.prixMax,
            unite: produit.unite,
            icone: existant.icone,
            stock: produit.stock,
            seuil: produit.seuil,
            espece: produit.espece,
            coutRevient: produit.coutRevient,
          ),
        );
      }
      await charger();
      return Succes(produit);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec enregistrement produit: $e');
      return const Echec('Impossible d\'enregistrer ce produit.');
    }
  }

  Future<Resultat<void>> supprimer(
    ProduitVendable produit, {
    AuteurArchivage? auteur,
  }) async {
    try {
      await _repository.supprimerProduit(
        produit.id,
        utilisateurId: auteur?.id,
        utilisateurNom: auteur?.nom,
      );
      await charger();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec suppression produit: $e');
      // Une cle etrangere depuis LIGNES_VENTE empeche la suppression d'un
      // produit deja vendu — c'est voulu : l'historique doit rester lisible.
      return const Echec(
        'Ce produit ne peut pas être supprimé : il figure dans des ventes '
        'déjà enregistrées.',
      );
    }
  }
}
