import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Peuplement initial du catalogue de produits vendables.
///
/// Les 14 lignes ci-dessous sont la transcription **litterale** de
/// `DEFAULT_STOCK` dans `prototype_html/assets/js/logialvia-store.js` (l.46-61) :
/// noms, prix, fourchettes, unites, icones, stocks et seuils, sans exception.
/// Aucune valeur n'a ete arrondie, completee ou inventee.
///
/// Idempotent : si le catalogue contient deja au moins une ligne, rien n'est
/// fait — le seed ne doit jamais ecraser un catalogue reellement edite par
/// l'utilisatrice (meme principe que `AdminSeeder`, Doc K4 §8).
class CatalogueSeeder {
  const CatalogueSeeder(this._db);

  final AppDatabase _db;

  /// NOTE (ecart reel avec Doc D1) : le dictionnaire de donnees contraint
  /// `PRODUITS_VENDABLES.cat` a ('Avicole','Commerce Annexe'). Le prototype
  /// utilise en realite **4** categories — 'Cuniculture' et 'Pisciculture' en
  /// plus. Ce sont les donnees sources qui font foi (Master Prompt §1), la
  /// contrainte de Doc D1 est donc incomplete et signalee comme telle.
  static const List<
    ({
      String name,
      String cat,
      double price,
      double? priceMax,
      String unit,
      String icon,
      int stock,
      int threshold,
      String? espece,
    })
  >
  produits = [
    (
      name: 'Poussin d\'un jour',
      cat: 'Avicole',
      price: 400,
      priceMax: null,
      unit: 'u',
      icon: 'egg',
      stock: 85,
      threshold: 20,
      espece: null,
    ),
    (
      name: 'Œufs fertiles pintade (u)',
      cat: 'Avicole',
      price: 600,
      priceMax: null,
      unit: 'u',
      icon: 'egg',
      stock: 120,
      threshold: 30,
      espece: null,
    ),
    (
      name: 'Œufs fertiles goliath (u)',
      cat: 'Avicole',
      price: 550,
      priceMax: null,
      unit: 'u',
      icon: 'egg',
      stock: 95,
      threshold: 30,
      espece: null,
    ),
    (
      name: 'Goliath mature',
      cat: 'Avicole',
      price: 6000,
      priceMax: 8500,
      unit: 'sujet(s)',
      icon: 'pets',
      stock: 31,
      threshold: 10,
      espece: 'goliaths',
    ),
    (
      name: 'Pintade mature',
      cat: 'Avicole',
      price: 6500,
      priceMax: 9000,
      unit: 'sujet(s)',
      icon: 'pets',
      stock: 28,
      threshold: 10,
      espece: 'pintades',
    ),
    (
      name: 'Fournitures scolaires (lot)',
      cat: 'Commerce Annexe',
      price: 1500,
      priceMax: 3500,
      unit: 'lot(s)',
      icon: 'school',
      stock: 34,
      threshold: 10,
      espece: null,
    ),
    (
      name: 'Tee-shirt enfant',
      cat: 'Commerce Annexe',
      price: 1000,
      priceMax: 2000,
      unit: 'u',
      icon: 'checkroom',
      stock: 26,
      threshold: 8,
      espece: null,
    ),
    (
      name: 'Pantalon enfant/adulte',
      cat: 'Commerce Annexe',
      price: 2000,
      priceMax: 4500,
      unit: 'u',
      icon: 'checkroom',
      stock: 18,
      threshold: 6,
      espece: null,
    ),
    (
      name: 'Chaussures enfant/adulte',
      cat: 'Commerce Annexe',
      price: 2500,
      priceMax: 6000,
      unit: 'paire(s)',
      icon: 'footprint',
      stock: 14,
      threshold: 5,
      espece: null,
    ),
    (
      name: 'Sac d\'écolier',
      cat: 'Commerce Annexe',
      price: 2000,
      priceMax: 4000,
      unit: 'u',
      icon: 'backpack',
      stock: 20,
      threshold: 6,
      espece: null,
    ),
    (
      name: 'Lapin vif (sujet)',
      cat: 'Cuniculture',
      price: 2800,
      priceMax: null,
      unit: 'sujet(s)',
      icon: 'cruelty_free',
      stock: 22,
      threshold: 8,
      espece: 'lapins',
    ),
    (
      name: 'Poulet de chair (sujet)',
      cat: 'Avicole',
      price: 3200,
      priceMax: null,
      unit: 'sujet(s)',
      icon: 'pets',
      stock: 18,
      threshold: 6,
      espece: 'poulets',
    ),
    (
      name: 'Œufs de table (plateau)',
      cat: 'Avicole',
      price: 2500,
      priceMax: null,
      unit: 'plateau(x)',
      icon: 'egg',
      stock: 12,
      threshold: 5,
      espece: 'pondeuses',
    ),
    (
      name: 'Poisson-chat vif (kg)',
      cat: 'Pisciculture',
      price: 1800,
      priceMax: null,
      unit: 'kg',
      icon: 'set_meal',
      stock: 15,
      threshold: 5,
      espece: 'poissons-chats',
    ),
  ];

  /// Retourne `true` si le catalogue vient d'etre peuple.
  Future<bool> executer() async {
    if (await _contientDejaDesLignes()) return false;

    await _db.batch((batch) {
      batch.insertAll(
        _db.produitsVendables,
        produits.indexed.map(
          (entree) => ProduitsVendablesCompanion.insert(
            // Le prototype affiche une colonne SKU sans documenter de regle de
            // codification : 'PRD-NNN' sequentiel, choix explicite.
            sku: Value('PRD-${(entree.$1 + 1).toString().padLeft(3, '0')}'),
            name: entree.$2.name,
            cat: entree.$2.cat,
            price: entree.$2.price,
            priceMax: Value(entree.$2.priceMax),
            unit: entree.$2.unit,
            icon: entree.$2.icon,
            stock: entree.$2.stock,
            threshold: entree.$2.threshold,
            espece: Value(entree.$2.espece),
          ),
        ),
      );
    });
    return true;
  }

  /// `LIMIT 1` plutot qu'un `COUNT(*)` : on veut seulement savoir si la table
  /// est vide, pas combien elle contient de lignes.
  Future<bool> _contientDejaDesLignes() async {
    final premiere = await (_db.select(
      _db.produitsVendables,
    )..limit(1)).getSingleOrNull();
    return premiere != null;
  }
}
