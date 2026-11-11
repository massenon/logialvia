import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/seed/modules_actifs_seeder.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/router/navigation_model.dart';
import 'package:logialvia_app/core/router/permission_service.dart';
import 'package:logialvia_app/elevage/data/repositories/parametres_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/seed/parametres_elevage_seeder.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/entities/parametres_elevage.dart';
import 'package:logialvia_app/elevage/domain/services/reperes_zootechniques.dart';

/// DV-22 : la filière Bovins est REMPLACÉE par Ovins (demande du client). La filière Ovins
/// existe partout (configuration, menu, droits, module, barèmes, catégorie de produit) et
/// plus rien ne parle de Bovins. Les repères zootechniques sont génériques, jamais « confirmés ».
void main() {
  group('Ovins existe, Bovins n\'existe plus', () {
    test('configuration : identifiant, libellé, route, icône', () {
      const c = ConfigurationsEspeces.ovins;
      expect(c.identifiant, 'ovins');
      expect(c.libelle, 'Ovins');
      expect(c.route, '/elevage/ovins');
      expect(c.icone, 'grass');
      expect(ConfigurationsEspeces.parIdentifiant['ovins'], same(c));
      expect(ConfigurationsEspeces.parIdentifiant.containsKey('bovins'), isFalse);
      expect(
        ConfigurationsEspeces.parIdentifiant.values.map((e) => e.route),
        isNot(contains('/elevage/bovins')),
      );
    });

    test('repères zootechniques ovins (à valider par l\'animalier)', () {
      const c = ConfigurationsEspeces.ovins;
      expect(c.categories.map((e) => e.libelle), [
        'Agneau',
        'Embouche',
        'Reproducteur',
      ]);
      expect(c.categories.map((e) => e.rationGrammesParJour), [300, 600, 800]);
      expect(c.indexCategorieJeune, 0);
      expect(c.indexCategorieCommercialisee, 1);
      expect(c.libelleNaissances, 'Nés (Agnelage)');
      expect(c.poidsMaturiteGrammes, 35000);
      expect(c.ageMaturiteJours, 365);
      expect(c.rationEnPourcentagePoidsVif, isTrue);
      expect(c.rationMaxGrammesParJour, 4000);
      expect(c.etapesCycle, [
        'Naissance (agnelage)',
        'Agneau (0 → 3 mois)',
        'Embouche (≥ 35 kg ou 12 mois) — Éligible à la Vente',
        'Reproducteur',
      ]);
      final poids = ReperesZootechniques.poidsMoyenPlausibleG('ovins');
      expect((poids.min, poids.max), (2000, 120000));
    });

    test('menu et droits : /elevage/ovins oui, /elevage/bovins nulle part', () {
      final entrees = NavigationModel.groupes.expand((g) => g.entrees).toList();
      final ovins = entrees.singleWhere((e) => e.route == '/elevage/ovins');
      expect(ovins.libelle, 'Fiche Ovins');
      expect(ovins.moduleId, 'ovins');
      expect(entrees.any((e) => e.route.contains('bovins')), isFalse);
      expect(entrees.any((e) => e.moduleId == 'bovins'), isFalse);
      expect(entrees.any((e) => e.libelle.contains('Bovins')), isFalse);

      for (final role in const ['animalier', 'caissier', 'comptable']) {
        expect(
          PermissionService.estAutorise(role, '/elevage/bovins'),
          isFalse,
          reason: role,
        );
      }
      expect(PermissionService.estAutorise('animalier', '/elevage/ovins'), isTrue);
    });

    test('module activable `ovins`, plus de module `bovins`', () {
      expect(ModulesActifsSeeder.especeParModule['ovins'], 'ovins');
      expect(ModulesActifsSeeder.especeParModule.containsKey('bovins'), isFalse);
    });

    test('catégorie de produit « Élevage ovin », plus « Élevage bovin »', () {
      expect(ProduitVendable.categories, contains('Élevage ovin'));
      expect(ProduitVendable.categories, isNot(contains('Élevage bovin')));
    });

    test('paramètres : sélecteur Ovins 🐑, aucune espèce bovins', () {
      final ids = EspecesParametrables.toutes.map((e) => e.id);
      expect(ids, contains('ovins'));
      expect(ids, isNot(contains('bovins')));
    });

    test('une base neuve sème barèmes, classes de poids et 9 échéances ovins', () async {
      final db = AppDatabase.enMemoire();
      addTearDown(db.close);
      await ParametresElevageSeeder(db).executer();
      final repository = ParametresElevageRepositoryDrift(db);

      final baremes = await repository.chargerBaremes();
      expect(baremes.where((b) => b.espece == 'bovins'), isEmpty);
      expect({
        for (final b in baremes.where((b) => b.espece == 'ovins'))
          b.stade: b.rationGrammesParJour,
      }, {'Agneau': 300, 'Embouche': 600, 'Reproducteur': 800});

      final taux = (await repository.chargerTauxPoids())
          .where((t) => t.espece == 'ovins')
          .toList();
      expect(taux.map((t) => (t.poidsMinG, t.poidsMaxG, t.tauxPourcent)), [
        (0, 15000, 4.0),
        (15000, 30000, 3.5),
        (30000, null, 3.0),
      ]);
      expect(taux.every((t) => !t.confirme), isTrue);

      final echeances = await repository.chargerProphylaxie();
      expect(echeances.where((e) => e.espece == 'bovins'), isEmpty);
      final ovins = echeances.where((e) => e.espece == 'ovins').toList();
      expect(ovins, hasLength(9));
      expect(
        ovins.map((e) => e.traitement).join(' | '),
        allOf(contains('peste des petits ruminants (PPR)'), isNot(contains('PPCB'))),
      );
    });
  });
}
