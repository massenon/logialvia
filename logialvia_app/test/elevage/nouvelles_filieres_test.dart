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

/// Filières **escargots** et **ovins** (DV-16, DV-17) et colonne `dose` du
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
        ConfigurationsEspeces.parIdentifiant['ovins'],
        same(ConfigurationsEspeces.ovins),
      );
    });

    for (final config in [
      ConfigurationsEspeces.escargots,
      ConfigurationsEspeces.ovins,
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
      expect(ConfigurationsEspeces.ovins.libelleNaissances, 'Nés (Agnelage)');
      expect(ConfigurationsEspeces.escargots.categories.map((c) => c.libelle), [
        'Naissain',
        'Marchand',
        'Reproducteur',
      ]);
      expect(ConfigurationsEspeces.ovins.categories.map((c) => c.libelle), [
        'Agneau',
        'Embouche',
        'Reproducteur',
      ]);
    });
  });

  group('Routes, menu et droits', () {
    final entrees = NavigationModel.groupes.expand((g) => g.entrees).toList();

    for (final (route, module) in const [
      ('/elevage/escargots', 'heliciculture'),
      ('/elevage/ovins', 'ovins'),
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
        ('ovins', {'Agneau': 300, 'Embouche': 600, 'Reproducteur': 800}),
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
        ConfigurationsEspeces.ovins,
      ]) {
        final stades = baremes
            .where((b) => b.espece == config.identifiant)
            .map((b) => b.stade)
            .toSet();
        expect(stades, config.categories.map((c) => c.libelle).toSet());
      }
    });

    test('21 échéances escargots et 9 ovins, toutes avec une dose', () async {
      final echeances = await repository.chargerProphylaxie();
      final escargots = echeances.where((e) => e.espece == 'escargots');
      final ovins = echeances.where((e) => e.espece == 'ovins');

      expect(escargots, hasLength(21));
      expect(ovins, hasLength(9));
      for (final e in [...escargots, ...ovins]) {
        expect(e.dose, isNotNull, reason: '${e.espece} ${e.libelleJour}');
        expect(e.dose!.trim(), isNotEmpty);
        expect(e.jourCycle, inInclusiveRange(1, 365));
        expect(e.remanenceJours, greaterThanOrEqualTo(0));
      }
    });

    test('les échéances d\'avant la v27 n\'ont pas de dose inventée', () async {
      final anciennes = (await repository.chargerProphylaxie()).where(
        (e) => e.espece != 'escargots' && e.espece != 'ovins',
      );
      expect(anciennes, hasLength(11));
      expect(anciennes.every((e) => e.dose == null), isTrue);
    });

    test(
      'rémanences ovines prudentes : ivermectine 35 j, albendazole 14 j',
      () async {
        final ovins = (await repository.chargerProphylaxie())
            .where((e) => e.espece == 'ovins')
            .toList();
        expect(
          ovins
              .singleWhere((e) => e.produit == 'Ivermectine 1 %')
              .remanenceJours,
          35,
        );
        expect(
          ovins
              .where((e) => e.produit == 'Albendazole')
              .map((e) => e.remanenceJours),
          everyElement(14),
        );
        // Les vaccins n'imposent pas de delai de commercialisation.
        expect(
          ovins
              .where((e) => e.traitement.toLowerCase().contains('vaccin'))
              .map((e) => e.remanenceJours),
          everyElement(0),
        );
      },
    );

    test(
      'l\'étiquette d\'un barème ajouté ne parle pas d\'aviculture',
      () async {
        final baremes = await repository.chargerBaremes();
        for (final espece in ['escargots', 'ovins']) {
          for (final b in baremes.where((b) => b.espece == espece)) {
            expect(b.badge, 'Repère à valider', reason: '$espece ${b.stade}');
          }
        }
        // Les anciens barèmes gardent la leur.
        expect(
          baremes.firstWhere((b) => b.espece == 'goliaths').badge,
          'Générique (Aviculture, à confirmer)',
        );
      },
    );

    test('deux modules de plus, désactivés par défaut', () async {
      await ModulesActifsSeeder(db).executer();
      final modules = await db.select(db.modulesActifs).get();
      final nouveaux = modules.where(
        (m) => m.moduleId == 'heliciculture' || m.moduleId == 'ovins',
      );
      expect(nouveaux, hasLength(2));
      expect(nouveaux.every((m) => !m.isActif), isTrue);
      expect(
        {for (final m in nouveaux) m.moduleId: m.espece},
        {'heliciculture': 'escargots', 'ovins': 'ovins'},
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
      vm.changerEspeceProphylaxie('ovins');
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
        (e) => e.espece == 'ovins' && e.jourCycle == 120,
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
        (e) => e.espece == 'ovins' && e.jourCycle == 121,
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

    test('le sélecteur propose escargots et ovins', () {
      expect(
        EspecesParametrables.toutes.map((e) => e.id),
        containsAll(['escargots', 'ovins']),
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

    /// Une base **telle qu'elle était en v26** : sans escargots ni ovins, sans
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
            ? "('heliciculture','ovins')"
            : "('escargots','ovins')";
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
          echeances.where((e) => e.espece == 'ovins' && e.dose != null),
          hasLength(9),
        );
        // Les 11 echeances d'avant gardent une dose vide.
        expect(
          echeances
              .where((e) => e.espece != 'escargots' && e.espece != 'ovins')
              .every((e) => e.dose == null),
          isTrue,
        );
        expect(await repository.chargerBaremes(), hasLength(18));
        expect(
          (await db.select(db.modulesActifs).get()).map((m) => m.moduleId),
          containsAll(['heliciculture', 'ovins']),
        );
      },
    );

    test('ne touche pas à ce que l\'animalier a déjà configuré', () async {
      // Une base deja passee a la main : un module active, une ration changee
      // et une echeance supprimee sur la filiere ovins.
      final fichier = File('${dossier.path}/logialvia.db');
      final prepa = AppDatabase.pourFichier(fichier);
      await ModulesActifsSeeder(prepa).executer();
      await ParametresElevageSeeder(prepa).executer();
      await prepa.customStatement(
        "UPDATE modules_actifs SET is_actif = 1 WHERE module_id = 'ovins'",
      );
      await prepa.customStatement(
        "UPDATE baremes_ration SET ration_grammes_par_jour = 8000 "
        "WHERE espece = 'ovins' AND stade = 'Embouche'",
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
      final ovins = (await db.select(db.modulesActifs).get()).singleWhere(
        (m) => m.moduleId == 'ovins',
      );
      expect(ovins.isActif, isTrue);

      // Ration modifiee : conservee, pas de doublon.
      final rations = (await db.select(db.baremesRation).get()).where(
        (b) => b.espece == 'ovins',
      );
      expect(rations, hasLength(3));
      expect(
        rations.singleWhere((b) => b.stade == 'Embouche').rationGrammesParJour,
        8000,
      );

      // Les ovins gardent leurs 9 echeances, sans doublon ; les escargots, sans
      // calendrier, recoivent le leur.
      final echeances = await db.select(db.calendrierProphylaxie).get();
      expect(echeances.where((e) => e.espece == 'ovins'), hasLength(9));
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
  group('Migration v29 : numérotation BAC et PARC', () {
    late Directory dossier;

    setUp(() {
      dossier = Directory.systemTemp.createTempSync('logialvia_v29');
    });

    tearDown(() {
      if (dossier.existsSync()) dossier.deleteSync(recursive: true);
    });

    test('ajoute BAC et PARC sans toucher aux préfixes déjà choisis', () async {
      final fichier = File('${dossier.path}/logialvia.db');
      final prepa = AppDatabase.pourFichier(fichier);
      await ParametresElevageRepositoryDrift(
        prepa,
      ).enregistrerFormatsNumerotation(
        const FormatsNumerotation(enclos: 'ENC', cage: 'CAG'),
      );
      // Une base telle qu'elle etait en v28 : sans les deux colonnes.
      await prepa.customStatement(
        'ALTER TABLE parametres_entreprise DROP COLUMN prefixe_bac',
      );
      await prepa.customStatement(
        'ALTER TABLE parametres_entreprise DROP COLUMN prefixe_parc',
      );
      await prepa.customStatement('PRAGMA user_version = 28');
      await prepa.close();

      final db = AppDatabase.pourFichier(fichier);
      addTearDown(db.close);
      final formats = await ParametresElevageRepositoryDrift(
        db,
      ).chargerFormatsNumerotation();

      expect(formats.bac, 'BAC');
      expect(formats.parc, 'PARC');
      expect(formats.enclos, 'ENC', reason: 'Choix de la Gérante conservé.');
      expect(formats.cage, 'CAG');
    });
  });
  group('Valider un repère : « à valider » -> « validé »', () {
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

    BaremeRation ration(String espece, String stade) =>
        vm.baremes.firstWhere((b) => b.espece == espece && b.stade == stade);

    test('le plafond de ration dépend de l\'espèce : 4 kg pour un ovin, '
        '5 kg pour les autres', () async {
      final embouche = ration('ovins', 'Embouche');
      expect(embouche.rationGrammesParJour, 600);

      // Modifier la ration d'un ovin a 2 kg doit etre possible...
      expect(
        await vm.modifierRation(bareme: embouche, ration: '2000'),
        isA<Succes<void>>(),
      );
      // ...mais pas a 5 kg, qui est une faute de frappe (plafond 4 kg).
      expect(
        await vm.modifierRation(
          bareme: ration('ovins', 'Embouche'),
          ration: '5000',
        ),
        isA<Echec<void>>(),
      );
      // Les autres especes gardent leur plafond de 5 kg.
      expect(
        await vm.modifierRation(
          bareme: ration('goliaths', 'Mature'),
          ration: '5001',
        ),
        isA<Echec<void>>(),
      );
      expect(
        await vm.ajouterBareme(
          espece: 'ovins',
          stade: 'Antenais',
          ration: '3500',
        ),
        isA<Succes<void>>(),
      );
      expect(
        await vm.ajouterBareme(
          espece: 'escargots',
          stade: 'Test',
          ration: '6000',
        ),
        isA<Echec<void>>(),
      );
    });

    test('table de vérité du statut', () {
      bool statut(bool avant, bool change, bool valider) =>
          ParametresElevageViewModel.statutApresModification(
            confirmeAvant: avant,
            valeurChangee: change,
            valider: valider,
          );
      // Valider confirme toujours, valeur changee ou non.
      expect(statut(false, false, true), isTrue);
      expect(statut(false, true, true), isTrue);
      expect(statut(true, true, true), isTrue);
      // Sans Valider : une valeur changee retombe, une valeur inchangee reste.
      expect(statut(true, true, false), isFalse);
      expect(statut(true, false, false), isTrue);
      expect(statut(false, true, false), isFalse);
      expect(statut(false, false, false), isFalse);
    });

    test('Valider passe une ration de « à valider » à « validé »', () async {
      final avant = ration('ovins', 'Embouche');
      expect(avant.confirme, isFalse);
      expect(avant.badge, 'Repère à valider');

      expect(
        await vm.modifierRation(
          bareme: avant,
          ration: '${avant.rationGrammesParJour}',
          valider: true,
        ),
        isA<Succes<void>>(),
      );

      final apres = ration('ovins', 'Embouche');
      expect(apres.confirme, isTrue);
      expect(apres.badge, 'Validé');
      expect(apres.rationGrammesParJour, avant.rationGrammesParJour);
    });

    test('Valider enregistre aussi la valeur saisie', () async {
      final avant = ration('escargots', 'Marchand');
      await vm.modifierRation(bareme: avant, ration: '6', valider: true);

      final apres = ration('escargots', 'Marchand');
      expect(apres.rationGrammesParJour, 6);
      expect(apres.confirme, isTrue);
    });

    test('Enregistrer seul ne valide pas', () async {
      final avant = ration('escargots', 'Naissain');
      await vm.modifierRation(bareme: avant, ration: '2');
      expect(ration('escargots', 'Naissain').confirme, isFalse);
    });

    test(
      'changer la valeur d\'un barème validé le ramène à « à valider »',
      () async {
        final lapin = ration('lapins', 'Chair / Jeune');
        expect(lapin.confirme, isTrue, reason: 'Confirmé dans le prototype.');
        expect(lapin.badge, 'Confirmé (Référence Cuniculture)');

        await vm.modifierRation(bareme: lapin, ration: '65');
        expect(ration('lapins', 'Chair / Jeune').confirme, isFalse);
      },
    );

    test('réenregistrer la même valeur garde le statut validé', () async {
      final lapin = ration('lapins', 'Chair / Jeune');
      await vm.modifierRation(
        bareme: lapin,
        ration: '${lapin.rationGrammesParJour}',
      );
      expect(ration('lapins', 'Chair / Jeune').confirme, isTrue);
    });

    test('un barème validé depuis l\'écran ne se dit pas « Référence '
        'Cuniculture »', () async {
      final avant = ration('goliaths', 'Mature');
      await vm.modifierRation(
        bareme: avant,
        ration: '${avant.rationGrammesParJour}',
        valider: true,
      );
      expect(ration('goliaths', 'Mature').badge, 'Validé');
    });

    group('classes de poids', () {
      TauxRationPoids classe(String espece, int minG) => vm.tauxPoids
          .firstWhere((t) => t.espece == espece && t.poidsMinG == minG);

      Future<Resultat<void>> enregistrer(
        TauxRationPoids t, {
        String? taux,
        bool valider = false,
      }) => vm.enregistrerTauxPoids(
        existant: t,
        espece: t.espece,
        poidsMin: '${t.poidsMinG / (t.espece == 'ovins' ? 1000 : 1)}',
        poidsMax: t.poidsMaxG == null
            ? ''
            : '${t.poidsMaxG! / (t.espece == 'ovins' ? 1000 : 1)}',
        taux: taux ?? '${t.tauxPourcent}',
        valider: valider,
      );

      test('Valider confirme une classe ovine', () async {
        final avant = classe('ovins', 15000);
        expect(avant.confirme, isFalse);

        expect(await enregistrer(avant, valider: true), isA<Succes<void>>());
        expect(classe('ovins', 15000).confirme, isTrue);
      });

      test(
        'Valider confirme une classe de poissons, valeur modifiée comprise',
        () async {
          final avant = classe('poissons-chats', 20);
          await enregistrer(avant, taux: '4,5', valider: true);

          final apres = classe('poissons-chats', 20);
          expect(apres.confirme, isTrue);
          expect(apres.tauxPourcent, 4.5);
        },
      );

      test('modifier une classe validée la ramène à « à valider »', () async {
        await enregistrer(classe('ovins', 0), valider: true);
        expect(classe('ovins', 0).confirme, isTrue);

        await enregistrer(classe('ovins', 0), taux: '3,2');
        expect(classe('ovins', 0).confirme, isFalse);
      });

      test('réenregistrer sans changement garde le statut', () async {
        await enregistrer(classe('ovins', 0), valider: true);
        await enregistrer(classe('ovins', 0));
        expect(classe('ovins', 0).confirme, isTrue);
      });

      test('une saisie invalide ne valide rien', () async {
        final avant = classe('ovins', 15000);
        // Chevauche la classe 30+ : refusee, donc ni valeur ni statut.
        final resultat = await vm.enregistrerTauxPoids(
          existant: avant,
          espece: 'ovins',
          poidsMin: '15',
          poidsMax: '40',
          taux: '3',
          valider: true,
        );
        expect(resultat, isA<Echec<void>>());
        expect(classe('ovins', 15000).confirme, isFalse);
      });
    });
  });
}
