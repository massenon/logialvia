import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/commercial/presentation/viewmodels/catalogue_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/rapports/data/repositories/rapports_repository_drift.dart';
import 'package:logialvia_app/rapports/presentation/viewmodels/rapports_view_model.dart';

/// Coût de revient — migration v18.
///
/// ⚠️ Le prototype confond coût et prix : sa colonne « CMUP » du Rapport de
/// Stocks reprend **exactement** le prix du catalogue (`price:6000` /
/// `cmup:6000` pour le Goliath mature). Valoriser un stock à son prix de vente
/// le surévalue et anticipe une marge non réalisée.
void main() {
  late AppDatabase db;
  late CatalogueViewModel catalogue;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    catalogue = CatalogueViewModel(VentesRepositoryDrift(db, EventBus()));
    await catalogue.charger();
  });

  tearDown(() async {
    catalogue.dispose();
    await db.close();
  });

  ProduitVendable goliath() =>
      catalogue.produits.firstWhere((p) => p.nom == 'Goliath mature');

  Future<Resultat<ProduitVendable>> definirCout(
    ProduitVendable p,
    double? cout,
  ) async {
    final resultat = await catalogue.enregistrer(
      id: p.id,
      nom: p.nom,
      categorie: p.categorie,
      prix: p.prix,
      prixMax: p.prixMax,
      unite: p.unite,
      stock: p.stock,
      seuil: p.seuil,
      espece: p.espece,
      coutRevient: cout,
    );
    await catalogue.charger();
    return resultat;
  }

  group('Le coût de revient n\'est pas le prix de vente', () {
    test('les deux valorisations coexistent et diffèrent', () async {
      final p = goliath();
      await definirCout(p, 3500);

      final apres = goliath();
      expect(apres.coutRevient, 3500);
      expect(apres.valeurStock, apres.stock * apres.prix);
      expect(apres.valeurStockAuCout, apres.stock * 3500);
      expect(
        apres.valeurStockAuCout,
        lessThan(apres.valeurStock),
        reason:
            'Un goliath encore dans l\'enclos a coute 3 500 F, il n\'a pas '
            'rapporte les 6 000 F de son prix.',
      );
    });

    test('la marge unitaire se déduit du couple prix / coût', () async {
      final p = goliath();
      await definirCout(p, 3500);
      expect(goliath().margeUnitaire, goliath().prix - 3500);
    });

    test('sans coût, il n\'y a ni valorisation ni marge', () {
      final p = goliath();
      expect(p.coutRevient, isNull);
      expect(p.valeurStockAuCout, isNull);
      expect(p.margeUnitaire, isNull);
      expect(
        p.valeurStock,
        isNotNull,
        reason: 'La valeur au prix de vente, elle, reste calculable.',
      );
    });
  });

  group('Contrôles de saisie', () {
    test('un coût négatif est refusé', () async {
      expect(await definirCout(goliath(), -100), isA<Echec<ProduitVendable>>());
    });

    test('un coût supérieur au tarif est refusé', () async {
      final p = goliath();
      final resultat = await definirCout(p, p.prix + 1);

      expect(
        resultat,
        isA<Echec<ProduitVendable>>(),
        reason:
            'Chaque vente serait a perte. Si c\'est vrai, c\'est le prix qu\'il '
            'faut corriger, pas le cout qu\'il faut accepter en silence.',
      );
      expect(goliath().coutRevient, isNull);
    });

    test('un coût égal au tarif passe — marge nulle, pas négative', () async {
      final p = goliath();
      expect(await definirCout(p, p.prix), isA<Succes<ProduitVendable>>());
      expect(goliath().margeUnitaire, 0);
    });
  });

  group(
    'Rapport de Stocks — le stock n\'est plus valorisé au prix de vente',
    () {
      late RapportsViewModel rapports;

      Future<void> rechargerRapports() async {
        rapports = RapportsViewModel(RapportsRepositoryDrift(db));
        await rapports.charger();
        addTearDown(rapports.dispose);
      }

      test('un produit fini sans coût n\'est pas valorisé', () async {
        await rechargerRapports();

        final ligne = rapports.donnees.stocks.firstWhere(
          (l) => l.designation == 'Goliath mature',
        );
        expect(ligne.cmup, isNull);
        expect(ligne.valeurTotale, isNull);
        expect(
          ligne.nonValorise,
          isTrue,
          reason:
              'Le prototype y mettrait 6 000 F l\'unite — le prix du catalogue.',
        );
      });

      test('le total exclut les lignes non valorisées et le dit', () async {
        await rechargerRapports();

        final nonValorises = rapports.articlesNonValorises;
        expect(nonValorises, greaterThan(0));

        final sommeValorisee = rapports.donnees.stocks
            .where((l) => !l.nonValorise)
            .fold<double>(0, (s, l) => s + l.valeurTotale!);
        expect(rapports.valeurTotaleStock, closeTo(sommeValorisee, 0.01));
      });

      test('renseigner le coût fait entrer la ligne dans le total', () async {
        await rechargerRapports();
        final avant = rapports.valeurTotaleStock;
        final avantNonValorises = rapports.articlesNonValorises;

        final p = goliath();
        await definirCout(p, 3500);
        await rechargerRapports();

        final ligne = rapports.donnees.stocks.firstWhere(
          (l) => l.designation == 'Goliath mature',
        );
        expect(ligne.cmup, 3500);
        expect(ligne.valeurTotale, p.stock * 3500);
        expect(
          rapports.valeurTotaleStock,
          closeTo(avant + p.stock * 3500, 0.01),
        );
        expect(rapports.articlesNonValorises, avantNonValorises - 1);
      });

      test('les intrants restent valorisés à leur PMP', () async {
        await rechargerRapports();

        final mais = rapports.donnees.stocks.firstWhere(
          (l) => l.designation == 'Maïs',
        );
        expect(
          mais.cmup,
          isNotNull,
          reason:
              'Le PMP des intrants est un vrai cout d\'achat, calcule a chaque '
              'reception : lui n\'a jamais ete un prix de vente.',
        );
        expect(mais.nonValorise, isFalse);
      });
    },
  );

  group('Migration v18', () {
    test('les produits existants n\'ont pas de coût inventé', () {
      for (final p in catalogue.produits) {
        expect(
          p.coutRevient,
          isNull,
          reason:
              '${p.nom} : reconduire le prix de vente comme cout perpetuerait '
              'la surevaluation.',
        );
      }
      expect(catalogue.produitsSansCout, hasLength(catalogue.produits.length));
      expect(catalogue.valeurCatalogueAuCout, 0);
    });

    test('la v18 est bien franchie sur une base neuve', () {
      // `schemaVersion` a continue de monter (v19 : axe analytique).
      expect(db.schemaVersion, greaterThanOrEqualTo(18));
    });
  });
}
