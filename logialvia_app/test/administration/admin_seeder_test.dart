import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/seed/admin_seeder.dart';
import 'package:logialvia_app/administration/domain/entities/role_utilisateur.dart';
import 'package:logialvia_app/administration/domain/services/hachage_mot_de_passe.dart';
import 'package:logialvia_app/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  late AdminSeeder seeder;

  setUp(() {
    db = AppDatabase.enMemoire();
    seeder = AdminSeeder(db);
  });

  tearDown(() async => db.close());

  group('AdminSeeder (Doc K4 §8)', () {
    test('cree les 3 roles reels et le compte administrateur', () async {
      final aSeme = await seeder.executer();

      expect(aSeme, isTrue);

      final roles = await db.select(db.roles).get();
      expect(roles.map((r) => r.id).toSet(), {
        RoleUtilisateur.idAdmin,
        RoleUtilisateur.idCaissier,
        RoleUtilisateur.idAnimalier,
      });

      final utilisateurs = await db.select(db.utilisateurs).get();
      expect(utilisateurs, hasLength(1));
      expect(utilisateurs.single.identifiant, AdminSeeder.identifiantAdmin);
      expect(utilisateurs.single.roleId, RoleUtilisateur.idAdmin);
    });

    test('stocke un hash sale, jamais le mot de passe en clair', () async {
      await seeder.executer();
      final admin = await db.select(db.utilisateurs).getSingle();

      expect(admin.motDePasseHash, isNot(AdminSeeder.motDePasseInitialAdmin));
      expect(admin.sel, isNotEmpty);
      expect(
        HachageMotDePasse.verifier(
          motDePasseSaisi: AdminSeeder.motDePasseInitialAdmin,
          sel: admin.sel,
          hashAttendu: admin.motDePasseHash,
        ),
        isTrue,
      );
    });

    test('est idempotent : un 2e appel ne recree rien', () async {
      expect(await seeder.executer(), isTrue);
      expect(await seeder.executer(), isFalse);

      expect(await db.select(db.utilisateurs).get(), hasLength(1));
      expect(await db.select(db.roles).get(), hasLength(3));
    });

    test(
      'ne reinitialise jamais des donnees deja saisies par un utilisateur reel',
      () async {
        await seeder.executer();

        // L'administratrice renomme son compte et change son mot de passe.
        const nouveauSel = 'sel-modifie';
        await (db.update(
              db.utilisateurs,
            )..where((u) => u.identifiant.equals(AdminSeeder.identifiantAdmin)))
            .write(
              UtilisateursCompanion(
                nom: const Value('Gérante ALLMANY'),
                sel: const Value(nouveauSel),
                motDePasseHash: Value(
                  HachageMotDePasse.hacher('NouveauMotDePasse', nouveauSel),
                ),
              ),
            );

        await seeder.executer();

        final admin = await db.select(db.utilisateurs).getSingle();
        expect(admin.nom, 'Gérante ALLMANY');
        expect(
          HachageMotDePasse.verifier(
            motDePasseSaisi: 'NouveauMotDePasse',
            sel: admin.sel,
            hashAttendu: admin.motDePasseHash,
          ),
          isTrue,
        );
      },
    );

    test(
      'ne peuple pas PERMISSIONS_ROLE (source de verite = Doc I1 §4)',
      () async {
        await seeder.executer();
        expect(await db.select(db.permissionsRole).get(), isEmpty);
      },
    );
  });
}
