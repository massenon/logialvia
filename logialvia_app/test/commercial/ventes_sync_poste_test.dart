import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/commercial/data/repositories/clients_repository_drift.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_produits_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_ventes_poste.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import '../core/sync/faux_serveur_sync.dart';

/// Palier 3c — produits (référentiel) et ventes (lot vente + lignes) entre deux
/// postes, contre un faux serveur qui rejoue la LOGIQUE du vrai.
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
        TableClientsPoste(db),
        TableVentesPoste(db),
      ],
      client: serveur.client,
    );
    bus = EventBus();
    ventes = VentesRepositoryDrift(db, bus);
  }

  final FauxServeurSync serveur;
  final String? code;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final EventBus bus;
  late final VentesRepositoryDrift ventes;

  Future<void> demarrer() async {
    await SeedInitial(db).executer();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: code ?? 'P0',
      compte: 'g',
      le: DateTime.now(),
    );
    if (code == null) {
      // Poste « avant appairage » : références sans code de poste.
      await db.delete(db.preferencesPoste).go();
      await preferences.definirAdresseServeur('http://serveur.test');
      await preferences.memoriserAppairage(
        codePoste: 'P0',
        compte: 'g',
        le: DateTime.now(),
      );
      await (db.delete(
        db.preferencesPoste,
      )..where((p) => p.cle.equals('poste.code_attribue'))).go();
    }
    await depot.ecrire('1|jeton');
  }

  Future<ProduitVendable> produit(String nom) async =>
      (await ventes.chargerCatalogue()).firstWhere((p) => p.nom == nom);

  Future<String> vendre(
    String nomProduit, {
    double qte = 1,
    String client = 'Client Comptant',
    String statut = StatutVente.payee,
    double? paye,
  }) async {
    final p = await produit(nomProduit);
    final r = await ventes.enregistrerVente(
      client: client,
      mode: ModeReglement.especes,
      statut: statut,
      montantPaye: paye ?? p.prix * qte,
      panier: [
        LignePanier(
          produitId: p.id,
          nom: p.nom,
          montantGlobal: p.prix * qte,
          quantite: qte,
          stockDisponible: p.stock,
          prixIndicatif: p.prix,
          prixIndicatifMax: p.prixMax,
          espece: p.espece,
          unite: p.unite,
        ),
      ],
    );
    return r.vente.reference;
  }

  Future<List<VenteRow>> lesVentes() =>
      (db.select(db.ventes)..orderBy([(v) => OrderingTerm.asc(v.ref)])).get();
  Future<VenteRow> vente(String ref) =>
      (db.select(db.ventes)..where((v) => v.ref.equals(ref))).getSingle();
  Future<int> stock(String nom) async => (await produit(nom)).stock;

  Future<void> fermer() async {
    bus.dispose();
    await db.close();
  }
}

void main() {
  late FauxServeurSync serveur;
  final postes = <_Poste>[];

  Future<_Poste> poste(String? code) async {
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
      await p.fermer();
    }
  });

  final annee = DateTime.now().year;

  group('envoi', () {
    test(
      'la première synchronisation propose le catalogue, PUIS envoie les ventes',
      () async {
        final a = await poste('P1');
        final ref = await a.vendre('Goliath mature', qte: 2);

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(
          serveur.produits,
          hasLength(14),
          reason: 'tout le catalogue est connu du serveur',
        );
        expect(serveur.ventes, hasLength(1));
        final v = serveur.ventes.values.single;
        expect(v['reference'], ref);
        expect((v['lignes'] as List), hasLength(1));
        expect((await a.vente(ref)).syncStatus, 'synced');
        // L'ordre compte : sans les produits d'abord, la vente serait refusée.
        final i = serveur.journal.indexOf('POST /api/sync/demandes');
        final j = serveur.journal.indexOf('POST /api/sync/push');
        expect(i, greaterThanOrEqualTo(0));
        expect(
          j,
          greaterThan(i),
          reason: 'demandes (produits) AVANT les faits (ventes)',
        );
      },
    );

    test(
      'le stock n\'est jamais envoyé, ni dans les produits ni dans les ventes',
      () async {
        final a = await poste('P1');
        await a.vendre('Goliath mature');
        await a.moteur.synchroniser();

        for (final p in serveur.produits.values) {
          expect(p.keys, isNot(contains('stock')));
        }
      },
    );

    test(
      'un produit créé au poste est proposé, avec sa vente dans le même passage',
      () async {
        final a = await poste('P1');
        await a.moteur.synchroniser(); // catalogue adopté
        final cree = await a.ventes.creerProduit(
          const ProduitVendable(
            id: '',
            nom: 'Aliment démarrage',
            categorie: 'Intrants',
            prix: 9000,
            unite: 'sac',
            icone: 'grain',
            stock: 12,
            seuil: 2,
          ),
        );
        final p = LignePanier(
          produitId: cree.id,
          nom: cree.nom,
          montantGlobal: 9000,
          quantite: 1,
          stockDisponible: 12,
          prixIndicatif: 9000,
          prixIndicatifMax: null,
          espece: null,
          unite: 'sac',
        );
        await a.ventes.enregistrerVente(
          client: 'X',
          mode: ModeReglement.especes,
          statut: StatutVente.payee,
          montantPaye: 9000,
          panier: [p],
        );

        final r = await a.moteur.synchroniser();

        expect(r.refusees, 0, reason: r.message);
        expect(serveur.produits.containsKey(cree.id), isTrue);
        expect(serveur.produits[cree.id]!.keys, isNot(contains('stock')));
        expect(serveur.ventes, hasLength(1));
      },
    );

    test(
      'produit refusé par le serveur : la vente qui le porte devient conflit, avec le motif',
      () async {
        final a = await poste('P1');
        serveur.refuserDemandes =
            'Droit insuffisant pour modifier le catalogue.';
        final ref = await a.vendre('Goliath mature');

        final r = await a.moteur.synchroniser();

        expect(r.refusees, 1);
        final v = await a.vente(ref);
        expect(v.syncStatus, 'conflict');
        expect(v.syncMotif, startsWith('Produit inconnu du serveur'));
      },
    );

    test('rejouer l\'envoi ne duplique ni vente ni lignes', () async {
      final a = await poste('P1');
      final ref = await a.vendre('Goliath mature');
      await a.moteur.synchroniser();
      await (a.db.update(
        a.db.ventes,
      )).write(const VentesCompanion(syncStatus: Value('pending')));

      await a.moteur.synchroniser();

      expect(serveur.ventes, hasLength(1));
      expect((await a.vente(ref)).syncStatus, 'synced');
    });
  });

  group('deux postes', () {
    test(
      'B reçoit la vente de A avec ses lignes, SANS toucher à son stock ni à sa comptabilité',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final stockB = await b.stock('Goliath mature');
        final ecrituresB =
            (await b.db.select(b.db.ecritureComptable).get()).length;
        final ref = await a.vendre('Goliath mature', qte: 3);
        await a.moteur.synchroniser();

        final r = await b.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(r.recues, greaterThanOrEqualTo(1));
        final v = await b.vente(ref);
        expect(v.syncStatus, 'synced');
        expect(v.total, (await a.vente(ref)).total);
        final lignes = await (b.db.select(
          b.db.lignesVente,
        )..where((l) => l.venteRef.equals(ref))).get();
        expect(lignes, hasLength(1));
        expect(lignes.single.qte, 3);
        expect(
          await b.stock('Goliath mature'),
          stockB,
          reason: 'le stock est propre à chaque poste',
        );
        expect(
          (await b.db.select(b.db.ecritureComptable).get()).length,
          ecrituresB,
          reason: 'la comptabilité est celle du poste qui a vendu',
        );
      },
    );

    test(
      'la séquence de références de B n\'est pas perturbée par les ventes de A',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.vendre('Goliath mature');
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        expect(await b.vendre('Goliath mature'), 'V-P2-$annee-001');
      },
    );

    test(
      'l\'annulation faite par A arrive chez B (entête), les lignes ne bougent pas',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final ref = await a.vendre('Goliath mature');
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await Future<void>.delayed(const Duration(milliseconds: 3));

        await a.ventes.annulerVente(reference: ref, motif: 'Erreur de saisie');
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        final v = await b.vente(ref);
        expect(v.status, StatutVente.annulee);
        expect(v.motifAnnulation, 'Erreur de saisie');
        expect(await (b.db.select(b.db.lignesVente)).get(), hasLength(1));
      },
    );

    test(
      'deux postes avec la même ancienne référence : le serveur accepte les deux, chacun garde la sienne',
      () async {
        final a = await poste(null);
        final b = await poste(null);
        expect(await a.vendre('Goliath mature'), 'V-$annee-001');
        expect(await b.vendre('Goliath mature'), 'V-$annee-001');

        await a.moteur.synchroniser();
        final rb = await b.moteur.synchroniser();
        final ra2 = await a.moteur.synchroniser();

        expect(
          serveur.ventes,
          hasLength(2),
          reason: 'unicité par poste pour les références sans code',
        );
        expect(
          rb.refuseesALaReception,
          1,
          reason: 'sa clé locale `ref` est déjà prise par sa propre vente',
        );
        expect(ra2.refuseesALaReception, 1);
        expect(await a.lesVentes(), hasLength(1));
        expect(await b.lesVentes(), hasLength(1));
      },
    );

    test(
      'homonymes : le client_id envoyé relie la vente au bon client chez l\'autre poste',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        final c = await ClientsRepositoryDrift(
          a.db,
        ).creerClient(nom: 'DOSSOU Félicité');
        final ref = await a.vendre('Goliath mature', client: 'DOSSOU Félicité');
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        expect((await b.vente(ref)).clientId, c.id);
        expect(
          await (b.db.select(
            b.db.clients,
          )..where((x) => x.id.equals(c.id))).getSingle(),
          isNotNull,
        );
      },
    );
  });

  group('absorbeur strict et règle du plus récent', () {
    Map<String, dynamic> venteServeur(
      String produitId, {
      Map<String, dynamic> surcharge = const {},
    }) => {
      'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'device_id': 'autre',
      'reference': 'V-P9-2026-001',
      'client': 'Client',
      'client_id': null,
      'date_vente': '2026-11-01T10:00:00.000000Z',
      'mode': ModeReglement.especes,
      'status': StatutVente.payee,
      'total': 25000,
      'paye': 25000,
      'updated_at': '2026-11-01T10:00:00.000000Z',
      'serveur_modifie_le': '2026-11-09T10:00:00.000001Z',
      'lignes': [
        {
          'id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
          'produit_id': produitId,
          'name': 'Goliath mature',
          'qte': 1,
          'pu': 25000,
        },
      ],
      ...surcharge,
    };

    Future<String> produitId(_Poste p) async =>
        (await p.produit('Goliath mature')).id;

    test('une vente cohérente est absorbée avec ses lignes', () async {
      final b = await poste('P2');
      serveur.ventes['x'] = venteServeur(await produitId(b));

      final r = await b.moteur.synchroniser();

      expect(r.recues, 1);
      expect(await b.lesVentes(), hasLength(1));
    });

    final cas = <String, Map<String, dynamic> Function(String)>{
      'référence invalide': (p) =>
          venteServeur(p, surcharge: {'reference': 'FACTURE-1'}),
      'sans ligne': (p) => venteServeur(p, surcharge: {'lignes': <Object>[]}),
      'payé au-delà du total': (p) =>
          venteServeur(p, surcharge: {'paye': 99999}),
      'mode inconnu': (p) => venteServeur(p, surcharge: {'mode': 'Troc'}),
      'statut inconnu': (p) => venteServeur(p, surcharge: {'status': 'Perdue'}),
      'produit inconnu du poste': (p) => venteServeur(
        p,
        surcharge: {
          'lignes': [
            {
              'id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
              'produit_id': '00000000-0000-4000-8000-000000000000',
              'name': 'Inconnu',
              'qte': 1,
              'pu': 1,
            },
          ],
        },
      ),
    };
    cas.forEach((nom, fabrique) {
      test('refusée, sans rien écrire : $nom', () async {
        final b = await poste('P2');
        serveur.ventes['x'] = fabrique(await produitId(b));

        final r = await b.moteur.synchroniser();

        expect(r.refuseesALaReception, 1);
        expect(await b.lesVentes(), isEmpty);
        expect(
          await b.db.select(b.db.lignesVente).get(),
          isEmpty,
          reason: 'jamais de ligne sans sa vente',
        );
      });
    });

    test(
      'une saisie locale plus récente que celle du serveur n\'est pas écrasée',
      () async {
        final a = await poste('P1');
        final ref = await a.vendre('Goliath mature');
        await a.moteur.synchroniser();
        final id = (await a.vente(ref)).id;
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await a.ventes.annulerVente(reference: ref, motif: 'Local');
        // Le serveur a une version plus ANCIENNE (statut « Payée »).
        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(serveur.ventes[id]!['status'], StatutVente.annulee);
        expect((await a.vente(ref)).status, StatutVente.annulee);
      },
    );

    test(
      'une version du serveur strictement plus récente remplace la saisie locale, et c\'est dit',
      () async {
        final a = await poste('P1');
        final ref = await a.vendre('Goliath mature');
        await a.moteur.synchroniser();
        final id = (await a.vente(ref)).id;
        // Saisie locale ANCIENNE (non envoyée)…
        await (a.db.update(a.db.ventes)..where((v) => v.id.equals(id))).write(
          const VentesCompanion(
            status: Value(StatutVente.avance),
            paye: Value(1000),
            syncStatus: Value('pending'),
            updatedAt: Value('2020-01-01T00:00:00.000000Z'),
          ),
        );
        // …le serveur a décidé plus tard.
        serveur.ventes[id]!['status'] = StatutVente.annulee;
        serveur.ventes[id]!['updated_at'] = '2026-11-09T12:00:00.000000Z';
        serveur.ventes[id]!['serveur_modifie_le'] = serveur.instantServeur();

        final r = await a.moteur.synchroniser();

        expect(r.supplantees, 1);
        expect((await a.vente(ref)).status, StatutVente.annulee);
      },
    );

    test('une vente saisie au WEB (V-WEB-2026-001) est absorbée', () async {
      final b = await poste('P2');
      serveur.ventes['x'] = venteServeur(
        await produitId(b),
        surcharge: {'reference': 'V-WEB-2026-001'},
      );

      final r = await b.moteur.synchroniser();

      expect(r.recues, 1);
      expect((await b.lesVentes()).single.ref, 'V-WEB-2026-001');
    });

    test(
      'une référence « V-WEB » sans année ni numéro reste refusée',
      () async {
        final b = await poste('P2');
        serveur.ventes['x'] = venteServeur(
          await produitId(b),
          surcharge: {'reference': 'V-WEB-2026'},
        );

        final r = await b.moteur.synchroniser();

        expect(r.refuseesALaReception, 1);
        expect(await b.lesVentes(), isEmpty);
      },
    );

    // UN champ à la fois : statut et montants restent identiques, seule la
    // modification faite au web doit suffire à déclencher l'écriture.
    final modifications = <String, (String, Object, bool Function(VenteRow))>{
      'le client': (
        'client',
        'AGOSSOU Prudence',
        (v) => v.client == 'AGOSSOU Prudence',
      ),
      'le client rattaché': (
        'client_id',
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        (v) => v.clientId == 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      ),
      'l\'échéance': (
        'echeance',
        '2026-12-15T11:00:00.000000Z',
        (v) => v.echeance != null,
      ),
      'l\'adresse de livraison': (
        'livraison_adresse',
        'Kantaborifa, Natitingou',
        (v) => v.livraisonAdresse == 'Kantaborifa, Natitingou',
      ),
      'le contact de livraison': (
        'livraison_contact',
        '+229 97 11 22 33',
        (v) => v.livraisonContact == '+229 97 11 22 33',
      ),
    };
    modifications.forEach((nom, cas) {
      final (champ, valeur, verifie) = cas;
      test('une modification faite au web de $nom est appliquée', () async {
        final b = await poste('P2');
        serveur.ventes['x'] = venteServeur(await produitId(b));
        await b.moteur.synchroniser();

        serveur.ventes['x']![champ] = valeur;
        serveur.ventes['x']!['updated_at'] = '2026-11-09T13:00:00.000000Z';
        serveur.ventes['x']!['serveur_modifie_le'] = serveur.instantServeur();
        final r = await b.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(verifie((await b.lesVentes()).single), isTrue);
      });
    });

    test('les lignes d\'une vente connue ne changent jamais', () async {
      final b = await poste('P2');
      final pid = await produitId(b);
      serveur.ventes['x'] = venteServeur(pid);
      await b.moteur.synchroniser();

      serveur.ventes['x']!['lignes'] = [
        {
          'id': 'abababab-abab-4bab-8bab-abababababab',
          'produit_id': pid,
          'name': 'Autre',
          'qte': 9,
          'pu': 1,
        },
      ];
      serveur.ventes['x']!['updated_at'] = '2026-11-09T13:00:00.000000Z';
      serveur.ventes['x']!['status'] = StatutVente.annulee;
      serveur.ventes['x']!['serveur_modifie_le'] = serveur.instantServeur();
      await b.moteur.synchroniser();

      final lignes = await b.db.select(b.db.lignesVente).get();
      expect(lignes, hasLength(1));
      expect(lignes.single.qte, 1);
      expect((await b.lesVentes()).single.status, StatutVente.annulee);
    });
  });

  group('produits : le serveur gagne, jamais le stock', () {
    test(
      'un produit modifié au poste A est proposé ; B le reçoit SANS toucher à son stock',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        final stockB = await b.stock('Goliath mature');

        final p = await a.produit('Goliath mature');
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await a.ventes.mettreAJourProduit(
          ProduitVendable(
            id: p.id,
            sku: p.sku,
            nom: p.nom,
            categorie: p.categorie,
            prix: 27000,
            prixMax: 30000,
            unite: p.unite,
            icone: p.icone,
            stock: 5,
            seuil: p.seuil,
            espece: p.espece,
          ),
        );
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        final chezB = await b.produit('Goliath mature');
        expect(chezB.prix, 27000);
        expect(chezB.stock, stockB, reason: 'le stock de B est le sien');
        expect(serveur.produits[p.id]!.keys, isNot(contains('stock')));
      },
    );

    test('un produit créé par A arrive chez B avec un stock de 0', () async {
      final a = await poste('P1');
      final b = await poste('P2');
      await a.moteur.synchroniser();
      final cree = await a.ventes.creerProduit(
        const ProduitVendable(
          id: '',
          nom: 'Nouveauté',
          categorie: 'Divers',
          prix: 500,
          unite: 'u',
          icone: 'box',
          stock: 40,
          seuil: 1,
        ),
      );
      await a.moteur.synchroniser();

      await b.moteur.synchroniser();

      final chez = (await b.ventes.chargerCatalogue()).firstWhere(
        (p) => p.id == cree.id,
      );
      expect(chez.nom, 'Nouveauté');
      expect(chez.stock, 0);
    });

    test(
      'même catalogue semé sur les deux postes : aucun doublon au serveur',
      () async {
        final a = await poste('P1');
        final b = await poste('P2');
        await a.moteur.synchroniser();
        final rb = await b.moteur.synchroniser();

        expect(serveur.produits, hasLength(14));
        expect(
          rb.demandesRefusees,
          0,
          reason: 'contenu identique : ce n\'est pas un conflit',
        );
      },
    );

    test(
      'une demande de produit locale plus récente n\'est pas défaite par le tirage',
      () async {
        final a = await poste('P1');
        await a.moteur.synchroniser();
        final p = await a.produit('Goliath mature');
        // Le serveur a une version ANCIENNE.
        serveur.produits[p.id]!['price'] = 1.0;
        serveur.produits[p.id]!['saisi_le'] = '2020-01-01T00:00:00.000000Z';
        serveur.produits[p.id]!['updated_at'] = serveur.instantServeur();
        await a.ventes.mettreAJourProduit(
          ProduitVendable(
            id: p.id,
            sku: p.sku,
            nom: p.nom,
            categorie: p.categorie,
            prix: 33000,
            prixMax: 40000,
            unite: p.unite,
            icone: p.icone,
            stock: p.stock,
            seuil: p.seuil,
            espece: p.espece,
          ),
        );

        await a.moteur.synchroniser();

        expect((await a.produit('Goliath mature')).prix, 33000);
        expect(serveur.produits[p.id]!['price'], 33000);
      },
    );
  });

  test(
    'une vente modifiée PENDANT l\'envoi repart au prochain envoi',
    () async {
      final a = await poste('P1');
      final ref = await a.vendre('Goliath mature');
      serveur.pendantEnvoi = () async {
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await a.ventes.annulerVente(reference: ref, motif: 'Pendant');
      };

      await a.moteur.synchroniser();

      final v = await a.vente(ref);
      expect(
        v.syncStatus,
        'pending',
        reason: 'modifiée après l\'envoi : jamais « synchronisée » à tort',
      );
      expect(v.status, StatutVente.annulee);

      await a.moteur.synchroniser();
      expect((await a.vente(ref)).syncStatus, 'synced');
      expect(serveur.ventes.values.single['status'], StatutVente.annulee);
    },
  );

  group('produits : absorbeur strict', () {
    Map<String, dynamic> produitServeur([
      Map<String, dynamic> surcharge = const {},
    ]) => {
      'id': '12121212-1212-4121-8121-121212121212',
      'sku': 'PRD-099',
      'name': 'Produit du serveur',
      'cat': 'Divers',
      'price': 1000,
      'price_max': null,
      'unit': 'u',
      'icon': 'box',
      'cout_revient': null,
      'groupe_taxe': 'A',
      'threshold': 1,
      'espece': null,
      'saisi_le': '2026-11-01T10:00:00.000000Z',
      'updated_at': '2026-11-09T10:00:00.000001Z',
      ...surcharge,
    };

    test(
      'un produit cohérent est absorbé avec un stock de 0, même si le serveur en annonce un',
      () async {
        final b = await poste('P2');
        serveur.produits['x'] = produitServeur({'stock': 77});

        await b.moteur.synchroniser();

        final p = (await b.ventes.chargerCatalogue()).firstWhere(
          (p) => p.nom == 'Produit du serveur',
        );
        expect(p.stock, 0, reason: 'le stock n\'est jamais absorbé');
      },
    );

    final cas = <String, Map<String, dynamic>>{
      'UUID invalide': {'id': 'pas-un-uuid'},
      'tarif nul': {'price': 0},
      'fourchette inversée': {'price': 100, 'price_max': 50},
      'sans désignation': {'name': '  '},
      'coût négatif': {'cout_revient': -5},
      'seuil négatif': {'threshold': -1},
    };
    cas.forEach((nom, surcharge) {
      test('refusé, rien d\'écrit : $nom', () async {
        final b = await poste('P2');
        serveur.produits['x'] = produitServeur(surcharge);

        final r = await b.moteur.synchroniser();

        expect(r.refuseesALaReception, 1);
        final noms = (await b.ventes.chargerCatalogue()).map((p) => p.nom);
        expect(noms, isNot(contains('Produit du serveur')));
        expect(noms, hasLength(14));
      });
    });

    test(
      'un produit connu garde SON stock quand le serveur change son prix',
      () async {
        final b = await poste('P2');
        await b.moteur.synchroniser();
        final p = await b.produit('Goliath mature');
        await (b.db.update(b.db.produitsVendables)
              ..where((x) => x.id.equals(p.id)))
            .write(const ProduitsVendablesCompanion(stock: Value(123)));
        serveur.produits[p.id] = produitServeur({
          'id': p.id,
          'sku': p.sku,
          'name': p.nom,
          'cat': p.categorie,
          'price': 9999,
          'stock': 999, // annonce du serveur : ignorée
          'unit': p.unite,
          'icon': p.icone,
          'espece': p.espece,
          'saisi_le': '2026-11-09T09:00:00.000000Z',
          'updated_at': serveur.instantServeur(),
        });

        await b.moteur.synchroniser();

        final apres = await b.produit('Goliath mature');
        expect(apres.prix, 9999);
        expect(apres.stock, 123);
      },
    );
  });

  test(
    'remise à zéro du serveur : les ventes partent, le catalogue reste',
    () async {
      final a = await poste('P1');
      await a.vendre('Goliath mature');
      await a.moteur.synchroniser();

      serveur.remettreAZero();
      final r = await a.moteur.synchroniser();

      expect(r.remiseAZero, isTrue);
      expect(await a.lesVentes(), isEmpty);
      expect(await a.db.select(a.db.lignesVente).get(), isEmpty);
      expect(
        (await a.ventes.chargerCatalogue()),
        hasLength(14),
        reason: 'une remise à zéro préserve le catalogue',
      );
    },
  );

  test(
    'hors ligne : la vente reste en attente et part à la reconnexion',
    () async {
      final a = await poste('P1');
      final ref = await a.vendre('Goliath mature');
      serveur.horsLigne = true;
      expect(
        (await a.moteur.synchroniser()).issue,
        IssueSynchronisation.horsLigne,
      );
      expect((await a.vente(ref)).syncStatus, 'pending');

      serveur.horsLigne = false;
      await a.moteur.synchroniser();

      expect((await a.vente(ref)).syncStatus, 'synced');
      expect(http.Client, isNotNull);
    },
  );
}
