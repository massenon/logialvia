import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/fiche_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/entities/journee_elevage.dart';
import 'package:logialvia_app/elevage/domain/services/calcul_fiche_journaliere.dart';
import 'package:logialvia_app/elevage/domain/usecases/enregistrer_journee_usecase.dart';

void main() {
  late AppDatabase db;
  late FicheElevageRepositoryDrift repository;
  late EnregistrerJourneeUseCase usecase;

  const config = ConfigurationsEspeces.goliaths;

  setUp(() {
    db = AppDatabase.enMemoire();
    repository = FicheElevageRepositoryDrift(db, config);
    usecase = EnregistrerJourneeUseCase(repository, config);
  });

  tearDown(() async => db.close());

  Future<JourneeElevage?> jour(int j) =>
      repository.chargerJour(espece: 'goliaths', date: DateTime(2026, 8, j));

  group('Enregistrement d\'une journée', () {
    test('persiste réellement en base — pas seulement un toast', () async {
      final resultat = await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: 50, ne: 10),
      );

      expect(resultat, isA<Succes<JourneeElevage>>());

      // Verification par relecture en base, pas par la valeur retournee :
      // c'est le pattern `validateSale()` que le Master Prompt §2.3 interdit.
      final relu = await jour(1);
      expect(relu, isNotNull);
      expect(relu!.isRecorded, isTrue);
      expect(relu.achat, 50);
      expect(relu.effectif, 60);
      expect(relu.effectifsParCategorie[0], 60); // tout sur la catégorie jeune
    });

    test('l\'effectif est recalculé, jamais repris de la saisie', () async {
      await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: 100),
      );
      await usecase.executer(
        date: DateTime(2026, 8, 2),
        mouvements: const MouvementsJour(mortsParCategorie: [10, 0, 0]),
      );

      final j2 = await jour(2);
      expect(j2!.effectif, 90);
      expect(j2.effectifsParCategorie[0], 90);
    });

    test('le poids et le traitement sont persistés', () async {
      await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: 10),
        poidsGeneralG: 28000,
        traitementObs: 'Vaccin Newcastle administré',
        traitementValide: true,
      );

      final j1 = await jour(1);
      expect(j1!.poidsGeneralG, 28000);
      expect(j1.traitementObs, 'Vaccin Newcastle administré');
      expect(j1.traitementValide, isTrue);
    });

    test('réenregistrer le même jour met à jour, ne duplique pas', () async {
      await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: 50),
      );
      await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: 80),
      );

      final mois = await repository.chargerMois(
        espece: 'goliaths',
        annee: 2026,
        mois: 8,
      );
      expect(mois, hasLength(1)); // UNIQUE(espece, date) respecté
      expect(mois.single.effectif, 80);
    });

    test('un mouvement négatif est refusé avant tout calcul', () async {
      final resultat = await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: -5),
      );

      expect(resultat, isA<Echec<JourneeElevage>>());
      expect(await jour(1), isNull); // rien n'a été écrit
    });
  });

  group('Continuité entre journées', () {
    test('chaque jour part de l\'effectif du jour précédent', () async {
      await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: 100),
      );
      await usecase.executer(
        date: DateTime(2026, 8, 2),
        mouvements: const MouvementsJour(ne: 20),
      );
      await usecase.executer(
        date: DateTime(2026, 8, 3),
        mouvements: const MouvementsJour(mortsParCategorie: [5, 0, 0]),
      );

      expect((await jour(1))!.effectif, 100);
      expect((await jour(2))!.effectif, 120);
      expect((await jour(3))!.effectif, 115);
    });

    test('la continuité franchit le changement de mois (BR-ELV-006)', () async {
      await usecase.executer(
        date: DateTime(2026, 8, 31),
        mouvements: const MouvementsJour(achat: 200),
      );
      await usecase.executer(
        date: DateTime(2026, 9, 1),
        mouvements: const MouvementsJour(mortsParCategorie: [3, 0, 0]),
      );

      final septembre = await repository.chargerJour(
        espece: 'goliaths',
        date: DateTime(2026, 9, 1),
      );
      // Reprend bien les 200 du 31 août, pas une base remise à zéro.
      expect(septembre!.effectif, 197);
    });

    test('un jour non saisi n\'est pas pris comme base', () async {
      await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: 100),
      );
      // Jour 2 explicitement non saisi, écrit directement en base.
      await repository.enregistrerJour(
        JourneeElevage.vierge(
          espece: 'goliaths',
          date: DateTime(2026, 8, 2),
          nombreCategories: 3,
        ),
      );
      await usecase.executer(
        date: DateTime(2026, 8, 3),
        mouvements: const MouvementsJour(ne: 10),
      );

      // La base du jour 3 est le jour 1 (100), pas le jour 2 vierge (0).
      expect((await jour(3))!.effectif, 110);
    });
  });

  group('Cascade — Doc 05 §5, le point le plus risqué', () {
    setUp(() async {
      await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: 100),
      );
      await usecase.executer(
        date: DateTime(2026, 8, 2),
        mouvements: const MouvementsJour(mortsParCategorie: [2, 0, 0]),
      );
      await usecase.executer(
        date: DateTime(2026, 8, 3),
        mouvements: const MouvementsJour(mortsParCategorie: [3, 0, 0]),
      );
      await usecase.executer(
        date: DateTime(2026, 8, 4),
        mouvements: const MouvementsJour(ne: 5),
      );
    });

    test('état initial cohérent', () async {
      expect((await jour(1))!.effectif, 100);
      expect((await jour(2))!.effectif, 98);
      expect((await jour(3))!.effectif, 95);
      expect((await jour(4))!.effectif, 100);
    });

    test(
      'modifier un jour passé recalcule TOUS les jours suivants déjà saisis',
      () async {
        // On corrige le jour 1 : 100 -> 150 achetés.
        await usecase.executer(
          date: DateTime(2026, 8, 1),
          mouvements: const MouvementsJour(achat: 150),
        );

        expect((await jour(1))!.effectif, 150);
        expect((await jour(2))!.effectif, 148); // +50 propagé
        expect((await jour(3))!.effectif, 145);
        expect((await jour(4))!.effectif, 150);
      },
    );

    test(
      'la cascade recalcule aussi les sous-effectifs par catégorie',
      () async {
        await usecase.executer(
          date: DateTime(2026, 8, 1),
          mouvements: const MouvementsJour(achat: 150),
        );

        final j4 = await jour(4);
        // Toute l'activité porte sur la catégorie jeune ici.
        expect(j4!.effectifsParCategorie[0], 150);
        expect(j4.effectifsParCategorie.reduce((a, b) => a + b), j4.effectif);
      },
    );

    test('la cascade s\'arrête au premier jour non saisi', () async {
      // Jour 6 saisi, jour 5 laissé vide : la continuité est rompue.
      await repository.enregistrerJour(
        JourneeElevage.vierge(
          espece: 'goliaths',
          date: DateTime(2026, 8, 5),
          nombreCategories: 3,
        ),
      );
      await repository.enregistrerJour(
        JourneeElevage(
          espece: 'goliaths',
          date: DateTime(2026, 8, 6),
          achat: 0,
          ne: 0,
          vente: 0,
          mortsParCategorie: const [0, 0, 0],
          donsParCategorie: const [0, 0, 0],
          effectif: 777, // valeur sentinelle
          effectifsParCategorie: const [777, 0, 0],
          isRecorded: true,
        ),
      );

      await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: 150),
      );

      // Les jours 2 à 4 sont recalculés…
      expect((await jour(4))!.effectif, 150);
      // …mais le jour 6, isolé derrière un trou, reste intact.
      expect((await jour(6))!.effectif, 777);
    });

    test(
      'la cascade préserve les mouvements saisis des jours suivants',
      () async {
        await usecase.executer(
          date: DateTime(2026, 8, 1),
          mouvements: const MouvementsJour(achat: 150),
        );

        final j3 = await jour(3);
        expect(j3!.mortsParCategorie[0], 3); // saisie d'origine intacte
        expect(j3.isRecorded, isTrue);
      },
    );

    test(
      'une modification à la baisse ne produit aucun effectif négatif',
      () async {
        await usecase.executer(
          date: DateTime(2026, 8, 1),
          mouvements: const MouvementsJour(achat: 1),
        );

        for (final j in [1, 2, 3, 4]) {
          final journee = await jour(j);
          expect(journee!.effectif, greaterThanOrEqualTo(0));
          expect(
            journee.effectifsParCategorie.every((e) => e >= 0),
            isTrue,
            reason: 'jour $j',
          );
        }
      },
    );
  });

  group('Ventes issues du POS', () {
    test('renvoie 0 quand aucune vente n\'a été enregistrée', () async {
      expect(
        await repository.venteDuJour(
          espece: 'goliaths',
          date: DateTime(2026, 8, 1),
        ),
        0,
      );
    });
  });

  group('Chargement du mois', () {
    test('ne renvoie que les journées du mois demandé', () async {
      await usecase.executer(
        date: DateTime(2026, 8, 31),
        mouvements: const MouvementsJour(achat: 10),
      );
      await usecase.executer(
        date: DateTime(2026, 9, 1),
        mouvements: const MouvementsJour(achat: 10),
      );

      final aout = await repository.chargerMois(
        espece: 'goliaths',
        annee: 2026,
        mois: 8,
      );
      final septembre = await repository.chargerMois(
        espece: 'goliaths',
        annee: 2026,
        mois: 9,
      );

      expect(aout, hasLength(1));
      expect(aout.single.date.day, 31);
      expect(septembre, hasLength(1));
      expect(septembre.single.date.day, 1);
    });

    test('les espèces sont isolées les unes des autres', () async {
      await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(achat: 100),
      );

      final pintades = await repository.chargerMois(
        espece: 'pintades',
        annee: 2026,
        mois: 8,
      );
      expect(pintades, isEmpty);
    });
  });
}
