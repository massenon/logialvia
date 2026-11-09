import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/domain/services/service_archivage.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';

/// Corbeille — « supprimer » archive, dans tous les modules.
void main() {
  late AppDatabase db;
  late ServiceArchivage service;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    service = ServiceArchivage(db);
  });

  tearDown(() async => db.close());

  Future<int> compter(String table) async {
    final ligne = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return ligne.read<int>('n');
  }

  Future<String> premierProduitId() async {
    final ligne = await db
        .customSelect('SELECT id FROM produits_vendables LIMIT 1')
        .getSingle();
    return ligne.read<String>('id');
  }

  group('Archiver ne détruit rien', () {
    test('la ligne quitte sa table et entre en corbeille', () async {
      final avant = await compter('produits_vendables');
      final id = await premierProduitId();

      await service.archiver(
        type: TypeArchivable.produits,
        cle: id,
        designation: 'Goliath mature',
      );

      expect(await compter('produits_vendables'), avant - 1);
      final corbeille = await service.lister();
      expect(corbeille, hasLength(1));
      expect(corbeille.single.designation, 'Goliath mature');
      expect(corbeille.single.module, 'Commercial');
      expect(corbeille.single.typeElement, 'Produit du catalogue');
    });

    test(
      'l\'auteur est enregistré, ou laissé vide s\'il est inconnu',
      () async {
        await service.archiver(
          type: TypeArchivable.produits,
          cle: await premierProduitId(),
          designation: 'X',
          utilisateurId: 'admin',
          utilisateurNom: 'SIDI ALI Raïmatou',
        );

        expect(
          (await service.lister()).single.archiveParNom,
          'SIDI ALI Raïmatou',
        );
      },
    );

    test(
      'archiver une clé inexistante ne crée pas d\'entrée fantôme',
      () async {
        await service.archiver(
          type: TypeArchivable.produits,
          cle: 999999,
          designation: 'Inexistant',
        );

        expect(await service.lister(), isEmpty);
      },
    );

    test('une clé textuelle fonctionne aussi', () async {
      final avant = await compter('intrants');

      await service.archiver(
        type: TypeArchivable.intrants,
        cle: 'INT-001',
        designation: 'Maïs',
      );

      expect(await compter('intrants'), avant - 1);
      expect((await service.lister()).single.nomTable, 'intrants');
    });
  });

  group('Restaurer remet la ligne à l\'identique', () {
    test('toutes les colonnes reviennent, valeurs comprises', () async {
      final id = await premierProduitId();
      final avant = await db
          .customSelect(
            'SELECT * FROM produits_vendables WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .getSingle();

      await service.archiver(
        type: TypeArchivable.produits,
        cle: id,
        designation: 'Goliath mature',
      );
      final archive = (await service.lister()).single;
      await service.restaurer(archive.id, estAdmin: true);

      final apres = await db
          .customSelect(
            'SELECT * FROM produits_vendables WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .getSingle();

      expect(apres.data, avant.data);
      expect(
        await service.lister(),
        isEmpty,
        reason: 'Un element restaure quitte la corbeille.',
      );
    });

    test('la date est restituée telle quelle, pas décalée', () async {
      await db.customStatement(
        'INSERT INTO cycle_couveuse (code_incubation, espece, date_incubation, '
        'oeufs_couves, statut) VALUES (?, ?, ?, ?, ?)',
        [
          'C-2026-777',
          'goliath',
          DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
          200,
          'En Incubation',
        ],
      );
      final id =
          (await db
                  .customSelect(
                    'SELECT id FROM cycle_couveuse WHERE code_incubation = ?',
                    variables: [Variable.withString('C-2026-777')],
                  )
                  .getSingle())
              .read<int>('id');

      await service.archiver(
        type: TypeArchivable.lots,
        cle: id,
        designation: 'C-2026-777',
      );
      await service.restaurer(
        (await service.lister()).single.id,
        estAdmin: true,
      );

      final relu = await db
          .customSelect(
            'SELECT date_incubation FROM cycle_couveuse WHERE id = ?',
            variables: [Variable.withInt(id)],
          )
          .getSingle();
      expect(
        relu.read<int>('date_incubation'),
        DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
        reason:
            'Une date decalee a la restauration deplacerait toutes les '
            'echeances du lot.',
      );
    });

    test('restaurer sur une référence réoccupée est refusé', () async {
      await service.archiver(
        type: TypeArchivable.intrants,
        cle: 'INT-001',
        designation: 'Maïs',
      );

      // La Gerante recree un intrant sous le meme code entre-temps.
      await db.customStatement(
        'INSERT INTO intrants (code, name, cat, unit, stock, threshold, pmp) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        ['INT-001', 'Maïs jaune', 'Intrants Provende', 'kg', 40, 25, 700],
      );

      final archive = (await service.lister()).single;
      expect(
        () => service.restaurer(archive.id, estAdmin: true),
        throwsA(isA<EchecRestauration>()),
        reason:
            'Ecraser remplacerait des donnees a jour par des donnees perimees.',
      );

      final relu = await db
          .customSelect(
            'SELECT name FROM intrants WHERE code = ?',
            variables: [Variable.withString('INT-001')],
          )
          .getSingle();
      expect(relu.read<String>('name'), 'Maïs jaune');
    });

    test('restaurer un élément absent de la corbeille échoue proprement', () {
      expect(
        () => service.restaurer(4242, estAdmin: true),
        throwsA(isA<EchecRestauration>()),
      );
    });
  });

  group('Sécurité — qui peut restaurer quoi', () {
    test('un utilisateur archivé ne se restaure que par une admin', () async {
      await db.customStatement(
        'INSERT INTO utilisateurs (nom, identifiant, mot_de_passe_hash, '
        'sel, role_id) VALUES (?, ?, ?, ?, ?)',
        ['Test', 'test', 'h', 's', 'caissier'],
      );
      final idUtilisateur =
          (await db
                  .customSelect(
                    'SELECT id FROM utilisateurs WHERE identifiant = ?',
                    variables: [Variable.withString('test')],
                  )
                  .getSingle())
              .read<int>('id');

      await service.archiver(
        type: TypeArchivable.utilisateurs,
        cle: idUtilisateur,
        designation: 'Test',
      );
      final archive = (await service.lister()).single;

      expect(
        () => service.restaurer(archive.id, estAdmin: false),
        throwsA(isA<EchecRestauration>()),
        reason:
            'Ressusciter un compte ne se fait pas depuis un poste de caisse.',
      );

      await service.restaurer(archive.id, estAdmin: true);
      expect(await compter('utilisateurs'), greaterThan(0));
    });

    test('un produit se restaure sans être administratrice', () async {
      await service.archiver(
        type: TypeArchivable.produits,
        cle: await premierProduitId(),
        designation: 'X',
      );
      final archive = (await service.lister()).single;

      await service.restaurer(archive.id, estAdmin: false);
      expect(await service.lister(), isEmpty);
    });

    test('les types réservés sont ceux qui engagent l\'entreprise', () {
      expect(TypeArchivable.utilisateurs.reserveALAdmin, isTrue);
      expect(TypeArchivable.ecritures.reserveALAdmin, isTrue);
      expect(TypeArchivable.produits.reserveALAdmin, isFalse);
      expect(TypeArchivable.baremes.reserveALAdmin, isFalse);
    });

    test('purger est réservé à l\'administratrice, sans exception', () async {
      await service.archiver(
        type: TypeArchivable.produits,
        cle: await premierProduitId(),
        designation: 'X',
      );
      final archive = (await service.lister()).single;

      expect(
        () => service.purger(archive.id, estAdmin: false),
        throwsA(isA<EchecRestauration>()),
      );
      expect(
        () => service.purgerTout(estAdmin: false),
        throwsA(isA<EchecRestauration>()),
      );

      await service.purger(archive.id, estAdmin: true);
      expect(await service.lister(), isEmpty);
    });

    test('purger détruit vraiment — la ligne ne revient pas', () async {
      final id = await premierProduitId();
      final avant = await compter('produits_vendables');

      await service.archiver(
        type: TypeArchivable.produits,
        cle: id,
        designation: 'X',
      );
      await service.purgerTout(estAdmin: true);

      expect(await service.lister(), isEmpty);
      expect(await compter('produits_vendables'), avant - 1);
    });
  });

  group('Liste blanche des tables', () {
    test('les 9 types couvrent les suppressions ouvertes à l\'utilisateur', () {
      expect(TypeArchivable.tous, hasLength(9));
      expect(TypeArchivable.tous.map((t) => t.nomTable).toSet(), {
        'utilisateurs',
        'ecriture_comptable',
        'produits_vendables',
        'intrants',
        'baremes_ration',
        'taux_ration_poids',
        'calendrier_prophylaxie',
        'cycle_couveuse',
        'messages_editeur',
      });
    });

    test('une table hors liste est inconnue', () {
      expect(TypeArchivable.parTable('ventes'), isNull);
      expect(TypeArchivable.parTable('sqlite_master'), isNull);
    });

    test('la corbeille est ordonnée du plus récent au plus ancien', () async {
      await service.archiver(
        type: TypeArchivable.intrants,
        cle: 'INT-001',
        designation: 'Maïs',
        maintenant: DateTime(2026, 8, 1),
      );
      await service.archiver(
        type: TypeArchivable.intrants,
        cle: 'INT-002',
        designation: 'Soja',
        maintenant: DateTime(2026, 8, 5),
      );

      final liste = await service.lister();
      expect(liste.map((e) => e.designation), ['Soja', 'Maïs']);
    });
  });

  group('Auteur — la corbeille dit qui a supprime', () {
    test('AuteurArchivage porte identifiant et nom', () {
      const auteur = AuteurArchivage(id: 'admin', nom: 'SIDI ALI Raimatou');
      expect(auteur.id, 'admin');
      expect(auteur.nom, 'SIDI ALI Raimatou');
    });

    test('un archivage depuis un ecran nomme son auteur', () async {
      const auteur = AuteurArchivage(id: 'caissier', nom: 'AGOSSOU Prudence');

      await service.archiver(
        type: TypeArchivable.produits,
        cle: await premierProduitId(),
        designation: 'Goliath mature',
        utilisateurId: auteur.id,
        utilisateurNom: auteur.nom,
      );

      final element = (await service.lister()).single;
      expect(
        element.archiveParNom,
        'AGOSSOU Prudence',
        reason:
            'Sur un poste partage entre trois roles, savoir QUI a supprime '
            'est la moitie de l\'interet de la corbeille.',
      );
    });

    test('hors session, l auteur reste vide plutot que devine', () async {
      await service.archiver(
        type: TypeArchivable.produits,
        cle: await premierProduitId(),
        designation: 'X',
      );

      expect(
        (await service.lister()).single.archiveParNom,
        isNull,
        reason: 'Inventer « admin » attribuerait l\'acte a quelqu\'un.',
      );
    });
  });
}
