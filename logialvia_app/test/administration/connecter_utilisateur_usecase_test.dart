import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/auth_repository_drift.dart';
import 'package:logialvia_app/administration/data/seed/admin_seeder.dart';
import 'package:logialvia_app/administration/domain/entities/role_utilisateur.dart';
import 'package:logialvia_app/administration/domain/entities/session_utilisateur.dart';
import 'package:logialvia_app/administration/domain/usecases/connecter_utilisateur_usecase.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';

void main() {
  late AppDatabase db;
  late ConnecterUtilisateurUseCase usecase;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await AdminSeeder(db).executer();
    usecase = ConnecterUtilisateurUseCase(AuthRepositoryDrift(db));
  });

  tearDown(() async => db.close());

  group('ConnecterUtilisateurUseCase (Doc F1 Ecran 3)', () {
    test('connecte le compte semeur avec les bons identifiants', () async {
      final resultat = await usecase.executer(
        identifiant: AdminSeeder.identifiantAdmin,
        motDePasse: AdminSeeder.motDePasseInitialAdmin,
      );

      expect(resultat, isA<Succes<SessionUtilisateur>>());
      final session = (resultat as Succes<SessionUtilisateur>).valeur;
      expect(session.utilisateur.identifiant, AdminSeeder.identifiantAdmin);
      expect(session.role.id, RoleUtilisateur.idAdmin);
      expect(session.role.libelle, 'Administratrice');
    });

    test('tolere les espaces autour de l\'identifiant', () async {
      final resultat = await usecase.executer(
        identifiant: '  ${AdminSeeder.identifiantAdmin}  ',
        motDePasse: AdminSeeder.motDePasseInitialAdmin,
      );

      expect(resultat, isA<Succes<SessionUtilisateur>>());
    });

    test(
      'renvoie le meme message pour un identifiant inconnu et un mot de passe '
      'errone (aucune fuite d\'information)',
      () async {
        final identifiantInconnu = await usecase.executer(
          identifiant: 'inconnu@allmany.bj',
          motDePasse: AdminSeeder.motDePasseInitialAdmin,
        );
        final motDePasseErrone = await usecase.executer(
          identifiant: AdminSeeder.identifiantAdmin,
          motDePasse: 'mauvais',
        );

        expect(identifiantInconnu, isA<Echec<SessionUtilisateur>>());
        expect(motDePasseErrone, isA<Echec<SessionUtilisateur>>());

        final messageIdentifiantInconnu =
            (identifiantInconnu as Echec<SessionUtilisateur>).message;
        final messageMotDePasseErrone =
            (motDePasseErrone as Echec<SessionUtilisateur>).message;

        expect(messageIdentifiantInconnu, messageMotDePasseErrone);
        expect(
          messageIdentifiantInconnu,
          ConnecterUtilisateurUseCase.messageIdentifiantsInvalides,
        );
      },
    );

    test('journalise chaque echec dans SECURITY_LOGS (Doc I3 §6)', () async {
      await usecase.executer(
        identifiant: AdminSeeder.identifiantAdmin,
        motDePasse: 'mauvais',
      );

      final logs = await db.select(db.securityLogs).get();
      expect(logs, hasLength(1));
      expect(logs.single.typeEvenement, 'echec_connexion');
      expect(logs.single.identifiantTente, AdminSeeder.identifiantAdmin);
      // Le mot de passe saisi ne doit jamais apparaitre dans un journal.
      expect(logs.single.detail, isNot(contains('mauvais')));
    });

    test(
      'journalise la connexion reussie dans AUDIT_LOGS (Doc I3 §6)',
      () async {
        await usecase.executer(
          identifiant: AdminSeeder.identifiantAdmin,
          motDePasse: AdminSeeder.motDePasseInitialAdmin,
        );

        final logs = await db.select(db.auditLogs).get();
        expect(logs, hasLength(1));
        expect(logs.single.action, 'connexion');
        expect(logs.single.entiteConcernee, 'Session');
        expect(logs.single.details, contains('connexion'));
      },
    );

    test('un echec n\'ouvre aucune session et n\'ecrit aucun audit', () async {
      await usecase.executer(identifiant: 'inconnu', motDePasse: 'x');

      expect(await db.select(db.auditLogs).get(), isEmpty);
    });
  });
}
