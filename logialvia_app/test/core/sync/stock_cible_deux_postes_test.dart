import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_achats_poste.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_fournisseurs_poste.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_intrants_poste.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_mouvements_intrant_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_mouvements_produit_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_produits_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_ventes_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:logialvia_app/core/sync/table_effets_stock_poste.dart';

import 'faux_serveur_sync.dart';

/// `47s_` — deux postes et un web : seul le poste désigné applique l'effet de stock, une
/// fois ; un poste hors ligne le reçoit à sa prochaine synchronisation ; les autres postes
/// voient la trace comme de l'historique.
class _Poste {
  _Poste(this.serveur, this.code) : db = AppDatabase.enMemoire() {
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
      tables: [
        TableProduitsPoste(db),
        TableIntrantsPoste(db),
        TableClientsPoste(db),
        TableFournisseursPoste(db),
        TableVentesPoste(db),
        TableAchatsPoste(db),
        TableMouvementsIntrantPoste(db),
        TableMouvementsProduitPoste(db),
        TableEffetsStockPoste(db),
      ],
      client: serveur.client,
    );
  }

  final FauxServeurSync serveur;
  final String code;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late String id;

  Future<void> demarrer() async {
    await SeedInitial(db).executer();
    await preferences.definirParametresElevageAdoptes();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: code,
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
    id = await preferences.identifiantPoste();
  }

  Future<int> stockProduit(String produitId) async => (await (db.select(
    db.produitsVendables,
  )..where((p) => p.id.equals(produitId))).getSingle()).stock;

  Future<void> fixerProduit(String produitId, int stock) =>
      (db.update(db.produitsVendables)..where((p) => p.id.equals(produitId)))
          .write(ProduitsVendablesCompanion(stock: Value(stock)));

  Future<IntrantRow> intrant() => (db.select(
    db.intrants,
  )..where((i) => i.code.equals('INT-001'))).getSingle();

  Future<List<EffetAppliqueRow>> effets() =>
      db.select(db.effetsAppliques).get();
}

void main() {
  late FauxServeurSync serveur;
  final postes = <_Poste>[];
  const web = '00000000-0000-0000-0000-000000000000';
  const idVente = '44444444-4444-4444-8444-444444444444';
  const idAchat = '11111111-1111-4111-8111-111111111111';

  Future<_Poste> poste(String code) async {
    final p = _Poste(serveur, code);
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

  Map<String, dynamic> venteWeb(
    String produitId,
    String cible, {
    String statut = 'Payée',
    int qte = 3,
    String maj = '2026-11-09T10:00:00.000000Z',
  }) => {
    'id': idVente,
    'device_id': web,
    'reference': 'V-WEB-2026-001',
    'client': 'Client Comptant',
    'client_id': null,
    'date_vente': '2026-11-09T10:00:00.000000Z',
    'mode': 'Espèces',
    'status': statut,
    'total': qte * 1000,
    'paye': qte * 1000,
    'poste_cible': cible,
    'updated_at': maj,
    'serveur_modifie_le': serveur.instantServeur(),
    'lignes': [
      {
        'id': '55555555-5555-4555-8555-555555555555',
        'produit_id': produitId,
        'name': 'Produit',
        'qte': qte,
        'pu': 1000,
        'espece': null,
      },
    ],
  };

  Future<String> premierProduit(_Poste p) async =>
      (await p.db.select(p.db.produitsVendables).get()).first.id;

  /// A et B se connaissent et ont adopté le catalogue au serveur.
  Future<(_Poste, _Poste)> deuxPostes() async {
    final a = await poste('P1');
    final b = await poste('P2');
    expect((await a.moteur.synchroniser()).reussie, isTrue);
    expect((await b.moteur.synchroniser()).reussie, isTrue);
    return (a, b);
  }

  group('vente du web ciblée sur A', () {
    test(
      'A hors ligne : rien tant qu\'il ne se synchronise pas ; B ne bouge jamais ; A applique une fois ; B voit la trace',
      () async {
        final (a, b) = await deuxPostes();
        final produit = await premierProduit(a);
        await a.fixerProduit(produit, 10);
        await b.fixerProduit(produit, 10);

        serveur.ventes[idVente] = venteWeb(produit, a.id);

        // B se synchronise : il apprend la vente, son stock ne change pas.
        expect((await b.moteur.synchroniser()).reussie, isTrue);
        expect(await b.stockProduit(produit), 10);
        expect(await b.effets(), isEmpty);
        // A est « hors ligne » : rien n'a bougé chez lui.
        expect(await a.stockProduit(produit), 10);

        // A revient : l'effet s'applique, UNE fois, et la trace remonte.
        final r = await a.moteur.synchroniser();
        expect(r.reussie, isTrue, reason: r.message);
        expect(await a.stockProduit(produit), 7);
        expect(await a.effets(), hasLength(1));
        expect(serveur.effetsStock, hasLength(1));
        expect(
          serveur.effetsStock.values.single['device_id'],
          a.id,
          reason: 'la trace dit quel poste a appliqué',
        );
        expect((await a.effets()).single.syncStatus, 'synced');

        // Resynchronisations, tirage complet ("renvoyer vers ce poste") : pas de double.
        await a.moteur.synchroniser();
        await a.moteur.synchroniser(complet: true);
        expect(await a.stockProduit(produit), 7);
        expect(await a.effets(), hasLength(1));

        // B reçoit la trace comme de l'historique : aucun stock bougé.
        await b.moteur.synchroniser();
        expect(await b.stockProduit(produit), 10);
        final trace = (await b.effets()).single;
        expect(trace.origine, a.id);
        expect(trace.nature, 'vente');
      },
    );

    test(
      'l\'annulation au web suit le même poste : réintégration à A, jamais à B',
      () async {
        final (a, b) = await deuxPostes();
        final produit = await premierProduit(a);
        await a.fixerProduit(produit, 10);
        await b.fixerProduit(produit, 10);
        serveur.ventes[idVente] = venteWeb(produit, a.id);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        expect(await a.stockProduit(produit), 7);

        serveur.ventes[idVente] = venteWeb(
          produit,
          a.id,
          statut: 'Annulée',
          maj: '2026-11-09T11:00:00.000000Z',
        );
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        expect(await a.stockProduit(produit), 10);
        expect(await b.stockProduit(produit), 10);
        expect((await a.effets()).map((e) => e.nature).toSet(), {
          'vente',
          'annulation_vente',
        });
      },
    );

    test(
      'A sans assez de stock : plancher à 0 et avertissement remonté au serveur',
      () async {
        final (a, _) = await deuxPostes();
        final produit = await premierProduit(a);
        await a.fixerProduit(produit, 1);
        serveur.ventes[idVente] = venteWeb(produit, a.id);

        await a.moteur.synchroniser();

        expect(await a.stockProduit(produit), 0);
        final trace = serveur.effetsStock.values.single;
        expect(trace['etat'], 'avertissement');
        expect(
          trace['avertissement'],
          contains('Stock insuffisant au poste P1'),
        );
      },
    );
  });

  group('réception du web ciblée sur A', () {
    Map<String, dynamic> achatWeb(
      String fournisseurId,
      String? cible, {
      String statut = 'Livré',
      String maj = '2026-11-09T10:00:00.000000Z',
    }) => {
      'id': idAchat,
      'device_id': web,
      'reference': 'ACH-WEB-2026-001',
      'fournisseur_id': fournisseurId,
      'date_achat': '2026-11-09T10:00:00.000000Z',
      'statut': statut,
      'total': 16000,
      'paye': 0,
      'mode': 'Crédit',
      'echeance': null,
      'poste_cible': cible,
      'updated_at': maj,
      'serveur_modifie_le': serveur.instantServeur(),
      'lignes': [
        {
          'id': '22222222-2222-4222-8222-222222222222',
          'intrant_code': 'INT-001',
          'nom': 'Maïs',
          'qte': 50,
          'pu_achat': 320,
        },
      ],
    };

    test(
      'entrée + PMP chez A seulement, annulation = sortie inverse',
      () async {
        final (a, b) = await deuxPostes();
        for (final p in [a, b]) {
          await (p.db.update(
            p.db.intrants,
          )..where((i) => i.code.equals('INT-001'))).write(
            const IntrantsCompanion(stock: Value(100), pmp: Value(200)),
          );
        }
        serveur.fournisseurs['f0000000-0000-4000-8000-000000000001'] = {
          'id': 'f0000000-0000-4000-8000-000000000001',
          'device_id': web,
          'nom': 'Maïs Local',
          'telephone': null,
          'adresse': null,
          'fournit': null,
          'updated_at': '2026-11-09T09:00:00.000000Z',
          'serveur_modifie_le': serveur.instantServeur(),
          'supprime_le': null,
        };
        serveur.achats[idAchat] = achatWeb(
          'f0000000-0000-4000-8000-000000000001',
          a.id,
        );

        await b.moteur.synchroniser();
        await a.moteur.synchroniser();

        expect((await a.intrant()).stock, 150);
        expect((await a.intrant()).pmp, 240);
        expect(
          (await b.intrant()).stock,
          100,
          reason: 'B : historique seulement',
        );
        expect((await b.intrant()).pmp, 200);

        serveur.achats[idAchat] = achatWeb(
          'f0000000-0000-4000-8000-000000000001',
          a.id,
          statut: 'Annulé',
          maj: '2026-11-09T11:00:00.000000Z',
        );
        await a.moteur.synchroniser();
        await a.moteur.synchroniser(complet: true);
        await b.moteur.synchroniser();

        expect((await a.intrant()).stock, 100);
        expect((await a.intrant()).pmp, 200);
        expect((await b.intrant()).stock, 100);
        expect(serveur.effetsStock, hasLength(2));
      },
    );
  });
}
