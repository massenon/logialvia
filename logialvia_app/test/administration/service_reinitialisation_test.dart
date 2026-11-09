import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/seed/admin_seeder.dart';
import 'package:logialvia_app/administration/domain/services/service_archivage.dart';
import 'package:logialvia_app/administration/domain/services/service_reinitialisation.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';

/// Réinitialisation des données de test — onglet des Paramètres Généraux.
void main() {
  late AppDatabase db;
  late ServiceReinitialisation service;

  Future<int> compter(String table) async {
    final ligne = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return ligne.read<int>('n');
  }

  /// Crée une activité complète : une vente, une écriture, une fiche, un lot.
  Future<void> creerActivite() async {
    await db.customStatement(
      'INSERT INTO ventes (id, updated_at, ref, client, date_vente, mode, status, total, paye) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        '2026-01-01T00:00:00.000Z',
        'V-2026-001',
        'AGOSSOU Prudence',
        DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
        'Espèces',
        'Payée',
        12000.0,
        12000.0,
      ],
    );
    await db.customStatement(
      'INSERT INTO ecriture_comptable (id, piece_id, updated_at, exercice_annee, '
      'numero_compte, date_ecriture, debit, credit, libelle) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        'ffffffff-ffff-4fff-8fff-ffffffffffff',
        '2026-08-01T00:00:00.000Z',
        2026,
        '531',
        DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
        12000.0,
        0.0,
        'Encaissement',
      ],
    );
    await db.customStatement(
      'INSERT INTO cycle_couveuse (id, updated_at, code_incubation, espece, '
      'date_incubation, oeufs_couves, statut) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        'a1b2c3d4-0000-4000-8000-000000000001',
        '2026-08-01T00:00:00.000000Z',
        'C-2026-001',
        'goliath',
        DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
        200,
        'En Incubation',
      ],
    );
    await db.customStatement(
      'INSERT INTO clients (id, nom, telephone, updated_at) VALUES (?, ?, ?, ?)',
      [
        '44444444-4444-4444-8444-444444444444',
        'AGOSSOU Prudence',
        '97000000',
        '2026-11-09T09:00:00.000Z',
      ],
    );
  }

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    await AdminSeeder(db).executer();
    service = ServiceReinitialisation(db);
  });

  tearDown(() async => db.close());

  group('Aperçu — ce qui serait effacé, sans rien effacer', () {
    test('il compte les lignes réelles, table par table', () async {
      await creerActivite();

      final apercu = await service.apercu();

      expect(apercu['ventes'], 1);
      expect(apercu['ecriture_comptable'], 1);
      expect(apercu['cycle_couveuse'], 1);
      expect(apercu['clients'], 1);
      expect(
        await compter('ventes'),
        1,
        reason: 'L\'apercu ne doit rien avoir efface.',
      );
    });

    test('les tables vides n\'encombrent pas l\'aperçu', () async {
      final apercu = await service.apercu();
      expect(
        apercu.values.every((n) => n > 0),
        isTrue,
        reason: 'Afficher « soins : 0 » ne renseigne personne.',
      );
    });
  });

  group('Ce qui est effacé', () {
    test('toute l\'activité disparaît', () async {
      await creerActivite();

      final bilan = await service.executer();

      expect(await compter('ventes'), 0);
      expect(await compter('ecriture_comptable'), 0);
      expect(await compter('cycle_couveuse'), 0);
      expect(await compter('clients'), 0);
      expect(bilan.lignesEffacees, 4);
    });

    test('la corbeille est vidée aussi', () async {
      final id =
          (await db
                  .customSelect('SELECT id FROM produits_vendables LIMIT 1')
                  .getSingle())
              .read<String>('id');
      await ServiceArchivage(
        db,
      ).archiver(type: TypeArchivable.produits, cle: id, designation: 'X');
      expect(await compter('corbeille'), 1);

      await service.executer();

      expect(
        await compter('corbeille'),
        0,
        reason: 'Son contenu ne designerait plus rien apres la remise a zero.',
      );
    });
  });

  group('Ce qui est préservé — le cœur de la garantie', () {
    test('le compte administrateur survit', () async {
      final avant = await compter('utilisateurs');
      expect(avant, greaterThan(0));

      await service.executer();

      expect(
        await compter('utilisateurs'),
        avant,
        reason:
            'Effacer le compte admin rendrait l\'application inaccessible : '
            'plus personne ne pourrait se connecter.',
      );
    });

    test('les rôles et permissions survivent', () async {
      final roles = await compter('roles');
      await service.executer();
      expect(await compter('roles'), roles);
    });

    test('les paramètres de l\'entreprise survivent', () async {
      // La table est a ligne unique et n'existe qu'une fois enregistree.
      await db.customStatement(
        'INSERT INTO parametres_entreprise (id, raison_sociale) VALUES (?, ?)',
        [1, 'ALLMANY ET COMPAGNIE'],
      );
      await service.executer();

      final ligne = await db
          .customSelect('SELECT raison_sociale FROM parametres_entreprise')
          .getSingle();
      expect(ligne.read<String>('raison_sociale'), 'ALLMANY ET COMPAGNIE');
    });

    test('le plan comptable et l\'exercice survivent', () async {
      final comptes = await compter('plan_comptable');
      expect(comptes, greaterThan(0));

      await service.executer();

      expect(await compter('plan_comptable'), comptes);
      expect(
        await compter('exercice_comptable'),
        greaterThan(0),
        reason:
            'Sans exercice ouvert, aucune ecriture ne pourrait plus etre '
            'saisie apres la remise a zero.',
      );
    });

    test('le catalogue, les intrants et les barèmes survivent', () async {
      final produits = await compter('produits_vendables');
      final intrants = await compter('intrants');
      final baremes = await compter('baremes_ration');

      await service.executer();

      expect(await compter('produits_vendables'), produits);
      expect(await compter('intrants'), intrants);
      expect(await compter('baremes_ration'), baremes);
    });

    test('les préférences du poste survivent', () async {
      await db.customStatement(
        'INSERT INTO preferences_poste (cle, valeur) VALUES (?, ?)',
        ['identifiant_memorise', 'admin'],
      );

      await service.executer();

      expect(await compter('preferences_poste'), 1);
    });

    test('les journaux d\'audit survivent — c\'est délibéré', () async {
      await db.customStatement(
        'INSERT INTO audit_logs (utilisateur_id, action, entite_concernee, '
        'entite_id, horodatage) VALUES (?, ?, ?, ?, ?)',
        [
          'admin',
          'connexion',
          'session',
          '1',
          DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
        ],
      );

      await service.executer();

      // La remise à zéro inscrit désormais sa **propre** trace : le journal
      // compte donc 2 entrées. La garantie testée ici est inchangée — celle
      // d'avant a survécu.
      final connexions = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM audit_logs WHERE action = 'connexion'",
          )
          .getSingle();
      expect(
        connexions.read<int>('n'),
        1,
        reason:
            'Une operation qui efface l\'activite ET la trace de qui l\'a '
            'effacee n\'est pas une reinitialisation.',
      );
    });

    test('une modification du catalogue n\'est pas réécrasée', () async {
      await db.customStatement(
        'UPDATE produits_vendables SET name = ? WHERE name = ?',
        ['Goliath adulte', 'Goliath mature'],
      );

      await service.executer();

      final ligne = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM produits_vendables WHERE name = ?',
            variables: [Variable.withString('Goliath adulte')],
          )
          .getSingle();
      expect(
        ligne.read<int>('n'),
        1,
        reason:
            'Les seeders sont completifs : ils n\'ecrasent pas ce que la '
            'Gerante a modifie.',
      );
    });
  });

  group('Après la réinitialisation, l\'application est utilisable', () {
    test('une nouvelle vente peut être enregistrée', () async {
      await creerActivite();
      await service.executer();

      await db.customStatement(
        'INSERT INTO ventes (id, updated_at, ref, client, date_vente, mode, status, total, '
        'paye) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          '2026-01-01T00:00:00.000Z',
          'V-2026-001',
          'Client Comptant',
          DateTime(2026, 9, 1).millisecondsSinceEpoch ~/ 1000,
          'Espèces',
          'Payée',
          5000.0,
          5000.0,
        ],
      );

      expect(
        await compter('ventes'),
        1,
        reason:
            'La reference V-2026-001 est libre : la sequence repart de zero '
            'comme le reste.',
      );
    });

    test('réinitialiser deux fois de suite ne casse rien', () async {
      await creerActivite();
      await service.executer();
      final second = await service.executer();

      expect(second.lignesEffacees, 0);
      expect(await compter('utilisateurs'), greaterThan(0));
    });
  });

  group('Périmètre déclaré', () {
    test('les tables d\'activité sont listées enfants avant parents', () {
      final tables = ServiceReinitialisation.tablesOperationnelles;

      expect(
        tables.indexOf('lignes_vente'),
        lessThan(tables.indexOf('ventes')),
        reason: 'Une ligne de vente reference sa vente.',
      );
      expect(
        tables.indexOf('lignes_achat'),
        lessThan(tables.indexOf('achats')),
      );
    });

    test('aucune table de configuration n\'y figure', () {
      const interdites = [
        'utilisateurs',
        'roles',
        'permissions_role',
        'parametres_entreprise',
        'plan_comptable',
        'exercice_comptable',
        'modules_actifs',
        'preferences_poste',
        'baremes_ration',
        'calendrier_prophylaxie',
        'produits_vendables',
        'intrants',
        // Ajoute en v26 : la grille de taxation est du referentiel fiscal, au
        // meme titre que le plan de comptes.
        'groupes_taxe',
        'audit_logs',
        'security_logs',
      ];
      for (final table in interdites) {
        expect(
          ServiceReinitialisation.tablesOperationnelles,
          isNot(contains(table)),
          reason: '$table decrit l\'exploitation, pas son activite.',
        );
      }
    });
  });

  group('La frontière arbitrée par la Gérante', () {
    test('les fournisseurs partent avec l\'activité', () async {
      // Ils etaient preserves, au motif qu'un fournisseur ressemble a du
      // referentiel. Arbitrage : un fournisseur saisi pendant l'essai n'en est
      // pas un, il part comme les clients.
      expect(
        ServiceReinitialisation.tablesOperationnelles,
        contains('fournisseurs'),
      );
    });

    test('les achats sont vidés avant les fournisseurs', () {
      // `achats.fournisseurId` les reference : l'ordre inverse violerait la
      // contrainte de cle etrangere, et la remise a zero echouerait a
      // mi-parcours.
      final tables = ServiceReinitialisation.tablesOperationnelles;
      expect(
        tables.indexOf('achats'),
        lessThan(tables.indexOf('fournisseurs')),
        reason:
            'Les enfants avant les parents, sinon SQLite refuse la '
            'suppression.',
      );
    });

    test('le référentiel comptable SYSCOHADA n\'est jamais vidé', () {
      // C'est la configuration comptable de l'exploitation. L'effacer
      // rendrait le logiciel incapable d'enregistrer la moindre ecriture.
      for (final table in ['plan_comptable', 'exercice_comptable']) {
        expect(
          ServiceReinitialisation.tablesOperationnelles,
          isNot(contains(table)),
          reason: '$table est du référentiel, pas de l\'activité.',
        );
      }
    });

    test('les écritures partent, parce qu\'une dépense est une écriture', () {
      // Il n'existe pas de table des depenses : `enregistrerPiece` ecrit dans
      // ECRITURE_COMPTABLE. Conserver les ecritures en effacant les ventes
      // laisserait un journal qui affirme un chiffre d'affaires sans aucune
      // vente derriere — des livres faux.
      expect(
        ServiceReinitialisation.tablesOperationnelles,
        contains('ecriture_comptable'),
      );
    });
  });

  group('La remise à zéro laisse sa propre trace', () {
    test('une entrée d\'audit est écrite, au nom de qui a effacé', () async {
      final avant = await compter('audit_logs');

      await service.executer(parIdentifiant: 'admin');

      final apres = await compter('audit_logs');
      expect(
        apres,
        avant + 1,
        reason:
            'Le journal etait bien preserve, mais rien n\'y etait inscrit : '
            'apres une remise a zero, plus rien ne disait qu\'elle avait eu '
            'lieu. Constate sur une base reelle — treize tables vides, '
            'quarante-quatre entrees d\'audit, toutes des connexions.',
      );

      final trace = await db
          .customSelect(
            "SELECT action, utilisateur_id, details FROM audit_logs "
            "WHERE action = 'reinitialisation' ORDER BY id DESC LIMIT 1",
          )
          .getSingle();
      expect(trace.read<String>('utilisateur_id'), 'admin');
      expect(trace.read<String>('details'), contains('lignes_effacees'));
    });

    test('la trace survit à la remise à zéro qui la produit', () async {
      await service.executer(parIdentifiant: 'admin');
      await service.executer(parIdentifiant: 'admin');

      final traces = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM audit_logs "
            "WHERE action = 'reinitialisation'",
          )
          .getSingle();
      expect(
        traces.read<int>('n'),
        2,
        reason:
            'La seconde remise a zero ne doit pas effacer la premiere '
            'trace : audit_logs n\'est pas une table d\'activite.',
      );
    });
  });
}
