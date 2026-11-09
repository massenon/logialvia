import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/cycle_couveuse_repository_drift.dart';
import 'package:logialvia_app/elevage/domain/entities/cycle_incubation.dart';
import 'package:logialvia_app/elevage/domain/repositories/cycle_couveuse_repository.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/cycle_couveuse_view_model.dart';

/// Couveuse multi-âges persistée — mirages, machines, sous-lots.
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

  Future<CycleIncubation> creer({
    EspeceCouvable espece = EspeceCouvable.goliath,
    DateTime? date,
    int oeufs = 200,
    String? machineId,
  }) async {
    final resultat = await vm.creerCycle(
      espece: espece,
      dateChargement: date ?? DateTime(2026, 8, 1),
      oeufsCharges: oeufs,
      machineId: machineId,
    );
    return (resultat as Succes<CycleIncubation>).valeur;
  }

  CycleIncubation relire(String code) =>
      vm.tousLesLots.firstWhere((l) => l.code == code);

  group('Machines incubateurs', () {
    test('une machine se crée et se relit', () async {
      final resultat = await vm.creerMachine(
        code: 'INC-01',
        libelle: 'Couveuse principale',
        capaciteOeufs: 500,
      );

      expect(resultat, isA<Succes<MachineIncubateur>>());
      expect(vm.machines, hasLength(1));
      expect(vm.machines.single.code, 'INC-01');
      expect(vm.machines.single.capaciteOeufs, 500);
    });

    test('deux machines ne peuvent pas porter le même code', () async {
      await vm.creerMachine(code: 'INC-01', libelle: 'A');
      final doublon = await vm.creerMachine(code: 'inc-01', libelle: 'B');

      expect(
        doublon,
        isA<Echec<MachineIncubateur>>(),
        reason:
            'Le code identifie la machine dans les alertes : deux « INC-01 » '
            'rendraient impossible de savoir laquelle ouvrir.',
      );
      expect(vm.machines, hasLength(1));
    });

    test('une capacité nulle ou négative est refusée', () async {
      expect(
        await vm.creerMachine(code: 'X', libelle: 'X', capaciteOeufs: 0),
        isA<Echec<MachineIncubateur>>(),
      );
    });

    test('un lot désigne sa machine, et l\'écran la retrouve', () async {
      final machine =
          (await vm.creerMachine(code: 'INC-02', libelle: 'Couveuse 2')
                  as Succes<MachineIncubateur>)
              .valeur;
      await creer(machineId: machine.id);

      final lot = vm.tousLesLots.single;
      expect(lot.machineId, machine.id);
      expect(
        lot.machineCode,
        'INC-02',
        reason:
            'Le code est resolu en une passe : une requete par ligne ferait '
            'N+1 appels sur un couvoir qui accumule les lots.',
      );
    });

    test('l\'occupation ne compte que les lots en incubation', () async {
      final machine =
          (await vm.creerMachine(code: 'INC-01', libelle: 'A')
                  as Succes<MachineIncubateur>)
              .valeur;
      final a = await creer(machineId: machine.id, oeufs: 100);
      await creer(machineId: machine.id, oeufs: 50);

      await vm.enregistrerMirage(lot: a, jour: 7, oeufsRetires: 10);
      expect(vm.occupation(machine.id), 140);

      await vm.enregistrerEclosion(
        cycle: relire(a.code),
        poussinsEclos: 80,
        oeufsPerdus: 10,
      );
      expect(vm.occupation(machine.id), 50);
    });
  });

  group('Mirages — le dénominateur du TER se construit ici', () {
    test('le mirage 1 retire les œufs clairs et se persiste', () async {
      final lot = await creer(oeufs: 200);

      final resultat = await vm.enregistrerMirage(
        lot: lot,
        jour: EspeceCouvable.jourMirage1,
        oeufsRetires: 30,
      );

      expect(resultat, isA<Succes<void>>());
      final relu = relire(lot.code);
      expect(relu.oeufsBlancsJ7, 30);
      expect(relu.oeufsGatesJ14, isNull);
      expect(relu.oeufsRetenusApresMirages, 170);
    });

    test('les deux mirages se cumulent', () async {
      final lot = await creer(oeufs: 200);
      await vm.enregistrerMirage(lot: lot, jour: 7, oeufsRetires: 30);
      await vm.enregistrerMirage(
        lot: relire(lot.code),
        jour: 14,
        oeufsRetires: 10,
      );

      final relu = relire(lot.code);
      expect(relu.oeufsRetenusApresMirages, 160);
      expect(relu.oeufsRetiresAuxMirages, 40);
    });

    test('un mirage zéro se distingue d\'un mirage non fait', () async {
      final lot = await creer(oeufs: 200);
      await vm.enregistrerMirage(lot: lot, jour: 7, oeufsRetires: 0);

      final relu = relire(lot.code);
      expect(
        relu.oeufsBlancsJ7,
        0,
        reason:
            'Zero oeuf clair est un RESULTAT ; `null` veut dire que personne '
            'n\'a encore mire. Les confondre laisserait l\'alerte disparaitre '
            'sans que le mirage soit fait.',
      );
      expect(relu.oeufsGatesJ14, isNull);
    });

    test('on ne peut pas retirer plus d\'œufs qu\'il n\'y en a', () async {
      final lot = await creer(oeufs: 100);
      await vm.enregistrerMirage(lot: lot, jour: 7, oeufsRetires: 60);

      final trop = await vm.enregistrerMirage(
        lot: relire(lot.code),
        jour: 14,
        oeufsRetires: 50, // 60 + 50 > 100
      );

      expect(trop, isA<Echec<void>>());
      expect(
        relire(lot.code).oeufsRetenusApresMirages,
        40,
        reason: 'Un denominateur negatif rendrait le TER absurde.',
      );
    });

    test('un mirage à un autre jour que J+7 ou J+14 est refusé', () async {
      final lot = await creer();
      expect(
        await vm.enregistrerMirage(lot: lot, jour: 10, oeufsRetires: 5),
        isA<Echec<void>>(),
      );
    });

    test('un lot clôturé n\'accepte plus de mirage', () async {
      final lot = await creer(oeufs: 100);
      await vm.enregistrerEclosion(
        cycle: lot,
        poussinsEclos: 80,
        oeufsPerdus: 20,
      );

      expect(
        await vm.enregistrerMirage(
          lot: relire(lot.code),
          jour: 7,
          oeufsRetires: 5,
        ),
        isA<Echec<void>>(),
      );
    });
  });

  group('TER persisté de bout en bout', () {
    test('la formule s\'applique sur les données relues de la base', () async {
      final lot = await creer(oeufs: 100);
      await vm.enregistrerMirage(lot: lot, jour: 7, oeufsRetires: 10);
      await vm.enregistrerMirage(
        lot: relire(lot.code),
        jour: 14,
        oeufsRetires: 5,
      );
      await vm.enregistrerEclosion(
        cycle: relire(lot.code),
        poussinsEclos: 68,
        oeufsPerdus: 17,
      );

      final relu = relire(lot.code);
      expect(relu.oeufsRetenusApresMirages, 85);
      expect(relu.tauxEclosionReel, closeTo(80, 0.001));
      expect(relu.tauxEclosionBrut, closeTo(68, 0.001));
    });

    test('l\'éclosion ne peut pas dépasser les œufs restants', () async {
      final lot = await creer(oeufs: 100);
      await vm.enregistrerMirage(lot: lot, jour: 7, oeufsRetires: 30);

      final trop = await vm.enregistrerEclosion(
        cycle: relire(lot.code),
        poussinsEclos: 80, // > 70 restants
        oeufsPerdus: 0,
      );

      expect(
        trop,
        isA<Echec<ResultatEclosion>>(),
        reason:
            'Un lot de 100 oeufs dont 30 ont ete retires ne peut pas rendre '
            '80 poussins.',
      );
      expect(relire(lot.code).estEnCours, isTrue);
    });
  });

  group('Remplacement — le sous-lot comble la place libérée', () {
    test('l\'éclosion avec remplacement crée un sous-lot rattaché', () async {
      final parent = await creer(oeufs: 200, date: DateTime(2026, 8, 1));

      final resultat = await vm.enregistrerEclosion(
        cycle: parent,
        poussinsEclos: 170,
        oeufsPerdus: 30,
        oeufsRemplacement: 180,
        dateRemplacement: DateTime(2026, 8, 22),
      );

      final valeur = (resultat as Succes<ResultatEclosion>).valeur;
      expect(valeur.aEteRemplace, isTrue);

      final sousLot = valeur.sousLot!;
      expect(sousLot.lotParentId, parent.id);
      expect(sousLot.oeufsCharges, 180);
      expect(sousLot.dateChargement, DateTime(2026, 8, 22));
      expect(sousLot.estEnCours, isTrue);
    });

    test(
      'le lot remplacé garde son éclosion et passe en « Remplacé »',
      () async {
        final parent = await creer(oeufs: 200);
        await vm.enregistrerEclosion(
          cycle: parent,
          poussinsEclos: 170,
          oeufsPerdus: 30,
          oeufsRemplacement: 180,
        );

        final relu = relire(parent.code);
        expect(relu.statut, StatutCycle.remplace);
        expect(
          relu.poussinsEclos,
          170,
          reason:
              '« Remplacé » dit que la place est reprise, pas que l\'eclosion '
              'n\'a pas eu lieu.',
        );
        expect(relu.tauxEclosionReel, closeTo(85, 0.001));
      },
    );

    test('sans remplacement, le lot est simplement clôturé', () async {
      final lot = await creer(oeufs: 100);
      final resultat = await vm.enregistrerEclosion(
        cycle: lot,
        poussinsEclos: 80,
        oeufsPerdus: 20,
      );

      expect(
        (resultat as Succes<ResultatEclosion>).valeur.aEteRemplace,
        isFalse,
      );
      expect(relire(lot.code).statut, StatutCycle.eclosionEffectuee);
      expect(vm.tousLesLots, hasLength(1));
    });

    test('le sous-lot hérite de la machine, pas du calendrier', () async {
      final machine =
          (await vm.creerMachine(code: 'INC-01', libelle: 'A')
                  as Succes<MachineIncubateur>)
              .valeur;
      final parent = await creer(
        oeufs: 100,
        date: DateTime(2026, 8, 1),
        machineId: machine.id,
      );

      final resultat = await vm.enregistrerEclosion(
        cycle: parent,
        poussinsEclos: 80,
        oeufsPerdus: 20,
        oeufsRemplacement: 90,
        dateRemplacement: DateTime(2026, 8, 22),
      );
      final sousLot = (resultat as Succes<ResultatEclosion>).valeur.sousLot!;

      expect(sousLot.machineId, machine.id);
      expect(
        sousLot.dateEclosionPrevue,
        DateTime(2026, 9, 12),
        reason:
            'Le sous-lot repart de SA date d\'insertion : c\'est tout l\'objet '
            'du suivi multi-ages.',
      );
    });

    test('le sous-lot peut changer d\'espèce', () async {
      final parent = await creer(espece: EspeceCouvable.goliath, oeufs: 100);

      final resultat = await vm.enregistrerEclosion(
        cycle: parent,
        poussinsEclos: 80,
        oeufsPerdus: 20,
        oeufsRemplacement: 90,
        especeRemplacement: EspeceCouvable.pintade,
        dateRemplacement: DateTime(2026, 8, 22),
      );
      final sousLot = (resultat as Succes<ResultatEclosion>).valeur.sousLot!;

      expect(sousLot.espece, EspeceCouvable.pintade);
      expect(sousLot.dateEclosionPrevue, DateTime(2026, 9, 19)); // +28
    });

    test('l\'historique des remplacements se lit sur la lignée', () async {
      final racine = await creer(oeufs: 100, date: DateTime(2026, 8, 1));
      final r1 = await vm.enregistrerEclosion(
        cycle: racine,
        poussinsEclos: 80,
        oeufsPerdus: 20,
        oeufsRemplacement: 100,
        dateRemplacement: DateTime(2026, 8, 22),
      );
      final second = (r1 as Succes<ResultatEclosion>).valeur.sousLot!;

      await vm.enregistrerEclosion(
        cycle: relire(second.code),
        poussinsEclos: 90,
        oeufsPerdus: 10,
        oeufsRemplacement: 100,
        dateRemplacement: DateTime(2026, 9, 12),
      );

      final lignee = vm.lignee(racine.id);
      expect(lignee, hasLength(3));
      expect(lignee.first.code, racine.code);
      expect(vm.racineDe(lignee.last)?.code, racine.code);
    });

    test('une quantité de remplacement négative est refusée', () async {
      final lot = await creer(oeufs: 100);
      expect(
        await vm.enregistrerEclosion(
          cycle: lot,
          poussinsEclos: 80,
          oeufsPerdus: 20,
          oeufsRemplacement: -5,
        ),
        isA<Echec<ResultatEclosion>>(),
      );
    });

    test('supprimer un lot ne fait pas disparaître ses sous-lots', () async {
      final parent = await creer(oeufs: 100);
      final r = await vm.enregistrerEclosion(
        cycle: parent,
        poussinsEclos: 80,
        oeufsPerdus: 20,
        oeufsRemplacement: 90,
      );
      final sousLot = (r as Succes<ResultatEclosion>).valeur.sousLot!;

      await repository.supprimer(parent.id);
      await vm.charger();

      final restant = relire(sousLot.code);
      expect(
        restant.lotParentId,
        isNull,
        reason:
            'Les oeufs du sous-lot sont physiquement dans la machine : une '
            'suppression en cascade les ferait s\'evaporer.',
      );
      expect(vm.tousLesLots, hasLength(1));
    });
  });

  group('Alertes et filtres de l\'écran', () {
    test('les alertes suivent la date de référence injectée', () async {
      await creer(oeufs: 100, date: DateTime(2026, 8, 1));

      vm.definirReference(DateTime(2026, 8, 5));
      expect(vm.alertes, isEmpty);

      vm.definirReference(DateTime(2026, 8, 8));
      expect(vm.alertes.map((a) => a.type), contains(TypeEcheance.mirage1));
    });

    test('le filtre par machine ne touche pas les KPI', () async {
      final m1 =
          (await vm.creerMachine(code: 'INC-01', libelle: 'A')
                  as Succes<MachineIncubateur>)
              .valeur;
      await creer(machineId: m1.id, oeufs: 100);
      await creer(oeufs: 50);

      vm.definirFiltreMachine(m1.id);

      expect(vm.cycles, hasLength(1));
      expect(
        vm.oeufsEnIncubation,
        150,
        reason:
            'Les KPI decrivent le couvoir entier, la table en montre une '
            'partie.',
      );
    });

    test('le contrat JSON reflète l\'état réel du couvoir', () async {
      final machine =
          (await vm.creerMachine(code: 'INC-01', libelle: 'A')
                  as Succes<MachineIncubateur>)
              .valeur;
      final lot = await creer(machineId: machine.id, oeufs: 100);
      await vm.enregistrerMirage(lot: lot, jour: 7, oeufsRetires: 10);
      vm.definirReference(DateTime(2026, 8, 20));

      final json = vm.versJson();

      expect((json['machines']! as List), hasLength(1));
      expect((json['lots']! as List), hasLength(1));
      final premierLot = (json['lots']! as List).first as Map<String, Object?>;
      expect(premierLot['oeufsBlancsJ7'], 10);
      expect(premierLot['oeufsRetenusApresMirages'], 90);
      expect(premierLot['machineCode'], 'INC-01');
      expect((json['alertes']! as List), isNotEmpty);
    });
  });
}
