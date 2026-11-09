import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/livraison.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/commercial/presentation/viewmodels/ventes_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';

/// Le point de vente est un POS **à montant négocié**, pas un POS de
/// supermarché — `ventes.html`, modale « Vente à la Pièce ».
///
/// Sa note est explicite : « saisissez directement le montant total convenu —
/// jamais un prix unitaire multiplié automatiquement. Le prix indicatif n'est
/// qu'une fourchette de référence. » Ces tests verrouillent cette règle.
void main() {
  late AppDatabase db;
  late VentesViewModel vm;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    vm = VentesViewModel(VentesRepositoryDrift(db, EventBus()), db);
    await vm.charger();
  });

  tearDown(() async => db.close());

  ProduitVendable produit(String nom) =>
      vm.produitsFiltres.firstWhere((p) => p.nom == nom);

  group('Le montant est saisi, jamais calculé', () {
    test('le total de la ligne est le montant convenu, même s\'il diffère du '
        'prix du catalogue', () {
      final goliath = produit('Goliath mature');

      // La Gerante negocie 2 sujets a 11 000 F au total, la ou le catalogue
      // afficherait 2 x 6 000 = 12 000.
      expect(
        vm.ajouterAuPanier(goliath, quantite: 2, montantGlobal: 11000),
        isNull,
      );

      expect(vm.panier.single.quantite, 2);
      expect(vm.panier.single.montantGlobal, 11000);
      expect(
        vm.panier.single.total,
        11000,
        reason:
            'Le total de la ligne EST le montant saisi. Multiplier le prix '
            'du catalogue facturerait 12 000, un montant que personne n\'a '
            'convenu.',
      );
      expect(vm.totalPanier, 11000);
    });

    test('le prix unitaire est déduit du montant, pas l\'inverse', () {
      final goliath = produit('Goliath mature');
      vm.ajouterAuPanier(goliath, quantite: 2, montantGlobal: 11000);

      expect(vm.panier.single.prixUnitaire, 5500);
      expect(
        vm.panier.single.prixIndicatif,
        goliath.prix,
        reason: 'La fourchette du catalogue reste consultable, sans effet.',
      );
    });

    test(
      'un même produit peut occuper deux lignes à des montants différents',
      () {
        final goliath = produit('Goliath mature');

        vm.ajouterAuPanier(goliath, quantite: 1, montantGlobal: 6000);
        vm.ajouterAuPanier(goliath, quantite: 1, montantGlobal: 5000);

        expect(
          vm.panier,
          hasLength(2),
          reason:
              'Le prototype empile les lignes (`cart.push`) : deux clients ne '
              'négocient pas au même prix.',
        );
        expect(vm.totalPanier, 11000);
      },
    );

    test('une quantité ou un montant nul est refusé', () {
      final goliath = produit('Goliath mature');

      expect(
        vm.ajouterAuPanier(goliath, quantite: 0, montantGlobal: 6000),
        isNotNull,
      );
      expect(
        vm.ajouterAuPanier(goliath, quantite: 1, montantGlobal: 0),
        isNotNull,
      );
      expect(vm.panier, isEmpty);
    });
  });

  group('Le stock reste une borne', () {
    test('la somme des quantités du panier ne peut pas dépasser le stock', () {
      final goliath = produit('Goliath mature'); // 31 en stock

      expect(
        vm.ajouterAuPanier(goliath, quantite: 30, montantGlobal: 180000),
        isNull,
      );
      final erreur = vm.ajouterAuPanier(
        goliath,
        quantite: 2,
        montantGlobal: 12000,
      );

      expect(erreur, isNotNull);
      expect(erreur, contains('Stock insuffisant'));
      expect(vm.panier, hasLength(1));
    });

    test('un produit épuisé est refusé', () async {
      final goliath = produit('Goliath mature');
      await db.customStatement(
        'UPDATE produits_vendables SET stock = 0 WHERE id = ?',
        [goliath.id],
      );
      await vm.charger();

      final erreur = vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      expect(erreur, contains('rupture de stock'));
    });
  });

  group('Modification d\'une ligne — `editWeightLine()`', () {
    test('la quantité et le montant se modifient indépendamment', () {
      final goliath = produit('Goliath mature');
      vm.ajouterAuPanier(goliath, quantite: 1, montantGlobal: 6000);

      expect(vm.modifierLigne(0, quantite: 3, montantGlobal: 16000), isNull);
      expect(vm.panier.single.quantite, 3);
      expect(vm.panier.single.montantGlobal, 16000);
      expect(vm.totalPanier, 16000);
    });

    test(
      'la modification respecte le stock, en tenant compte des autres lignes',
      () {
        final goliath = produit('Goliath mature'); // 31
        vm.ajouterAuPanier(goliath, quantite: 20, montantGlobal: 120000);
        vm.ajouterAuPanier(goliath, quantite: 5, montantGlobal: 30000);

        // Porter la 2e ligne a 15 ferait 35 > 31.
        expect(
          vm.modifierLigne(1, quantite: 15, montantGlobal: 90000),
          isNotNull,
        );
        expect(vm.panier[1].quantite, 5);

        // 11 passe : 20 + 11 = 31.
        expect(vm.modifierLigne(1, quantite: 11, montantGlobal: 66000), isNull);
      },
    );

    test('retirer une ligne se fait par index, pas par produit', () {
      final goliath = produit('Goliath mature');
      vm.ajouterAuPanier(goliath, quantite: 1, montantGlobal: 6000);
      vm.ajouterAuPanier(goliath, quantite: 1, montantGlobal: 5000);

      vm.retirerLigne(0);

      expect(
        vm.panier,
        hasLength(1),
        reason:
            'Retirer par `produitId` viderait les deux lignes du même produit.',
      );
      expect(vm.panier.single.montantGlobal, 5000);
    });
  });

  group('La vente enregistrée porte le montant négocié', () {
    test('le total en base est celui saisi, pas celui du catalogue', () async {
      final goliath = produit('Goliath mature');
      vm.ajouterAuPanier(goliath, quantite: 2, montantGlobal: 11000);
      vm.montantRecu = 11000;

      final resultat = await vm.encaisser();
      expect(resultat, isA<Object>());
      await vm.charger();

      final vente = vm.ventes.first;
      expect(vente.total, 11000);
      expect(vente.lignes.single.quantite, 2);
      expect(
        vente.lignes.single.prixUnitaire,
        5500,
        reason:
            'La ligne de vente stocke un prix unitaire déduit — 11 000 / 2 — '
            'pour que l\'historique et l\'écriture comptable restent exacts.',
      );
      expect(vente.lignes.single.total, 11000);
    });
  });

  group('Livraison — la modale du prototype n\'enregistre rien', () {
    test('sans livraison, le total est celui des lignes', () {
      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      expect(vm.livraisonConcernee, isFalse);
      expect(vm.totalPanier, 6000);
      expect(vm.totalLignes, 6000);
    });

    test('seule une livraison FACTURÉE séparément s\'ajoute au total', () {
      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );

      for (final mode in [
        ModeLivraison.gratuite,
        ModeLivraison.client,
        ModeLivraison.incluse,
      ]) {
        expect(vm.definirLivraison(Livraison(mode: mode)), isNull);
        expect(
          vm.totalPanier,
          6000,
          reason: '${mode.libelle} n\'ajoute rien au total.',
        );
      }

      expect(
        vm.definirLivraison(
          const Livraison(mode: ModeLivraison.facturee, frais: 1500),
        ),
        isNull,
      );
      expect(vm.totalLignes, 6000);
      expect(vm.totalPanier, 7500);
    });

    test('une livraison facturée sans montant est refusée', () {
      final erreur = vm.definirLivraison(
        const Livraison(mode: ModeLivraison.facturee),
      );
      expect(erreur, isNotNull);
      expect(vm.livraisonConcernee, isFalse);
    });

    test('la livraison est réellement persistée sur la vente', () async {
      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      vm.definirLivraison(
        const Livraison(
          mode: ModeLivraison.facturee,
          frais: 1500,
          adresse: 'Quartier Kantaborifa, Natitingou',
          contact: '+229 97 00 11 22',
        ),
      );
      vm.montantRecu = 7500;

      await vm.encaisser();

      final ligne = await db
          .customSelect(
            'SELECT total, livraison_mode, livraison_frais, '
            'livraison_adresse, livraison_contact FROM ventes LIMIT 1',
          )
          .getSingle();

      expect(ligne.read<double>('total'), 7500);
      expect(ligne.read<String?>('livraison_mode'), 'facturee');
      expect(ligne.read<double?>('livraison_frais'), 1500);
      expect(
        ligne.read<String?>('livraison_adresse'),
        'Quartier Kantaborifa, Natitingou',
      );
      expect(ligne.read<String?>('livraison_contact'), '+229 97 00 11 22');
    });

    test('vider le panier retire aussi la livraison', () {
      vm.definirLivraison(const Livraison(mode: ModeLivraison.gratuite));
      expect(vm.livraisonConcernee, isTrue);
      vm.viderPanier();
      expect(vm.livraisonConcernee, isFalse);
    });
  });

  group('Mode et condition sont saisis séparément (arbitrage Gérante)', () {
    test('une avance en Mobile Money conserve les deux informations', () async {
      final goliath = produit('Goliath mature');
      vm.ajouterAuPanier(goliath, quantite: 2, montantGlobal: 12000);
      vm.mode = ModeReglement.mobileMoney;
      vm.condition = ConditionPaiement.avance;
      vm.montantRecu = 5000;

      expect(vm.validerAvantEncaissement(), isNull);
      await vm.encaisser();
      await vm.charger();

      final vente = vm.ventes.first;
      expect(
        vente.mode,
        ModeReglement.mobileMoney,
        reason:
            'Avant l\'arbitrage, `mode` valait « Avance » et l\'instrument '
            'reel etait perdu — impossible de rapprocher la caisse.',
      );
      expect(vente.statut, StatutVente.avance);
      expect(vente.paye, 5000);
      expect(vente.resteDu, 7000);
    });

    test('une avance sans montant reçu est refusée', () {
      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      vm.condition = ConditionPaiement.avance;

      expect(vm.validerAvantEncaissement(), isNotNull);
    });

    test('une avance qui solde la vente renvoie vers « Comptant »', () {
      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      vm.condition = ConditionPaiement.avance;
      vm.montantRecu = 6000;

      expect(
        vm.validerAvantEncaissement(),
        isNotNull,
        reason:
            'Elle apparaitrait sinon en creance dans Clients avec un reste '
            'du nul.',
      );
    });

    test('revenir en comptant remet le montant reçu à zéro', () {
      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      vm.condition = ConditionPaiement.avance;
      vm.montantRecu = 2000;

      vm.condition = ConditionPaiement.comptant;

      expect(
        vm.montantRecu,
        0,
        reason:
            'Un reliquat de 2 000 bloquerait la validation sans que la '
            'caissiere comprenne pourquoi.',
      );
    });

    test('vider le panier remet les deux sélecteurs par défaut', () {
      vm.ajouterAuPanier(
        produit('Goliath mature'),
        quantite: 1,
        montantGlobal: 6000,
      );
      vm.mode = ModeReglement.mobileMoney;
      vm.condition = ConditionPaiement.avance;

      vm.viderPanier();

      expect(vm.mode, ModeReglement.especes);
      expect(vm.condition, ConditionPaiement.comptant);
    });
  });
}
