import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/commercial/data/repositories/clients_repository_drift.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/commercial/domain/services/numerotation_pieces.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';

/// Palier 3b — références à préfixe de poste (DV-21), liaison au client,
/// remise « à envoyer » après toute modification.
void main() {
  late AppDatabase db;
  late EventBus bus;
  late VentesRepositoryDrift repository;
  late PreferencesPosteRepository preferences;
  late ProduitVendable produit;

  final annee = DateTime.now().year;
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    bus = EventBus();
    repository = VentesRepositoryDrift(db, bus);
    preferences = PreferencesPosteRepository(db);
    produit = (await repository.chargerCatalogue()).firstWhere(
      (p) => p.nom == 'Goliath mature',
    );
  });

  tearDown(() async {
    bus.dispose();
    await db.close();
  });

  Future<String> vendre({
    String client = 'Client Comptant',
    double qte = 1,
  }) async {
    final r = await repository.enregistrerVente(
      client: client,
      mode: ModeReglement.especes,
      statut: StatutVente.payee,
      montantPaye: produit.prix * qte,
      panier: [
        LignePanier(
          produitId: produit.id,
          nom: produit.nom,
          montantGlobal: produit.prix * qte,
          quantite: qte,
          stockDisponible: produit.stock,
          prixIndicatif: produit.prix,
          prixIndicatifMax: produit.prixMax,
          espece: produit.espece,
          unite: produit.unite,
        ),
      ],
    );
    return r.vente.reference;
  }

  Future<VenteRow> ligneVente(String ref) =>
      (db.select(db.ventes)..where((v) => v.ref.equals(ref))).getSingle();

  group('NumerotationPieces', () {
    test('préfixe de poste, ou ancien format sans code', () {
      expect(NumerotationPieces.prefixeVente(2026, 'P2'), 'V-P2-2026-');
      expect(NumerotationPieces.prefixeVente(2026, null), 'V-2026-');
      expect(NumerotationPieces.prefixeVente(2026, ''), 'V-2026-');
    });

    test('séquence sur 3 chiffres au moins, et au-delà', () {
      expect(NumerotationPieces.composer('V-P2-2026-', 1), 'V-P2-2026-001');
      expect(NumerotationPieces.composer('V-P2-2026-', 1000), 'V-P2-2026-1000');
    });

    test('lit la séquence d\'une référence de CE préfixe seulement', () {
      expect(NumerotationPieces.sequence('V-P2-2026-014', 'V-P2-2026-'), 14);
      expect(
        NumerotationPieces.sequence('V-P12-2026-014', 'V-P1-2026-'),
        isNull,
      );
      expect(NumerotationPieces.sequence('V-2026-014', 'V-P2-2026-'), isNull);
      expect(
        NumerotationPieces.sequence('V-P2-2026-abc', 'V-P2-2026-'),
        isNull,
      );
    });
  });

  group('Références des ventes', () {
    test('poste jamais appairé : ancien format V-AAAA-NNN', () async {
      expect(await vendre(), 'V-$annee-001');
      expect(await vendre(), 'V-$annee-002');
    });

    test(
      'poste appairé P2 : V-P2-AAAA-NNN, séquence propre à ce préfixe',
      () async {
        await preferences.memoriserAppairage(
          codePoste: 'P2',
          compte: 'g',
          le: DateTime.now(),
        );

        expect(await vendre(), 'V-P2-$annee-001');
        expect(await vendre(), 'V-P2-$annee-002');
      },
    );

    test(
      'les anciennes références restent valides, la séquence repart à 001 avec le code',
      () async {
        expect(await vendre(), 'V-$annee-001');
        expect(await vendre(), 'V-$annee-002');
        await preferences.memoriserAppairage(
          codePoste: 'P2',
          compte: 'g',
          le: DateTime.now(),
        );

        expect(await vendre(), 'V-P2-$annee-001');
        final anciennes = await (db.select(
          db.ventes,
        )..where((v) => v.ref.like('V-$annee-%'))).get();
        expect(
          anciennes,
          hasLength(2),
          reason: 'aucune renumérotation rétroactive (DV-21)',
        );
      },
    );

    test('deux postes ne produisent jamais la même référence', () async {
      final autre = AppDatabase.enMemoire();
      addTearDown(autre.close);
      await SeedInitial(autre).executer();
      final repoAutre = VentesRepositoryDrift(autre, EventBus());
      final produitAutre = (await repoAutre.chargerCatalogue()).first;
      await PreferencesPosteRepository(
        autre,
      ).memoriserAppairage(codePoste: 'P3', compte: 'g', le: DateTime.now());
      await preferences.memoriserAppairage(
        codePoste: 'P2',
        compte: 'g',
        le: DateTime.now(),
      );

      final a = await vendre();
      final b = (await repoAutre.enregistrerVente(
        client: 'X',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: produitAutre.prix,
        panier: [
          LignePanier(
            produitId: produitAutre.id,
            nom: produitAutre.nom,
            montantGlobal: produitAutre.prix,
            quantite: 1,
            stockDisponible: produitAutre.stock,
            prixIndicatif: produitAutre.prix,
            prixIndicatifMax: produitAutre.prixMax,
            espece: produitAutre.espece,
            unite: produitAutre.unite,
          ),
        ],
      )).vente.reference;

      expect(a, 'V-P2-$annee-001');
      expect(b, 'V-P3-$annee-001');
      expect(a, isNot(b));
    });

    test(
      'le code survit à la déconnexion : le poste ne repasse pas au format sans code',
      () async {
        await preferences.memoriserAppairage(
          codePoste: 'P2',
          compte: 'g',
          le: DateTime.now(),
        );
        await vendre();
        await preferences.oublierAppairage();

        expect(await preferences.codePoste(), isNull);
        expect(await preferences.codeAttribue(), 'P2');
        expect(await vendre(), 'V-P2-$annee-002');
      },
    );

    test(
      'P1 et P12 ne se mélangent pas (le préfixe se termine par un tiret)',
      () async {
        await preferences.memoriserAppairage(
          codePoste: 'P12',
          compte: 'g',
          le: DateTime.now(),
        );
        await vendre();
        await preferences.memoriserAppairage(
          codePoste: 'P1',
          compte: 'g',
          le: DateTime.now(),
        );

        expect(await vendre(), 'V-P1-$annee-001');
      },
    );
  });

  group('Identité synchronisée', () {
    test(
      'chaque vente a son UUID, à envoyer, avec un instant de saisie',
      () async {
        final ref = await vendre();
        final v = await ligneVente(ref);

        expect(v.id, matches(uuid));
        expect(v.syncStatus, 'pending');
        expect(DateTime.parse(v.updatedAt).isUtc, isTrue);
      },
    );

    test(
      'annuler une vente la remet à envoyer, avec un instant plus récent',
      () async {
        final ref = await vendre();
        await db
            .update(db.ventes)
            .write(const VentesCompanion(syncStatus: Value('synced')));
        final avant = (await ligneVente(ref)).updatedAt;
        await Future<void>.delayed(const Duration(milliseconds: 3));

        await repository.annulerVente(
          reference: ref,
          motif: 'Erreur de saisie',
        );

        final v = await ligneVente(ref);
        expect(v.syncStatus, 'pending');
        expect(
          DateTime.parse(v.updatedAt).isAfter(DateTime.parse(avant)),
          isTrue,
        );
      },
    );

    test('encaisser le reste d\'une avance la remet à envoyer', () async {
      final r = await repository.enregistrerVente(
        client: 'Mama Rita',
        mode: ModeReglement.especes,
        statut: StatutVente.avance,
        montantPaye: 1000,
        panier: [
          LignePanier(
            produitId: produit.id,
            nom: produit.nom,
            montantGlobal: produit.prix,
            quantite: 1,
            stockDisponible: produit.stock,
            prixIndicatif: produit.prix,
            prixIndicatifMax: produit.prixMax,
            espece: produit.espece,
            unite: produit.unite,
          ),
        ],
      );
      await db
          .update(db.ventes)
          .write(const VentesCompanion(syncStatus: Value('synced')));
      await Future<void>.delayed(const Duration(milliseconds: 3));

      await repository.enregistrerPaiement(
        reference: r.vente.reference,
        montant: 500,
      );

      expect((await ligneVente(r.vente.reference)).syncStatus, 'pending');
    });
  });

  group('Liaison au client (homonymes)', () {
    test(
      'un seul client de ce nom : la vente lui est rattachée (casse et espaces ignorés)',
      () async {
        final c = await ClientsRepositoryDrift(
          db,
        ).creerClient(nom: 'DOSSOU Félicité');

        final ref = await vendre(client: '  dossou félicité ');

        expect((await ligneVente(ref)).clientId, c.id);
      },
    );

    test(
      'deux clients homonymes : on ne devine pas, client_id reste vide',
      () async {
        final repo = ClientsRepositoryDrift(db);
        await repo.creerClient(nom: 'Mama Rita');
        await repo.creerClient(nom: 'Mama Rita');

        final ref = await vendre(client: 'Mama Rita');

        final v = await ligneVente(ref);
        expect(v.clientId, isNull);
        expect(
          v.client,
          'Mama Rita',
          reason: 'le nom saisi est conservé tel quel',
        );
      },
    );

    test('nom libre (« Client Comptant ») : aucun client', () async {
      await ClientsRepositoryDrift(db).creerClient(nom: 'DOSSOU');
      expect((await ligneVente(await vendre())).clientId, isNull);
    });
  });
}
