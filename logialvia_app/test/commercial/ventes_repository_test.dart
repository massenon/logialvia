import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';

/// Master Prompt §2.3 désigne nommément l'échec à ne pas reproduire :
/// `validateSale()` générait une référence aléatoire **sans rien persister**.
/// Chaque test ci-dessous vérifie donc l'état de la BASE après l'opération,
/// jamais la valeur retournée par la méthode.
void main() {
  late AppDatabase db;
  late EventBus bus;
  late VentesRepositoryDrift repository;
  late List<ProduitVendable> catalogue;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    bus = EventBus();
    repository = VentesRepositoryDrift(db, bus);
    catalogue = await repository.chargerCatalogue();
  });

  tearDown(() async {
    bus.dispose();
    await db.close();
  });

  ProduitVendable produit(String nom) =>
      catalogue.firstWhere((p) => p.nom == nom);

  /// Vente a la piece : le montant global est le total convenu. Par defaut le
  /// test reprend `prix x quantite`, mais le montant reste **saisi**, pas
  /// calcule par le panier — voir [LignePanier].
  LignePanier ligne(ProduitVendable p, double qte, {double? montant}) =>
      LignePanier(
        produitId: p.id,
        nom: p.nom,
        montantGlobal: montant ?? p.prix * qte,
        quantite: qte,
        stockDisponible: p.stock,
        prixIndicatif: p.prix,
        prixIndicatifMax: p.prixMax,
        espece: p.espece,
        unite: p.unite,
      );

  group('Le catalogue seedé est bien le point de départ', () {
    test('14 produits, Goliath mature à 31 en stock', () {
      expect(catalogue, hasLength(14));
      expect(produit('Goliath mature').stock, 31);
      expect(produit('Goliath mature').espece, 'goliaths');
    });
  });

  group('Encaissement — persistance réelle (BR-VTE-002)', () {
    test('la vente et ses lignes sont réellement écrites en base', () async {
      final goliath = produit('Goliath mature');

      final resultat = await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 12000,
        panier: [ligne(goliath, 2)],
      );

      expect(resultat.vente.reference, 'V-${DateTime.now().year}-001');

      // Relecture depuis la base — le seul critere qui compte.
      final ventes = await db.select(db.ventes).get();
      expect(ventes, hasLength(1));
      expect(ventes.single.total, 12000);
      expect(ventes.single.client, 'Client Comptant');

      final lignes = await db.select(db.lignesVente).get();
      expect(lignes, hasLength(1));
      expect(lignes.single.qte, 2);
      expect(lignes.single.name, 'Goliath mature');
    });

    test('le stock du produit est réellement décrémenté', () async {
      final goliath = produit('Goliath mature');

      await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 12000,
        panier: [ligne(goliath, 2)],
      );

      final relu = (await repository.chargerCatalogue()).firstWhere(
        (p) => p.id == goliath.id,
      );
      expect(relu.stock, 29); // 31 − 2
    });

    test('le compteur de ventes du jour de la fiche d\'élevage est incrémenté '
        '— c\'est la synchronisation POS → Fiche de Doc C1 §1', () async {
      await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 12000,
        panier: [ligne(produit('Goliath mature'), 2)],
      );

      final compteurs = await db.select(db.ficheVentesJour).get();
      expect(compteurs, hasLength(1));
      expect(compteurs.single.espece, 'goliaths');
      expect(compteurs.single.qte, 2);
    });

    test('un produit sans espèce ne touche aucune fiche d\'élevage', () async {
      await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 2000,
        panier: [ligne(produit('Sac d\'écolier'), 1)],
      );

      expect(await db.select(db.ficheVentesJour).get(), isEmpty);
    });

    test('deux ventes le même jour cumulent le compteur de la fiche', () async {
      final goliath = produit('Goliath mature');
      for (var i = 0; i < 2; i++) {
        await repository.enregistrerVente(
          client: 'Client Comptant',
          mode: ModeReglement.especes,
          statut: StatutVente.payee,
          montantPaye: 6000,
          panier: [ligne(goliath, 1)],
        );
      }

      final compteurs = await db.select(db.ficheVentesJour).get();
      expect(compteurs, hasLength(1)); // UNIQUE(espece, date) respecté
      expect(compteurs.single.qte, 2);
    });

    test('un panier multi-lignes écrit tout, et rien de plus', () async {
      await repository.enregistrerVente(
        client: 'DOSSOU Félicité',
        mode: ModeReglement.mobileMoney,
        statut: StatutVente.payee,
        montantPaye: 8500,
        panier: [
          ligne(produit('Goliath mature'), 1),
          ligne(produit('Sac d\'écolier'), 1),
          ligne(produit('Pintade mature'), 1),
        ],
      );

      expect(await db.select(db.lignesVente).get(), hasLength(3));
      // 2 especes distinctes -> 2 compteurs de fiche.
      expect(await db.select(db.ficheVentesJour).get(), hasLength(2));
    });

    test('les références s\'incrémentent sans collision', () async {
      final goliath = produit('Goliath mature');
      for (var i = 0; i < 3; i++) {
        await repository.enregistrerVente(
          client: 'Client Comptant',
          mode: ModeReglement.especes,
          statut: StatutVente.payee,
          montantPaye: 6000,
          panier: [ligne(goliath, 1)],
        );
      }

      final annee = DateTime.now().year;
      final refs = (await db.select(db.ventes).get()).map((v) => v.ref).toSet();
      expect(refs, {'V-$annee-001', 'V-$annee-002', 'V-$annee-003'});
    });

    test('un événement de domaine est publié après la transaction', () async {
      final evenements = <VenteValideeEvent>[];
      final abonnement = bus.on<VenteValideeEvent>().listen(evenements.add);

      await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 6000,
        panier: [ligne(produit('Goliath mature'), 1)],
      );
      await Future<void>.delayed(Duration.zero);

      expect(evenements, hasLength(1));
      expect(evenements.single.lignes.single.espece, 'goliaths');
      await abonnement.cancel();
    });
  });

  group('Atomicité — un échec ne doit rien laisser derrière lui', () {
    test(
      'un produit inexistant fait échouer TOUTE la vente — rien n\'est écrit',
      () async {
        final goliath = produit('Goliath mature');

        // La cle etrangere `LIGNES_VENTE.produitId` refuse la ligne fantome
        // (PRAGMA foreign_keys = ON). La transaction entiere est annulee : la
        // premiere ligne, deja inseree, et le decrement de stock deja applique
        // sont annules avec elle. C'est exactement l'atomicite exigee par
        // BR-VTE-002.
        await expectLater(
          repository.enregistrerVente(
            client: 'Client Comptant',
            mode: ModeReglement.especes,
            statut: StatutVente.payee,
            montantPaye: 6000,
            panier: [
              ligne(goliath, 1),
              const LignePanier(
                produitId: 'aaaaaaaa-0000-4000-8000-000000000000',
                nom: 'Produit fantôme',
                montantGlobal: 100,
                quantite: 1,
                stockDisponible: 10,
                prixIndicatif: 100,
              ),
            ],
          ),
          throwsA(anything),
        );

        // Aucune vente, aucune ligne, aucun compteur de fiche…
        expect(await db.select(db.ventes).get(), isEmpty);
        expect(await db.select(db.lignesVente).get(), isEmpty);
        expect(await db.select(db.ficheVentesJour).get(), isEmpty);

        // …et surtout : le stock du produit valide est INTACT. Sans
        // transaction, il aurait ete decremente a 30 pour une vente qui
        // n'existe pas — l'incoherence silencieuse type de ce projet.
        final relu = (await repository.chargerCatalogue()).firstWhere(
          (p) => p.id == goliath.id,
        );
        expect(relu.stock, 31);
      },
    );

    test('le stock ne descend jamais sous zéro', () async {
      final oeufs = produit('Œufs de table (plateau)'); // stock 12

      await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 100000,
        panier: [ligne(oeufs, 999)],
      );

      final relu = (await repository.chargerCatalogue()).firstWhere(
        (p) => p.id == oeufs.id,
      );
      expect(relu.stock, 0);
    });
  });

  group('Annulation — FRS-VTE-05', () {
    late String reference;

    setUp(() async {
      final resultat = await repository.enregistrerVente(
        client: 'AGOSSOU Prudence',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 12000,
        panier: [ligne(produit('Goliath mature'), 2)],
      );
      reference = resultat.vente.reference;
    });

    test('restitue le stock', () async {
      expect(
        (await repository.chargerCatalogue())
            .firstWhere((p) => p.nom == 'Goliath mature')
            .stock,
        29,
      );

      await repository.annulerVente(
        reference: reference,
        motif: 'Erreur de saisie',
      );

      expect(
        (await repository.chargerCatalogue())
            .firstWhere((p) => p.nom == 'Goliath mature')
            .stock,
        31, // restitué
      );
    });

    test('décrémente le compteur de la fiche d\'élevage', () async {
      expect((await db.select(db.ficheVentesJour).get()).single.qte, 2);

      await repository.annulerVente(
        reference: reference,
        motif: 'Erreur de saisie',
      );

      // Sans cela, une vente annulée continuerait de compter comme une sortie
      // du jour sur la fiche d'élevage.
      expect((await db.select(db.ficheVentesJour).get()).single.qte, 0);
    });

    test('annulation logique : la vente reste en base (BR-VTE-004)', () async {
      await repository.annulerVente(
        reference: reference,
        motif: 'Client non honoré',
      );

      final vente = await repository.chargerVente(reference);
      expect(vente, isNotNull);
      expect(vente!.statut, StatutVente.annulee);
      expect(vente.motifAnnulation, 'Client non honoré');
      // Les lignes ne sont pas supprimées non plus.
      expect(await db.select(db.lignesVente).get(), hasLength(1));
    });

    test('refuse d\'annuler deux fois', () async {
      await repository.annulerVente(reference: reference, motif: 'Autre');
      expect(
        () => repository.annulerVente(reference: reference, motif: 'Autre'),
        throwsStateError,
      );
    });

    test('refuse une référence inconnue', () {
      expect(
        () => repository.annulerVente(reference: 'V-2000-999', motif: 'Autre'),
        throwsStateError,
      );
    });
  });

  group('Paiement d\'une créance — Doc F4 Écran 3', () {
    late String reference;

    setUp(() async {
      final resultat = await repository.enregistrerVente(
        client: 'AGOSSOU Prudence',
        mode: ModeReglement.especes,
        statut: StatutVente.avance,
        montantPaye: 3500,
        panier: [ligne(produit('Goliath mature'), 2)], // total 12 000
      );
      reference = resultat.vente.reference;
    });

    test('un paiement partiel laisse la vente en avance', () async {
      await repository.enregistrerPaiement(reference: reference, montant: 2000);

      final vente = await repository.chargerVente(reference);
      expect(vente!.paye, 5500);
      expect(vente.statut, StatutVente.avance);
      expect(vente.resteDu, 6500);
    });

    test('le solde complet fait passer le statut à « Payée »', () async {
      await repository.enregistrerPaiement(reference: reference, montant: 8500);

      final vente = await repository.chargerVente(reference);
      expect(vente!.paye, 12000);
      expect(vente.statut, StatutVente.payee);
      expect(vente.resteDu, 0);
    });

    test('on ne peut jamais encaisser plus que le total dû', () async {
      await repository.enregistrerPaiement(
        reference: reference,
        montant: 999999,
      );

      final vente = await repository.chargerVente(reference);
      expect(vente!.paye, 12000); // borné au total
      expect(vente.statut, StatutVente.payee);
    });

    test('une vente annulée ne peut pas être encaissée', () async {
      await repository.annulerVente(reference: reference, motif: 'Autre');
      expect(
        () =>
            repository.enregistrerPaiement(reference: reference, montant: 1000),
        throwsStateError,
      );
    });
  });

  group('Catalogue — CRUD produit', () {
    test('création, modification et suppression persistent', () async {
      final cree = await repository.creerProduit(
        const ProduitVendable(
          id: '',
          nom: 'Œufs fertiles goliath (lot)',
          categorie: 'Avicole',
          prix: 5000,
          unite: 'lot(s)',
          icone: 'egg',
          stock: 10,
          seuil: 3,
        ),
      );
      expect((await repository.chargerCatalogue()), hasLength(15));

      await repository.mettreAJourProduit(
        ProduitVendable(
          id: cree.id,
          nom: cree.nom,
          categorie: cree.categorie,
          prix: 5500,
          unite: cree.unite,
          icone: cree.icone,
          stock: 8,
          seuil: cree.seuil,
        ),
      );
      final modifie = (await repository.chargerCatalogue()).firstWhere(
        (p) => p.id == cree.id,
      );
      expect(modifie.prix, 5500);
      expect(modifie.stock, 8);

      await repository.supprimerProduit(cree.id);
      expect(await repository.chargerCatalogue(), hasLength(14));
    });

    test('estCritique suit le seuil du produit', () async {
      // Maïs est un intrant, pas un produit — on prend un produit vendable.
      final oeufs = produit('Œufs de table (plateau)'); // stock 12, seuil 5
      expect(oeufs.estCritique, isFalse);

      await (db.update(db.produitsVendables)
            ..where((p) => p.id.equals(oeufs.id)))
          .write(const ProduitsVendablesCompanion(stock: Value(5)));

      final relu = (await repository.chargerCatalogue()).firstWhere(
        (p) => p.id == oeufs.id,
      );
      expect(relu.estCritique, isTrue); // seuil inclusif
    });
  });
}
