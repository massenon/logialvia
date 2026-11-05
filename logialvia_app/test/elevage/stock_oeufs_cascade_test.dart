import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/fiche_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/entities/journee_elevage.dart';
import 'package:logialvia_app/elevage/domain/services/calcul_fiche_journaliere.dart';
import 'package:logialvia_app/elevage/domain/usecases/enregistrer_journee_usecase.dart';

/// Doc H2 §« Point de Vigilance Transversal » : le bug SRH/TS est le plus grave
/// et le plus silencieux de tout le projet, et sa répétition dans la
/// documentation est volontaire. Ces tests couvrent la persistance ET la
/// cascade, c'est-à-dire les deux bugs distincts qui avaient été corrigés
/// séparément côté web.
void main() {
  late AppDatabase db;
  late FicheElevageRepositoryDrift repository;
  late EnregistrerJourneeUseCase usecase;

  const config = ConfigurationsEspeces.pondeuses;

  setUp(() {
    db = AppDatabase.enMemoire();
    repository = FicheElevageRepositoryDrift(db, config);
    usecase = EnregistrerJourneeUseCase(repository, config);
  });

  tearDown(() async => db.close());

  Future<JourneeElevage?> jour(int j) =>
      repository.chargerJour(espece: 'pondeuses', date: DateTime(2026, 8, j));

  Future<Resultat<JourneeElevage>> saisir(
    int j, {
    int pondus = 0,
    int casses = 0,
    int sorties = 0,
    int achat = 0,
  }) {
    return usecase.executer(
      date: DateTime(2026, 8, j),
      mouvements: MouvementsJour(achat: achat),
      stockOeufs: SaisieStockOeufs(
        oeufsPondus: pondus,
        oeufsCasses: casses,
        sortiesPlateaux: sorties,
      ),
    );
  }

  group('Persistance des saisies — 1er bug historique', () {
    test(
      'les 3 saisies sont persistées, pas seulement les 3 résultats',
      () async {
        await saisir(1, pondus: 400, casses: 10, sorties: 3);

        final j1 = await jour(1);
        // Les entrees...
        expect(j1!.oeufsPondus, 400);
        expect(j1.oeufsCasses, 10);
        expect(j1.sortiesPlateaux, 3);
        // ...et les resultats.
        expect(j1.srh, 0);
        expect(j1.totalStock, 390);
        expect(j1.stockFinalOeufs, 300); // 390 − 3×30
      },
    );

    test('rouvrir un jour saisi retrouve ses valeurs d\'entrée', () async {
      await saisir(1, pondus: 250, casses: 5, sorties: 2);

      final relu = await jour(1);
      // Sans ces colonnes, le formulaire se serait rouvert vide et un
      // reenregistrement aurait ecrase le stock par des zeros.
      expect(relu!.oeufsPondus, 250);
      expect(relu.oeufsCasses, 5);
      expect(relu.sortiesPlateaux, 2);
    });
  });

  group('SRH = Stock Final de la veille — 2ᵉ bug historique', () {
    test(
      'le SRH du jour J+1 est le Stock Final de J, pas son Total Stock',
      () async {
        await saisir(1, pondus: 300, casses: 0, sorties: 5); // TS 300, SF 150
        await saisir(2, pondus: 200, casses: 0, sorties: 0);

        final j1 = await jour(1);
        final j2 = await jour(2);

        expect(j1!.totalStock, 300);
        expect(j1.stockFinalOeufs, 150);

        // Le coeur de la regle.
        expect(j2!.srh, 150);
        expect(j2.srh, isNot(j1.totalStock));
        expect(j2.totalStock, 350);
        expect(j2.stockFinalOeufs, 350);
      },
    );

    test('chaîne de 5 jours avec sorties variables', () async {
      await saisir(1, pondus: 300, casses: 5, sorties: 0);
      await saisir(2, pondus: 280, casses: 0, sorties: 4);
      await saisir(3, pondus: 310, casses: 10, sorties: 0);
      await saisir(4, pondus: 290, casses: 2, sorties: 6);
      await saisir(5, pondus: 305, casses: 0, sorties: 3);

      final stocks = <int>[];
      for (var j = 1; j <= 5; j++) {
        stocks.add((await jour(j))!.stockFinalOeufs!);
      }
      expect(stocks, [295, 455, 755, 863, 1078]);
    });

    test('un jour sans sortie fait coïncider TS et Stock Final — '
        'c\'est ce qui masquait le bug', () async {
      await saisir(1, pondus: 200, casses: 0, sorties: 0);
      final j1 = await jour(1);
      expect(j1!.totalStock, j1.stockFinalOeufs);
    });
  });

  group('Cascade sur le stock d\'œufs — Doc 05 §5, vigilance n°2', () {
    setUp(() async {
      await saisir(1, pondus: 300, casses: 0, sorties: 0); // SF 300
      await saisir(2, pondus: 200, casses: 0, sorties: 5); // SF 350
      await saisir(3, pondus: 100, casses: 0, sorties: 0); // SF 450
    });

    test('état initial cohérent', () async {
      expect((await jour(1))!.stockFinalOeufs, 300);
      expect((await jour(2))!.stockFinalOeufs, 350);
      expect((await jour(3))!.stockFinalOeufs, 450);
    });

    test(
      'modifier un jour passé recalcule SRH/TS/Stock Final des jours suivants, '
      'pas seulement les effectifs',
      () async {
        // Correction du jour 1 : 300 -> 500 œufs pondus.
        await saisir(1, pondus: 500, casses: 0, sorties: 0);

        expect((await jour(1))!.stockFinalOeufs, 500);

        final j2 = await jour(2);
        // Si la cascade ne recalculait que les effectifs, le SRH du jour 2
        // serait resté a 300 — l'incoherence silencieuse du bug historique.
        expect(j2!.srh, 500);
        expect(j2.totalStock, 700);
        expect(j2.stockFinalOeufs, 550);

        final j3 = await jour(3);
        expect(j3!.srh, 550);
        expect(j3.stockFinalOeufs, 650);
      },
    );

    test('la cascade préserve les saisies des jours suivants', () async {
      await saisir(1, pondus: 500, casses: 0, sorties: 0);

      final j2 = await jour(2);
      expect(j2!.oeufsPondus, 200); // saisie d'origine intacte
      expect(j2.sortiesPlateaux, 5);
    });

    test('la cascade s\'arrête au premier jour non saisi', () async {
      await repository.enregistrerJour(
        JourneeElevage.vierge(
          espece: 'pondeuses',
          date: DateTime(2026, 8, 4),
          nombreCategories: 4,
        ),
      );
      await saisir(5, pondus: 50, casses: 0, sorties: 0);
      final avant = (await jour(5))!.stockFinalOeufs;

      await saisir(1, pondus: 500, casses: 0, sorties: 0);

      // Le jour 5, isole derriere un trou, n'est pas touche.
      expect((await jour(5))!.stockFinalOeufs, avant);
    });

    test('une baisse ne produit jamais de stock négatif', () async {
      await saisir(1, pondus: 0, casses: 0, sorties: 0);

      for (var j = 1; j <= 3; j++) {
        final journee = await jour(j);
        expect(
          journee!.stockFinalOeufs,
          greaterThanOrEqualTo(0),
          reason: 'jour $j',
        );
      }
    });
  });

  group('Validations du formulaire Pondeuses — Doc H2', () {
    test('refuse plus d\'œufs cassés que pondus', () async {
      final resultat = await saisir(1, pondus: 100, casses: 150);

      expect(resultat, isA<Echec<JourneeElevage>>());
      expect(await jour(1), isNull); // rien n'a été écrit
    });

    test('accepte cassés == pondus', () async {
      expect(
        await saisir(1, pondus: 100, casses: 100),
        isA<Succes<JourneeElevage>>(),
      );
      expect((await jour(1))!.totalStock, 0);
    });

    test('refuse des valeurs négatives', () async {
      expect(await saisir(1, pondus: -1), isA<Echec<JourneeElevage>>());
      expect(await saisir(1, casses: -1), isA<Echec<JourneeElevage>>());
      expect(await saisir(1, sorties: -1), isA<Echec<JourneeElevage>>());
    });
  });

  group('Les 4 catégories des Pondeuses coexistent avec le stock d\'œufs', () {
    test(
      'un achat alimente Poussin Ponte et le stock reste cohérent',
      () async {
        await saisir(1, achat: 100, pondus: 300, casses: 0, sorties: 0);

        final j1 = await jour(1);
        expect(j1!.effectif, 100);
        expect(j1.effectifsParCategorie, hasLength(4));
        expect(j1.effectifsParCategorie[0], 100); // Poussin Ponte
        expect(j1.effectifsParCategorie[3], 0); // Pondeuse
        expect(j1.stockFinalOeufs, 300);
      },
    );

    test('une espèce à 3 catégories n\'écrit aucun stock d\'œufs', () async {
      const goliaths = ConfigurationsEspeces.goliaths;
      final repoGoliaths = FicheElevageRepositoryDrift(db, goliaths);
      final usecaseGoliaths = EnregistrerJourneeUseCase(repoGoliaths, goliaths);

      await usecaseGoliaths.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: 50),
      );

      final journee = await repoGoliaths.chargerJour(
        espece: 'goliaths',
        date: DateTime(2026, 8, 1),
      );
      expect(journee!.stockFinalOeufs, isNull);
      expect(journee.oeufsPondus, isNull);
    });
  });
}
