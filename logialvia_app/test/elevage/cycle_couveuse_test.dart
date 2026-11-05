import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/cycle_couveuse_repository_drift.dart';
import 'package:logialvia_app/elevage/domain/entities/cycle_incubation.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/cycle_couveuse_view_model.dart';

void main() {
  late AppDatabase db;
  late CycleCouveuseRepositoryDrift repository;
  late CycleCouveuseViewModel vm;

  setUp(() async {
    db = AppDatabase.enMemoire();
    repository = CycleCouveuseRepositoryDrift(db);
    vm = CycleCouveuseViewModel(repository);
    await vm.charger();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  group('Durée d\'incubation — corrige la règle « +21 jours » de Doc F3', () {
    test('Goliath incube 21 jours, Pintade 28', () {
      expect(EspeceCouvable.goliath.dureeIncubationJours, 21);
      expect(
        EspeceCouvable.pintade.dureeIncubationJours,
        28,
        reason:
            'Le prototype ecrit `data-duree="27"`. La Gerante a corrige : sur '
            'un couvoir en continu, un jour d\'ecart se repete a chaque lot.',
      );
    });

    test('la date d\'éclosion prévue applique la durée de l\'espèce', () {
      final chargement = DateTime(2026, 8, 1);

      final goliath = CycleIncubation(
        id: 1,
        code: 'C-2026-001',
        espece: EspeceCouvable.goliath,
        dateChargement: chargement,
        oeufsCharges: 100,
        statut: StatutCycle.enIncubation,
      );
      final pintade = CycleIncubation(
        id: 2,
        code: 'C-2026-002',
        espece: EspeceCouvable.pintade,
        dateChargement: chargement,
        oeufsCharges: 100,
        statut: StatutCycle.enIncubation,
      );

      expect(goliath.dateEclosionPrevue, DateTime(2026, 8, 22)); // +21
      expect(pintade.dateEclosionPrevue, DateTime(2026, 8, 29)); // +28
      // Appliquer 21 jours a une pintade l'avancerait d'une semaine pleine.
      expect(
        pintade.dateEclosionPrevue
            .difference(goliath.dateEclosionPrevue)
            .inDays,
        7,
      );
    });
  });

  group('Création d\'un cycle', () {
    test('persiste réellement et génère un code séquentiel', () async {
      final resultat = await vm.creerCycle(
        espece: EspeceCouvable.goliath,
        dateChargement: DateTime(2026, 8, 10),
        oeufsCharges: 200,
      );

      expect(resultat, isA<Succes<CycleIncubation>>());
      final cycles = await repository.chargerTous();
      expect(cycles, hasLength(1));
      expect(cycles.single.code, 'C-2026-001');
      expect(cycles.single.oeufsCharges, 200);
      expect(cycles.single.statut, StatutCycle.enIncubation);
    });

    test('les codes s\'incrémentent par année', () async {
      await vm.creerCycle(
        espece: EspeceCouvable.goliath,
        dateChargement: DateTime(2026, 8, 10),
        oeufsCharges: 100,
      );
      await vm.creerCycle(
        espece: EspeceCouvable.pintade,
        dateChargement: DateTime(2026, 9, 1),
        oeufsCharges: 150,
      );
      await vm.creerCycle(
        espece: EspeceCouvable.goliath,
        dateChargement: DateTime(2027, 1, 5),
        oeufsCharges: 120,
      );

      final codes = (await repository.chargerTous()).map((c) => c.code).toSet();
      expect(codes, {'C-2026-001', 'C-2026-002', 'C-2027-001'});
    });

    test('refuse une espèce non renseignée', () async {
      final resultat = await vm.creerCycle(
        espece: null,
        dateChargement: DateTime(2026, 8, 10),
        oeufsCharges: 100,
      );
      expect(resultat, isA<Echec<CycleIncubation>>());
      expect(await repository.chargerTous(), isEmpty);
    });

    test('refuse une date non renseignée', () async {
      final resultat = await vm.creerCycle(
        espece: EspeceCouvable.goliath,
        dateChargement: null,
        oeufsCharges: 100,
      );
      expect(resultat, isA<Echec<CycleIncubation>>());
    });

    test('refuse un nombre d\'œufs nul ou absent', () async {
      expect(
        await vm.creerCycle(
          espece: EspeceCouvable.goliath,
          dateChargement: DateTime(2026, 8, 10),
          oeufsCharges: 0,
        ),
        isA<Echec<CycleIncubation>>(),
      );
      expect(
        await vm.creerCycle(
          espece: EspeceCouvable.goliath,
          dateChargement: DateTime(2026, 8, 10),
          oeufsCharges: null,
        ),
        isA<Echec<CycleIncubation>>(),
      );
    });
  });

  group('Enregistrement d\'une éclosion', () {
    late CycleIncubation cycle;

    setUp(() async {
      await vm.creerCycle(
        espece: EspeceCouvable.goliath,
        dateChargement: DateTime(2026, 8, 1),
        oeufsCharges: 200,
      );
      cycle = (await repository.chargerTous()).single;
    });

    test(
      'passe le cycle en « Éclosion Effectuée » et calcule les taux',
      () async {
        final resultat = await vm.enregistrerEclosion(
          cycle: cycle,
          poussinsEclos: 168,
          oeufsPerdus: 32,
        );

        expect(resultat, isA<Succes<void>>());
        final relu = (await repository.chargerTous()).single;
        expect(relu.statut, StatutCycle.eclosionEffectuee);
        expect(relu.poussinsEclos, 168);
        expect(relu.oeufsPerdus, 32);
        expect(relu.tauxEclosion, 84); // 168 / 200
        expect(relu.tauxPerte, 16);
      },
    );

    test(
      'refuse un total supérieur aux œufs chargés — invariant métier',
      () async {
        final resultat = await vm.enregistrerEclosion(
          cycle: cycle,
          poussinsEclos: 150,
          oeufsPerdus: 100, // 250 > 200
        );

        expect(resultat, isA<Echec<void>>());
        // Le cycle reste en incubation : rien n'a ete ecrit.
        expect(
          (await repository.chargerTous()).single.statut,
          StatutCycle.enIncubation,
        );
      },
    );

    test('refuse des quantités négatives', () async {
      final resultat = await vm.enregistrerEclosion(
        cycle: cycle,
        poussinsEclos: -5,
        oeufsPerdus: 0,
      );
      expect(resultat, isA<Echec<void>>());
    });

    test('accepte exactement le total des œufs chargés', () async {
      final resultat = await vm.enregistrerEclosion(
        cycle: cycle,
        poussinsEclos: 180,
        oeufsPerdus: 20,
      );
      expect(resultat, isA<Succes<void>>());
    });
  });

  group('KPI de l\'écran', () {
    test('taux moyens à null tant qu\'aucune éclosion n\'existe', () async {
      await vm.creerCycle(
        espece: EspeceCouvable.goliath,
        dateChargement: DateTime(2026, 8, 1),
        oeufsCharges: 200,
      );

      expect(vm.cyclesEnCours, 1);
      // Une moyenne sur zero echantillon n'existe pas : elle ne vaut pas 0.
      expect(vm.tauxEclosionMoyen, isNull);
      expect(vm.tauxPerteMoyen, isNull);
      expect(vm.poussinsAttendus, 0);
    });

    test('la moyenne se calcule sur les cycles éclos uniquement', () async {
      await vm.creerCycle(
        espece: EspeceCouvable.goliath,
        dateChargement: DateTime(2026, 8, 1),
        oeufsCharges: 200,
      );
      final premier = (await repository.chargerTous()).single;
      await vm.enregistrerEclosion(
        cycle: premier,
        poussinsEclos: 160,
        oeufsPerdus: 40,
      );

      await vm.creerCycle(
        espece: EspeceCouvable.pintade,
        dateChargement: DateTime(2026, 9, 1),
        oeufsCharges: 100,
      );

      expect(vm.tauxEclosionMoyen, 80);
      expect(vm.cyclesEnCours, 1);
      // 100 œufs en cours x 80 % historique.
      expect(vm.poussinsAttendus, 80);
    });
  });

  group('Filtres', () {
    setUp(() async {
      await vm.creerCycle(
        espece: EspeceCouvable.goliath,
        dateChargement: DateTime(2026, 8, 1),
        oeufsCharges: 200,
      );
      await vm.creerCycle(
        espece: EspeceCouvable.pintade,
        dateChargement: DateTime(2026, 8, 5),
        oeufsCharges: 150,
      );
      final goliath = (await repository.chargerTous()).firstWhere(
        (c) => c.espece == EspeceCouvable.goliath,
      );
      await vm.enregistrerEclosion(
        cycle: goliath,
        poussinsEclos: 170,
        oeufsPerdus: 30,
      );
    });

    test('filtre par statut', () {
      vm.definirFiltreStatut('en_cours');
      expect(vm.cycles, hasLength(1));
      expect(vm.cycles.single.espece, EspeceCouvable.pintade);

      vm.definirFiltreStatut('eclos');
      expect(vm.cycles, hasLength(1));
      expect(vm.cycles.single.espece, EspeceCouvable.goliath);
    });

    test('filtre par espèce', () {
      vm.definirFiltreEspece('pintade');
      expect(vm.cycles, hasLength(1));
      expect(vm.cycles.single.espece, EspeceCouvable.pintade);
    });

    test('les filtres se combinent', () {
      vm.definirFiltreStatut('eclos');
      vm.definirFiltreEspece('pintade');
      expect(vm.cycles, isEmpty);
    });

    test('aucun filtre renvoie tous les cycles', () {
      vm.definirFiltreStatut(null);
      vm.definirFiltreEspece(null);
      expect(vm.cycles, hasLength(2));
    });
  });

  group('Colonne Actions du tableau « Lot d\'Incubation »', () {
    Future<CycleIncubation> creer() async {
      final resultat = await vm.creerCycle(
        espece: EspeceCouvable.goliath,
        dateChargement: DateTime(2026, 8, 1),
        oeufsCharges: 100,
      );
      return (resultat as Succes<CycleIncubation>).valeur;
    }

    test('un lot en incubation se modifie, dates recalculees', () async {
      final cycle = await creer();

      final resultat = await vm.modifierCycle(
        cycle: cycle,
        espece: EspeceCouvable.pintade,
        dateChargement: DateTime(2026, 8, 5),
        oeufsCharges: 120,
      );
      expect(resultat, isA<Succes<void>>());

      final modifie = vm.cycles.firstWhere((c) => c.id == cycle.id);
      expect(modifie.espece, EspeceCouvable.pintade);
      expect(modifie.oeufsCharges, 120);
      expect(
        modifie.dateEclosionPrevue,
        DateTime(2026, 9, 2),
        reason:
            '5 aout + 27 jours de pintade. Changer d\'espece doit recalculer '
            'l\'echeance, pas conserver celle du goliath.',
      );
    });

    test('un lot en incubation se supprime', () async {
      final cycle = await creer();
      expect(vm.cycles, hasLength(1));

      expect(await vm.supprimerCycle(cycle), isA<Succes<void>>());
      expect(vm.cycles, isEmpty);
    });

    test('un lot deja eclos ne se modifie plus', () async {
      final cycle = await creer();
      await vm.enregistrerEclosion(
        cycle: cycle,
        poussinsEclos: 85,
        oeufsPerdus: 15,
      );
      final eclos = vm.cycles.single;

      final resultat = await vm.modifierCycle(
        cycle: eclos,
        espece: EspeceCouvable.goliath,
        dateChargement: DateTime(2026, 8, 1),
        oeufsCharges: 50,
      );

      expect(resultat, isA<Echec<void>>());
      expect(
        vm.cycles.single.oeufsCharges,
        100,
        reason:
            'Ramener les oeufs charges de 100 a 50 ferait passer le taux '
            'd\'eclosion de 85 % a 170 % — une statistique deja publiee ne se '
            'reecrit pas.',
      );
    });

    test('un lot deja eclos ne se supprime plus', () async {
      final cycle = await creer();
      await vm.enregistrerEclosion(
        cycle: cycle,
        poussinsEclos: 85,
        oeufsPerdus: 15,
      );

      final resultat = await vm.supprimerCycle(vm.cycles.single);

      expect(resultat, isA<Echec<void>>());
      expect(
        vm.cycles,
        hasLength(1),
        reason:
            'Ses 85 poussins sont entres dans les effectifs : les effacer '
            'laisserait des sujets sans origine.',
      );
    });

    test('la modification refuse un lot vide', () async {
      final cycle = await creer();
      expect(
        await vm.modifierCycle(
          cycle: cycle,
          espece: EspeceCouvable.goliath,
          dateChargement: DateTime(2026, 8, 1),
          oeufsCharges: 0,
        ),
        isA<Echec<void>>(),
      );
    });
  });
}
