import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/repositories/auth_repository_drift.dart';
import 'package:logialvia_app/administration/data/seed/admin_seeder.dart';
import 'package:logialvia_app/administration/domain/usecases/connecter_utilisateur_usecase.dart';
import 'package:logialvia_app/administration/presentation/viewmodels/auth_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  late AuthViewModel vm;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await AdminSeeder(db).executer();
    final repository = AuthRepositoryDrift(db);
    vm = AuthViewModel(
      ConnecterUtilisateurUseCase(repository),
      repository,
      PreferencesPosteRepository(db),
    );
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  Future<ReponseConnexion> echouer() => vm.seConnecter(
    identifiant: AdminSeeder.identifiantAdmin,
    motDePasse: 'mauvais',
  );

  group('AuthViewModel', () {
    test('signale les 2 champs vides sans appeler la base', () async {
      final reponse = await vm.seConnecter(identifiant: '  ', motDePasse: '');

      expect(reponse.issue, IssueConnexion.champsInvalides);
      expect(
        reponse.messageToast,
        'Veuillez renseigner tous les champs requis.',
      );
      expect(vm.erreurIdentifiant, 'L\'adresse e-mail est obligatoire.');
      expect(vm.erreurMotDePasse, 'Le mot de passe est obligatoire.');
      expect(await db.select(db.securityLogs).get(), isEmpty);
    });

    test('compte les tentatives et les affiche dans le message', () async {
      final premiere = await echouer();
      expect(premiere.issue, IssueConnexion.identifiantsIncorrects);
      expect(premiere.messageToast, endsWith('(1/5)'));

      final deuxieme = await echouer();
      expect(deuxieme.messageToast, endsWith('(2/5)'));
    });

    test('verrouille au 5e echec, sans toast (fidele a login.html)', () async {
      for (var i = 0; i < 4; i++) {
        await echouer();
      }
      expect(vm.verrouille, isFalse);

      final cinquieme = await echouer();

      expect(cinquieme.issue, IssueConnexion.compteVerrouille);
      expect(cinquieme.messageToast, isNull);
      expect(vm.verrouille, isTrue);
      expect(vm.libelleVerrouillage, '15min');
    });

    test('refuse toute tentative pendant le verrouillage', () async {
      for (var i = 0; i < 5; i++) {
        await echouer();
      }
      final logsApresVerrouillage =
          (await db.select(db.securityLogs).get()).length;

      final pendantVerrou = await vm.seConnecter(
        identifiant: AdminSeeder.identifiantAdmin,
        motDePasse: AdminSeeder.motDePasseInitialAdmin, // pourtant valide
      );

      expect(pendantVerrou.issue, IssueConnexion.compteVerrouille);
      expect(vm.estConnecte, isFalse);
      // Aucune tentative supplementaire n'a atteint la base.
      expect(
        (await db.select(db.securityLogs).get()).length,
        logsApresVerrouillage,
      );
    });

    test(
      'quitter puis revenir sur l\'ecran ne remet pas le verrou a zero',
      () async {
        for (var i = 0; i < 5; i++) {
          await echouer();
        }

        vm.reinitialiserErreursSaisie();

        expect(vm.verrouille, isTrue);
        expect(vm.tentatives, AuthViewModel.nombreTentativesMax);
      },
    );

    test('ouvre la session et remet le compteur a zero au succes', () async {
      await echouer();
      expect(vm.tentatives, 1);

      final reponse = await vm.seConnecter(
        identifiant: AdminSeeder.identifiantAdmin,
        motDePasse: AdminSeeder.motDePasseInitialAdmin,
      );

      expect(reponse.issue, IssueConnexion.succes);
      expect(reponse.messageToast, 'Connexion réussie — Bienvenue !');
      expect(vm.estConnecte, isTrue);
      expect(vm.session!.role.libelle, 'Administratrice');
      expect(vm.tentatives, 0);
    });

    test(
      'la deconnexion ferme la session et prepare le toast de retour',
      () async {
        await vm.seConnecter(
          identifiant: AdminSeeder.identifiantAdmin,
          motDePasse: AdminSeeder.motDePasseInitialAdmin,
        );

        await vm.seDeconnecter();

        expect(vm.estConnecte, isFalse);
        expect(
          vm.consommerMessageDiffere(),
          'Déconnexion réussie. À bientôt !',
        );
        // Le message n'est consommable qu'une seule fois.
        expect(vm.consommerMessageDiffere(), isNull);

        final audits = await db.select(db.auditLogs).get();
        expect(audits, hasLength(2)); // connexion + deconnexion
        expect(audits.last.details, contains('deconnexion'));
      },
    );

    test('bascule la visibilite du mot de passe', () {
      expect(vm.motDePasseMasque, isTrue);
      vm.basculerVisibiliteMotDePasse();
      expect(vm.motDePasseMasque, isFalse);
    });
  });
}
