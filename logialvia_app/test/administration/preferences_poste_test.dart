import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/auth_repository_drift.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/seed/admin_seeder.dart';
import 'package:logialvia_app/administration/domain/usecases/connecter_utilisateur_usecase.dart';
import 'package:logialvia_app/administration/presentation/viewmodels/auth_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// « Se souvenir de moi » et l'état de la barre latérale — migration v20.
///
/// La case existait depuis le portage de Doc F1 et **ne pilotait qu'elle-même** :
/// aucune écriture, nulle part. C'était le dernier manquement debout à la règle
/// « zéro fonctionnalité décorative » (Cahier des Charges §2.3).
void main() {
  late AppDatabase db;
  late PreferencesPosteRepository preferences;
  late AuthViewModel vm;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await AdminSeeder(db).executer();
    preferences = PreferencesPosteRepository(db);
    final repository = AuthRepositoryDrift(db);
    vm = AuthViewModel(
      ConnecterUtilisateurUseCase(repository),
      repository,
      preferences,
    );
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  Future<ReponseConnexion> connexion({
    String identifiant = 'admin',
    String motDePasse = 'ALLMANY2026',
  }) => vm.seConnecter(identifiant: identifiant, motDePasse: motDePasse);

  group('Se souvenir de moi — la case écrit enfin quelque chose', () {
    test('cochée, l\'identifiant survit à la fermeture', () async {
      vm.definirSeSouvenirDeMoi(true);
      final reponse = await connexion();
      expect(reponse.issue, IssueConnexion.succes);

      expect(await preferences.identifiantMemorise(), 'admin');
    });

    test('décochée, rien n\'est conservé', () async {
      vm.definirSeSouvenirDeMoi(false);
      await connexion();

      expect(await preferences.identifiantMemorise(), isNull);
    });

    test('la décocher efface un identifiant déjà mémorisé', () async {
      vm.definirSeSouvenirDeMoi(true);
      await connexion();
      expect(await preferences.identifiantMemorise(), 'admin');

      vm.definirSeSouvenirDeMoi(false);
      await connexion();

      expect(
        await preferences.identifiantMemorise(),
        isNull,
        reason:
            'Decocher doit oublier : laisser l\'ancien identifiant en base '
            'contredirait le geste de la Gerante.',
      );
    });

    test('un échec de connexion ne mémorise rien', () async {
      vm.definirSeSouvenirDeMoi(true);
      final reponse = await connexion(motDePasse: 'mauvais');

      expect(reponse.issue, IssueConnexion.identifiantsIncorrects);
      expect(
        await preferences.identifiantMemorise(),
        isNull,
        reason:
            'Memoriser un identifiant refuse le proposerait ensuite a chaque '
            'lancement, en boucle.',
      );
    });

    test('l\'identifiant est nettoyé de ses espaces', () async {
      vm.definirSeSouvenirDeMoi(true);
      await connexion(identifiant: '  admin  ');

      expect(await preferences.identifiantMemorise(), 'admin');
    });
  });

  group('Au retour sur l\'écran de connexion', () {
    test('la case reflète l\'état réel, elle ne le devine pas', () async {
      vm.definirSeSouvenirDeMoi(true);
      await connexion();

      // Nouvelle session de l'application.
      final repository = AuthRepositoryDrift(db);
      final autre = AuthViewModel(
        ConnecterUtilisateurUseCase(repository),
        repository,
        preferences,
      );
      addTearDown(autre.dispose);

      expect(autre.seSouvenirDeMoi, isFalse, reason: 'Avant chargement.');
      await autre.chargerPreferencesConnexion();

      expect(autre.identifiantMemorise, 'admin');
      expect(
        autre.seSouvenirDeMoi,
        isTrue,
        reason:
            'Une case decochee alors que l\'identifiant revient serait un '
            'mensonge de plus.',
      );
    });

    test('sans rien de mémorisé, le champ reste vide', () async {
      await vm.chargerPreferencesConnexion();

      expect(vm.identifiantMemorise, isNull);
      expect(vm.seSouvenirDeMoi, isFalse);
    });
  });

  group('La session, elle, n\'est JAMAIS mémorisée', () {
    test('aucune préférence ne porte de mot de passe ni de session', () async {
      vm.definirSeSouvenirDeMoi(true);
      await connexion();

      final lignes = await db.select(db.preferencesPoste).get();
      for (final ligne in lignes) {
        expect(
          ligne.valeur,
          isNot(contains('ALLMANY2026')),
          reason: 'Le mot de passe ne doit apparaitre nulle part.',
        );
      }
      expect(
        lignes.map((l) => l.cle),
        everyElement(isNot(contains('session'))),
      );
    });

    test('une application relancée n\'a pas de session ouverte', () async {
      vm.definirSeSouvenirDeMoi(true);
      await connexion();
      expect(vm.session, isNotNull);

      final repository = AuthRepositoryDrift(db);
      final relancee = AuthViewModel(
        ConnecterUtilisateurUseCase(repository),
        repository,
        preferences,
      );
      addTearDown(relancee.dispose);
      await relancee.chargerPreferencesConnexion();

      expect(
        relancee.session,
        isNull,
        reason:
            'Le poste est partage entre 3 roles dont un point de vente qui '
            'manipule des especes : rouvrir la session donnerait a quiconque '
            'ouvre l\'ordinateur les droits du dernier connecte.',
      );
    });
  });

  group('Barre latérale — l\'état survit au redémarrage', () {
    test('elle est dépliée par défaut', () async {
      expect(await preferences.barreLateraleRepliee(), isFalse);
    });

    test('repliée puis relue, elle le reste', () async {
      await preferences.definirBarreLateraleRepliee(repliee: true);
      expect(await preferences.barreLateraleRepliee(), isTrue);

      await preferences.definirBarreLateraleRepliee(repliee: false);
      expect(await preferences.barreLateraleRepliee(), isFalse);
    });

    test('écrire deux fois la même clé ne la duplique pas', () async {
      await preferences.definirBarreLateraleRepliee(repliee: true);
      await preferences.definirBarreLateraleRepliee(repliee: true);

      final lignes = await db.select(db.preferencesPoste).get();
      expect(
        lignes.where((l) => l.cle == 'barre_laterale_repliee'),
        hasLength(1),
      );
    });
  });

  test('la v20 est bien franchie sur une base neuve', () {
    // `schemaVersion` a continue de monter (v21 : couveuse multi-ages).
    expect(db.schemaVersion, greaterThanOrEqualTo(20));
  });
}
