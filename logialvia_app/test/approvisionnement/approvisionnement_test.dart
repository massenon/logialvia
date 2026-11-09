import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/approvisionnement/data/repositories/approvisionnement_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/approvisionnement.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';

void main() {
  late AppDatabase db;
  late ApprovisionnementRepositoryDrift repository;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    repository = ApprovisionnementRepositoryDrift(db);
  });

  tearDown(() async => db.close());

  Future<Intrant> intrant(String code) async =>
      (await repository.chargerIntrants()).firstWhere((i) => i.code == code);

  Future<String> fournisseur() async {
    final f = await repository.creerFournisseur(
      nom: 'Fournisseur Maïs Local',
      telephone: '+229 97 00 11 22',
      fournit: 'Maïs, Soja',
    );
    return f.id;
  }

  group('Intrants seedés', () {
    test('les 6 intrants du prototype avec leur PMP', () async {
      final tous = await repository.chargerIntrants();
      expect(tous, hasLength(6));

      final mais = await intrant('INT-001');
      expect(mais.nom, 'Maïs');
      expect(mais.stock, 18);
      expect(mais.seuil, 25);
      expect(mais.pmp, 600);
      expect(mais.estCritique, isTrue);
      expect(mais.valeur, 10800); // 18 × 600
    });
  });

  group('Ajustement d\'inventaire — BR-ADM-003', () {
    test(
      'remplace le stock théorique par le stock physique constaté',
      () async {
        await repository.ajusterInventaire(
          code: 'INT-001',
          stockPhysique: 15,
          motif: 'Inventaire physique mensuel',
        );

        expect((await intrant('INT-001')).stock, 15);
      },
    );

    test(
      'journalise l\'écart — sans quoi il disparaîtrait en silence',
      () async {
        await repository.ajusterInventaire(
          code: 'INT-001',
          stockPhysique: 15, // théorique 18 -> écart -3
          motif: 'Inventaire physique mensuel',
        );

        final mouvements = await repository.chargerMouvements();
        expect(mouvements, hasLength(1));
        expect(mouvements.single.type, TypeMouvement.ajustement);
        expect(mouvements.single.quantite, -3);
        expect(mouvements.single.motif, 'Inventaire physique mensuel');
        expect(mouvements.single.article, 'Maïs');
      },
    );

    test('un écart positif est journalisé aussi', () async {
      await repository.ajusterInventaire(
        code: 'INT-001',
        stockPhysique: 30,
        motif: 'Régularisation',
      );

      final mouvements = await repository.chargerMouvements();
      expect(mouvements.single.quantite, 12); // 30 − 18
    });

    test('refuse un intrant inconnu', () {
      expect(
        () => repository.ajusterInventaire(
          code: 'INT-999',
          stockPhysique: 10,
          motif: 'Test',
        ),
        throwsStateError,
      );
    });
  });

  group('Commande livrée — stock, PMP et journal', () {
    test('incrémente le stock et journalise l\'entrée', () async {
      final idFournisseur = await fournisseur();

      final achat = await repository.enregistrerAchat(
        fournisseurId: idFournisseur,
        mode: 'Espèces',
        montantPaye: 30000,
        livree: true,
        panier: [
          const LignePanierAchat(
            intrantCode: 'INT-001',
            nom: 'Maïs',
            quantite: 50,
            prixUnitaire: 600,
            unite: 'kg',
          ),
        ],
      );

      expect(achat.statut, StatutAchat.livre);
      expect((await intrant('INT-001')).stock, 68); // 18 + 50

      final mouvements = await repository.chargerMouvements();
      expect(mouvements.single.type, TypeMouvement.entree);
      expect(mouvements.single.quantite, 50);
      expect(mouvements.single.reference, achat.reference);
    });

    test('le PMP est recalculé en moyenne pondérée — sinon la valorisation du '
        'stock serait fausse dès le premier achat à un autre prix', () async {
      final idFournisseur = await fournisseur();

      // 18 kg à 600 F en stock, on reçoit 82 kg à 700 F.
      // PMP' = (18×600 + 82×700) / 100 = (10 800 + 57 400) / 100 = 682
      await repository.enregistrerAchat(
        fournisseurId: idFournisseur,
        mode: 'Espèces',
        montantPaye: 57400,
        livree: true,
        panier: [
          const LignePanierAchat(
            intrantCode: 'INT-001',
            nom: 'Maïs',
            quantite: 82,
            prixUnitaire: 700,
            unite: 'kg',
          ),
        ],
      );

      final mais = await intrant('INT-001');
      expect(mais.stock, 100);
      expect(mais.pmp, 682);
      // Sans recalcul, le PMP serait reste a 600 et la valorisation aurait
      // sous-estime le stock de 8 200 F.
      expect(mais.valeur, 68200);
    });

    test('un achat au même prix laisse le PMP inchangé', () async {
      final idFournisseur = await fournisseur();
      await repository.enregistrerAchat(
        fournisseurId: idFournisseur,
        mode: 'Espèces',
        montantPaye: 12000,
        livree: true,
        panier: [
          const LignePanierAchat(
            intrantCode: 'INT-001',
            nom: 'Maïs',
            quantite: 20,
            prixUnitaire: 600,
            unite: 'kg',
          ),
        ],
      );

      expect((await intrant('INT-001')).pmp, 600);
    });

    test('un intrant repasse au-dessus de son seuil après réception', () async {
      expect((await intrant('INT-001')).estCritique, isTrue);

      final idFournisseur = await fournisseur();
      await repository.enregistrerAchat(
        fournisseurId: idFournisseur,
        mode: 'Espèces',
        montantPaye: 30000,
        livree: true,
        panier: [
          const LignePanierAchat(
            intrantCode: 'INT-001',
            nom: 'Maïs',
            quantite: 50,
            prixUnitaire: 600,
            unite: 'kg',
          ),
        ],
      );

      expect((await intrant('INT-001')).estCritique, isFalse);
    });
  });

  group('Commande non livrée', () {
    test('ne touche ni le stock ni le journal', () async {
      final idFournisseur = await fournisseur();

      await repository.enregistrerAchat(
        fournisseurId: idFournisseur,
        mode: 'Espèces',
        montantPaye: 0,
        livree: false,
        panier: [
          const LignePanierAchat(
            intrantCode: 'INT-001',
            nom: 'Maïs',
            quantite: 50,
            prixUnitaire: 600,
            unite: 'kg',
          ),
        ],
      );

      expect((await intrant('INT-001')).stock, 18); // inchangé
      expect(await repository.chargerMouvements(), isEmpty);
    });

    test('la réception applique le stock et le journal', () async {
      final idFournisseur = await fournisseur();
      final achat = await repository.enregistrerAchat(
        fournisseurId: idFournisseur,
        mode: 'Espèces',
        montantPaye: 0,
        livree: false,
        panier: [
          const LignePanierAchat(
            intrantCode: 'INT-001',
            nom: 'Maïs',
            quantite: 50,
            prixUnitaire: 600,
            unite: 'kg',
          ),
        ],
      );

      await repository.receptionnerAchat(achat.reference);

      expect((await intrant('INT-001')).stock, 68);
      expect(await repository.chargerMouvements(), hasLength(1));
      expect(
        (await repository.chargerAchats()).single.statut,
        StatutAchat.livre,
      );
    });

    test('refuse une double réception', () async {
      final idFournisseur = await fournisseur();
      final achat = await repository.enregistrerAchat(
        fournisseurId: idFournisseur,
        mode: 'Espèces',
        montantPaye: 0,
        livree: false,
        panier: [
          const LignePanierAchat(
            intrantCode: 'INT-001',
            nom: 'Maïs',
            quantite: 50,
            prixUnitaire: 600,
            unite: 'kg',
          ),
        ],
      );
      await repository.receptionnerAchat(achat.reference);

      expect(
        () => repository.receptionnerAchat(achat.reference),
        throwsStateError,
      );
      // Le stock n'a pas ete incremente deux fois.
      expect((await intrant('INT-001')).stock, 68);
    });
  });

  group('Dettes fournisseurs — miroir des créances clients', () {
    test('agrégats recalculés depuis ACHATS', () async {
      final idFournisseur = await fournisseur();
      await repository.enregistrerAchat(
        fournisseurId: idFournisseur,
        mode: 'Espèces',
        montantPaye: 10000,
        livree: true,
        panier: [
          const LignePanierAchat(
            intrantCode: 'INT-001',
            nom: 'Maïs',
            quantite: 50,
            prixUnitaire: 600,
            unite: 'kg',
          ),
        ],
      );

      final f = (await repository.chargerFournisseurs()).single;
      expect(f.nombreCommandes, 1);
      expect(f.totalAchats, 30000);
      expect(f.soldeDu, 20000);
      expect(f.aUneDette, isTrue);
    });

    test('un règlement réduit la dette et est borné au total', () async {
      final idFournisseur = await fournisseur();
      final achat = await repository.enregistrerAchat(
        fournisseurId: idFournisseur,
        mode: 'Espèces',
        montantPaye: 0,
        livree: true,
        panier: [
          const LignePanierAchat(
            intrantCode: 'INT-001',
            nom: 'Maïs',
            quantite: 10,
            prixUnitaire: 600,
            unite: 'kg',
          ),
        ],
      );

      await repository.reglerAchat(reference: achat.reference, montant: 2000);
      expect((await repository.chargerFournisseurs()).single.soldeDu, 4000);

      await repository.reglerAchat(reference: achat.reference, montant: 999999);
      expect((await repository.chargerFournisseurs()).single.soldeDu, 0);
      expect((await repository.chargerAchats()).single.paye, 6000);
    });

    test('les références de commande s\'incrémentent', () async {
      final idFournisseur = await fournisseur();
      for (var i = 0; i < 3; i++) {
        await repository.enregistrerAchat(
          fournisseurId: idFournisseur,
          mode: 'Espèces',
          montantPaye: 0,
          livree: false,
          panier: [
            const LignePanierAchat(
              intrantCode: 'INT-001',
              nom: 'Maïs',
              quantite: 1,
              prixUnitaire: 600,
              unite: 'kg',
            ),
          ],
        );
      }

      final annee = DateTime.now().year;
      final refs = (await repository.chargerAchats())
          .map((a) => a.reference)
          .toSet();
      expect(refs, {'ACH-$annee-001', 'ACH-$annee-002', 'ACH-$annee-003'});
    });
  });

  group('CRUD intrant', () {
    test('création, modification et suppression persistent', () async {
      await repository.enregistrerIntrant(
        const Intrant(
          code: 'INT-007',
          nom: 'Son de blé',
          categorie: 'Intrants Provende',
          stock: 40,
          unite: 'kg',
          seuil: 10,
          pmp: 450,
        ),
        creation: true,
      );
      expect(await repository.chargerIntrants(), hasLength(7));

      await repository.enregistrerIntrant(
        const Intrant(
          code: 'INT-007',
          nom: 'Son de blé',
          categorie: 'Intrants Provende',
          stock: 35,
          unite: 'kg',
          seuil: 15,
          pmp: 470,
        ),
        creation: false,
      );
      final modifie = await intrant('INT-007');
      expect(modifie.stock, 35);
      expect(modifie.pmp, 470);

      await repository.supprimerIntrant('INT-007');
      expect(await repository.chargerIntrants(), hasLength(6));
    });
  });
}
