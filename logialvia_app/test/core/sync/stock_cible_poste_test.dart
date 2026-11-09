import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/approvisionnement/data/repositories/approvisionnement_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_achats_poste.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_mouvements_intrant_poste.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/approvisionnement.dart';
import 'package:logialvia_app/approvisionnement/domain/services/calcul_pmp.dart';
import 'package:logialvia_app/commercial/data/sync/table_mouvements_produit_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_ventes_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/sync/effets_stock_poste.dart';
import 'package:logialvia_app/core/sync/table_effets_stock_poste.dart';

/// `47s_` — **stock ciblé** : l'exception documentée à la règle d'or. Seul le poste que le
/// web désigne (`poste_cible`) applique, UNE fois, l'effet de stock et de PMP d'un fait web ;
/// les autres l'absorbent comme historique.
void main() {
  late AppDatabase db;
  late String moi;
  late TableAchatsPoste achats;
  late TableVentesPoste ventes;
  late TableMouvementsProduitPoste corrections;
  late TableMouvementsIntrantPoste journal;
  late ApprovisionnementRepositoryDrift appro;

  const autre = '99999999-9999-4999-8999-999999999999';
  const idAchat = '11111111-1111-4111-8111-111111111111';
  const idLigneA = '22222222-2222-4222-8222-222222222222';
  const idVente = '44444444-4444-4444-8444-444444444444';
  const idLigneV = '55555555-5555-4555-8555-555555555555';
  const idMvt = '66666666-6666-4666-8666-666666666666';

  // ------------------------------------------------------------- aides

  Future<void> fixerIntrant(int stock, int pmp) =>
      (db.update(db.intrants)..where((i) => i.code.equals('INT-001'))).write(
        IntrantsCompanion(stock: Value(stock), pmp: Value(pmp)),
      );

  Future<IntrantRow> intrant() => (db.select(
    db.intrants,
  )..where((i) => i.code.equals('INT-001'))).getSingle();

  Future<String> fournisseur() async =>
      (await appro.creerFournisseur(nom: 'Maïs Local')).id;

  Map<String, dynamic> achat(
    String f, {
    String statut = 'Commandé',
    String? cible,
    String maj = '2026-11-09T10:00:00.000000Z',
    num paye = 0,
    int qte = 50,
    num pu = 320,
  }) => {
    'id': idAchat,
    'reference': 'ACH-WEB-2026-001',
    'fournisseur_id': f,
    'date_achat': '2026-11-09T10:00:00.000000Z',
    'statut': statut,
    'total': qte * pu,
    'paye': paye,
    'mode': 'Espèces',
    'echeance': null,
    'poste_cible': cible,
    'updated_at': maj,
    'lignes': [
      {
        'id': idLigneA,
        'intrant_code': 'INT-001',
        'nom': 'Maïs',
        'qte': qte,
        'pu_achat': pu,
      },
    ],
  };

  Future<ProduitVendableRow> produit() async =>
      (await db.select(db.produitsVendables).get()).first;

  Future<void> fixerProduit(String id, int stock) =>
      (db.update(db.produitsVendables)..where((p) => p.id.equals(id))).write(
        ProduitsVendablesCompanion(stock: Value(stock)),
      );

  Future<int> stockProduit(String id) async => (await (db.select(
    db.produitsVendables,
  )..where((p) => p.id.equals(id))).getSingle()).stock;

  Map<String, dynamic> vente(
    String produitId, {
    String statut = 'Payée',
    String? cible,
    String maj = '2026-11-09T10:00:00.000000Z',
    int qte = 3,
  }) => {
    'id': idVente,
    'reference': 'V-WEB-2026-001',
    'client': 'Client Comptant',
    'date_vente': '2026-11-09T10:00:00.000000Z',
    'mode': 'Espèces',
    'status': statut,
    'total': qte * 1000,
    'paye': qte * 1000,
    'poste_cible': cible,
    'updated_at': maj,
    'lignes': [
      {
        'id': idLigneV,
        'produit_id': produitId,
        'name': 'Produit',
        'qte': qte,
        'pu': 1000,
        'espece': null,
      },
    ],
  };

  Future<List<EffetAppliqueRow>> effets() =>
      db.select(db.effetsAppliques).get();

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    final prefs = PreferencesPosteRepository(db);
    moi = await prefs.identifiantPoste();
    await prefs.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    achats = TableAchatsPoste(db);
    ventes = TableVentesPoste(db);
    corrections = TableMouvementsProduitPoste(db);
    journal = TableMouvementsIntrantPoste(db);
    appro = ApprovisionnementRepositoryDrift(db);
    await fixerIntrant(100, 200);
  });

  tearDown(() async => db.close());

  // ===================================================== PMP : une formule

  group('PMP : la formule du poste, une seule', () {
    test('la réception du poste et l\'effet web donnent le même PMP', () async {
      // Poste A : réception saisie ici (chemin historique).
      final f = await fournisseur();
      final saisie = await appro.enregistrerAchat(
        fournisseurId: f,
        panier: const [
          LignePanierAchat(
            intrantCode: 'INT-001',
            nom: 'Maïs',
            quantite: 50,
            prixUnitaire: 320,
            unite: '',
          ),
        ],
        livree: true,
        montantPaye: 0,
        mode: 'Espèces',
      );
      expect(saisie.reference, isNotEmpty);
      final local = await intrant();

      // Poste B : même point de départ, mais l'achat vient du web.
      await fixerIntrant(100, 200);
      await achats.absorber([achat(f, statut: 'Livré', cible: moi)]);
      final parWeb = await intrant();

      expect(parWeb.stock, local.stock);
      expect(parWeb.pmp, local.pmp);
      expect(parWeb.pmp, 240, reason: '(100×200 + 50×320) ÷ 150');
    });

    test('CalculPmp : cas limites', () {
      expect(
        CalculPmp.apresReception(
          stock: 0,
          pmp: 0,
          quantite: 10,
          prixUnitaire: 150.4,
        ),
        150,
      );
      expect(
        CalculPmp.apresReception(
          stock: -5,
          pmp: 200,
          quantite: 5,
          prixUnitaire: 999,
        ),
        200,
        reason: 'stock résultant nul : PMP inchangé',
      );
      // Retrait : inverse exact ; plancher et stock vidé laissent le PMP.
      expect(
        CalculPmp.apresRetrait(
          stock: 150,
          pmp: 240,
          quantite: 50,
          prixUnitaire: 320,
        ),
        200,
      );
      expect(
        CalculPmp.apresRetrait(
          stock: 20,
          pmp: 240,
          quantite: 50,
          prixUnitaire: 320,
        ),
        240,
      );
      expect(
        CalculPmp.apresRetrait(
          stock: 50,
          pmp: 240,
          quantite: 50,
          prixUnitaire: 320,
        ),
        240,
      );
    });
  });

  // ============================================================ achats

  group('réception d\'achat saisie au web', () {
    test(
      'le poste désigné entre le stock et recalcule le PMP, une trace est écrite',
      () async {
        final f = await fournisseur();

        final r = await achats.absorber([
          achat(f, statut: 'Livré', cible: moi),
        ]);

        expect(r.absorbees, 1);
        final i = await intrant();
        expect(i.stock, 150);
        expect(i.pmp, 240);
        final e = (await effets()).single;
        expect(e.nature, 'reception');
        expect(e.faitType, 'achat');
        expect(e.faitId, idAchat);
        expect(e.reference, 'ACH-WEB-2026-001');
        expect(e.etat, 'applique');
        expect(e.avertissement, isNull);
        expect(e.origine, isNull);
        expect(e.syncStatus, 'pending', reason: 'la trace part au serveur');
        expect(e.id, EffetsStockPoste.idEffet(idAchat, 'reception'));
        expect(e.libelle, contains('Maïs +50'));
      },
    );

    test(
      'commande puis livraison : l\'effet n\'a lieu qu\'à la livraison',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, cible: moi)]);
        expect((await intrant()).stock, 100, reason: 'commandé : rien');
        expect(await effets(), isEmpty);

        await achats.absorber([
          achat(
            f,
            statut: 'Livré',
            cible: moi,
            maj: '2026-11-09T11:00:00.000000Z',
          ),
        ]);

        expect((await intrant()).stock, 150);
        expect(await effets(), hasLength(1));
      },
    );

    test(
      'rejeu, version identique, règlement ultérieur, tirage complet : jamais de double effet',
      () async {
        final f = await fournisseur();
        final livre = achat(f, statut: 'Livré', cible: moi);
        await achats.absorber([livre]);
        await achats.absorber([livre]);
        await achats.absorber([
          achat(
            f,
            statut: 'Livré',
            cible: moi,
            maj: '2026-11-09T12:00:00.000000Z',
            paye: 5000,
          ),
        ]);
        // Tirage complet : la même ligne revient dans un lot, deux fois.
        await achats.absorber([livre, livre]);

        expect((await intrant()).stock, 150);
        expect(await effets(), hasLength(1));
      },
    );

    test(
      'un tirage complet sur une base où l\'achat est connu mais l\'effet déjà tracé ne réapplique rien',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, statut: 'Livré', cible: moi)]);
        // Simule « renvoyer vers ce poste » : on vide les achats mais on garde le journal
        // des effets (la base est la même) ; l'achat revient et l'effet existe déjà.
        await db.delete(db.lignesAchat).go();
        await db.delete(db.achats).go();

        await achats.absorber([achat(f, statut: 'Livré', cible: moi)]);

        expect((await intrant()).stock, 150, reason: 'pas de seconde entrée');
        expect(await effets(), hasLength(1));
      },
    );

    test(
      'un autre poste désigné, ou aucun : historique, aucun effet',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, statut: 'Livré', cible: autre)]);
        expect((await intrant()).stock, 100);
        expect((await intrant()).pmp, 200);
        expect(await effets(), isEmpty);

        await db.delete(db.lignesAchat).go();
        await db.delete(db.achats).go();
        await achats.absorber([achat(f, statut: 'Livré')]);
        expect((await intrant()).stock, 100);
        expect(await effets(), isEmpty);
      },
    );

    test(
      'un poste cible invalide (pas un UUID) fait refuser l\'achat',
      () async {
        final f = await fournisseur();
        final r = await achats.absorber([
          achat(f, statut: 'Livré', cible: 'poste-p2'),
        ]);
        expect(r.refusees, 1);
        expect((await intrant()).stock, 100);
      },
    );

    test(
      'annulation d\'une commande livrée : sortie inverse et PMP rendu',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, statut: 'Livré', cible: moi)]);

        await achats.absorber([
          achat(
            f,
            statut: 'Annulé',
            cible: moi,
            maj: '2026-11-09T11:00:00.000000Z',
          ),
        ]);

        final i = await intrant();
        expect(i.stock, 100);
        expect(i.pmp, 200, reason: '(150×240 − 50×320) ÷ 100');
        final tous = await effets();
        expect(tous.map((e) => e.nature).toSet(), {
          'reception',
          'annulation_reception',
        });
        expect(
          tous.firstWhere((e) => e.nature == 'annulation_reception').etat,
          'applique',
        );

        // Rejeu de l'annulation : pas de seconde sortie.
        await achats.absorber([
          achat(
            f,
            statut: 'Annulé',
            cible: moi,
            maj: '2026-11-09T11:00:00.000000Z',
          ),
        ]);
        expect((await intrant()).stock, 100);
      },
    );

    test(
      'annuler une commande jamais livrée ici : rien n\'était entré',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, cible: moi)]);
        await achats.absorber([
          achat(
            f,
            statut: 'Annulé',
            cible: moi,
            maj: '2026-11-09T11:00:00.000000Z',
          ),
        ]);
        expect((await intrant()).stock, 100);
        expect(await effets(), isEmpty);

        // Une commande qui arrive déjà annulée : idem.
        await db.delete(db.lignesAchat).go();
        await db.delete(db.achats).go();
        await achats.absorber([achat(f, statut: 'Annulé', cible: moi)]);
        expect((await intrant()).stock, 100);
        expect(await effets(), isEmpty);
      },
    );

    test(
      'annulation sans le stock : plancher à 0, PMP inchangé, avertissement tracé',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, statut: 'Livré', cible: moi)]);
        await fixerIntrant(20, 240); // le magasin a consommé entre-temps

        await achats.absorber([
          achat(
            f,
            statut: 'Annulé',
            cible: moi,
            maj: '2026-11-09T11:00:00.000000Z',
          ),
        ]);

        final i = await intrant();
        expect(i.stock, 0, reason: 'jamais de stock négatif');
        expect(i.pmp, 240);
        final e = (await effets()).firstWhere(
          (e) => e.nature == 'annulation_reception',
        );
        expect(e.etat, 'avertissement');
        expect(e.avertissement, contains('Stock insuffisant au poste P1'));
        expect(e.avertissement, contains('50 à retirer, 20 disponibles'));
      },
    );

    test(
      'commande déjà livrée au poste avant que le web la désigne : non appliquée (pas de double entrée)',
      () async {
        final f = await fournisseur();
        // Le poste reçoit sa propre commande (même identité, statut Livré local).
        await achats.absorber([achat(f, statut: 'Livré')]);
        expect((await intrant()).stock, 100);

        // Le web livre la même commande en désignant CE poste : arrivée trop tard.
        await achats.absorber([
          achat(
            f,
            statut: 'Livré',
            cible: moi,
            maj: '2026-11-09T12:00:00.000000Z',
            paye: 100,
          ),
        ]);

        expect((await intrant()).stock, 100);
        final e = (await effets()).single;
        expect(e.etat, 'ignore');
        expect(e.avertissement, contains('déjà livrée'));
      },
    );

    test(
      'le poste de stock se pose une fois (commande sans poste, livrée au web avec lui)',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f)]); // commande saisie sans poste
        await achats.absorber([
          achat(
            f,
            statut: 'Livré',
            cible: moi,
            maj: '2026-11-09T11:00:00.000000Z',
          ),
        ]);
        expect((await intrant()).stock, 150);
        final a = await db.select(db.achats).getSingle();
        expect(a.posteCible, moi);
      },
    );

    test(
      'le poste cible est IMMUABLE : l\'effet suit le lien d\'origine',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, cible: moi)]);
        await achats.absorber([
          achat(
            f,
            statut: 'Livré',
            cible: autre,
            maj: '2026-11-09T11:00:00.000000Z',
          ),
        ]);
        // Le message désignait un autre poste : le lien d'origine (moi) gagne, jamais l'inverse.
        expect((await db.select(db.achats).getSingle()).posteCible, moi);
        expect((await intrant()).stock, 150);
        expect((await effets()).single.etat, 'applique');
      },
    );

    test(
      'lié à un autre poste, la livraison désignant celui-ci n\'applique rien',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, cible: autre)]);
        await achats.absorber([
          achat(
            f,
            statut: 'Livré',
            cible: moi,
            maj: '2026-11-09T11:00:00.000000Z',
          ),
        ]);
        expect((await db.select(db.achats).getSingle()).posteCible, autre);
        expect((await intrant()).stock, 100);
        expect((await effets()).single.etat, 'ignore');
      },
    );

    test(
      'les lignes du journal partagé (mouvements) n\'appliquent JAMAIS rien',
      () async {
        await journal.absorber([
          {
            'id': idMvt,
            'device_id': '00000000-0000-0000-0000-000000000000',
            'horodatage': '2026-11-09T10:00:00.000000Z',
            'intrant_code': 'INT-001',
            'article': 'Maïs',
            'type': 'Entrée',
            'motif': 'Réception commande ACH-WEB-2026-001',
            'quantite': 50,
            'reference': 'ACH-WEB-2026-001',
            'poste_cible': moi,
          },
        ]);
        expect(
          (await intrant()).stock,
          100,
          reason: 'l\'effet est porté par l\'achat',
        );
        final m = await db.select(db.mouvementsIntrant).getSingle();
        expect(
          m.posteCible,
          moi,
          reason: 'informatif, affiché dans le journal',
        );
        expect(m.origine, isNotNull);
        expect(await effets(), isEmpty);
      },
    );
  });

  // ============================================================ ventes

  group('vente saisie au web', () {
    test(
      'le poste désigné décrémente SON stock ; fiche_ventes_jour n\'est pas touchée',
      () async {
        final p = await produit();
        await fixerProduit(p.id, 10);

        final r = await ventes.absorber([vente(p.id, cible: moi)]);

        expect(r.absorbees, 1);
        expect(await stockProduit(p.id), 7);
        final e = (await effets()).single;
        expect(e.nature, 'vente');
        expect(e.etat, 'applique');
        expect(e.reference, 'V-WEB-2026-001');
        expect(
          await db.select(db.ficheVentesJour).get(),
          isEmpty,
          reason: 'le compteur du jour reste celui du web (46a_)',
        );
      },
    );

    test(
      'stock insuffisant : plancher à 0 ET avertissement tracé, jamais de négatif',
      () async {
        final p = await produit();
        await fixerProduit(p.id, 2);

        await ventes.absorber([vente(p.id, cible: moi, qte: 5)]);

        expect(await stockProduit(p.id), 0);
        final e = (await effets()).single;
        expect(e.etat, 'avertissement');
        expect(
          e.avertissement,
          'Stock insuffisant au poste P1 : « Produit » — 5 demandés, 2 '
          'disponibles ; stock ramené à 0',
        );
      },
    );

    test(
      'annulation : réintégration, une seule fois, même rejouée ou tirée de nouveau',
      () async {
        final p = await produit();
        await fixerProduit(p.id, 10);
        await ventes.absorber([vente(p.id, cible: moi)]);

        final annulee = vente(
          p.id,
          cible: moi,
          statut: 'Annulée',
          maj: '2026-11-09T11:00:00.000000Z',
        );
        await ventes.absorber([annulee]);
        await ventes.absorber([annulee]);
        await ventes.absorber([annulee, annulee]);

        expect(await stockProduit(p.id), 10);
        expect((await effets()).map((e) => e.nature).toSet(), {
          'vente',
          'annulation_vente',
        });
      },
    );

    test('rejeu et tirage complet de la vente : un seul décrément', () async {
      final p = await produit();
      await fixerProduit(p.id, 10);
      final v = vente(p.id, cible: moi);
      await ventes.absorber([v]);
      await ventes.absorber([v]);
      await db.delete(db.lignesVente).go();
      await db.delete(db.ventes).go();
      await ventes.absorber([v]);

      expect(await stockProduit(p.id), 7);
      expect(await effets(), hasLength(1));
    });

    test(
      'annulée AUSSI sur ce poste : pas de seconde restitution (le poste a rendu le stock lui-même)',
      () async {
        final p = await produit();
        await fixerProduit(p.id, 10);
        await ventes.absorber([vente(p.id, cible: moi)]);
        expect(await stockProduit(p.id), 7);

        // L'annulation locale du poste : statut Annulée + stock restitué par le poste.
        await (db.update(db.ventes)..where((v) => v.id.equals(idVente))).write(
          const VentesCompanion(
            status: Value('Annulée'),
            syncStatus: Value('synced'),
          ),
        );
        await fixerProduit(p.id, 10);

        // Le web annule la même vente : arrivée d'une annulation déjà connue.
        await ventes.absorber([
          {
            ...vente(
              p.id,
              cible: moi,
              statut: 'Annulée',
              maj: '2026-11-09T11:00:00.000000Z',
            ),
            'motif_annulation': 'Erreur de saisie',
          },
        ]);

        expect(
          await stockProduit(p.id),
          10,
          reason: 'pas de double restitution',
        );
        final e = (await effets()).firstWhere(
          (e) => e.nature == 'annulation_vente',
        );
        expect(e.etat, 'ignore');
      },
    );

    test('une vente déjà annulée à son arrivée n\'a jamais d\'effet', () async {
      final p = await produit();
      await fixerProduit(p.id, 10);
      await ventes.absorber([vente(p.id, cible: moi, statut: 'Annulée')]);
      expect(await stockProduit(p.id), 10);
      expect(await effets(), isEmpty);
    });

    test('un autre poste désigné, ou aucun : aucun effet ici', () async {
      final p = await produit();
      await fixerProduit(p.id, 10);
      await ventes.absorber([vente(p.id, cible: autre)]);
      expect(await stockProduit(p.id), 10);

      await db.delete(db.lignesVente).go();
      await db.delete(db.ventes).go();
      await ventes.absorber([vente(p.id)]);
      expect(await stockProduit(p.id), 10);
      expect(await effets(), isEmpty);
    });

    test(
      'le lien est immuable : un message qui change de poste ne déplace pas l\'effet',
      () async {
        final p = await produit();
        await fixerProduit(p.id, 10);
        await ventes.absorber([vente(p.id, cible: moi)]);

        // Le message d'annulation prétend désigner un autre poste : le lien d'origine gagne,
        // l'annulation suit le même poste (la réintégration a lieu ICI).
        await ventes.absorber([
          vente(
            p.id,
            cible: autre,
            statut: 'Annulée',
            maj: '2026-11-09T11:00:00.000000Z',
          ),
        ]);

        expect(await stockProduit(p.id), 10);
        expect((await db.select(db.ventes).getSingle()).posteCible, moi);
      },
    );

    test(
      'une vente annulée sur un poste qui n\'était pas le cible ne réintègre rien',
      () async {
        final p = await produit();
        await fixerProduit(p.id, 10);
        await ventes.absorber([vente(p.id, cible: autre)]);
        await ventes.absorber([
          vente(
            p.id,
            cible: autre,
            statut: 'Annulée',
            maj: '2026-11-09T11:00:00.000000Z',
          ),
        ]);
        expect(await stockProduit(p.id), 10);
        expect(await effets(), isEmpty);
      },
    );
  });

  // ================================================ garde-fous du service

  group('EffetsStockPoste : chaque effet est unique par lui-même', () {
    test(
      'appliquer deux fois le même effet est refusé par le service, sans rien changer',
      () async {
        final effets = EffetsStockPoste(db);
        final p = await produit();
        await fixerProduit(p.id, 10);
        const lignesI = [
          LigneEffetIntrant(
            code: 'INT-001',
            nom: 'Maïs',
            quantite: 50,
            prixUnitaire: 320,
          ),
        ];
        final lignesP = [
          LigneEffetProduit(produitId: p.id, nom: 'Produit', quantite: 3),
        ];

        expect(
          await effets.appliquerReception(
            achatId: idAchat,
            reference: 'R',
            lignes: lignesI,
          ),
          isTrue,
        );
        expect(
          await effets.appliquerReception(
            achatId: idAchat,
            reference: 'R',
            lignes: lignesI,
          ),
          isFalse,
        );
        expect((await intrant()).stock, 150);

        expect(
          await effets.annulerReception(
            achatId: idAchat,
            reference: 'R',
            lignes: lignesI,
          ),
          isTrue,
        );
        expect(
          await effets.annulerReception(
            achatId: idAchat,
            reference: 'R',
            lignes: lignesI,
          ),
          isFalse,
        );
        expect((await intrant()).stock, 100);

        expect(
          await effets.appliquerVente(
            venteId: idVente,
            reference: 'V',
            lignes: lignesP,
          ),
          isTrue,
        );
        expect(
          await effets.annulerVente(
            venteId: idVente,
            reference: 'V',
            lignes: lignesP,
          ),
          isTrue,
        );
        expect(
          await effets.annulerVente(
            venteId: idVente,
            reference: 'V',
            lignes: lignesP,
          ),
          isFalse,
        );
        expect(await stockProduit(p.id), 10);

        expect(
          await effets.appliquerCorrection(
            mouvementId: idMvt,
            produitId: p.id,
            article: 'Produit',
            motif: 'm',
            variation: 5,
          ),
          isTrue,
        );
        expect(
          await effets.appliquerCorrection(
            mouvementId: idMvt,
            produitId: p.id,
            article: 'Produit',
            motif: 'm',
            variation: 5,
          ),
          isFalse,
        );
        expect(await stockProduit(p.id), 15);
      },
    );

    test(
      'commande liée à ce poste, réceptionnée AUSSI localement avant la livraison web : une seule entrée',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, cible: moi)]);
        // Le poste reçoit lui-même la commande (stock +50 par sa propre réception).
        await appro.receptionnerAchat('ACH-WEB-2026-001');
        expect((await intrant()).stock, 150);

        // La livraison du web arrive ensuite (version plus récente que la saisie locale).
        await achats.absorber([
          achat(
            f,
            statut: 'Livré',
            cible: moi,
            maj: '2099-01-01T00:00:00.000000Z',
          ),
        ]);

        expect((await intrant()).stock, 150, reason: 'pas de seconde entrée');
        final e = (await effets()).single;
        expect(e.etat, 'ignore');
        expect(e.avertissement, contains('n\'était plus « Commandé »'));
      },
    );
  });

  group('le poste cible fait l\'aller-retour', () {
    test(
      'un achat ou une vente liés renvoient leur poste cible au serveur',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, statut: 'Livré', cible: moi)]);
        await (db.update(db.achats)..where((a) => a.id.equals(idAchat))).write(
          const AchatsCompanion(syncStatus: Value('pending')),
        );
        expect((await achats.aEnvoyer()).single.corps['poste_cible'], moi);

        final p = await produit();
        await ventes.absorber([vente(p.id, cible: moi)]);
        await (db.update(db.ventes)..where((v) => v.id.equals(idVente))).write(
          const VentesCompanion(syncStatus: Value('pending')),
        );
        expect((await ventes.aEnvoyer()).single.corps['poste_cible'], moi);
      },
    );
  });

  // ======================================================= corrections

  group('correction de stock produit saisie au web', () {
    Map<String, dynamic> correction({
      String? cible,
      num quantite = 5,
      String id = idMvt,
      required String produitId,
    }) => {
      'id': id,
      'device_id': '00000000-0000-0000-0000-000000000000',
      'horodatage': '2026-11-09T10:00:00.000000Z',
      'produit_id': produitId,
      'article': 'Produit',
      'motif': 'Comptage du magasin',
      'quantite': quantite,
      'poste_cible': cible,
    };

    test(
      'la variation signée s\'applique au poste désigné, une fois',
      () async {
        final p = await produit();
        await fixerProduit(p.id, 10);

        await corrections.absorber([correction(cible: moi, produitId: p.id)]);
        await corrections.absorber([correction(cible: moi, produitId: p.id)]);

        expect(await stockProduit(p.id), 15);
        final e = (await effets()).single;
        expect(e.nature, 'correction');
        expect(e.faitType, 'mouvement_produit');
        expect(e.libelle, contains('+5'));
        expect(e.libelle, contains('Comptage du magasin'));
      },
    );

    test('une baisse sous zéro : plancher et avertissement', () async {
      final p = await produit();
      await fixerProduit(p.id, 3);
      await corrections.absorber([
        correction(cible: moi, quantite: -10, produitId: p.id),
      ]);
      expect(await stockProduit(p.id), 0);
      expect((await effets()).single.etat, 'avertissement');
    });

    test('les autres postes : historique pur, stock inchangé', () async {
      final p = await produit();
      await fixerProduit(p.id, 10);
      await corrections.absorber([correction(cible: autre, produitId: p.id)]);
      await corrections.absorber([
        correction(id: '77777777-7777-4777-8777-777777777777', produitId: p.id),
      ]);
      expect(await stockProduit(p.id), 10);
      expect(await effets(), isEmpty);
      expect(await db.select(db.mouvementsProduit).get(), hasLength(2));
    });
  });

  // ======================================================== affichage

  group('ce que le poste montre', () {
    Map<String, dynamic> mouvementWeb(String id, String? cible) => {
      'id': id,
      'device_id': '00000000-0000-0000-0000-000000000000',
      'horodatage': '2026-11-09T10:00:00.000000Z',
      'intrant_code': 'INT-001',
      'article': 'Maïs',
      'type': 'Entrée',
      'motif': 'Réception commande ACH-WEB-2026-001',
      'quantite': 50,
      'reference': 'ACH-WEB-2026-001',
      'poste_cible': cible,
    };

    test(
      'la ligne du journal est marquée « appliqué depuis le web » pour le poste désigné seulement',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, statut: 'Livré', cible: moi)]);
        await journal.absorber([mouvementWeb(idMvt, moi)]);

        final m = (await appro.chargerMouvements()).single;
        expect(m.appliqueIci, isTrue);
        expect(m.posteCible, moi);
      },
    );

    test(
      'sans effet appliqué ici (autre poste, ou « non appliqué »), pas de badge',
      () async {
        final f = await fournisseur();
        await achats.absorber([achat(f, statut: 'Livré', cible: autre)]);
        await journal.absorber([mouvementWeb(idMvt, autre)]);
        expect((await appro.chargerMouvements()).single.appliqueIci, isFalse);

        // Désigné mais non appliqué (commande déjà livrée localement) : pas de badge.
        await db.delete(db.mouvementsIntrant).go();
        await db.delete(db.lignesAchat).go();
        await db.delete(db.achats).go();
        await achats.absorber([achat(f, statut: 'Livré')]);
        await achats.absorber([
          achat(
            f,
            statut: 'Livré',
            cible: moi,
            maj: '2026-11-09T12:00:00.000000Z',
            paye: 100,
          ),
        ]);
        await journal.absorber([mouvementWeb(idMvt, moi)]);
        expect((await appro.chargerMouvements()).single.appliqueIci, isFalse);
      },
    );

    test(
      'le panneau liste les effets de CE poste, avertissements compris',
      () async {
        final p = await produit();
        await fixerProduit(p.id, 1);
        await ventes.absorber([vente(p.id, cible: moi, qte: 4)]);

        final e = (await appro.chargerEffetsWeb()).single;
        expect(e.alerte, isTrue);
        expect(e.avertissement, contains('Stock insuffisant au poste P1'));
        expect(e.reference, 'V-WEB-2026-001');
      },
    );
  });

  // ================================================ la trace qui voyage

  group('effets_stock : la trace partagée', () {
    TableEffetsStockPoste table() => TableEffetsStockPoste(db);

    Map<String, dynamic> trace(
      String faitId,
      String nature, {
      String? emetteur,
    }) => {
      'id': EffetsStockPoste.idEffet(faitId, nature),
      'device_id': emetteur ?? autre,
      'fait_type': 'vente',
      'fait_id': faitId,
      'nature': nature,
      'reference': 'V-WEB-2026-009',
      'libelle': 'Vente V-WEB-2026-009 reçue du web',
      'etat': 'avertissement',
      'avertissement': 'Stock insuffisant au poste P2 : …',
      'applique_le': '2026-11-09T10:00:00.000000Z',
    };

    test(
      'l\'effet d\'un autre poste est de l\'historique : aucun stock touché',
      () async {
        final p = await produit();
        await fixerProduit(p.id, 10);

        final r = await table().absorber([trace(idVente, 'vente')]);

        expect(r.absorbees, 1);
        expect(await stockProduit(p.id), 10);
        final e = (await effets()).single;
        expect(e.origine, autre);
        expect(e.syncStatus, 'synced');
        expect((await table().aEnvoyer()), isEmpty, reason: 'jamais renvoyé');
      },
    );

    test(
      'mon propre effet qui revient (base restaurée) redevient le mien',
      () async {
        await table().absorber([trace(idVente, 'vente', emetteur: moi)]);
        expect((await effets()).single.origine, isNull);
        expect(
          await EffetsStockPoste(db).dejaApplique(idVente, 'vente'),
          isTrue,
          reason: 'l\'effet est connu : jamais appliqué une seconde fois',
        );
      },
    );

    test(
      'un identifiant forgé, une nature inconnue ou un état inconnu sont refusés',
      () async {
        final forge = {...trace(idVente, 'vente'), 'id': idMvt};
        final nature = {...trace(idVente, 'vente'), 'nature': 'magie'};
        final etat = {...trace(idVente, 'vente'), 'etat': 'ok'};
        final r = await table().absorber([forge, nature, etat]);
        expect(r.refusees, 3);
        expect(await effets(), isEmpty);
      },
    );

    test(
      'mes effets en attente partent ; accusés, ils ne repartent plus ; purge',
      () async {
        final p = await produit();
        await fixerProduit(p.id, 10);
        await ventes.absorber([vente(p.id, cible: moi)]);

        final envoi = await table().aEnvoyer();
        expect(envoi, hasLength(1));
        expect(envoi.single.corps['nature'], 'vente');
        expect(envoi.single.corps['fait_id'], idVente);

        await table().marquerSynchronise(envoi.single.id, '');
        expect(await table().aEnvoyer(), isEmpty);

        expect(await table().purger(), 0);
        expect(await effets(), isEmpty);
      },
    );
  });
}
