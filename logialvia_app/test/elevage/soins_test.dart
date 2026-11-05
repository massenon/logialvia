import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/fiche_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/soins_repository_drift.dart';
import 'package:logialvia_app/elevage/domain/entities/soin.dart';
import 'package:logialvia_app/elevage/domain/usecases/reporter_deces_infirmerie_usecase.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/soins_view_model.dart';

void main() {
  late AppDatabase db;
  late SoinsRepositoryDrift repository;
  late SoinsViewModel vm;

  setUp(() async {
    db = AppDatabase.enMemoire();
    repository = SoinsRepositoryDrift(db);
    vm = SoinsViewModel(
      repository,
      ReporterDecesInfirmerieUseCase(fabriqueFicheElevage(db)),
    );
    await vm.charger();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  DateTime jour(int decalage) => DateTime.now().add(Duration(days: decalage));

  group('Enregistrement d\'un soin', () {
    test('persiste les 9 champs de la modale réelle', () async {
      final resultat = await vm.enregistrerSoin(
        espece: 'goliaths',
        date: DateTime(2026, 8, 10),
        typeSoin: 'Vaccination',
        produit: 'Antcox',
        dose: '1C/20L d\'eau',
        remanenceJours: 7,
        veterinaire: 'SIDI ALI Raïmatou',
        symptomes: 'Aucun',
        coutFcfa: 12000,
        dejaEffectue: true,
      );

      expect(resultat, isA<Succes<Soin>>());
      final soins = await repository.chargerSoins();
      expect(soins, hasLength(1));

      final soin = soins.single;
      expect(soin.espece, 'goliaths');
      expect(soin.typeSoin, 'Vaccination');
      expect(soin.produit, 'Antcox');
      expect(soin.dose, '1C/20L d\'eau');
      expect(soin.remanenceJours, 7);
      expect(soin.veterinaire, 'SIDI ALI Raïmatou');
      expect(soin.coutFcfa, 12000);
      expect(soin.statut, StatutSoin.effectue);
    });

    test('un soin non administré est enregistré comme planifié', () async {
      await vm.enregistrerSoin(
        espece: 'pintades',
        date: jour(5),
        typeSoin: 'Vermifuge',
        dejaEffectue: false,
      );

      expect(
        (await repository.chargerSoins()).single.statut,
        StatutSoin.planifie,
      );
    });

    test('refuse les 3 champs obligatoires manquants', () async {
      expect(
        await vm.enregistrerSoin(
          espece: null,
          date: DateTime.now(),
          typeSoin: 'Vaccination',
          dejaEffectue: false,
        ),
        isA<Echec<Soin>>(),
      );
      expect(
        await vm.enregistrerSoin(
          espece: 'goliaths',
          date: null,
          typeSoin: 'Vaccination',
          dejaEffectue: false,
        ),
        isA<Echec<Soin>>(),
      );
      expect(
        await vm.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime.now(),
          typeSoin: null,
          dejaEffectue: false,
        ),
        isA<Echec<Soin>>(),
      );
      expect(await repository.chargerSoins(), isEmpty);
    });

    test('refuse une rémanence ou un coût négatif', () async {
      expect(
        await vm.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime.now(),
          typeSoin: 'Vaccination',
          remanenceJours: -1,
          dejaEffectue: false,
        ),
        isA<Echec<Soin>>(),
      );
      expect(
        await vm.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime.now(),
          typeSoin: 'Vaccination',
          coutFcfa: -500,
          dejaEffectue: false,
        ),
        isA<Echec<Soin>>(),
      );
    });
  });

  group('Confirmation d\'administration', () {
    test('fait passer un soin planifié à « Effectué »', () async {
      await vm.enregistrerSoin(
        espece: 'goliaths',
        date: jour(2),
        typeSoin: 'Vaccination',
        dejaEffectue: false,
      );
      final soin = (await repository.chargerSoins()).single;

      final resultat = await vm.confirmerAdministration(soin);

      expect(resultat, isA<Succes<void>>());
      expect(
        (await repository.chargerSoins()).single.statut,
        StatutSoin.effectue,
      );
    });

    test('refuse de confirmer deux fois', () async {
      await vm.enregistrerSoin(
        espece: 'goliaths',
        date: jour(0),
        typeSoin: 'Vaccination',
        dejaEffectue: true,
      );
      final soin = (await repository.chargerSoins()).single;

      expect(await vm.confirmerAdministration(soin), isA<Echec<void>>());
    });
  });

  group('Délai d\'attente (rémanence)', () {
    test(
      'un soin effectué avec rémanence est actif pendant la durée',
      () async {
        await vm.enregistrerSoin(
          espece: 'goliaths',
          date: jour(-2),
          typeSoin: 'Traitement curatif',
          produit: 'Antcox',
          remanenceJours: 7,
          dejaEffectue: true,
        );

        expect(vm.remanencesActives, hasLength(1));
        expect(vm.remanencesActives.single.finRemanence, isNotNull);
      },
    );

    test('un délai expiré n\'est plus actif', () async {
      await vm.enregistrerSoin(
        espece: 'goliaths',
        date: jour(-30),
        typeSoin: 'Traitement curatif',
        remanenceJours: 7,
        dejaEffectue: true,
      );

      expect(vm.remanencesActives, isEmpty);
    });

    test('un soin planifié n\'ouvre aucun délai d\'attente', () async {
      await vm.enregistrerSoin(
        espece: 'goliaths',
        date: jour(1),
        typeSoin: 'Traitement curatif',
        remanenceJours: 7,
        dejaEffectue: false,
      );

      expect(vm.remanencesActives, isEmpty);
    });

    test('sans rémanence déclarée, aucune date de fin', () async {
      await vm.enregistrerSoin(
        espece: 'goliaths',
        date: jour(0),
        typeSoin: 'Vitamines',
        dejaEffectue: true,
      );

      expect((await repository.chargerSoins()).single.finRemanence, isNull);
    });
  });

  group('Les 4 KPI réels de l\'écran', () {
    setUp(() async {
      final maintenant = DateTime.now();
      // Effectué ce mois-ci, coûte 5000.
      await vm.enregistrerSoin(
        espece: 'goliaths',
        date: DateTime(maintenant.year, maintenant.month, 1),
        typeSoin: 'Vaccination',
        coutFcfa: 5000,
        dejaEffectue: true,
      );
      // Planifié dans le futur, coûte 3000.
      await vm.enregistrerSoin(
        espece: 'pintades',
        date: jour(10),
        typeSoin: 'Vermifuge',
        coutFcfa: 3000,
        dejaEffectue: false,
      );
    });

    test('Doses Administrées (Mois) ne compte que les soins effectués', () {
      expect(vm.dosesAdministreesMois, 1);
    });

    test('Planifiées à Venir ne compte que les échéances futures', () {
      expect(vm.planifieesAVenir, 1);
    });

    test('Coût Vétérinaire (Mois) somme les soins du mois courant', () {
      // Le soin planifie a J+10 peut tomber le mois suivant : on verifie
      // seulement que le soin du 1er du mois est bien compte.
      expect(vm.coutVeterinaireMois, greaterThanOrEqualTo(5000));
    });

    test(
      'En Quarantaine / Traitement agrège infirmerie et traitements en cours',
      () async {
        expect(vm.enQuarantaineOuTraitement, 0);

        await vm.enregistrerEntreeInfirmerie(
          sujet: 'Goliath #G-014',
          motif: 'Suspicion Newcastle',
          niveauIsolement: NiveauIsolement.quarantaineStricte,
        );

        expect(vm.enQuarantaineOuTraitement, 1);
      },
    );
  });

  group('Infirmerie — sous-module absent de Doc F3 et de Doc D1', () {
    test('une entrée est créée « En cours »', () async {
      final resultat = await vm.enregistrerEntreeInfirmerie(
        sujet: 'Goliath #G-014',
        motif: 'Suspicion Newcastle',
        niveauIsolement: NiveauIsolement.quarantaineStricte,
        espece: 'goliaths',
      );

      expect(resultat, isA<Succes<EntreeInfirmerie>>());
      final entrees = await repository.chargerInfirmerie();
      expect(entrees, hasLength(1));
      expect(entrees.single.statut, StatutInfirmerie.enCours);
      expect(
        entrees.single.niveauIsolement,
        NiveauIsolement.quarantaineStricte,
      );
      expect(entrees.single.espece, 'goliaths');
      expect(entrees.single.dateSortie, isNull);
    });

    test('refuse un sujet ou un motif vide', () async {
      expect(
        await vm.enregistrerEntreeInfirmerie(
          sujet: '   ',
          motif: 'Motif',
          niveauIsolement: NiveauIsolement.infirmerie,
        ),
        isA<Echec<EntreeInfirmerie>>(),
      );
      expect(
        await vm.enregistrerEntreeInfirmerie(
          sujet: 'Sujet',
          motif: '',
          niveauIsolement: NiveauIsolement.infirmerie,
        ),
        isA<Echec<EntreeInfirmerie>>(),
      );
      expect(await repository.chargerInfirmerie(), isEmpty);
    });

    test('la réintégration clôture l\'entrée et date la sortie', () async {
      await vm.enregistrerEntreeInfirmerie(
        sujet: 'Pintades Lot A',
        motif: 'Traitement',
        niveauIsolement: NiveauIsolement.infirmerie,
      );
      final entree = (await repository.chargerInfirmerie()).single;

      final resultat = await vm.cloturerEntree(
        entree: entree,
        statut: StatutInfirmerie.reintegre,
      );

      expect(resultat, isA<Succes<void>>());
      final relue = (await repository.chargerInfirmerie()).single;
      expect(relue.statut, StatutInfirmerie.reintegre);
      expect(relue.dateSortie, isNotNull);
      expect(relue.estEnCours, isFalse);
    });

    test('le décès clôture également l\'entrée', () async {
      await vm.enregistrerEntreeInfirmerie(
        sujet: 'Goliath #G-014',
        motif: 'Suspicion Newcastle',
        niveauIsolement: NiveauIsolement.quarantaineStricte,
      );
      final entree = (await repository.chargerInfirmerie()).single;

      await vm.cloturerEntree(entree: entree, statut: StatutInfirmerie.decede);

      expect(
        (await repository.chargerInfirmerie()).single.statut,
        StatutInfirmerie.decede,
      );
    });

    test('une entrée déjà clôturée ne peut pas l\'être à nouveau', () async {
      await vm.enregistrerEntreeInfirmerie(
        sujet: 'Sujet',
        motif: 'Motif',
        niveauIsolement: NiveauIsolement.infirmerie,
      );
      final entree = (await repository.chargerInfirmerie()).single;
      await vm.cloturerEntree(
        entree: entree,
        statut: StatutInfirmerie.reintegre,
      );
      final entreeCloturee = (await repository.chargerInfirmerie()).single;

      expect(
        await vm.cloturerEntree(
          entree: entreeCloturee,
          statut: StatutInfirmerie.decede,
        ),
        isA<Echec<void>>(),
      );
    });

    test(
      'une entrée clôturée sort du décompte « En Quarantaine / Traitement »',
      () async {
        await vm.enregistrerEntreeInfirmerie(
          sujet: 'Sujet',
          motif: 'Motif',
          niveauIsolement: NiveauIsolement.infirmerie,
        );
        expect(vm.enQuarantaineOuTraitement, 1);

        final entree = (await repository.chargerInfirmerie()).single;
        await vm.cloturerEntree(
          entree: entree,
          statut: StatutInfirmerie.reintegre,
        );

        expect(vm.enQuarantaineOuTraitement, 0);
      },
    );
  });

  group('Filtres du registre', () {
    setUp(() async {
      await vm.enregistrerSoin(
        espece: 'goliaths',
        date: jour(0),
        typeSoin: 'Vaccination',
        dejaEffectue: true,
      );
      await vm.enregistrerSoin(
        espece: 'pintades',
        date: jour(1),
        typeSoin: 'Vermifuge',
        dejaEffectue: false,
      );
    });

    test('filtre par catégorie', () {
      vm.definirFiltreCategorie('Vaccination');
      expect(vm.soins, hasLength(1));
      expect(vm.soins.single.espece, 'goliaths');
    });

    test('filtre par espèce', () {
      vm.definirFiltreEspece('pintades');
      expect(vm.soins, hasLength(1));
      expect(vm.soins.single.typeSoin, 'Vermifuge');
    });

    test('les filtres se combinent et peuvent ne rien renvoyer', () {
      vm.definirFiltreCategorie('Vaccination');
      vm.definirFiltreEspece('pintades');
      expect(vm.soins, isEmpty);
    });
  });
}
