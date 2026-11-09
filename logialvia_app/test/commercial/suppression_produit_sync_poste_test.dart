import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/administration/domain/services/service_archivage.dart';
import 'package:logialvia_app/commercial/presentation/viewmodels/catalogue_view_model.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/commercial/data/sync/table_mouvements_produit_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_produits_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import '../core/sync/faux_serveur_sync.dart';

/// Suppression d'un produit propagée (pierre tombale) et motif des corrections.
class _Poste {
  _Poste(this.serveur) : db = AppDatabase.enMemoire() {
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: serveur.client,
    );
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: appairage,
      demandes: DepotDemandesReferentiel(db),
      tables: [TableProduitsPoste(db), TableMouvementsProduitPoste(db)],
      client: serveur.client,
    );
    ventes = VentesRepositoryDrift(db, EventBus());
  }

  final FauxServeurSync serveur;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final VentesRepositoryDrift ventes;

  Future<void> demarrer() async {
    await SeedInitial(db).executer();
    await preferences.definirIntrantsAdoptes();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }

  Future<ProduitVendableRow> produit() async => (await (db.select(
    db.produitsVendables,
  )..orderBy([(p) => OrderingTerm.asc(p.name)])).get()).first;
  Future<ProduitVendableRow> produitId(String id) => (db.select(
    db.produitsVendables,
  )..where((p) => p.id.equals(id))).getSingle();
  Future<List<MouvementProduitRow>> mouvements() =>
      db.select(db.mouvementsProduit).get();
  Future<List<MouvementProduitRow>> locaux() =>
      (db.select(db.mouvementsProduit)..where((m) => m.origine.isNull())).get();

  /// Corrige le stock par le chemin du formulaire du catalogue.
  Future<void> corriger(ProduitVendableRow p, int nouveauStock) =>
      ventes.mettreAJourProduit(
        ProduitVendable(
          id: p.id,
          nom: p.name,
          categorie: p.cat,
          prix: p.price,
          prixMax: p.priceMax,
          unite: p.unit,
          icone: p.icon,
          stock: nouveauStock,
          seuil: p.threshold,
          espece: p.espece,
          sku: p.sku,
          coutRevient: p.coutRevient,
        ),
      );
}

void main() {
  late FauxServeurSync serveur;
  final postes = <_Poste>[];

  Future<_Poste> poste() async {
    final p = _Poste(serveur);
    postes.add(p);
    await p.demarrer();
    return p;
  }

  Future<List<ProduitVendableRow>> produitsDe(_Poste p, String id) =>
      (p.db.select(
        p.db.produitsVendables,
      )..where((x) => x.id.equals(id))).get();

  setUp(() {
    serveur = FauxServeurSync();
    postes.clear();
  });

  tearDown(() async {
    for (final p in postes) {
      await p.db.close();
    }
  });

  group('motif de la correction de stock', () {
    test('le motif saisi entre au journal', () async {
      final a = await poste();
      final p = await a.produit();

      await a.ventes.mettreAJourProduit(
        ProduitVendable(
          id: p.id,
          nom: p.name,
          categorie: p.cat,
          prix: p.price,
          prixMax: p.priceMax,
          unite: p.unit,
          icone: p.icon,
          stock: p.stock - 2,
          seuil: p.threshold,
          espece: p.espece,
          sku: p.sku,
          coutRevient: p.coutRevient,
        ),
        motifCorrection: '  Casse à la livraison ',
      );

      expect((await a.mouvements()).single.motif, 'Casse à la livraison');
    });

    test('le formulaire refuse un changement de stock sans motif', () async {
      final a = await poste();
      final p = await a.produit();
      final vm = CatalogueViewModel(a.ventes);
      await vm.charger();

      Future<Resultat<ProduitVendable>> enregistrer(int stock, String? motif) =>
          vm.enregistrer(
            id: p.id,
            nom: p.name,
            categorie: p.cat,
            prix: p.price,
            prixMax: p.priceMax,
            unite: p.unit,
            stock: stock,
            seuil: p.threshold,
            espece: p.espece,
            coutRevient: p.coutRevient,
            motifCorrection: motif,
          );

      final refus = await enregistrer(p.stock + 1, '  ');
      expect(refus, isA<Echec<ProduitVendable>>());
      expect(
        (refus as Echec<ProduitVendable>).message,
        'Indiquez le motif de la correction de stock.',
      );
      expect(
        (await a.produitId(p.id)).stock,
        p.stock,
        reason: 'rien n\'est écrit',
      );
      expect(await a.mouvements(), isEmpty);

      // Sans changement de stock, aucun motif n'est demandé.
      expect(await enregistrer(p.stock, null), isA<Succes<ProduitVendable>>());
      expect(await a.mouvements(), isEmpty);

      expect(
        await enregistrer(p.stock + 3, 'Retour de ferme'),
        isA<Succes<ProduitVendable>>(),
      );
      expect((await a.mouvements()).single.motif, 'Retour de ferme');
    });
  });

  group('suppression d\'un produit propagée', () {
    test('A supprime : B l\'archive à son tour, dans SA corbeille', () async {
      final a = await poste();
      final b = await poste();
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();
      final p = await a.produit();

      await a.ventes.supprimerProduit(p.id);
      await a.moteur.synchroniser();
      final r = await b.moteur.synchroniser();

      expect(r.reussie, isTrue, reason: r.message);
      expect(
        serveur.produits[p.id]!['archive_le'],
        isNotNull,
        reason: 'jamais effacé du serveur',
      );
      expect(await produitsDe(a, p.id), isEmpty);
      expect(await produitsDe(b, p.id), isEmpty);
      final corbeille = await ServiceArchivage(b.db).lister();
      expect(corbeille.map((e) => e.designation), contains(p.name));
    });

    test('un produit déjà vendu sur B y reste (historique)', () async {
      final a = await poste();
      final b = await poste();
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();
      final p = await a.produit();
      final catalogue = await b.ventes.chargerCatalogue();
      final prod = catalogue.firstWhere((x) => x.id == p.id);
      await b.ventes.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: prod.prix,
        panier: [
          LignePanier(
            produitId: prod.id,
            nom: prod.nom,
            montantGlobal: prod.prix,
            quantite: 1,
            stockDisponible: prod.stock,
            prixIndicatif: prod.prix,
            prixIndicatifMax: prod.prixMax,
            espece: prod.espece,
            unite: prod.unite,
          ),
        ],
      );

      await a.ventes.supprimerProduit(p.id);
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();

      expect(await produitsDe(b, p.id), hasLength(1));
    });

    test('un poste neuf ne recrée jamais un produit archivé', () async {
      final a = await poste();
      await a.moteur.synchroniser();
      final p = await a.produit();
      await a.ventes.supprimerProduit(p.id);
      await a.moteur.synchroniser();

      final c = _Poste(serveur);
      postes.add(c);
      await c.demarrer();
      await c.db.customStatement('PRAGMA foreign_keys = OFF');
      await (c.db.delete(
        c.db.produitsVendables,
      )..where((x) => x.id.equals(p.id))).go();
      await c.db.customStatement('PRAGMA foreign_keys = ON');
      await c.moteur.synchroniser();

      expect(await produitsDe(c, p.id), isEmpty);
    });

    test(
      'une saisie locale plus récente que la suppression n\'est pas écrasée',
      () async {
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        final p = await a.produit();
        await a.ventes.supprimerProduit(p.id);
        await a.moteur.synchroniser();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await b.ventes.mettreAJourProduit(
          ProduitVendable(
            id: p.id,
            nom: 'Nom plus récent',
            categorie: p.cat,
            prix: p.price,
            prixMax: p.priceMax,
            unite: p.unit,
            icone: p.icon,
            stock: p.stock,
            seuil: p.threshold,
            espece: p.espece,
            sku: p.sku,
            coutRevient: p.coutRevient,
          ),
        );

        await b.moteur.synchroniser();

        // La demande de B est postérieure : elle lève l'archivage et B garde son produit.
        expect((await produitsDe(b, p.id)).single.name, 'Nom plus récent');
        expect(serveur.produits[p.id]!['archive_le'], isNull);
      },
    );

    test(
      'restaurer depuis la corbeille lève l\'archivage au serveur',
      () async {
        final a = await poste();
        await a.moteur.synchroniser();
        final p = await a.produit();
        await a.ventes.supprimerProduit(p.id);
        await a.moteur.synchroniser();
        expect(serveur.produits[p.id]!['archive_le'], isNotNull);
        final archive = (await ServiceArchivage(
          a.db,
        ).lister()).firstWhere((e) => e.designation == p.name);
        await Future<void>.delayed(const Duration(milliseconds: 5));

        await ServiceArchivage(a.db).restaurer(archive.id, estAdmin: true);
        await a.moteur.synchroniser();

        expect(await produitsDe(a, p.id), hasLength(1));
        expect(serveur.produits[p.id]!['archive_le'], isNull);
      },
    );

    test('hors ligne : la suppression part à la reconnexion', () async {
      final a = await poste();
      await a.moteur.synchroniser();
      final p = await a.produit();
      serveur.horsLigne = true;
      await a.ventes.supprimerProduit(p.id);
      await a.moteur.synchroniser();
      expect(serveur.produits[p.id]!['archive_le'], isNull);

      serveur.horsLigne = false;
      await a.moteur.synchroniser();

      expect(serveur.produits[p.id]!['archive_le'], isNotNull);
    });
  });
}
