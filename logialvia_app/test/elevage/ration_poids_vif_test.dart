import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/bandes_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/fiche_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/parametres_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/soins_repository_drift.dart';
import 'package:logialvia_app/elevage/data/seed/parametres_elevage_seeder.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/entities/parametres_elevage.dart';
import 'package:logialvia_app/elevage/domain/services/calcul_fiche_journaliere.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/fiche_espece_view_model.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/parametres_elevage_view_model.dart';
import 'package:logialvia_app/administration/domain/services/service_archivage.dart';

/// Ration en % du poids vif — les bovins (DV-17).
///
/// Un ruminant ne mange pas « 7 kg par tête » : il mange une part de son poids.
/// Le calcul est `pesée totale du lot × taux de la classe du poids moyen`. Les
/// tests verrouillent ce qui fausserait la provende d'un troupeau sans qu'on
/// s'en aperçoive : une borne de classe, un repli silencieux, une espèce
/// voisine contaminée par le tableau des bovins.
/// Les classes des bovins seulement : le tableau contient aussi celles des
/// poissons-chats (DV-01), qui ont leurs propres tests.
Future<List<TauxRationPoids>> tauxBovins(
  ParametresElevageRepositoryDrift repository,
) async => [
  for (final t in await repository.chargerTauxPoids())
    if (t.espece == 'bovins') t,
];

void main() {
  // Les 3 classes d'ouverture, telles qu'elles sont semées.
  const classes = [
    TauxRationPoids(
      id: 1,
      espece: 'bovins',
      poidsMinG: 0,
      poidsMaxG: 150000,
      tauxPourcent: 3.5,
      confirme: false,
    ),
    TauxRationPoids(
      id: 2,
      espece: 'bovins',
      poidsMinG: 150000,
      poidsMaxG: 300000,
      tauxPourcent: 3.0,
      confirme: false,
    ),
    TauxRationPoids(
      id: 3,
      espece: 'bovins',
      poidsMinG: 300000,
      poidsMaxG: null,
      tauxPourcent: 2.5,
      confirme: false,
    ),
  ];

  const calcul = CalculFicheJournaliere(
    ConfigurationsEspeces.bovins,
    tauxParClasse: classes,
  );

  group('Calcul : pesée × taux de la classe du poids moyen', () {
    test('10 bœufs de 250 kg à 3 % : 75 kg de matière sèche', () {
      // 10 × 250 kg = 2 500 000 g ; poids moyen 250 kg -> classe 150-300 (3 %).
      final provende = calcul.provendeDuJour(const [
        0,
        10,
        0,
      ], poidsTotalGrammes: 2500000);

      expect(provende.surPoidsVif, isTrue);
      expect(provende.grammes, 75000);
      expect(provende.tauxPourcent, 3.0);
      expect(provende.poidsMoyenGrammes, 250000);
    });

    test('la classe se choisit sur le poids MOYEN, pas sur la pesée totale', () {
      // 4 veaux de 100 kg = 400 kg au total. Un calcul sur la pesée totale
      // choisirait la classe 300+ (2,5 %) ; le bon est celle des 100 kg (3,5 %).
      final provende = calcul.provendeDuJour(const [
        4,
        0,
        0,
      ], poidsTotalGrammes: 400000);

      expect(provende.tauxPourcent, 3.5);
      expect(provende.grammes, 14000);
    });

    test('bornes : la borne basse est comprise, la haute est exclue', () {
      double? tauxPour(int poidsMoyenG) => calcul.provendeDuJour(const [
        0,
        1,
        0,
      ], poidsTotalGrammes: poidsMoyenG).tauxPourcent;

      expect(tauxPour(149999), 3.5);
      expect(tauxPour(150000), 3.0, reason: '150 kg pile : classe 150-300.');
      expect(tauxPour(299999), 3.0);
      expect(tauxPour(300000), 2.5, reason: '300 kg pile : dernière classe.');
      expect(tauxPour(900000), 2.5, reason: 'Dernière classe ouverte.');
    });

    test('la provende ne dépend pas de la répartition entre catégories', () {
      // Même pesée, même effectif total : le stade déclaré n'y change rien.
      final a = calcul.provendeDuJour(const [
        10,
        0,
        0,
      ], poidsTotalGrammes: 2500000);
      final b = calcul.provendeDuJour(const [
        3,
        4,
        3,
      ], poidsTotalGrammes: 2500000);
      expect(a.grammes, b.grammes);
    });
  });

  group('Repli sur la ration par tête (jamais silencieux)', () {
    // Veau 1 500 g, Embouche 7 000 g, Reproducteur 9 000 g.
    const parTete = [
      [10, 0, 0, 15000],
      [0, 10, 0, 70000],
      [0, 0, 10, 90000],
    ];

    for (final cas in parTete) {
      test('sans pesée : ${cas.sublist(0, 3)} -> ${cas[3]} g', () {
        final provende = calcul.provendeDuJour(cas.sublist(0, 3));
        expect(provende.surPoidsVif, isFalse);
        expect(provende.grammes, cas[3]);
        expect(provende.tauxPourcent, isNull);
      });
    }

    test('une pesée nulle ou négative ne déclenche pas le calcul', () {
      for (final poids in [0, -5]) {
        final provende = calcul.provendeDuJour(const [
          0,
          10,
          0,
        ], poidsTotalGrammes: poids);
        expect(provende.surPoidsVif, isFalse, reason: 'poids $poids');
        expect(provende.grammes, 70000);
      }
    });

    test('un effectif nul ne divise pas par zéro', () {
      final provende = calcul.provendeDuJour(const [
        0,
        0,
        0,
      ], poidsTotalGrammes: 2500000);
      expect(provende.surPoidsVif, isFalse);
      expect(provende.grammes, 0);
    });

    test(
      'un poids moyen hors de toute classe retombe sur la ration par tête',
      () {
        // Classes avec un trou : 100-200 kg seulement.
        const troue = CalculFicheJournaliere(
          ConfigurationsEspeces.bovins,
          tauxParClasse: [
            TauxRationPoids(
              id: 1,
              espece: 'bovins',
              poidsMinG: 100000,
              poidsMaxG: 200000,
              tauxPourcent: 3,
              confirme: false,
            ),
          ],
        );
        final provende = troue.provendeDuJour(const [
          0,
          10,
          0,
        ], poidsTotalGrammes: 2500000);
        expect(provende.surPoidsVif, isFalse);
        expect(provende.grammes, 70000);
      },
    );

    test('sans aucune classe configurée, tout reste par tête', () {
      const vide = CalculFicheJournaliere(ConfigurationsEspeces.bovins);
      expect(
        vide.provendeDuJour(const [
          0,
          10,
          0,
        ], poidsTotalGrammes: 2500000).surPoidsVif,
        isFalse,
      );
    });
  });

  group('Les autres espèces ne sont pas touchées', () {
    test(
      'les goliaths ignorent le tableau des bovins, même avec une pesée',
      () {
        const goliaths = CalculFicheJournaliere(
          ConfigurationsEspeces.goliaths,
          tauxParClasse: classes,
        );
        final provende = goliaths.provendeDuJour(const [
          10,
          10,
          10,
        ], poidsTotalGrammes: 2500000);

        // 10 × (30 + 60 + 110) = 2 000 g : la ration par tête, inchangée.
        expect(provende.surPoidsVif, isFalse);
        expect(provende.grammes, 2000);
      },
    );

    test('seuls les bovins et les poissons-chats sont rationnés sur le poids '
        'vif', () {
      for (final config in ConfigurationsEspeces.parIdentifiant.values) {
        expect(
          config.rationEnPourcentagePoidsVif,
          const {'bovins', 'poissons-chats'}.contains(config.identifiant),
          reason: config.identifiant,
        );
      }
    });

    test('les classes d\'une autre espèce sont ignorées', () {
      const autre = CalculFicheJournaliere(
        ConfigurationsEspeces.bovins,
        tauxParClasse: [
          TauxRationPoids(
            id: 9,
            espece: 'escargots',
            poidsMinG: 0,
            poidsMaxG: null,
            tauxPourcent: 9,
            confirme: false,
          ),
        ],
      );
      expect(
        autre.provendeDuJour(const [
          0,
          10,
          0,
        ], poidsTotalGrammes: 2500000).surPoidsVif,
        isFalse,
      );
    });

    test('provendeTotaleGrammes garde sa signature d\'origine', () {
      // Les appelants existants ne passent pas de pesée.
      const goliaths = CalculFicheJournaliere(ConfigurationsEspeces.goliaths);
      expect(goliaths.provendeTotaleGrammes(const [10, 10, 10]), 2000);
    });
  });

  group('Libellés des classes', () {
    test('en kilos, avec les bornes dites', () {
      expect(classes[0].libelleClasse, 'Moins de 150 kg');
      expect(classes[1].libelleClasse, 'De 150 à moins de 300 kg');
      expect(classes[2].libelleClasse, '300 kg et plus');
      expect(classes[0].libelleTaux, '3,5 %');
    });
  });

  group('Peuplement et corbeille', () {
    late AppDatabase db;
    late ParametresElevageRepositoryDrift repository;

    setUp(() async {
      db = AppDatabase.enMemoire();
      await ParametresElevageSeeder(db).executer();
      repository = ParametresElevageRepositoryDrift(db);
    });

    tearDown(() async => db.close());

    test('3 classes bovines semées, contiguës, jamais « confirmées »', () async {
      final taux = await tauxBovins(repository);
      expect(taux, hasLength(3));
      expect(taux.every((t) => t.espece == 'bovins' && !t.confirme), isTrue);
      expect(taux.map((t) => t.tauxPourcent), [3.5, 3.0, 2.5]);

      // Aucun trou ni chevauchement : chaque borne haute est la basse suivante.
      expect(taux.first.poidsMinG, 0);
      for (var i = 0; i < taux.length - 1; i++) {
        expect(taux[i].poidsMaxG, taux[i + 1].poidsMinG);
      }
      expect(taux.last.poidsMaxG, isNull);
    });

    test('supprimer une classe l\'archive : la corbeille la garde', () async {
      final taux = (await tauxBovins(repository)).first;
      await repository.supprimerTauxPoids(
        taux.id,
        utilisateurId: 'u1',
        utilisateurNom: 'Animalier',
      );

      expect(await tauxBovins(repository), hasLength(2));
      final corbeille = await ServiceArchivage(db).lister();
      expect(
        corbeille.where((e) => e.nomTable == 'taux_ration_poids'),
        hasLength(1),
      );

      // Et elle revient telle quelle.
      await ServiceArchivage(db).restaurer(corbeille.first.id, estAdmin: false);
      final retablie = await tauxBovins(repository);
      expect(retablie, hasLength(3));
      expect(retablie.first.tauxPourcent, 3.5);
    });
  });

  group('Validation de la saisie', () {
    late AppDatabase db;
    late ParametresElevageViewModel vm;
    late ParametresElevageRepositoryDrift repository;

    setUp(() async {
      db = AppDatabase.enMemoire();
      await ParametresElevageSeeder(db).executer();
      repository = ParametresElevageRepositoryDrift(db);
      vm = ParametresElevageViewModel(repository);
      await vm.charger();
    });

    tearDown(() async => db.close());

    Future<Resultat<void>> saisir({
      String espece = 'bovins',
      String min = '',
      String max = '',
      String taux = '',
      TauxRationPoids? existant,
    }) => vm.enregistrerTauxPoids(
      existant: existant,
      espece: espece,
      poidsMin: min,
      poidsMax: max,
      taux: taux,
    );

    test(
      'seules les espèces rationnées sur le poids vif sont acceptées',
      () async {
        expect(
          await saisir(espece: 'goliaths', min: '0', taux: '3'),
          isA<Echec<void>>(),
        );
        expect(
          ParametresElevageViewModel.especesSurPoidsVif.map((e) => e.id),
          unorderedEquals(['bovins', 'poissons-chats']),
        );
      },
    );

    test(
      'un chevauchement est refusé : un animal n\'aurait pas deux taux',
      () async {
        // 200-400 kg recouvre 150-300 et 300+.
        final resultat = await saisir(min: '200', max: '400', taux: '2,8');
        expect(resultat, isA<Echec<void>>());
        expect((resultat as Echec<void>).message, contains('chevauche'));
        expect(await tauxBovins(repository), hasLength(3));
      },
    );

    test('un maximum qui ne dépasse pas le minimum est refusé', () async {
      expect(
        await saisir(min: '500', max: '500', taux: '2'),
        isA<Echec<void>>(),
      );
      expect(
        await saisir(min: '500', max: '400', taux: '2'),
        isA<Echec<void>>(),
      );
    });

    test(
      'le taux doit être raisonnable : entre 0 et 10 % du poids vif',
      () async {
        for (final mauvais in ['0', '-1', '11', '35', 'abc', '']) {
          expect(
            await saisir(min: '600', taux: mauvais),
            isA<Echec<void>>(),
            reason: 'taux « $mauvais »',
          );
        }
      },
    );

    test(
      'une classe valide est enregistrée en grammes, virgule acceptée',
      () async {
        // Une classe au-dessus de toutes : 300+ doit d'abord etre refermee.
        final derniere = (await tauxBovins(repository)).last;
        expect(
          await saisir(
            existant: derniere,
            espece: 'bovins',
            min: '300',
            max: '450,5',
            taux: '2,4',
          ),
          isA<Succes<void>>(),
        );
        expect(await saisir(min: '450,5', taux: '2,2'), isA<Succes<void>>());

        final taux = await tauxBovins(repository);
        expect(taux, hasLength(4));
        final modifiee = taux.firstWhere((t) => t.id == derniere.id);
        expect(modifiee.poidsMaxG, 450500);
        expect(modifiee.tauxPourcent, 2.4);
        expect(taux.last.poidsMinG, 450500);
        expect(taux.last.poidsMaxG, isNull);
      },
    );

    test(
      'modifier une classe ne la déclare pas en chevauchement avec elle-même',
      () async {
        final milieu = (await tauxBovins(repository))[1];
        expect(
          await saisir(existant: milieu, min: '150', max: '300', taux: '3,2'),
          isA<Succes<void>>(),
        );
        expect((await tauxBovins(repository))[1].tauxPourcent, 3.2);
      },
    );
  });

  group('La configuration pilote RÉELLEMENT la fiche', () {
    late AppDatabase db;
    late ParametresElevageViewModel parametres;
    late FicheEspeceViewModel fiche;

    setUp(() async {
      db = AppDatabase.enMemoire();
      await ParametresElevageSeeder(db).executer();
      final repository = ParametresElevageRepositoryDrift(db);
      parametres = ParametresElevageViewModel(repository);
      await parametres.charger();

      const config = ConfigurationsEspeces.bovins;
      fiche = FicheEspeceViewModel(
        configuration: config,
        repository: FicheElevageRepositoryDrift(db, config),
        parametresRepository: repository,
        bandesRepository: BandesRepositoryDrift(db),
        soinsRepository: SoinsRepositoryDrift(db),
      );
    });

    tearDown(() async {
      fiche.dispose();
      await db.close();
    });

    test('la fiche applique le taux semé', () async {
      await fiche.charger();
      final provende = fiche.provendeDuJour(const [
        0,
        10,
        0,
      ], poidsTotalGrammes: 2500000);
      expect(provende.surPoidsVif, isTrue);
      expect(provende.grammes, 75000);
    });

    test(
      'un taux modifié dans les paramètres change la provende de la fiche',
      () async {
        final milieu = parametres.tauxPoids[1];
        await parametres.enregistrerTauxPoids(
          existant: milieu,
          espece: 'bovins',
          poidsMin: '150',
          poidsMax: '300',
          taux: '4',
        );

        await fiche.charger();
        final provende = fiche.provendeDuJour(const [
          0,
          10,
          0,
        ], poidsTotalGrammes: 2500000);
        // Un ecran de parametres qui ne change rien au calcul serait decoratif.
        expect(provende.grammes, 100000);
        expect(provende.tauxPourcent, 4.0);
      },
    );

    test(
      'une classe supprimée : la fiche retombe sur la ration par tête',
      () async {
        await parametres.supprimerTauxPoids(parametres.tauxPoids[1]);
        await fiche.charger();

        final provende = fiche.provendeDuJour(const [
          0,
          10,
          0,
        ], poidsTotalGrammes: 2500000);
        expect(provende.surPoidsVif, isFalse);
        expect(provende.grammes, 70000);
      },
    );
  });

  group('Migration v28 sur une base en service', () {
    late Directory dossier;

    setUp(() {
      dossier = Directory.systemTemp.createTempSync('logialvia_v28');
    });

    tearDown(() {
      if (dossier.existsSync()) dossier.deleteSync(recursive: true);
    });

    /// Une base telle qu'elle etait en v27 : sans la table des taux.
    Future<File> baseV27({bool avecModification = false}) async {
      final fichier = File('${dossier.path}/logialvia.db');
      final db = AppDatabase.pourFichier(fichier);
      await ParametresElevageSeeder(db).executer();
      if (avecModification) {
        await db.customStatement(
          "UPDATE taux_ration_poids SET taux_pourcent = 3.9 "
          "WHERE espece = 'bovins' AND poids_min_g = 150000",
        );
      }
      await db.customStatement('DROP TABLE taux_ration_poids');
      await db.customStatement('PRAGMA user_version = 27');
      await db.close();
      return fichier;
    }

    test('crée la table et sème les 3 classes bovines', () async {
      final fichier = await baseV27();

      final db = AppDatabase.pourFichier(fichier);
      addTearDown(db.close);
      final taux = await tauxBovins(ParametresElevageRepositoryDrift(db));

      expect(taux, hasLength(3));
      expect(taux.map((t) => t.tauxPourcent), [3.5, 3.0, 2.5]);
    });

    test(
      'rejouée, elle ne duplique rien et laisse les taux modifiés',
      () async {
        final fichier = await baseV27();

        var db = AppDatabase.pourFichier(fichier);
        // Un taux modifie apres la migration...
        await db.customStatement(
          "UPDATE taux_ration_poids SET taux_pourcent = 3.9 "
          "WHERE espece = 'bovins' AND poids_min_g = 150000",
        );
        // ...puis un user_version faux, comme apres une restauration.
        await db.customStatement('PRAGMA user_version = 27');
        await db.close();

        db = AppDatabase.pourFichier(fichier);
        addTearDown(db.close);
        final taux = await tauxBovins(ParametresElevageRepositoryDrift(db));
        expect(taux, hasLength(3));
        expect(taux[1].tauxPourcent, 3.9);
      },
    );
  });
  group('Poissons-chats : pourcentage de la biomasse (DV-01)', () {
    const classesPoissons = [
      TauxRationPoids(
        id: 11,
        espece: 'poissons-chats',
        poidsMinG: 0,
        poidsMaxG: 5,
        tauxPourcent: 15,
        confirme: false,
      ),
      TauxRationPoids(
        id: 12,
        espece: 'poissons-chats',
        poidsMinG: 5,
        poidsMaxG: 20,
        tauxPourcent: 7,
        confirme: false,
      ),
      TauxRationPoids(
        id: 13,
        espece: 'poissons-chats',
        poidsMinG: 20,
        poidsMaxG: 100,
        tauxPourcent: 4,
        confirme: false,
      ),
      TauxRationPoids(
        id: 14,
        espece: 'poissons-chats',
        poidsMinG: 100,
        poidsMaxG: 500,
        tauxPourcent: 2.5,
        confirme: false,
      ),
      TauxRationPoids(
        id: 15,
        espece: 'poissons-chats',
        poidsMinG: 500,
        poidsMaxG: null,
        tauxPourcent: 1.5,
        confirme: false,
      ),
    ];

    const poissons = CalculFicheJournaliere(
      ConfigurationsEspeces.poissonsChats,
      tauxParClasse: classesPoissons,
    );

    test('1 000 poissons de 50 g à 4 % : 2 kg d\'aliment', () {
      // Biomasse = 1 000 x 50 g = 50 kg ; 4 % = 2 kg.
      final provende = poissons.provendeDuJour(const [
        0,
        1000,
        0,
      ], poidsTotalGrammes: 50000);
      expect(provende.surPoidsVif, isTrue);
      expect(provende.grammes, 2000);
      expect(provende.tauxPourcent, 4.0);
      expect(provende.poidsMoyenGrammes, 50);
    });

    test('le taux décroît avec la taille : l\'appétit relatif baisse', () {
      double? taux(int poidsMoyenG) => poissons.provendeDuJour([
        0,
        1000,
        0,
      ], poidsTotalGrammes: poidsMoyenG * 1000).tauxPourcent;
      expect(taux(2), 15);
      expect(taux(10), 7);
      expect(taux(50), 4);
      expect(taux(200), 2.5);
      expect(taux(800), 1.5);
    });

    test('bornes en grammes : basse comprise, haute exclue', () {
      double? taux(int poidsMoyenG) => poissons.provendeDuJour([
        0,
        1,
        0,
      ], poidsTotalGrammes: poidsMoyenG).tauxPourcent;
      expect(taux(4), 15);
      expect(taux(5), 7, reason: '5 g pile : classe 5-20.');
      expect(taux(20), 4);
      expect(taux(100), 2.5);
      expect(taux(500), 1.5, reason: '500 g pile : dernière classe.');
    });

    test('sans pesée : ration par tête, signalée', () {
      final provende = poissons.provendeDuJour(const [0, 100, 0]);
      expect(provende.surPoidsVif, isFalse);
      expect(provende.grammes, 100 * 60);
    });

    test('libellés en grammes, unité répétée seulement si elle change', () {
      expect(classesPoissons[0].libelleClasse, 'Moins de 5 g');
      expect(classesPoissons[1].libelleClasse, 'De 5 à moins de 20 g');
      expect(classesPoissons[3].libelleClasse, 'De 100 à moins de 500 g');
      expect(classesPoissons[4].libelleClasse, '500 g et plus');
      const mixte = TauxRationPoids(
        id: 99,
        espece: 'poissons-chats',
        poidsMinG: 500,
        poidsMaxG: 2000,
        tauxPourcent: 1.5,
        confirme: false,
      );
      expect(mixte.libelleClasse, 'De 500 g à moins de 2 kg');
    });

    test('unités de saisie : g pour les poissons, kg pour les bovins', () {
      expect(ConfigurationsEspeces.poissonsChats.uniteClassePoids, 'g');
      expect(ConfigurationsEspeces.poissonsChats.grammesParUniteClassePoids, 1);
      expect(ConfigurationsEspeces.bovins.uniteClassePoids, 'kg');
      expect(ConfigurationsEspeces.bovins.grammesParUniteClassePoids, 1000);
    });

    group('Peuplement et saisie', () {
      late AppDatabase db;
      late ParametresElevageRepositoryDrift repository;
      late ParametresElevageViewModel vm;

      setUp(() async {
        db = AppDatabase.enMemoire();
        await ParametresElevageSeeder(db).executer();
        repository = ParametresElevageRepositoryDrift(db);
        vm = ParametresElevageViewModel(repository);
        await vm.charger();
      });

      tearDown(() async => db.close());

      Future<List<TauxRationPoids>> classes() async => [
        for (final t in await repository.chargerTauxPoids())
          if (t.espece == 'poissons-chats') t,
      ];

      test('5 classes semées, contiguës, repères non confirmés', () async {
        final taux = await classes();
        expect(taux.map((t) => t.tauxPourcent), [15, 7, 4, 2.5, 1.5]);
        expect(taux.every((t) => !t.confirme), isTrue);
        expect(taux.first.poidsMinG, 0);
        for (var i = 0; i < taux.length - 1; i++) {
          expect(taux[i].poidsMaxG, taux[i + 1].poidsMinG);
        }
        expect(taux.last.poidsMaxG, isNull);
        // Chaque taux est dans la fourchette du registre DV-01.
        const fourchettes = [(10, 20), (6, 8), (3, 5), (2, 3), (1, 2)];
        for (var i = 0; i < taux.length; i++) {
          expect(
            taux[i].tauxPourcent,
            inInclusiveRange(fourchettes[i].$1, fourchettes[i].$2),
          );
        }
      });

      test(
        'les bornes se saisissent en grammes, sans multiplier par 1 000',
        () async {
          final derniere = (await classes()).last;
          expect(
            await vm.enregistrerTauxPoids(
              existant: derniere,
              espece: 'poissons-chats',
              poidsMin: '500',
              poidsMax: '2000',
              taux: '1,5',
            ),
            isA<Succes<void>>(),
          );
          expect(
            await vm.enregistrerTauxPoids(
              espece: 'poissons-chats',
              poidsMin: '2000',
              poidsMax: '',
              taux: '1',
            ),
            isA<Succes<void>>(),
          );

          final taux = await classes();
          expect(taux, hasLength(6));
          expect(taux[4].poidsMaxG, 2000, reason: '2 000 g, pas 2 000 000.');
          expect(taux.last.poidsMinG, 2000);
        },
      );

      test('un chevauchement de classes de poissons est refusé', () async {
        final resultat = await vm.enregistrerTauxPoids(
          espece: 'poissons-chats',
          poidsMin: '10',
          poidsMax: '60',
          taux: '5',
        );
        expect(resultat, isA<Echec<void>>());
        expect(await classes(), hasLength(5));
      });

      test('le plafond du taux dépend de l\'espèce : 25 % pour un alevin, '
          '10 % pour un bovin', () async {
        final alevin = (await classes()).first;
        Future<Resultat<void>> poisson(String taux) => vm.enregistrerTauxPoids(
          existant: alevin,
          espece: 'poissons-chats',
          poidsMin: '0',
          poidsMax: '5',
          taux: taux,
        );
        expect(await poisson('20'), isA<Succes<void>>());
        expect(await poisson('26'), isA<Echec<void>>());

        final veau = (await tauxBovins(repository)).first;
        Future<Resultat<void>> bovin(String taux) => vm.enregistrerTauxPoids(
          existant: veau,
          espece: 'bovins',
          poidsMin: '0',
          poidsMax: '150',
          taux: taux,
        );
        expect(await bovin('12'), isA<Echec<void>>());
        expect(await bovin('4'), isA<Succes<void>>());
      });

      test('les classes des bovins et des poissons ne se gênent pas', () async {
        // 0 a 5 g (poissons) et 0 a 150 kg (bovins) se recouvrent en
        // grammes... mais pas entre especes.
        expect(
          await vm.enregistrerTauxPoids(
            existant: (await classes()).first,
            espece: 'poissons-chats',
            poidsMin: '0',
            poidsMax: '5',
            taux: '16',
          ),
          isA<Succes<void>>(),
        );
      });

      test('la suppression est archivée avec un libellé en grammes', () async {
        final cible = (await classes())[1];
        await repository.supprimerTauxPoids(cible.id);
        final corbeille = await ServiceArchivage(db).lister();
        final element = corbeille.singleWhere(
          (e) => e.nomTable == 'taux_ration_poids',
        );
        expect(element.designation, contains('De 5 à moins de 20 g'));
      });
    });

    group('La fiche Poissons-Chats applique le tableau', () {
      late AppDatabase db;
      late FicheEspeceViewModel fiche;
      late ParametresElevageViewModel parametres;

      setUp(() async {
        db = AppDatabase.enMemoire();
        await ParametresElevageSeeder(db).executer();
        final repository = ParametresElevageRepositoryDrift(db);
        parametres = ParametresElevageViewModel(repository);
        await parametres.charger();
        const config = ConfigurationsEspeces.poissonsChats;
        fiche = FicheEspeceViewModel(
          configuration: config,
          repository: FicheElevageRepositoryDrift(db, config),
          parametresRepository: repository,
          bandesRepository: BandesRepositoryDrift(db),
          soinsRepository: SoinsRepositoryDrift(db),
        );
      });

      tearDown(() async {
        fiche.dispose();
        await db.close();
      });

      test('provende sur la biomasse, et un taux modifié la change', () async {
        await fiche.charger();
        var provende = fiche.provendeDuJour(const [
          0,
          1000,
          0,
        ], poidsTotalGrammes: 50000);
        expect(provende.surPoidsVif, isTrue);
        expect(provende.grammes, 2000);

        final classe = parametres.tauxPoids.firstWhere(
          (t) => t.espece == 'poissons-chats' && t.poidsMinG == 20,
        );
        await parametres.enregistrerTauxPoids(
          existant: classe,
          espece: 'poissons-chats',
          poidsMin: '20',
          poidsMax: '100',
          taux: '5',
        );
        await fiche.charger();
        provende = fiche.provendeDuJour(const [
          0,
          1000,
          0,
        ], poidsTotalGrammes: 50000);
        expect(provende.grammes, 2500);
      });
    });

    group('Migration v30', () {
      late Directory dossier;

      setUp(() {
        dossier = Directory.systemTemp.createTempSync('logialvia_v30');
      });

      tearDown(() {
        if (dossier.existsSync()) dossier.deleteSync(recursive: true);
      });

      test(
        'ajoute les classes de poissons sans toucher à celles des bovins',
        () async {
          final fichier = File('${dossier.path}/logialvia.db');
          final prepa = AppDatabase.pourFichier(fichier);
          await ParametresElevageSeeder(prepa).executer();
          // Une base en v29 : bovins deja la, un taux de bovins modifie, aucune
          // classe de poissons.
          await prepa.customStatement(
            "UPDATE taux_ration_poids SET taux_pourcent = 3.9 "
            "WHERE espece = 'bovins' AND poids_min_g = 150000",
          );
          await prepa.customStatement(
            "DELETE FROM taux_ration_poids WHERE espece = 'poissons-chats'",
          );
          await prepa.customStatement('PRAGMA user_version = 29');
          await prepa.close();

          final db = AppDatabase.pourFichier(fichier);
          addTearDown(db.close);
          final repository = ParametresElevageRepositoryDrift(db);
          final tous = await repository.chargerTauxPoids();

          expect(tous.where((t) => t.espece == 'poissons-chats'), hasLength(5));
          final bovins = tous.where((t) => t.espece == 'bovins').toList();
          expect(bovins, hasLength(3), reason: 'Aucun doublon.');
          expect(
            bovins[1].tauxPourcent,
            3.9,
            reason: 'Modification conservée.',
          );
        },
      );
    });
  });
}
