import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/seed/modules_actifs_seeder.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/core/router/navigation_model.dart';
import 'package:logialvia_app/core/router/permission_service.dart';
import 'package:logialvia_app/elevage/data/repositories/parametres_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/seed/parametres_elevage_seeder.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/entities/parametres_elevage.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/parametres_elevage_view_model.dart';

/// Filières **escargots** et **bovins** (DV-16, DV-17) et colonne `dose` du
/// calendrier de prophylaxie (schéma v27).
///
/// Ces filières n'existaient pas dans le prototype : leurs valeurs sont des
/// repères validés par l'animalier, jamais présentés comme « confirmés ». Les
/// tests verrouillent surtout ce qui peut faire mal en exploitation : une
/// migration qui écraserait la configuration de l'animalier, ou une filière
/// accessible par l'URL sans module activé.
void main() {
  group('Configuration des fiches', () {
    test('les deux filières sont déclarées et trouvables par identifiant', () {
      expect(
        ConfigurationsEspeces.parIdentifiant['escargots'],
        same(ConfigurationsEspeces.escargots),
      );
      expect(
        ConfigurationsEspeces.parIdentifiant['bovins'],
        same(ConfigurationsEspeces.bovins),
      );
    });

    for (final config in [
      ConfigurationsEspeces.escargots,
      ConfigurationsEspeces.bovins,
    ]) {
      test(
        '${config.libelle} : 3 catégories, une jeune, une commercialisée',
        () {
          expect(config.nombreCategories, 3);
          expect(config.indexCategorieJeune, 0);
          expect(config.indexCategorieCommercialisee, 1);
          expect(
            config.categories.where((c) => c.recoitAchatEtNaissances),
            hasLength(1),
          );
          expect(
            config.categories.where((c) => c.deduiteDesVentes),
            hasLength(1),
          );
          expect(config.route, '/elevage/${config.identifiant}');
        },
      );
    }

    test('glossaire propre à chaque filière', () {
      expect(
        ConfigurationsEspeces.escargots.libelleNaissances,
        'Nés (Éclosions)',
      );
      expect(ConfigurationsEspeces.bovins.libelleNaissances, 'Nés (Vêlage)');
      expect(ConfigurationsEspeces.escargots.categories.map((c) => c.libelle), [
        'Naissain',
        'Marchand',
        'Reproducteur',
      ]);
      expect(ConfigurationsEspeces.bovins.categories.map((c) => c.libelle), [
        'Veau',
        'Embouche',
        'Reproducteur',
      ]);
    });
  });

  group('Routes, menu et droits', () {
    final entrees = NavigationModel.groupes.expand((g) => g.entrees).toList();

    for (final (route, module) in const [
      ('/elevage/escargots', 'heliciculture'),
      ('/elevage/bovins', 'bovins'),
    ]) {
      test('$route est au menu, derrière le module « $module »', () {
        final entree = entrees.singleWhere((e) => e.route == route);
        expect(entree.moduleId, module);
      });

      test('$route : administrateur et animalier oui, caissier non', () {
        expect(PermissionService.estAutorise('admin', route), isTrue);
        expect(PermissionService.estAutorise('animalier', route), isTrue);
        expect(PermissionService.estAutorise('caissier', route), isFalse);
        expect(PermissionService.estAutorise('comptable', route), isFalse);
      });
    }
  });

  group('Peuplement d\'une base neuve', () {
    late AppDatabase db;
    late ParametresElevageRepositoryDrift repository;

    setUp(() async {
      db = AppDatabase.enMemoire();
      await ParametresElevageSeeder(db).executer();
      repository = ParametresElevageRepositoryDrift(db);
    });

    tearDown(() async => db.close());

    test('3 rations par filière, jamais « confirmées »', () async {
      final baremes = await repository.chargerBaremes();
      for (final (espece, rations) in const [
        ('escargots', {'Naissain': 1, 'Marchand': 5, 'Reproducteur': 8}),
        ('bovins', {'Veau': 1500, 'Embouche': 7000, 'Reproducteur': 9000}),
      ]) {
        final lignes = baremes.where((b) => b.espece == espece).toList();
        expect(lignes, hasLength(3), reason: espece);
        expect(lignes.every((b) => !b.confirme), isTrue, reason: espece);
        expect({
          for (final b in lignes) b.stade: b.rationGrammesParJour,
        }, rations);
      }
    });

    test('le stade de chaque ration est une catégorie de la fiche', () async {
      // C'est ce lien qui fait piloter le calcul de provende par la ration.
      final baremes = await repository.chargerBaremes();
      for (final config in [
        ConfigurationsEspeces.escargots,
        ConfigurationsEspeces.bovins,
      ]) {
        final stades = baremes
            .where((b) => b.espece == config.identifiant)
            .map((b) => b.stade)
            .toSet();
        expect(stades, config.categories.map((c) => c.libelle).toSet());
      }
    });

    test('21 échéances escargots et 9 bovins, toutes avec une dose', () async {
      final echeances = await repository.chargerProphylaxie();
      final escargots = echeances.where((e) => e.espece == 'escargots');
      final bovins = echeances.where((e) => e.espece == 'bovins');

      expect(escargots, hasLength(21));
      expect(bovins, hasLength(9));
      for (final e in [...escargots, ...bovins]) {
        expect(e.dose, isNotNull, reason: '${e.espece} ${e.libelleJour}');
        expect(e.dose!.trim(), isNotEmpty);
        expect(e.jourCycle, inInclusiveRange(1, 365));
        expect(e.remanenceJours, greaterThanOrEqualTo(0));
      }
    });

    test('les échéances d\'avant la v27 n\'ont pas de dose inventée', () async {
      final anciennes = (await repository.chargerProphylaxie()).where(
        (e) => e.espece != 'escargots' && e.espece != 'bovins',
      );
      expect(anciennes, hasLength(11));
      expect(anciennes.every((e) => e.dose == null), isTrue);
    });

    test(
      'rémanences bovines prudentes : ivermectine 35 j, albendazole 14 j',
      () async {
        final bovins = (await repository.chargerProphylaxie())
            .where((e) => e.espece == 'bovins')
            .toList();
        expect(
          bovins
              .singleWhere((e) => e.produit == 'Ivermectine 1 %')
              .remanenceJours,
          35,
        );
        expect(
          bovins
              .where((e) => e.produit == 'Albendazole')
              .map((e) => e.remanenceJours),
          everyElement(14),
        );
        // Les vaccins n'imposent pas de delai de commercialisation.
        expect(
          bovins
              .where((e) => e.traitement.toLowerCase().contains('vaccin'))
              .map((e) => e.remanenceJours),
          everyElement(0),
        );
      },
    );

    test('deux modules de plus, désactivés par défaut', () async {
      await ModulesActifsSeeder(db).executer();
      final modules = await db.select(db.modulesActifs).get();
      final nouveaux = modules.where(
        (m) => m.moduleId == 'heliciculture' || m.moduleId == 'bovins',
      );
      expect(nouveaux, hasLength(2));
      expect(nouveaux.every((m) => !m.isActif), isTrue);
      expect(
        {for (final m in nouveaux) m.moduleId: m.espece},
        {'heliciculture': 'escargots', 'bovins': 'bovins'},
      );
    });
  });

  group('Dose du calendrier de prophylaxie', () {
    late AppDatabase db;
    late ParametresElevageRepositoryDrift repository;
    late ParametresElevageViewModel vm;

    setUp(() async {
      db = AppDatabase.enMemoire();
      await ParametresElevageSeeder(db).executer();
      repository = ParametresElevageRepositoryDrift(db);
      vm = ParametresElevageViewModel(repository);
      await vm.charger();
      vm.changerEspeceProphylaxie('bovins');
    });

    tearDown(() async => db.close());

    test('une dose saisie est enregistrée, puis relue', () async {
      final resultat = await vm.enregistrerEcheance(
        jour: '120',
        traitement: 'Détiquage (rappel)',
        produit: 'Deltaméthrine',
        remanence: '7',
        dose: '  Dilution selon la notice  ',
      );
      expect(resultat, isA<Succes<void>>());

      final ajoutee = (await repository.chargerProphylaxie()).singleWhere(
        (e) => e.espece == 'bovins' && e.jourCycle == 120,
      );
      expect(ajoutee.dose, 'Dilution selon la notice');
    });

    test('une dose vide reste absente : jamais une chaîne vide', () async {
      await vm.enregistrerEcheance(
        jour: '121',
        traitement: 'Test',
        produit: 'Test',
        remanence: '0',
        dose: '   ',
      );
      final ajoutee = (await repository.chargerProphylaxie()).singleWhere(
        (e) => e.espece == 'bovins' && e.jourCycle == 121,
      );
      expect(ajoutee.dose, isNull);
    });

    test('la dose se modifie et s\'efface', () async {
      final albendazole = vm.echeancesFiltrees.firstWhere(
        (e) => e.produit == 'Albendazole' && e.jourCycle == 1,
      );
      await vm.enregistrerEcheance(
        existante: albendazole,
        jour: '1',
        traitement: albendazole.traitement,
        produit: albendazole.produit,
        remanence: '14',
        dose: '10 mg par kg de poids vif, voie orale',
      );
      var relue = (await repository.chargerProphylaxie()).singleWhere(
        (e) => e.id == albendazole.id,
      );
      expect(relue.dose, '10 mg par kg de poids vif, voie orale');

      await vm.enregistrerEcheance(
        existante: relue,
        jour: '1',
        traitement: relue.traitement,
        produit: relue.produit,
        remanence: '14',
      );
      relue = (await repository.chargerProphylaxie()).singleWhere(
        (e) => e.id == albendazole.id,
      );
      expect(relue.dose, isNull);
    });

    test('le sélecteur propose escargots et bovins', () {
      expect(
        EspecesParametrables.toutes.map((e) => e.id),
        containsAll(['escargots', 'bovins']),
      );
    });
  });

  group('Migration v27 sur une base en service', () {
    late Directory dossier;

    setUp(() {
      dossier = Directory.systemTemp.createTempSync('logialvia_v27');
    });

    tearDown(() {
      if (dossier.existsSync()) dossier.deleteSync(recursive: true);
    });

    /// Une base **telle qu'elle était en v26** : sans escargots ni bovins, sans
    /// colonne `dose`, estampillée 26.
    Future<File> baseV26({
      Future<void> Function(AppDatabase db)? avantDegradation,
    }) async {
      final fichier = File('${dossier.path}/logialvia.db');
      final db = AppDatabase.pourFichier(fichier);
      await ModulesActifsSeeder(db).executer();
      await ParametresElevageSeeder(db).executer();
      if (avantDegradation != null) await avantDegradation(db);

      for (final table in const [
        'modules_actifs',
        'baremes_ration',
        'calendrier_prophylaxie',
      ]) {
        final colonne = table == 'modules_actifs' ? 'module_id' : 'espece';
        final valeurs = table == 'modules_actifs'
            ? "('heliciculture','bovins')"
            : "('escargots','bovins')";
        await db.customStatement(
          'DELETE FROM $table WHERE $colonne IN $valeurs',
        );
      }
      await db.customStatement(
        'ALTER TABLE calendrier_prophylaxie DROP COLUMN dose',
      );
      await db.customStatement('PRAGMA user_version = 26');
      await db.close();
      return fichier;
    }

    test(
      'ajoute la colonne, les modules, les rations et les échéances',
      () async {
        final fichier = await baseV26();

        final db = AppDatabase.pourFichier(fichier);
        addTearDown(db.close);
        final repository = ParametresElevageRepositoryDrift(db);

        final echeances = await repository.chargerProphylaxie();
        expect(echeances, hasLength(41));
        expect(
          echeances.where((e) => e.espece == 'bovins' && e.dose != null),
          hasLength(9),
        );
        // Les 11 echeances d'avant gardent une dose vide.
        expect(
          echeances
              .where((e) => e.espece != 'escargots' && e.espece != 'bovins')
              .every((e) => e.dose == null),
          isTrue,
        );
        expect(await repository.chargerBaremes(), hasLength(18));
        expect(
          (await db.select(db.modulesActifs).get()).map((m) => m.moduleId),
          containsAll(['heliciculture', 'bovins']),
        );
      },
    );

    test('ne touche pas à ce que l\'animalier a déjà configuré', () async {
      // Une base deja passee a la main : un module active, une ration changee
      // et une echeance supprimee sur la filiere bovins.
      final fichier = File('${dossier.path}/logialvia.db');
      final prepa = AppDatabase.pourFichier(fichier);
      await ModulesActifsSeeder(prepa).executer();
      await ParametresElevageSeeder(prepa).executer();
      await prepa.customStatement(
        "UPDATE modules_actifs SET is_actif = 1 WHERE module_id = 'bovins'",
      );
      await prepa.customStatement(
        "UPDATE baremes_ration SET ration_grammes_par_jour = 8000 "
        "WHERE espece = 'bovins' AND stade = 'Embouche'",
      );
      // Les escargots n'ont aucune echeance : pour la migration c'est une
      // filiere nouvelle, elle recoit son calendrier.
      await prepa.customStatement(
        "DELETE FROM calendrier_prophylaxie WHERE espece = 'escargots'",
      );
      await prepa.customStatement(
        'ALTER TABLE calendrier_prophylaxie DROP COLUMN dose',
      );
      await prepa.customStatement('PRAGMA user_version = 26');
      await prepa.close();

      final db = AppDatabase.pourFichier(fichier);
      addTearDown(db.close);

      // Module deja actif : conserve son etat.
      final bovins = (await db.select(db.modulesActifs).get()).singleWhere(
        (m) => m.moduleId == 'bovins',
      );
      expect(bovins.isActif, isTrue);

      // Ration modifiee : conservee, pas de doublon.
      final rations = (await db.select(db.baremesRation).get()).where(
        (b) => b.espece == 'bovins',
      );
      expect(rations, hasLength(3));
      expect(
        rations.singleWhere((b) => b.stade == 'Embouche').rationGrammesParJour,
        8000,
      );

      // Les bovins gardent leurs 9 echeances, sans doublon ; les escargots, sans
      // calendrier, recoivent le leur.
      final echeances = await db.select(db.calendrierProphylaxie).get();
      expect(echeances.where((e) => e.espece == 'bovins'), hasLength(9));
      expect(echeances.where((e) => e.espece == 'escargots'), hasLength(21));
    });

    test('rejouée, elle ne duplique rien', () async {
      final fichier = await baseV26();

      var db = AppDatabase.pourFichier(fichier);
      await db.customSelect('SELECT 1').get();
      await db.customStatement('PRAGMA user_version = 26');
      await db.close();

      db = AppDatabase.pourFichier(fichier);
      addTearDown(db.close);
      expect(await db.select(db.calendrierProphylaxie).get(), hasLength(41));
      expect(await db.select(db.baremesRation).get(), hasLength(18));
      expect(await db.select(db.modulesActifs).get(), hasLength(5));
    });
  });
}
