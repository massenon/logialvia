// Meme famille de piege que le conflit `Column` de Doc K3 §6 : Drift et
// `flutter_test` exportent tous deux `isNull`/`isNotNull` (une expression SQL
// d'un cote, un matcher de l'autre). Sans ce `hide`, tout fichier de test qui
// importe Drift echoue a la compilation.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/approvisionnement/data/seed/intrants_seeder.dart';
import 'package:logialvia_app/commercial/data/seed/catalogue_seeder.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/router/navigation_model.dart';
import 'package:logialvia_app/pilotage/data/repositories/tableau_bord_repository_drift.dart';

void main() {
  late AppDatabase db;
  late TableauBordRepositoryDrift repository;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    repository = TableauBordRepositoryDrift(db);
  });

  tearDown(() async => db.close());

  group('Seed initial (données réelles du prototype)', () {
    test(
      'le catalogue contient les 14 produits de logialvia-store.js',
      () async {
        final produits = await db.select(db.produitsVendables).get();
        expect(produits, hasLength(14));
        expect(
          produits.map((p) => p.name),
          containsAll(<String>[
            'Poussin d\'un jour',
            'Goliath mature',
            'Pintade mature',
            'Poisson-chat vif (kg)',
          ]),
        );

        // Valeurs de reference etablies transversalement (Doc F2, section
        // Coherence Transversale) : Goliath mature = 31, Pintade mature = 28.
        final goliath = produits.firstWhere((p) => p.name == 'Goliath mature');
        final pintade = produits.firstWhere((p) => p.name == 'Pintade mature');
        expect(goliath.stock, 31);
        expect(pintade.stock, 28);
        expect(goliath.priceMax, 8500);
      },
    );

    test('les 6 intrants sont peuplés avec leurs seuils réels', () async {
      final intrants = await db.select(db.intrants).get();
      expect(intrants, hasLength(6));

      final mais = intrants.firstWhere((i) => i.code == 'INT-001');
      expect(mais.name, 'Maïs');
      expect(mais.stock, 18);
      expect(mais.threshold, 25);
    });

    test('seuls les 5 modules basculables existent, tous désactivés', () async {
      final modules = await db.select(db.modulesActifs).get();

      expect(modules, hasLength(5));
      expect(modules.every((m) => m.isActif == false), isTrue);
      expect(modules.map((m) => m.moduleId).toSet(), {
        'pisciculture',
        'cuniculture',
        'aviculture_classique',
        'heliciculture',
        'bovins',
      });
      // Goliaths et Pintades n'ont volontairement aucune ligne (Doc I2 §2).
      expect(
        modules.map((m) => m.moduleId),
        isNot(anyElement(anyOf('goliaths', 'pintades'))),
      );
    });

    test('les seeders sont idempotents', () async {
      await SeedInitial(db).executer();
      await SeedInitial(db).executer();

      expect(await db.select(db.produitsVendables).get(), hasLength(14));
      expect(await db.select(db.intrants).get(), hasLength(6));
      expect(await db.select(db.modulesActifs).get(), hasLength(5));
    });

    test('un catalogue déjà modifié n\'est jamais réécrasé', () async {
      await (db.update(db.produitsVendables)
            ..where((p) => p.name.equals('Goliath mature')))
          .write(const ProduitsVendablesCompanion(stock: Value(999)));

      await CatalogueSeeder(db).executer();

      final goliath = await (db.select(
        db.produitsVendables,
      )..where((p) => p.name.equals('Goliath mature'))).getSingle();
      expect(goliath.stock, 999);
    });
  });

  group('KPI « Stock Critique » — calcul réel, pas recopie du HTML', () {
    test('un seul intrant est sous son seuil : le Maïs', () async {
      final alertes = await repository.articlesSousSeuil();
      final intrantsEnAlerte = alertes.where((a) => a.estIntrant).toList();

      // dashboard.html l.162-163 affiche « 1 intrant / Maïs sous le seuil
      // d'alerte ». Ce resultat sort ici d'une requete sur les donnees seedees,
      // il n'est pas recopie du HTML.
      expect(intrantsEnAlerte, hasLength(1));
      expect(intrantsEnAlerte.single.libelle, 'Maïs');
      expect(intrantsEnAlerte.single.stock, 18);
      expect(intrantsEnAlerte.single.seuil, 25);
    });

    test('aucun produit vendable n\'est sous son seuil au départ', () async {
      final alertes = await repository.articlesSousSeuil();
      expect(alertes.where((a) => !a.estIntrant), isEmpty);
    });

    test('un intrant réapprovisionné sort de la liste d\'alerte', () async {
      await (db.update(db.intrants)..where((i) => i.code.equals('INT-001')))
          .write(const IntrantsCompanion(stock: Value(60)));

      final alertes = await repository.articlesSousSeuil();
      expect(alertes.where((a) => a.estIntrant), isEmpty);
    });

    test(
      'le seuil est inclusif : stock == seuil déclenche l\'alerte',
      () async {
        await (db.update(db.intrants)..where((i) => i.code.equals('INT-002')))
            .write(const IntrantsCompanion(stock: Value(15))); // seuil = 15

        final alertes = await repository.articlesSousSeuil();
        expect(
          alertes.where((a) => a.estIntrant).map((a) => a.libelle),
          containsAll(<String>['Maïs', 'Soja']),
        );
      },
    );
  });

  group('KPI sans données — jamais un chiffre inventé', () {
    test(
      'chiffre d\'affaires à zéro tant qu\'aucune vente n\'existe',
      () async {
        final ca = await repository.chiffreAffaires(
          debut: DateTime(2020),
          fin: DateTime(2030),
        );
        expect(ca.total, 0);
        expect(ca.avicole, 0);
        expect(ca.commerceAnnexe, 0);
      },
    );

    test('encours client vide', () async {
      final encours = await repository.encoursClients();
      expect(encours.montant, 0);
      expect(encours.nombreVentes, 0);
    });

    test('effectif du cheptel à zéro sans journée saisie', () async {
      expect(await repository.effectifCheptel({'goliaths', 'pintades'}), 0);
    });

    test(
      'taux d\'éclosion à null (et non 0) sans aucune éclosion enregistrée',
      () async {
        final stats = await repository.statistiquesCouveuse();
        expect(stats.cyclesEnCours, 0);
        // Une moyenne sur zero echantillon n'existe pas : elle ne vaut pas 0.
        expect(stats.tauxEclosionMoyen, isNull);
        expect(stats.eclosionImminente, isNull);
      },
    );

    test('la courbe 6 mois renvoie bien 6 points, tous à zéro', () async {
      final points = await repository.evolutionMensuelle();
      expect(points, hasLength(6));
      expect(points.every((p) => p.chiffreAffaires == 0), isTrue);
      expect(points.every((p) => p.depenses == 0), isTrue);
    });
  });

  group('Chiffre d\'affaires — ventilation par activité', () {
    setUp(() async {
      final produits = await db.select(db.produitsVendables).get();
      final goliath = produits.firstWhere((p) => p.name == 'Goliath mature');
      final sac = produits.firstWhere((p) => p.name == 'Sac d\'écolier');

      await db
          .into(db.ventes)
          .insert(
            VentesCompanion.insert(
              ref: 'V-2026-001',
              client: 'Client Comptant',
              dateVente: DateTime(2026, 8, 10),
              mode: 'Espèces',
              status: 'Payée',
              total: 8000,
              paye: 8000,
            ),
          );
      await db
          .into(db.lignesVente)
          .insert(
            LignesVenteCompanion.insert(
              venteRef: 'V-2026-001',
              produitId: goliath.id,
              name: goliath.name,
              qte: 1,
              pu: 6000,
            ),
          );
      await db
          .into(db.lignesVente)
          .insert(
            LignesVenteCompanion.insert(
              venteRef: 'V-2026-001',
              produitId: sac.id,
              name: sac.name,
              qte: 1,
              pu: 2000,
            ),
          );
    });

    test('sépare Avicole et Commerce Annexe', () async {
      final ca = await repository.chiffreAffaires(
        debut: DateTime(2026, 8, 1),
        fin: DateTime(2026, 8, 31),
      );

      expect(ca.total, 8000);
      expect(ca.avicole, 6000);
      expect(ca.commerceAnnexe, 2000);
    });

    test('une vente annulée est exclue du chiffre d\'affaires', () async {
      await (db.update(db.ventes)..where((v) => v.ref.equals('V-2026-001')))
          .write(const VentesCompanion(status: Value('Annulée')));

      final ca = await repository.chiffreAffaires(
        debut: DateTime(2026, 8, 1),
        fin: DateTime(2026, 8, 31),
      );
      expect(ca.total, 0);
    });

    test('une vente hors période est exclue', () async {
      final ca = await repository.chiffreAffaires(
        debut: DateTime(2026, 9, 1),
        fin: DateTime(2026, 9, 30),
      );
      expect(ca.total, 0);
    });

    test('les meilleures ventes sont classées par CA décroissant', () async {
      final top = await repository.meilleuresVentes(
        debut: DateTime(2026, 8, 1),
        fin: DateTime(2026, 8, 31),
      );

      expect(top, hasLength(2));
      expect(top.first.produit, 'Goliath mature');
      expect(top.first.chiffreAffaires, 6000);
      expect(top.first.activite, 'Avicole');
      expect(top.last.activite, 'Commerce');
    });
  });

  group('Encours client', () {
    test('une vente en avance alimente le solde restant dû', () async {
      await db
          .into(db.ventes)
          .insert(
            VentesCompanion.insert(
              ref: 'V-2026-002',
              client: 'AGOSSOU Prudence',
              dateVente: DateTime(2026, 8, 11),
              mode: 'Avance (Solde Restant Dû)',
              status: 'Avance',
              total: 10000,
              paye: 3500,
            ),
          );

      final encours = await repository.encoursClients();
      expect(encours.nombreVentes, 1);
      expect(encours.montant, 6500);
    });
  });

  group('Recensement d\'une filière', () {
    test(
      'renvoie une carte vide mais presente si aucune journée n\'est saisie',
      () async {
        final recensement = await repository.recensementFiliere('goliaths');
        expect(recensement, isNotNull);
        expect(recensement!.aDesDonnees, isFalse);
        expect(recensement.effectif, 0);
        expect(recensement.libelleJeunes, 'Goliathaux');
        expect(recensement.route, '/elevage/goliaths');
      },
    );

    // Regression : `/elevage/poulets` etait construit a partir du code espece
    // et levait « GoException: no routes for location » au clic.
    test(
      'chaque filière pointe vers une route réellement déclarée',
      () async {
        final routesDeclarees = {
          for (final groupe in NavigationModel.groupes)
            for (final entree in groupe.entrees) entree.route,
        };
        for (final espece in const [
          'goliaths',
          'pintades',
          'lapins',
          'poulets',
          'pondeuses',
          'poissons-chats',
        ]) {
          final recensement = await repository.recensementFiliere(espece);
          expect(
            routesDeclarees,
            contains(recensement!.route),
            reason: 'Filière $espece',
          );
        }
        expect(
          (await repository.recensementFiliere('poulets'))!.route,
          '/elevage/poulets-pondeuses',
        );
      },
    );

    test(
      'lit la dernière journée saisie et ignore les jours non saisis',
      () async {
        await db
            .into(db.ficheJournee)
            .insert(
              FicheJourneeCompanion.insert(
                espece: 'goliaths',
                date: DateTime(2026, 8, 10),
                effectif: const Value(94),
                effCat2Day: const Value(63),
                effCat3Day: const Value(31),
                isRecorded: const Value(true),
              ),
            );
        // Jour posterieur mais NON saisi : ne doit pas etre retenu.
        await db
            .into(db.ficheJournee)
            .insert(
              FicheJourneeCompanion.insert(
                espece: 'goliaths',
                date: DateTime(2026, 8, 11),
                effectif: const Value(0),
              ),
            );

        final recensement = await repository.recensementFiliere('goliaths');
        expect(recensement!.aDesDonnees, isTrue);
        expect(recensement.effectif, 94);
        expect(recensement.effectifMatures, 31);
        expect(recensement.effectifJeunes, 63);
      },
    );

    test('effectif du cheptel = somme des filières actives', () async {
      await db
          .into(db.ficheJournee)
          .insert(
            FicheJourneeCompanion.insert(
              espece: 'goliaths',
              date: DateTime(2026, 8, 10),
              effectif: const Value(94),
              isRecorded: const Value(true),
            ),
          );
      await db
          .into(db.ficheJournee)
          .insert(
            FicheJourneeCompanion.insert(
              espece: 'pintades',
              date: DateTime(2026, 8, 10),
              effectif: const Value(92),
              isRecorded: const Value(true),
            ),
          );
      // Filiere desactivee : ne doit pas etre comptee (Doc I2 §3).
      await db
          .into(db.ficheJournee)
          .insert(
            FicheJourneeCompanion.insert(
              espece: 'lapins',
              date: DateTime(2026, 8, 10),
              effectif: const Value(410),
              isRecorded: const Value(true),
            ),
          );

      expect(
        await repository.effectifCheptel({'goliaths', 'pintades'}),
        186, // 94 + 92
      );
    });
  });

  group('Couveuse', () {
    test('détecte une éclosion imminente à J+21 moins de 3 jours', () async {
      await db
          .into(db.cycleCouveuse)
          .insert(
            CycleCouveuseCompanion.insert(
              codeIncubation: 'C-2026-014',
              bandeReproducteurs: const Value('Bande A'),
              // Incubee il y a 19 jours -> eclosion prevue dans 2 jours.
              dateIncubation: DateTime.now().subtract(const Duration(days: 19)),
              oeufsCouves: 170,
              statut: 'En Incubation',
            ),
          );

      final stats = await repository.statistiquesCouveuse();
      expect(stats.cyclesEnCours, 1);
      expect(stats.oeufsCharges, 170);
      expect(stats.eclosionImminente, 'C-2026-014');
    });

    test(
      'la durée d\'incubation dépend de l\'espèce : une pintade à J+19 '
      'n\'est PAS imminente (27 j), un goliath au même jour l\'est (21 j)',
      () async {
        // Meme date de chargement, deux especes : seul le goliath doit alerter.
        final chargement = DateTime.now().subtract(const Duration(days: 19));

        await db
            .into(db.cycleCouveuse)
            .insert(
              CycleCouveuseCompanion.insert(
                codeIncubation: 'C-2026-100',
                espece: const Value('pintade'),
                bandeReproducteurs: const Value('Bande P'),
                dateIncubation: chargement,
                oeufsCouves: 150,
                statut: 'En Incubation',
              ),
            );

        var stats = await repository.statistiquesCouveuse();
        // Pintade : eclosion a J+27, donc dans 8 jours -> pas imminente.
        expect(stats.eclosionImminente, isNull);

        await db
            .into(db.cycleCouveuse)
            .insert(
              CycleCouveuseCompanion.insert(
                codeIncubation: 'C-2026-101',
                espece: const Value('goliath'),
                bandeReproducteurs: const Value('Bande G'),
                dateIncubation: chargement,
                oeufsCouves: 150,
                statut: 'En Incubation',
              ),
            );

        stats = await repository.statistiquesCouveuse();
        // Goliath : eclosion a J+21, donc dans 2 jours -> imminente.
        expect(stats.eclosionImminente, 'C-2026-101');
      },
    );

    test('un cycle récent n\'est pas signalé comme imminent', () async {
      await db
          .into(db.cycleCouveuse)
          .insert(
            CycleCouveuseCompanion.insert(
              codeIncubation: 'C-2026-015',
              bandeReproducteurs: const Value('Bande B'),
              dateIncubation: DateTime.now(),
              oeufsCouves: 100,
              statut: 'En Incubation',
            ),
          );

      final stats = await repository.statistiquesCouveuse();
      expect(stats.eclosionImminente, isNull);
    });

    test('le taux d\'éclosion moyen se calcule sur les cycles éclos', () async {
      await db
          .into(db.cycleCouveuse)
          .insert(
            CycleCouveuseCompanion.insert(
              codeIncubation: 'C-2026-010',
              bandeReproducteurs: const Value('Bande A'),
              dateIncubation: DateTime(2026, 6, 1),
              oeufsCouves: 100,
              poussinsNes: const Value(84),
              statut: 'Éclosion Effectuée',
            ),
          );

      final stats = await repository.statistiquesCouveuse();
      expect(stats.tauxEclosionMoyen, 84);
      expect(stats.cyclesEnCours, 0);
    });
  });

  group('Intrants — cohérence du seeder', () {
    test('les seuils du seeder correspondent au prototype', () {
      final mais = IntrantsSeeder.intrants.firstWhere(
        (i) => i.code == 'INT-001',
      );
      expect(mais.stock, lessThan(mais.threshold)); // c'est bien une alerte

      // Les 5 autres intrants sont au-dessus de leur seuil.
      final autres = IntrantsSeeder.intrants.where((i) => i.code != 'INT-001');
      expect(autres.every((i) => i.stock > i.threshold), isTrue);
    });
  });
}
