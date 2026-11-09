import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/commercial/data/sync/table_mouvements_produit_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_produits_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import '../core/sync/faux_serveur_sync.dart';

/// Palier 6 — décision du client : **stock propre à chaque poste + journal partagé**.
/// Seules les corrections manuelles de stock sont journalisées (les ventes voyagent
/// déjà avec leurs lignes).
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

  setUp(() {
    serveur = FauxServeurSync();
    postes.clear();
  });

  tearDown(() async {
    for (final p in postes) {
      await p.db.close();
    }
  });

  group('trace d\'une correction de stock', () {
    test(
      'une correction laisse une ligne signée, locale et en attente',
      () async {
        final a = await poste();
        final p = await a.produit();

        await a.corriger(p, p.stock + 7);

        final m = (await a.mouvements()).single;
        expect(m.quantite, 7);
        expect(m.produitId, p.id);
        expect(m.article, p.name);
        expect(m.origine, isNull);
        expect(m.syncStatus, 'pending');
        expect((await a.produitId(p.id)).stock, p.stock + 7);
      },
    );

    test(
      'une baisse est négative ; un stock inchangé ne laisse aucune trace',
      () async {
        final a = await poste();
        final p = await a.produit();

        await a.corriger(p, p.stock);
        expect(await a.mouvements(), isEmpty);

        expect(
          p.stock,
          greaterThan(0),
          reason: 'le catalogue de départ a du stock',
        );
        await a.corriger(p, 0);
        expect((await a.mouvements()).single.quantite, -p.stock.toDouble());
      },
    );

    test('un produit créé avec du stock laisse un « Stock initial »', () async {
      final a = await poste();

      final cree = await a.ventes.creerProduit(
        const ProduitVendable(
          id: '',
          nom: 'Oeufs de test',
          categorie: 'Avicole',
          prix: 100,
          unite: 'plateau',
          icone: 'egg',
          stock: 12,
          seuil: 2,
        ),
      );

      final m = (await a.mouvements()).single;
      expect(m.produitId, cree.id);
      expect(m.quantite, 12);
      expect(m.motif, contains('Stock initial'));
    });

    test('un produit créé à stock 0 ne laisse aucune trace', () async {
      final a = await poste();
      await a.ventes.creerProduit(
        const ProduitVendable(
          id: '',
          nom: 'Vide',
          categorie: 'Avicole',
          prix: 100,
          unite: 'u',
          icone: 'egg',
          stock: 0,
          seuil: 0,
        ),
      );
      expect(await a.mouvements(), isEmpty);
    });
  });

  group('cycle de vie du produit', () {
    test(
      'supprimer un produit emporte son journal local, sans erreur',
      () async {
        final a = await poste();
        final p = await a.produit();
        await a.corriger(p, p.stock + 2);
        expect(await a.mouvements(), hasLength(1));

        await a.ventes.supprimerProduit(p.id);

        expect(await a.mouvements(), isEmpty);
        expect(
          await (a.db.select(
            a.db.produitsVendables,
          )..where((x) => x.id.equals(p.id))).get(),
          isEmpty,
        );
      },
    );
  });

  group('journal partagé, jamais un stock', () {
    test(
      'la correction part après le produit (demande avant envoi) et est marquée synchronisée',
      () async {
        final a = await poste();
        final p = await a.produit();
        await a.corriger(p, p.stock + 4);

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(r.refusees, 0, reason: r.message);
        expect(serveur.mouvementsProduit, hasLength(1));
        expect((await a.mouvements()).single.syncStatus, 'synced');
        final i = serveur.journal.indexOf('POST /api/sync/demandes');
        final j = serveur.journal.indexOf('POST /api/sync/push');
        expect(j, greaterThan(i));
      },
    );

    test('B reçoit la correction de A SANS que son stock bouge', () async {
      final a = await poste();
      final b = await poste();
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();
      final p = await a.produit();
      final stockB = (await b.produitId(p.id)).stock;
      await a.corriger(p, p.stock + 9);
      await a.moteur.synchroniser();

      final r = await b.moteur.synchroniser();

      expect(r.reussie, isTrue, reason: r.message);
      final m = (await b.mouvements()).single;
      expect(m.origine, isNotNull);
      expect(m.quantite, 9);
      expect(
        (await b.produitId(p.id)).stock,
        stockB,
        reason: 'stock propre à chaque poste',
      );
      expect((await a.produitId(p.id)).stock, p.stock + 9);
    });

    test(
      'ma propre correction qui revient au tirage n\'est pas dupliquée',
      () async {
        final a = await poste();
        final p = await a.produit();
        await a.corriger(p, p.stock + 1);
        await a.moteur.synchroniser();
        await a.preferences.definirCurseurTirage(null);

        await a.moteur.synchroniser();

        final m = await a.mouvements();
        expect(m, hasLength(1));
        expect(m.single.origine, isNull);
      },
    );

    test(
      'un mouvement ne se modifie jamais : la version du serveur est ignorée',
      () async {
        final a = await poste();
        final b = await poste();
        final p = await a.produit();
        await a.corriger(p, p.stock + 3);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        final id = (await b.mouvements()).single.id;
        serveur.mouvementsProduit[id]!['quantite'] = 9999.0;
        serveur.mouvementsProduit[id]!['motif'] = 'Falsifié';
        serveur.mouvementsProduit[id]!['serveur_modifie_le'] = serveur
            .instantServeur();

        await b.moteur.synchroniser();

        final m = (await b.mouvements()).single;
        expect(m.quantite, 3);
        expect(m.motif, isNot('Falsifié'));
      },
    );

    final cas = <String, Map<String, dynamic>>{
      'UUID invalide': {'id': 'pas-un-uuid'},
      'produit non UUID': {'produit_id': 'x'},
      'quantité nulle': {'quantite': 0},
      'motif vide': {'motif': ' '},
      'désignation vide': {'article': ''},
      'date invalide': {'horodatage': 'hier'},
      'produit inconnu de ce poste': {
        'produit_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      },
    };
    cas.forEach((nom, surcharge) {
      test('refusé, rien d\'écrit : $nom', () async {
        final b = await poste();
        await b.moteur.synchroniser();
        final p = await b.produit();
        serveur.mouvementsProduit['x'] = {
          'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'device_id': 'autre',
          'horodatage': '2026-11-01T10:00:00.000000Z',
          'produit_id': p.id,
          'article': p.name,
          'motif': 'Correction',
          'quantite': 5,
          'serveur_modifie_le': serveur.instantServeur(),
          ...surcharge,
        };

        final r = await b.moteur.synchroniser();

        expect(r.refuseesALaReception, 1);
        expect(await b.mouvements(), isEmpty);
      });
    });

    test('hors ligne : la correction reste en attente puis part', () async {
      final a = await poste();
      final p = await a.produit();
      await a.corriger(p, p.stock + 2);
      serveur.horsLigne = true;
      expect(
        (await a.moteur.synchroniser()).issue,
        IssueSynchronisation.horsLigne,
      );
      expect((await a.mouvements()).single.syncStatus, 'pending');

      serveur.horsLigne = false;
      await a.moteur.synchroniser();

      expect((await a.mouvements()).single.syncStatus, 'synced');
    });

    test(
      'remise à zéro : le journal part, les produits et le stock restent',
      () async {
        final a = await poste();
        final b = await poste();
        final p = await a.produit();
        await a.corriger(p, p.stock + 5);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        final stockB = (await b.produitId(p.id)).stock;
        final nbProduits =
            (await b.db.select(b.db.produitsVendables).get()).length;

        serveur.remettreAZero();
        final r = await b.moteur.synchroniser();

        expect(r.remiseAZero, isTrue, reason: r.message);
        expect(await b.mouvements(), isEmpty);
        expect(
          await b.db.select(b.db.produitsVendables).get(),
          hasLength(nbProduits),
        );
        expect((await b.produitId(p.id)).stock, stockB);
      },
    );

    test('la correction d\'un autre poste n\'est jamais renvoyée', () async {
      final a = await poste();
      final b = await poste();
      final p = await a.produit();
      await a.corriger(p, p.stock + 3);
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();
      serveur.envois.clear();

      await b.moteur.synchroniser();

      for (final e in serveur.envois) {
        final t = e['tables'] as Map;
        expect(
          t.containsKey('mouvements_produit')
              ? t['mouvements_produit'] as List
              : const [],
          isEmpty,
        );
      }
    });
  });
}
