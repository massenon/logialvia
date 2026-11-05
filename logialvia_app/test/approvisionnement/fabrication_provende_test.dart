import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/approvisionnement/data/repositories/approvisionnement_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/approvisionnement.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/fabrication_provende.dart';
import 'package:logialvia_app/approvisionnement/presentation/viewmodels/approvisionnement_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';

/// Fabrication de provende — `#modal-fabrication` de `gestion-stocks.html`.
///
/// Le Cahier des Charges Technique §6.2 interdit la sortie isolée d'un intrant
/// de provende : les stocks sont décrémentés **en une seule opération**. Le
/// prototype, lui, affiche « stocks des 5 intrants décrémentés automatiquement »
/// sans rien décrémenter. Ces tests verrouillent l'opération réelle.
void main() {
  late AppDatabase db;
  late ApprovisionnementViewModel vm;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    vm = ApprovisionnementViewModel(ApprovisionnementRepositoryDrift(db));
    await vm.charger();
  });

  tearDown(() async => db.close());

  Intrant intrant(String code) =>
      vm.tousLesIntrants.firstWhere((i) => i.code == code);

  group('Composition', () {
    test('les 5 intrants de provende du socle sont les candidats', () {
      expect(vm.intrantsDeProvende, hasLength(5));
      expect(
        vm.intrantsDeProvende.map((i) => i.nom),
        containsAll(['Maïs', 'Soja']),
      );
    });

    test('le total ignore les lignes à zéro', () {
      const fabrication = FabricationProvende({
        'INT-001': 10,
        'INT-002': 0,
        'INT-003': 5,
      });
      expect(fabrication.totalKg, 15);
      expect(fabrication.composition.keys, ['INT-001', 'INT-003']);
    });

    test(
      'la composition par défaut du prototype dépasse déjà le stock de Maïs',
      () {
        // 25 kg demandes pour 18 en stock : l'alerte doit s'afficher des
        // l'ouverture. Ce n'est pas une erreur de recopie, c'est l'etat du
        // prototype — le Mais y est l'intrant sous seuil critique.
        const fabrication = FabricationProvende(
          FabricationProvende.compositionParDefaut,
        );
        expect(fabrication.totalKg, 45);

        final manquants = fabrication.manquants(vm.intrantsDeProvende);
        expect(manquants, hasLength(1));
        expect(manquants.single, contains('Maïs'));
        expect(manquants.single, contains('18'));
      },
    );
  });

  group('Validation', () {
    test('une fabrication vide est refusée', () async {
      final resultat = await vm.fabriquerProvende(const {});
      expect(resultat, isA<Echec<String>>());
    });

    test('une quantité négative est refusée', () async {
      final resultat = await vm.fabriquerProvende(const {'INT-002': -5});
      expect(resultat, isA<Echec<String>>());
    });

    test(
      'un stock insuffisant est refusé, avec le disponible en clair',
      () async {
        final resultat = await vm.fabriquerProvende(const {'INT-001': 25});
        expect(resultat, isA<Echec<String>>());
        switch (resultat) {
          case Echec(:final message):
            expect(message, contains('Stock insuffisant'));
            expect(message, contains('Maïs'));
          case Succes():
            fail('La fabrication aurait dû être refusée.');
        }
      },
    );
  });

  group('L\'opération est atomique — le point qui compte', () {
    test('une fabrication valide décrémente TOUS les intrants', () async {
      final avant = {for (final i in vm.intrantsDeProvende) i.code: i.stock};

      final resultat = await vm.fabriquerProvende(const {
        'INT-001': 10, // Maïs 18 → 8
        'INT-002': 10, // Soja 42 → 32
        'INT-003': 5, // Coquille 22 → 17
      });
      expect(resultat, isA<Succes<String>>());

      expect(intrant('INT-001').stock, avant['INT-001']! - 10);
      expect(intrant('INT-002').stock, avant['INT-002']! - 10);
      expect(intrant('INT-003').stock, avant['INT-003']! - 5);
      expect(
        intrant('INT-004').stock,
        avant['INT-004'],
        reason: 'Un intrant absent de la composition n\'est pas touché.',
      );
    });

    test(
      'si UN SEUL stock est insuffisant, aucun autre n\'est décrémenté',
      () async {
        final avant = {for (final i in vm.intrantsDeProvende) i.code: i.stock};

        // Soja et Coquille passent, le Mais non : la transaction entiere doit
        // etre annulee. Decrementer au fil de l'eau laisserait 2 stocks amputes
        // d'une fabrication qui n'a pas eu lieu.
        final resultat = await vm.fabriquerProvende(const {
          'INT-002': 10,
          'INT-003': 5,
          'INT-001': 999,
        });
        expect(resultat, isA<Echec<String>>());

        for (final code in avant.keys) {
          expect(
            intrant(code).stock,
            avant[code],
            reason: '$code ne doit pas avoir bougé.',
          );
        }
        expect(
          vm.mouvements.where((m) => m.motif.contains('Fabrication')),
          isEmpty,
        );
      },
    );

    test('chaque sortie est journalisée sous une même référence', () async {
      await vm.fabriquerProvende(const {
        'INT-001': 5,
        'INT-002': 10,
        'INT-003': 3,
      });

      final mouvements = vm.mouvements
          .where((m) => m.motif.contains('Fabrication de provende'))
          .toList();

      expect(mouvements, hasLength(3));
      expect(
        mouvements.map((m) => m.reference).toSet(),
        hasLength(1),
        reason: 'Les 3 sorties appartiennent à la même fabrication.',
      );
      expect(mouvements.first.reference, startsWith('FAB-'));
      expect(mouvements.every((m) => m.type == TypeMouvement.sortie), isTrue);
      expect(
        mouvements.every((m) => m.quantite < 0),
        isTrue,
        reason: 'La quantité est signée : négative en sortie (Doc D1).',
      );
      expect(
        mouvements.first.motif,
        contains('18 kg'),
        reason: 'Le motif porte le total fabriqué.',
      );
    });

    test('la référence s\'incrémente d\'une fabrication à l\'autre', () async {
      await vm.fabriquerProvende(const {'INT-002': 1});
      await vm.fabriquerProvende(const {'INT-002': 1});

      final references = vm.mouvements
          .where((m) => m.reference?.startsWith('FAB-') ?? false)
          .map((m) => m.reference)
          .toSet();

      expect(references, hasLength(2));
      final annee = DateTime.now().year;
      expect(references, contains('FAB-$annee-0001'));
      expect(references, contains('FAB-$annee-0002'));
    });

    test('la valeur du stock suit la décrémentation', () async {
      final valeurAvant = vm.valeurTotaleStock;
      final mais = intrant('INT-001');

      await vm.fabriquerProvende(const {'INT-001': 5});

      expect(
        vm.valeurTotaleStock,
        valeurAvant - 5 * mais.pmp,
        reason: 'La valorisation se recalcule sur le stock restant.',
      );
    });
  });
}
