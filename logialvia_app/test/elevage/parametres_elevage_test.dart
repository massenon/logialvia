import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/approvisionnement/data/repositories/approvisionnement_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/approvisionnement.dart';
import 'package:logialvia_app/approvisionnement/presentation/viewmodels/approvisionnement_view_model.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/bandes_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/fiche_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/soins_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/parametres_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/seed/parametres_elevage_seeder.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/entities/parametres_elevage.dart';
import 'package:logialvia_app/elevage/domain/services/calcul_fiche_journaliere.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/fiche_espece_view_model.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/parametres_elevage_view_model.dart';

void main() {
  late AppDatabase db;
  late ParametresElevageRepositoryDrift repository;
  late ParametresElevageViewModel vm;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    repository = ParametresElevageRepositoryDrift(db);
    vm = ParametresElevageViewModel(repository);
    await vm.charger();
  });

  tearDown(() async => db.close());

  group('Socle — les valeurs viennent du prototype, pas d\'une invention', () {
    test('les 12 barèmes de `RATIONS` sont présents, plus 6 pour les filières '
        'ajoutées (escargots, bovins)', () async {
      expect(vm.baremes, hasLength(18));
      expect(
        vm.baremes.where(
          (b) => b.espece != 'escargots' && b.espece != 'bovins',
        ),
        hasLength(12),
      );

      final goliathau = vm.baremes.firstWhere(
        (b) => b.espece == 'goliaths' && b.stade == 'Goliathau',
      );
      expect(goliathau.rationGrammesParJour, 60);
      expect(goliathau.confirme, isFalse);

      final alevin = vm.baremes.firstWhere(
        (b) => b.espece == 'poissons-chats' && b.stade == 'Alevin',
      );
      // Repli par tete corrige par l'expert (`47e_`) : 1 g, pas 8 g, pour un alevin.
      expect(alevin.rationGrammesParJour, 1);
    });

    test('seuls les 3 barèmes Lapins portent le badge « Confirmé » — c\'est le '
        'prototype qui le dit, pas une généralisation', () {
      final confirmes = vm.baremes.where((b) => b.confirme).toList();
      expect(confirmes, hasLength(3));
      expect(confirmes.every((b) => b.espece == 'lapins'), isTrue);
    });

    test('les 11 échéances de `PROPHYLAXIE_STORE` sont présentes, plus 21 '
        '(escargots) et 9 (bovins)', () async {
      final toutes = await repository.chargerProphylaxie();
      expect(toutes, hasLength(41));
      expect(
        toutes.where((e) => e.espece != 'escargots' && e.espece != 'bovins'),
        hasLength(11),
      );

      vm.changerEspeceProphylaxie('pintades');
      expect(vm.echeancesFiltrees, hasLength(4));
      expect(vm.echeancesFiltrees.first.libelleJour, 'J1');

      vm.changerEspeceProphylaxie('lapins');
      expect(vm.echeancesFiltrees, hasLength(2));
      expect(
        vm.echeancesFiltrees.first.produit,
        'Levalap',
        reason:
            'Le déparasitage des lapins n\'utilise pas le produit volaille.',
      );
    });

    test('le socle ne réécrit pas un barème modifié par la Gérante', () async {
      final mature = vm.baremes.firstWhere(
        (b) => b.espece == 'goliaths' && b.stade == 'Mature',
      );
      await vm.modifierRation(bareme: mature, ration: '130');

      // Deuxieme demarrage.
      await ParametresElevageSeeder(db).executer();
      await vm.charger();

      expect(
        vm.baremes
            .firstWhere((b) => b.espece == 'goliaths' && b.stade == 'Mature')
            .rationGrammesParJour,
        130,
      );
      expect(vm.baremes, hasLength(18), reason: 'Aucun doublon inséré.');
    });
  });

  group('Le barème pilote RÉELLEMENT le calcul de provende', () {
    test(
      'une ration modifiée dans les paramètres change la provende de la fiche',
      () async {
        const config = ConfigurationsEspeces.goliaths;
        final ficheVm = FicheEspeceViewModel(
          configuration: config,
          repository: FicheElevageRepositoryDrift(db, config),
          parametresRepository: repository,
          bandesRepository: BandesRepositoryDrift(db),
          soinsRepository: SoinsRepositoryDrift(db),
        );
        await ficheVm.charger();

        // Baremes du socle : 30 / 60 / 110 g/j.
        expect(ficheVm.rationCategorie(0), 30);
        expect(ficheVm.rationCategorie(1), 60);
        expect(ficheVm.rationCategorie(2), 110);
        expect(
          ficheVm.provendeTotaleGrammes([10, 10, 10]),
          2000, // 300 + 600 + 1100
        );

        // La Gerante releve la ration des Matures a 130 g/j.
        final mature = vm.baremes.firstWhere(
          (b) => b.espece == 'goliaths' && b.stade == 'Mature',
        );
        expect(
          await vm.modifierRation(bareme: mature, ration: '130'),
          isA<Succes<void>>(),
        );

        await ficheVm.charger();
        expect(ficheVm.rationCategorie(2), 130);
        expect(
          ficheVm.provendeTotaleGrammes([10, 10, 10]),
          2200, // 300 + 600 + 1300
          reason:
              'Sans ce report, l\'écran Paramètres Élevage serait décoratif : '
              'il afficherait 130 pendant que la fiche continuerait à compter '
              '110.',
        );
      },
    );

    test(
      'un barème supprimé fait retomber la fiche sur la ration de référence, '
      'pas sur zéro',
      () async {
        const config = ConfigurationsEspeces.goliaths;
        final mature = vm.baremes.firstWhere(
          (b) => b.espece == 'goliaths' && b.stade == 'Mature',
        );
        await vm.modifierRation(bareme: mature, ration: '130');
        await vm.supprimerBareme(mature);

        final ficheVm = FicheEspeceViewModel(
          configuration: config,
          repository: FicheElevageRepositoryDrift(db, config),
          parametresRepository: repository,
          bandesRepository: BandesRepositoryDrift(db),
          soinsRepository: SoinsRepositoryDrift(db),
        );
        await ficheVm.charger();

        expect(ficheVm.rationCategorie(2), 110);
      },
    );

    test(
      'un stade libre n\'affecte aucune catégorie : il est documentaire',
      () async {
        expect(
          await vm.ajouterBareme(
            espece: 'goliaths',
            stade: 'Adulte',
            ration: '200',
          ),
          isA<Succes<void>>(),
        );

        // « Adulte » ne correspond a aucune categorie de la fiche Goliaths.
        final calcul = const CalculFicheJournaliere(
          ConfigurationsEspeces.goliaths,
          rationsConfigurees: {'Adulte': 200},
        );
        expect(calcul.rationCategorie(0), 30);
        expect(calcul.rationCategorie(1), 60);
        expect(calcul.rationCategorie(2), 110);
        expect(calcul.provendeTotaleGrammes([10, 10, 10]), 2000);
      },
    );

    test('ajouter deux fois le même stade met la ration à jour', () async {
      await vm.ajouterBareme(
        espece: 'goliaths',
        stade: 'Mature',
        ration: '150',
      );
      final matures = vm.baremes.where(
        (b) => b.espece == 'goliaths' && b.stade == 'Mature',
      );
      expect(matures, hasLength(1));
      expect(matures.single.rationGrammesParJour, 150);
    });
  });

  group('Validations', () {
    test('une ration nulle ou absurde est refusée', () async {
      expect(
        await vm.ajouterBareme(espece: 'lapins', stade: 'Test', ration: '0'),
        isA<Echec<void>>(),
      );
      expect(
        await vm.ajouterBareme(espece: 'lapins', stade: 'Test', ration: '9000'),
        isA<Echec<void>>(),
      );
      expect(
        await vm.ajouterBareme(espece: 'lapins', stade: '', ration: '50'),
        isA<Echec<void>>(),
      );
      expect(vm.baremes, hasLength(18));
    });

    test(
      'le jour du cycle reste dans les bornes du formulaire (1 à 365)',
      () async {
        expect(
          await vm.enregistrerEcheance(
            jour: '0',
            traitement: 'Test',
            produit: 'Test',
            remanence: '0',
          ),
          isA<Echec<void>>(),
        );
        expect(
          await vm.enregistrerEcheance(
            jour: '366',
            traitement: 'Test',
            produit: 'Test',
            remanence: '0',
          ),
          isA<Echec<void>>(),
        );
        // Un rappel annuel (bovins : J365) doit pouvoir etre saisi.
        expect(
          await vm.enregistrerEcheance(
            jour: '365',
            traitement: 'Rappel annuel',
            produit: 'Vaccin',
            remanence: '0',
          ),
          isA<Succes<void>>(),
        );
        expect(
          await vm.enregistrerEcheance(
            jour: '20',
            traitement: 'Vaccin test',
            produit: 'Produit test',
            remanence: '3',
          ),
          isA<Succes<void>>(),
        );

        vm.changerEspeceProphylaxie('goliaths');
        expect(vm.echeancesFiltrees, hasLength(5));
      },
    );

    test('une échéance modifiée reste sur son espèce d\'origine', () async {
      vm.changerEspeceProphylaxie('lapins');
      final echeance = vm.echeancesFiltrees.first;

      // L'utilisatrice bascule sur une autre espece avant de valider la modale.
      vm.changerEspeceProphylaxie('pintades');
      await vm.enregistrerEcheance(
        existante: echeance,
        jour: '3',
        traitement: 'Déparasitage révisé',
        produit: 'Levalap',
        remanence: '7',
      );

      vm.changerEspeceProphylaxie('lapins');
      final modifiee = vm.echeancesFiltrees.firstWhere(
        (e) => e.id == echeance.id,
      );
      expect(modifiee.jourCycle, 3);
      expect(modifiee.traitement, 'Déparasitage révisé');

      vm.changerEspeceProphylaxie('pintades');
      expect(
        vm.echeancesFiltrees.any((e) => e.id == echeance.id),
        isFalse,
        reason: 'L\'échéance n\'a pas changé d\'espèce.',
      );
    });
  });

  group('Onglet 3 — provende en lecture seule, lue depuis Gestion Stocks', () {
    test('les intrants affichés sont les vrais intrants de provende', () async {
      expect(vm.provendes, isNotEmpty);
      expect(vm.provendes.every((p) => p.unite.isNotEmpty), isTrue);

      final mais = vm.provendes.firstWhere((p) => p.nom == 'Maïs');
      expect(mais.stock, 18);
      expect(mais.prixIndicatif, 600);
      expect(
        mais.critique,
        isTrue,
        reason:
            'Le Maïs est sous son seuil — le prototype l\'affiche en rouge.',
      );
    });

    test('la recherche filtre sur le nom', () {
      vm.definirRechercheProvende('soja');
      expect(vm.provendesFiltrees, hasLength(1));
      vm.definirRechercheProvende('');
      expect(vm.provendesFiltrees, equals(vm.provendes));
    });
  });

  group('Onglet 4 — numérotation persistée', () {
    test('les valeurs par défaut sont celles du prototype', () {
      expect(vm.formats.enclos, 'E');
      expect(vm.formats.cage, 'C');
      expect(vm.formats.bande, 'B');
      expect(vm.formats.bassin, 'B');
      expect(vm.formats.apercuCage, 'C1, C2, C5, C12');
      expect(vm.formats.apercuEnclos, 'E1, E2, E3');
    });

    test('bacs des escargots et parcs des bovins : BAC et PARC par défaut', () {
      expect(vm.formats.bac, 'BAC');
      expect(vm.formats.parc, 'PARC');
      expect(vm.formats.apercuBac, 'BAC1, BAC2, BAC3');
      expect(vm.formats.apercuParc, 'PARC1, PARC2, PARC3');
    });

    test('les préfixes bac et parc se modifient, se persistent, et un préfixe '
        'vide est refusé', () async {
      vm.modifierBrouillon(bac: ' ');
      expect(await vm.enregistrerNumerotation(), isA<Echec<void>>());
      expect(vm.formats.bac, 'BAC');

      vm.modifierBrouillon(bac: 'ESC', parc: 'BOV');
      expect(vm.numerotationModifiee, isTrue);
      expect(await vm.enregistrerNumerotation(), isA<Succes<void>>());

      final relu = ParametresElevageViewModel(repository);
      await relu.charger();
      expect(relu.formats.bac, 'ESC');
      expect(relu.formats.parc, 'BOV');
      expect(relu.formats.bassin, 'B', reason: 'Les autres sont intacts.');
    });

    test('l\'aperçu suit la frappe avant même l\'enregistrement', () {
      vm.modifierBrouillon(enclos: 'ENC');
      expect(vm.brouillon.apercuEnclos, 'ENC1, ENC2, ENC3');
      expect(vm.numerotationModifiee, isTrue);
      expect(
        vm.formats.enclos,
        'E',
        reason: 'Rien n\'est persisté tant que le bouton n\'est pas actionné.',
      );
    });

    test('un préfixe vide est refusé', () async {
      vm.modifierBrouillon(cage: '  ');
      final resultat = await vm.enregistrerNumerotation();
      expect(resultat, isA<Echec<void>>());
      expect(vm.formats.cage, 'C');
    });

    test('l\'enregistrement survit à un rechargement complet', () async {
      vm.modifierBrouillon(enclos: 'ENC', bassin: 'BAS');
      expect(await vm.enregistrerNumerotation(), isA<Succes<void>>());
      expect(vm.numerotationModifiee, isFalse);

      final relu = ParametresElevageViewModel(repository);
      await relu.charger();
      expect(relu.formats.enclos, 'ENC');
      expect(relu.formats.bassin, 'BAS');
      expect(relu.formats.cage, 'C');
    });

    test('enregistrer la numérotation ne touche pas aux autres paramètres '
        'd\'entreprise', () async {
      await db.customStatement(
        "INSERT INTO parametres_entreprise (id, raison_sociale, ifu) "
        "VALUES (1, 'ALLMANY ET COMPAGNIE', '0123456789') "
        "ON CONFLICT(id) DO UPDATE SET ifu = '0123456789'",
      );

      vm.modifierBrouillon(enclos: 'Z');
      expect(await vm.enregistrerNumerotation(), isA<Succes<void>>());

      final ligne = await db
          .customSelect('SELECT ifu, prefixe_enclos FROM parametres_entreprise')
          .getSingle();
      expect(ligne.read<String?>('ifu'), '0123456789');
      expect(ligne.read<String>('prefixe_enclos'), 'Z');
    });
  });

  group('Filtres du rationnement', () {
    test('recherche et filtre espèce se combinent', () {
      vm.definirEspeceRation('lapins');
      expect(vm.baremesFiltres, hasLength(3));

      vm.definirRechercheRation('reproducteur');
      expect(vm.baremesFiltres, hasLength(1));

      vm.reinitialiserFiltresRation();
      expect(vm.baremesFiltres, hasLength(18));
    });

    test('la recherche porte aussi sur le libellé d\'espèce', () {
      vm.definirRechercheRation('poissons');
      expect(vm.baremesFiltres, hasLength(3));
    });
  });

  group('Onglet « Intrants de Provende » — administrable (ÉCART_DELIBERE)', () {
    late ApprovisionnementViewModel appro;

    setUp(() async {
      appro = ApprovisionnementViewModel(ApprovisionnementRepositoryDrift(db));
      await appro.charger();
    });

    test('un intrant ajouté apparaît aussitôt dans les deux écrans', () async {
      final resultat = await appro.enregistrerIntrant(
        nom: 'Son de blé',
        categorie: Intrant.categories.first,
        stock: 0,
        unite: 'kg',
        seuil: 10,
        pmp: 350,
      );
      expect(resultat, isA<Succes<void>>());

      await vm.charger();
      final ajoute = vm.provendes.firstWhere((p) => p.nom == 'Son de blé');
      expect(ajoute.unite, 'kg');
      expect(ajoute.seuil, 10);
      expect(ajoute.prixIndicatif, 350);
      expect(
        ajoute.stock,
        0,
        reason:
            'Un intrant démarre à 0 : il se remplit par une réception de '
            'commande, jamais par une saisie directe.',
      );
      expect(
        ajoute.critique,
        isTrue,
        reason: 'Stock 0 ≤ seuil 10 : il est signalé dès sa création.',
      );
    });

    test('la modification conserve le stock et le code', () async {
      final mais = vm.provendes.firstWhere((p) => p.nom == 'Maïs');
      expect(mais.stock, 18);

      final resultat = await appro.enregistrerIntrant(
        code: mais.code,
        nom: 'Maïs jaune',
        categorie: Intrant.categories.first,
        stock: mais.stock.round(),
        unite: 'kg',
        seuil: 30,
        pmp: 650,
      );
      expect(resultat, isA<Succes<void>>());

      await vm.charger();
      final modifie = vm.provendes.firstWhere((p) => p.code == mais.code);
      expect(modifie.nom, 'Maïs jaune');
      expect(modifie.seuil, 30);
      expect(modifie.prixIndicatif, 650);
      expect(
        modifie.stock,
        18,
        reason: 'Le stock n\'est pas modifiable depuis cet écran.',
      );
    });

    test('un intrant jamais mouvementé peut être supprimé', () async {
      await appro.enregistrerIntrant(
        nom: 'Son de blé',
        categorie: Intrant.categories.first,
        stock: 0,
        unite: 'kg',
        seuil: 10,
        pmp: 350,
      );
      await vm.charger();
      final avant = vm.provendes.length;

      final ajoute = appro.tousLesIntrants.firstWhere(
        (i) => i.nom == 'Son de blé',
      );
      expect(await appro.supprimerIntrant(ajoute), isA<Succes<void>>());

      await vm.charger();
      expect(vm.provendes, hasLength(avant - 1));
    });

    test('un intrant déjà mouvementé ne peut PAS être supprimé — '
        'la clé étrangère protège l\'historique', () async {
      // Une fabrication de provende laisse une sortie sur le Mais.
      await appro.fabriquerProvende(const {'INT-001': 5});
      await vm.charger();
      final avant = vm.provendes.length;

      final mais = appro.tousLesIntrants.firstWhere((i) => i.code == 'INT-001');
      final resultat = await appro.supprimerIntrant(mais);

      expect(resultat, isA<Echec<void>>());
      await vm.charger();
      expect(vm.provendes, hasLength(avant));
      expect(
        vm.provendes.any((p) => p.code == 'INT-001'),
        isTrue,
        reason:
            'Effacer un intrant mouvementé rendrait illisible le journal '
            'qui le référence.',
      );
    });

    test('un intrant créé ici est utilisable en fabrication', () async {
      await appro.enregistrerIntrant(
        nom: 'Son de blé',
        categorie: Intrant.categories.first,
        stock: 0,
        unite: 'kg',
        seuil: 10,
        pmp: 350,
      );
      await appro.charger();

      final ajoute = appro.intrantsDeProvende.firstWhere(
        (i) => i.nom == 'Son de blé',
      );
      expect(
        appro.intrantsDeProvende.map((i) => i.code),
        contains(ajoute.code),
        reason: 'Il apparaît dans la modale de Fabrication de Provende.',
      );

      // Stock a 0 : la fabrication doit le refuser.
      final resultat = await appro.fabriquerProvende({ajoute.code: 1});
      expect(resultat, isA<Echec<String>>());
    });
  });
}

/// Rappel : `FormatsNumerotation` n'est utilisé que via le ViewModel ci-dessus.
/// Cette référence garde l'import explicite et documente la dépendance.
const FormatsNumerotation formatsParDefaut = FormatsNumerotation();
