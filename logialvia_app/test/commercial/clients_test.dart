import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/commercial/data/repositories/clients_repository_drift.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/client.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/commercial/presentation/viewmodels/catalogue_view_model.dart';
import 'package:logialvia_app/commercial/presentation/viewmodels/clients_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';

void main() {
  late AppDatabase db;
  late EventBus bus;
  late VentesRepositoryDrift ventes;
  late ClientsRepositoryDrift clientsRepo;
  late ClientsViewModel vm;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    bus = EventBus();
    ventes = VentesRepositoryDrift(db, bus);
    clientsRepo = ClientsRepositoryDrift(db);
    vm = ClientsViewModel(clientsRepo, ventes);
    await vm.charger();
  });

  tearDown(() async {
    vm.dispose();
    bus.dispose();
    await db.close();
  });

  Future<String> venteAvance({
    required String client,
    required double total,
    required double paye,
    DateTime? date,
  }) async {
    final catalogue = await ventes.chargerCatalogue();
    final goliath = catalogue.firstWhere((p) => p.nom == 'Goliath mature');
    final resultat = await ventes.enregistrerVente(
      client: client,
      // Depuis l'arbitrage : le mode dit l'instrument, le statut la condition.
      mode: ModeReglement.especes,
      statut: StatutVente.avance,
      montantPaye: paye,
      panier: [
        LignePanier(
          produitId: goliath.id,
          nom: goliath.nom,
          montantGlobal: total,
          quantite: 1,
          stockDisponible: goliath.stock,
          prixIndicatif: goliath.prix,
          espece: goliath.espece,
        ),
      ],
    );
    return resultat.vente.reference;
  }

  group('Création de client', () {
    test('persiste nom, téléphone et date de naissance', () async {
      final resultat = await vm.creerClient(
        nom: 'DOSSOU Félicité',
        telephone: '+229 97 11 22 33',
        dateNaissance: DateTime(1988, 5, 12),
      );

      expect(resultat, isA<Succes<Client>>());
      final relus = await clientsRepo.chargerClients();
      expect(relus, hasLength(1));
      expect(relus.single.nom, 'DOSSOU Félicité');
      expect(relus.single.telephone, '+229 97 11 22 33');
      expect(relus.single.dateNaissance, DateTime(1988, 5, 12));
    });

    test('refuse un nom vide', () async {
      expect(await vm.creerClient(nom: '  '), isA<Echec<Client>>());
    });

    test(
      'refuse un homonyme — le nom sert de clé de rapprochement avec VENTES',
      () async {
        await vm.creerClient(nom: 'DOSSOU Félicité');
        expect(
          await vm.creerClient(nom: 'dossou félicité'),
          isA<Echec<Client>>(),
        );
        expect(vm.clients, hasLength(1));
      },
    );
  });

  group('Agrégats recalculés depuis VENTES, jamais depuis un cumul stocké', () {
    setUp(() async {
      await vm.creerClient(nom: 'AGOSSOU Prudence');
    });

    test('total achats et solde suivent les ventes réelles', () async {
      await venteAvance(client: 'AGOSSOU Prudence', total: 12000, paye: 3500);
      await vm.charger();

      final client = vm.clients.single;
      expect(client.totalAchats, 12000);
      expect(client.soldeActuel, 8500);
      expect(client.aUneCreance, isTrue);
    });

    test('une vente annulée sort des agrégats', () async {
      final ref = await venteAvance(
        client: 'AGOSSOU Prudence',
        total: 12000,
        paye: 3500,
      );
      await ventes.annulerVente(reference: ref, motif: 'Erreur de saisie');
      await vm.charger();

      final client = vm.clients.single;
      expect(client.totalAchats, 0);
      expect(client.soldeActuel, 0);
    });

    test('un paiement complet solde la créance', () async {
      final ref = await venteAvance(
        client: 'AGOSSOU Prudence',
        total: 12000,
        paye: 3500,
      );

      final resultat = await vm.enregistrerPaiement(
        referenceVente: ref,
        montant: 8500,
      );

      expect(resultat, isA<Succes<void>>());
      expect(vm.creances, isEmpty); // la vente est passée en « Payée »
      expect(vm.clients.single.soldeActuel, 0);
      expect(vm.clients.single.totalAchats, 12000); // l'achat reste compté
    });

    test('refuse un montant nul ou négatif', () async {
      await venteAvance(client: 'AGOSSOU Prudence', total: 12000, paye: 0);
      await vm.charger();
      expect(
        await vm.enregistrerPaiement(
          referenceVente: vm.creances.single.referenceVente,
          montant: 0,
        ),
        isA<Echec<void>>(),
      );
    });
  });

  group('Les 4 KPI réels de l\'écran', () {
    test('tous à zéro sur une base vierge', () {
      expect(vm.clientsEnregistres, 0);
      expect(vm.soldeTotalRestantDu, 0);
      expect(vm.soldesAnciens, 0);
      expect(vm.evenementsCrm, 0);
    });

    test('« Solde Total Restant Dû » somme toutes les créances', () async {
      await vm.creerClient(nom: 'Client A');
      await vm.creerClient(nom: 'Client B');
      await venteAvance(client: 'Client A', total: 10000, paye: 2000);
      await venteAvance(client: 'Client B', total: 5000, paye: 1000);
      await vm.charger();

      expect(vm.soldeTotalRestantDu, 12000); // 8000 + 4000
    });

    test(
      '« Soldes Anciens » ne compte que les créances de plus de 10 j',
      () async {
        await vm.creerClient(nom: 'Client A');
        await venteAvance(client: 'Client A', total: 10000, paye: 0);
        await vm.charger();

        // Vente du jour : pas encore ancienne.
        expect(vm.soldesAnciens, 0);
        expect(vm.creances.single.ancienneteJours(DateTime.now()), 0);
        expect(
          vm.creances.single.estAncienne(
            DateTime.now().add(const Duration(days: 11)),
          ),
          isTrue,
        );
      },
    );
  });

  group('Événements CRM — dérivés de la date de naissance', () {
    test('un anniversaire dans 3 jours apparaît', () async {
      final dans3Jours = DateTime.now().add(const Duration(days: 3));
      await vm.creerClient(
        nom: 'DOSSOU Félicité',
        dateNaissance: DateTime(1988, dans3Jours.month, dans3Jours.day),
      );

      expect(vm.evenementsCrm, 1);
      expect(vm.evenements.single.type, EvenementCrm.anniversaire);
      expect(vm.evenements.single.joursRestants, 3);
    });

    test(
      'un anniversaire dans 30 jours n\'apparaît pas (fenêtre 7 j)',
      () async {
        final dans30Jours = DateTime.now().add(const Duration(days: 30));
        await vm.creerClient(
          nom: 'Client Lointain',
          dateNaissance: DateTime(1988, dans30Jours.month, dans30Jours.day),
        );

        expect(vm.evenementsCrm, 0);
      },
    );

    test(
      'un client sans date de naissance ne génère aucun événement',
      () async {
        await vm.creerClient(nom: 'Sans Date');
        expect(vm.evenementsCrm, 0);
      },
    );

    test(
      '« Marquer contacté » horodate réellement le dernier contact',
      () async {
        final dans2Jours = DateTime.now().add(const Duration(days: 2));
        await vm.creerClient(
          nom: 'DOSSOU Félicité',
          dateNaissance: DateTime(1988, dans2Jours.month, dans2Jours.day),
        );
        expect(vm.clients.single.dernierContact, isNull);

        await vm.marquerContact(vm.clients.single);

        expect(vm.clients.single.dernierContact, isNotNull);
        expect(vm.evenements.single.dernierContact, isNotNull);
      },
    );
  });

  group('Catalogue — SKU et validations', () {
    late CatalogueViewModel catalogue;

    setUp(() async {
      catalogue = CatalogueViewModel(ventes);
      await catalogue.charger();
    });

    tearDown(() => catalogue.dispose());

    test('les 14 produits seedés ont un SKU séquentiel', () {
      expect(catalogue.produitsActifs, 14);
      expect(catalogue.produits.first.sku, isNotNull);
      final skus = catalogue.produits.map((p) => p.sku).toSet();
      expect(skus, hasLength(14)); // tous distincts
    });

    test('un nouveau produit reçoit le SKU suivant', () async {
      final resultat = await catalogue.enregistrer(
        nom: 'Miel local (pot)',
        categorie: 'Commerce Annexe',
        prix: 2500,
        unite: 'pot(s)',
        stock: 20,
        seuil: 5,
      );

      expect(resultat, isA<Succes<ProduitVendable>>());
      final cree = catalogue.produits.firstWhere(
        (p) => p.nom == 'Miel local (pot)',
      );
      expect(cree.sku, 'PRD-015');
    });

    test('le SKU d\'un produit modifié n\'est jamais réécrit', () async {
      final existant = catalogue.produits.first;
      final skuOrigine = existant.sku;

      await catalogue.enregistrer(
        id: existant.id,
        nom: existant.nom,
        categorie: existant.categorie,
        prix: existant.prix + 100,
        unite: existant.unite,
        stock: existant.stock,
        seuil: existant.seuil,
      );

      final modifie = catalogue.produits.firstWhere((p) => p.id == existant.id);
      expect(modifie.sku, skuOrigine);
      expect(modifie.prix, existant.prix + 100);
    });

    test('refuse un prix haut inférieur au prix bas', () async {
      expect(
        await catalogue.enregistrer(
          nom: 'Test',
          categorie: 'Avicole',
          prix: 5000,
          prixMax: 3000,
          unite: 'u',
          stock: 1,
          seuil: 0,
        ),
        isA<Echec<ProduitVendable>>(),
      );
    });

    test('refuse un stock ou un seuil négatif', () async {
      expect(
        await catalogue.enregistrer(
          nom: 'Test',
          categorie: 'Avicole',
          prix: 5000,
          unite: 'u',
          stock: -1,
          seuil: 0,
        ),
        isA<Echec<ProduitVendable>>(),
      );
    });

    test('le 2ᵉ tableau ne liste que les produits sous seuil', () async {
      expect(catalogue.produitsSousSeuil, isEmpty);

      // On vide le stock d'un produit.
      final cible = catalogue.produits.first;
      await catalogue.enregistrer(
        id: cible.id,
        nom: cible.nom,
        categorie: cible.categorie,
        prix: cible.prix,
        unite: cible.unite,
        stock: 0,
        seuil: cible.seuil,
      );

      expect(catalogue.produitsSousSeuil, hasLength(1));
      expect(catalogue.produitsCritiques, 1);
    });

    test(
      'un produit déjà vendu ne peut pas être supprimé — l\'historique prime',
      () async {
        final catalogueProduits = await ventes.chargerCatalogue();
        final goliath = catalogueProduits.firstWhere(
          (p) => p.nom == 'Goliath mature',
        );
        await ventes.enregistrerVente(
          client: 'Client Comptant',
          mode: ModeReglement.especes,
          statut: StatutVente.payee,
          montantPaye: 6000,
          panier: [
            LignePanier(
              produitId: goliath.id,
              nom: goliath.nom,
              montantGlobal: goliath.prix,
              quantite: 1,
              stockDisponible: goliath.stock,
              prixIndicatif: goliath.prix,
            ),
          ],
        );
        await catalogue.charger();

        final resultat = await catalogue.supprimer(
          catalogue.produits.firstWhere((p) => p.id == goliath.id),
        );

        expect(resultat, isA<Echec<void>>());
        expect(catalogue.produitsActifs, 14); // toujours là
      },
    );
  });
}
