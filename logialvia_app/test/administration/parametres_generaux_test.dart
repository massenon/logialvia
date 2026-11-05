import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/parametres_repository_drift.dart';
import 'package:logialvia_app/administration/data/repositories/auth_repository_drift.dart';
import 'package:logialvia_app/administration/domain/entities/role_utilisateur.dart';
import 'package:logialvia_app/administration/domain/entities/utilisateur.dart';
import 'package:logialvia_app/administration/domain/usecases/connecter_utilisateur_usecase.dart';
import 'package:logialvia_app/administration/presentation/viewmodels/parametres_generaux_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';

void main() {
  late AppDatabase db;
  late ParametresRepositoryDrift repository;
  late ParametresGenerauxViewModel vm;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    repository = ParametresRepositoryDrift(db);
    vm = ParametresGenerauxViewModel(repository);
    await vm.charger();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  group('Paramètres de l\'entreprise', () {
    test('les valeurs par défaut du prototype sont proposées', () {
      expect(vm.parametres.raisonSociale, 'ALLMANY ET COMPAGNIE');
      expect(vm.parametres.nomPromoteur, 'SIDI ALI Raïmatou');
      expect(vm.parametres.adresseSiege, 'Natitingou, Bénin');
    });

    test('l\'enregistrement persiste réellement', () async {
      vm.mettreAJour(
        vm.parametres.copyWith(
          raisonSociale: 'ALLMANY SARL',
          ifu: '1234567890',
          rccm: 'RB/NAT/26 B 123',
        ),
      );

      expect(await vm.enregistrerParametres(), isA<Succes<void>>());

      // Relecture depuis la base, pas depuis l'etat en memoire.
      final relu = await ParametresRepositoryDrift(db).charger();
      expect(relu.raisonSociale, 'ALLMANY SARL');
      expect(relu.ifu, '1234567890');
    });

    test('la raison sociale est obligatoire', () async {
      vm.mettreAJour(vm.parametres.copyWith(raisonSociale: '  ', ifu: '123'));
      expect(await vm.enregistrerParametres(), isA<Echec<void>>());
    });

    test('l\'IFU est obligatoire', () async {
      vm.mettreAJour(vm.parametres.copyWith(ifu: ''));
      expect(await vm.enregistrerParametres(), isA<Echec<void>>());
    });

    test('l\'IFU n\'accepte que des chiffres (F8 Onglet 2)', () async {
      vm.mettreAJour(vm.parametres.copyWith(ifu: 'ABC123'));
      expect(await vm.enregistrerParametres(), isA<Echec<void>>());

      vm.mettreAJour(vm.parametres.copyWith(ifu: '0987654321'));
      expect(await vm.enregistrerParametres(), isA<Succes<void>>());
    });

    test('un e-mail mal formé est refusé', () async {
      vm.mettreAJour(vm.parametres.copyWith(ifu: '123', email: 'pas-un-email'));
      expect(await vm.enregistrerParametres(), isA<Echec<void>>());
    });
  });

  group('BR-ADM-004 — activation conditionnelle de MeCeF', () {
    test('MeCeF n\'est pas activable sans IFU ni RCCM', () {
      expect(vm.parametres.mecefActivable, isFalse);
      expect(vm.basculerMecef(actif: true), isA<Echec<void>>());
      expect(vm.parametres.mecefActif, isFalse);
    });

    test('l\'IFU seul ne suffit pas', () {
      vm.mettreAJour(vm.parametres.copyWith(ifu: '1234567890'));
      expect(vm.parametres.mecefActivable, isFalse);
      expect(vm.basculerMecef(actif: true), isA<Echec<void>>());
    });

    test('IFU + RCCM rendent MeCeF activable', () {
      vm.mettreAJour(
        vm.parametres.copyWith(ifu: '1234567890', rccm: 'RB/NAT/26 B 123'),
      );
      expect(vm.parametres.mecefActivable, isTrue);
      expect(vm.basculerMecef(actif: true), isA<Succes<void>>());
      expect(vm.parametres.mecefActif, isTrue);
    });

    test(
      'la règle est appliquée à la persistance, pas seulement à l\'écran',
      () async {
        // MeCeF actif mais RCCM vide : la base ne doit pas le persister actif.
        vm.mettreAJour(
          vm.parametres.copyWith(ifu: '1234567890', rccm: 'RB/NAT/26 B 123'),
        );
        vm.basculerMecef(actif: true);
        vm.mettreAJour(vm.parametres.copyWith(rccm: ''));

        await vm.enregistrerParametres();

        final relu = await ParametresRepositoryDrift(db).charger();
        expect(relu.mecefActif, isFalse);
      },
    );
  });

  group('Gestion des utilisateurs', () {
    test('le compte administrateur seedé est listé', () {
      expect(vm.utilisateurs, hasLength(1));
      expect(vm.utilisateurs.single.utilisateur.identifiant, 'admin');
      expect(vm.utilisateurs.single.role.libelle, 'Administratrice');
    });

    test('un compte créé peut réellement se connecter', () async {
      final creation = await vm.creerUtilisateur(
        nom: 'KOSSOU Marc',
        identifiant: 'marc',
        roleId: RoleUtilisateur.idCaissier,
        motDePasse: 'MotDePasse2026',
        confirmation: 'MotDePasse2026',
      );
      expect(creation, isA<Succes<Utilisateur>>());

      // Le vrai critere : le compte est utilisable pour se connecter.
      // Sans les champs identifiant/mot de passe ajoutes a la modale, cette
      // verification serait impossible — le compte serait inerte.
      final connexion = await ConnecterUtilisateurUseCase(
        AuthRepositoryDrift(db),
      ).executer(identifiant: 'marc', motDePasse: 'MotDePasse2026');

      expect(connexion, isA<Succes<dynamic>>());
    });

    test('refuse un identifiant déjà utilisé', () async {
      final resultat = await vm.creerUtilisateur(
        nom: 'Doublon',
        identifiant: 'admin',
        roleId: RoleUtilisateur.idCaissier,
        motDePasse: 'MotDePasse2026',
        confirmation: 'MotDePasse2026',
      );
      expect(resultat, isA<Echec<Utilisateur>>());
      expect(vm.utilisateurs, hasLength(1));
    });

    test('refuse un mot de passe trop court ou non confirmé', () async {
      expect(
        await vm.creerUtilisateur(
          nom: 'Test',
          identifiant: 'test1',
          roleId: RoleUtilisateur.idCaissier,
          motDePasse: 'court',
          confirmation: 'court',
        ),
        isA<Echec<Utilisateur>>(),
      );
      expect(
        await vm.creerUtilisateur(
          nom: 'Test',
          identifiant: 'test2',
          roleId: RoleUtilisateur.idCaissier,
          motDePasse: 'MotDePasse2026',
          confirmation: 'AutreChose2026',
        ),
        isA<Echec<Utilisateur>>(),
      );
    });

    test('refuse un rôle non renseigné', () async {
      expect(
        await vm.creerUtilisateur(
          nom: 'Test',
          identifiant: 'test3',
          roleId: null,
          motDePasse: 'MotDePasse2026',
          confirmation: 'MotDePasse2026',
        ),
        isA<Echec<Utilisateur>>(),
      );
    });

    test('seuls caissier et animalier sont attribuables (F8 Onglet 3)', () {
      final ids = ParametresGenerauxViewModel.rolesAttribuables
          .map((r) => r.id)
          .toList();
      expect(ids, [RoleUtilisateur.idCaissier, RoleUtilisateur.idAnimalier]);
      expect(ids, isNot(contains(RoleUtilisateur.idAdmin)));
    });

    test(
      'le dernier administrateur ne peut pas être supprimé — garde-fou ajouté',
      () async {
        final admin = vm.utilisateurs.single;
        final resultat = await vm.supprimerUtilisateur(admin);

        expect(resultat, isA<Echec<void>>());
        expect(vm.utilisateurs, hasLength(1));
      },
    );

    test('un compte secondaire peut être supprimé', () async {
      await vm.creerUtilisateur(
        nom: 'KOSSOU Marc',
        identifiant: 'marc',
        roleId: RoleUtilisateur.idCaissier,
        motDePasse: 'MotDePasse2026',
        confirmation: 'MotDePasse2026',
      );
      expect(vm.utilisateurs, hasLength(2));

      final marc = vm.utilisateurs.firstWhere(
        (u) => u.utilisateur.identifiant == 'marc',
      );
      expect(await vm.supprimerUtilisateur(marc), isA<Succes<void>>());
      expect(vm.utilisateurs, hasLength(1));
    });
  });
}
