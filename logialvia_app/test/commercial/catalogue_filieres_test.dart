import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/commercial/presentation/viewmodels/catalogue_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';

/// Un produit du catalogue peut être rattaché à une filière d'élevage — dont
/// escargots et ovins (DV-16, DV-17).
///
/// Sans ce rattachement, la vente ne décrémente aucune catégorie de la fiche,
/// n'incrémente pas le compteur de ventes du jour et n'est imputée à aucun
/// centre analytique : la fiche et le stock racontent deux histoires.
///
/// Les prix ci-dessous sont des valeurs de TEST : le logiciel n'en sème aucun
/// pour ces deux filières, c'est à la Gérante de les fixer.
void main() {
  late AppDatabase db;
  late EventBus bus;
  late VentesRepositoryDrift repository;
  late CatalogueViewModel catalogue;

  setUp(() async {
    db = AppDatabase.enMemoire();
    // Base realiste : l'exercice comptable ouvert permet l'ecriture automatique.
    await SeedInitial(db).executer();
    bus = EventBus();
    repository = VentesRepositoryDrift(db, bus);
    catalogue = CatalogueViewModel(repository);
    await catalogue.charger();
  });

  tearDown(() async {
    catalogue.dispose();
    bus.dispose();
    await db.close();
  });

  Future<ProduitVendable> creer({
    required String nom,
    required String categorie,
    String? espece,
    String unite = 'sujet(s)',
    double prix = 1000,
    int stock = 10,
  }) async {
    final resultat = await catalogue.enregistrer(
      nom: nom,
      categorie: categorie,
      prix: prix,
      unite: unite,
      stock: stock,
      seuil: 2,
      espece: espece,
    );
    expect(resultat, isA<Succes<ProduitVendable>>());
    // L'identifiant est attribue par la base : on relit le produit.
    return (await repository.chargerCatalogue()).firstWhere(
      (p) => p.nom == nom,
    );
  }

  test('les catégories proposées incluent les deux filières', () {
    expect(
      ProduitVendable.categories,
      containsAll(['Héliciculture', 'Élevage ovin']),
    );
  });

  test('la filière choisie est enregistrée, relue et modifiable', () async {
    final produit = await creer(
      nom: 'Escargot marchand (sujet)',
      categorie: 'Héliciculture',
      espece: 'escargots',
    );

    var relu = (await repository.chargerCatalogue()).firstWhere(
      (p) => p.id == produit.id,
    );
    expect(relu.espece, 'escargots');

    // Rattache autrement, puis detache : « aucune » reste possible.
    await catalogue.enregistrer(
      id: produit.id,
      nom: produit.nom,
      categorie: produit.categorie,
      prix: produit.prix,
      unite: produit.unite,
      stock: produit.stock,
      seuil: produit.seuil,
      espece: null,
    );
    relu = (await repository.chargerCatalogue()).firstWhere(
      (p) => p.id == produit.id,
    );
    expect(relu.espece, isNull);
  });

  test('un produit sans filière reste sans filière', () async {
    final produit = await creer(nom: 'Cahier', categorie: 'Commerce Annexe');
    expect(produit.espece, isNull);
  });

  group('La vente suit la filière, comme pour les goliaths', () {
    LignePanier ligne(ProduitVendable p, double qte) => LignePanier(
      produitId: p.id,
      nom: p.nom,
      montantGlobal: p.prix * qte,
      quantite: qte,
      stockDisponible: p.stock,
      prixIndicatif: p.prix,
      prixIndicatifMax: p.prixMax,
      espece: p.espece,
      unite: p.unite,
    );

    for (final cas in const [
      ('escargots', 'Héliciculture', 'Escargot marchand (sujet)', 1500.0),
      ('ovins', 'Élevage ovin', 'Ovin d\'embouche (tête)', 350000.0),
    ]) {
      test(
        '${cas.$1} : stock décrémenté et compteur de la fiche incrémenté',
        () async {
          final produit = await creer(
            nom: cas.$3,
            categorie: cas.$2,
            espece: cas.$1,
            prix: cas.$4,
            stock: 5,
          );

          await repository.enregistrerVente(
            client: 'Client Comptant',
            mode: ModeReglement.especes,
            statut: StatutVente.payee,
            montantPaye: cas.$4 * 2,
            panier: [ligne(produit, 2)],
          );

          final relu = (await repository.chargerCatalogue()).firstWhere(
            (p) => p.id == produit.id,
          );
          expect(relu.stock, 3); // 5 − 2

          final compteurs = await db.select(db.ficheVentesJour).get();
          expect(compteurs, hasLength(1));
          expect(compteurs.single.espece, cas.$1);
          expect(compteurs.single.qte, 2);
        },
      );
    }
  });
}
