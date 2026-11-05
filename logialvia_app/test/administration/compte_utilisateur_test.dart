import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/auth_repository_drift.dart';
import 'package:logialvia_app/administration/data/repositories/compte_repository_drift.dart';
import 'package:logialvia_app/administration/data/tables/messages_editeur_table.dart';
import 'package:logialvia_app/administration/domain/entities/compte_utilisateur.dart';
import 'package:logialvia_app/administration/domain/entities/role_utilisateur.dart';
import 'package:logialvia_app/administration/domain/entities/session_utilisateur.dart';
import 'package:logialvia_app/administration/domain/entities/utilisateur.dart';
import 'package:logialvia_app/administration/domain/services/hachage_mot_de_passe.dart';
import 'package:logialvia_app/administration/presentation/viewmodels/compte_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';

void main() {
  late AppDatabase db;
  late CompteRepositoryDrift repository;
  late CompteViewModel vm;
  late Utilisateur admin;

  const motDePasseInitial = 'ALLMANY2026';

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();

    final auth = AuthRepositoryDrift(db);
    admin = (await auth.trouverParIdentifiant('admin'))!;
    final role = (await auth.trouverRole(admin.roleId))!;

    repository = CompteRepositoryDrift(db);
    vm = CompteViewModel(
      repository,
      SessionUtilisateur(utilisateur: admin, role: role),
    );
    await vm.charger();
  });

  tearDown(() async => db.close());

  Future<bool> motDePasseValide(String candidat) async {
    final secret = await AuthRepositoryDrift(db).chargerSecret(admin.id);
    return HachageMotDePasse.verifier(
      motDePasseSaisi: candidat,
      sel: secret!.sel,
      hashAttendu: secret.motDePasseHash,
    );
  }

  group('Identité affichée', () {
    test('nom, identifiant et rôle viennent de la session réelle', () {
      expect(vm.identifiant, 'admin');
      expect(vm.nomAffiche, isNotEmpty);
      expect(vm.libelleRole, isNotEmpty);
    });

    test('les initiales tiennent sur un nom composé comme sur un mot seul', () {
      final roleFactice = const RoleUtilisateur(id: 'admin', libelle: 'Test');
      String initialesDe(String nom) => CompteViewModel(
        repository,
        SessionUtilisateur(
          utilisateur: Utilisateur(
            id: 1,
            nom: nom,
            identifiant: 'x',
            roleId: 'admin',
          ),
          role: roleFactice,
        ),
      ).initiales;

      expect(initialesDe('SIDI ALI Raïmatou'), 'SR');
      expect(initialesDe('Raïmatou'), 'RA');
      expect(initialesDe('A'), 'A');
      expect(initialesDe(''), '?');
    });
  });

  group('Changement de mot de passe — le compte est réellement modifié', () {
    test(
      'le mot de passe du seeder est bien celui attendu au départ',
      () async {
        expect(await motDePasseValide(motDePasseInitial), isTrue);
      },
    );

    test(
      'un ancien mot de passe erroné est refusé et ne change rien',
      () async {
        final resultat = await vm.changerMotDePasse(
          ancien: 'MauvaisMotDePasse1',
          nouveau: 'NouveauSecret1',
          confirmation: 'NouveauSecret1',
        );
        expect(resultat, isA<Echec<void>>());
        expect(await motDePasseValide(motDePasseInitial), isTrue);
        expect(await motDePasseValide('NouveauSecret1'), isFalse);
      },
    );

    test('les 3 règles de complexité annoncées sont réellement appliquées — '
        'le prototype ne vérifiait que la longueur', () {
      expect(CompteViewModel.erreurComplexite('Court1'), isNotNull);
      expect(CompteViewModel.erreurComplexite('minuscules1'), isNotNull);
      expect(CompteViewModel.erreurComplexite('SansChiffre'), isNotNull);
      expect(CompteViewModel.erreurComplexite('Correct12'), isNull);
    });

    test('la confirmation doit correspondre', () async {
      final resultat = await vm.changerMotDePasse(
        ancien: motDePasseInitial,
        nouveau: 'NouveauSecret1',
        confirmation: 'AutreSecret1',
      );
      expect(resultat, isA<Echec<void>>());
      expect(await motDePasseValide(motDePasseInitial), isTrue);
    });

    test('le nouveau mot de passe doit différer de l\'ancien', () async {
      final resultat = await vm.changerMotDePasse(
        ancien: motDePasseInitial,
        nouveau: motDePasseInitial,
        confirmation: motDePasseInitial,
      );
      expect(resultat, isA<Echec<void>>());
    });

    test('un changement réussi remplace le hash ET régénère le sel', () async {
      final avant = await AuthRepositoryDrift(db).chargerSecret(admin.id);

      final resultat = await vm.changerMotDePasse(
        ancien: motDePasseInitial,
        nouveau: 'NouveauSecret1',
        confirmation: 'NouveauSecret1',
      );
      expect(resultat, isA<Succes<void>>());

      expect(await motDePasseValide('NouveauSecret1'), isTrue);
      expect(await motDePasseValide(motDePasseInitial), isFalse);

      final apres = await AuthRepositoryDrift(db).chargerSecret(admin.id);
      expect(
        apres!.sel,
        isNot(avant!.sel),
        reason:
            'Réutiliser le sel permettrait de reconnaître qu\'un ancien mot '
            'de passe revient.',
      );
    });

    test(
      'le changement est tracé sans jamais journaliser le mot de passe',
      () async {
        await vm.changerMotDePasse(
          ancien: motDePasseInitial,
          nouveau: 'NouveauSecret1',
          confirmation: 'NouveauSecret1',
        );

        final lignes = await db.select(db.auditLogs).get();
        final trace = lignes.where(
          (l) =>
              l.entiteConcernee == 'Utilisateur' && l.action == 'modification',
        );
        expect(trace, hasLength(1));

        final tout = lignes
            .map((l) => '${l.entiteId} ${l.details ?? ''}')
            .join(' ');
        expect(tout.contains('NouveauSecret1'), isFalse);
        expect(tout.contains(motDePasseInitial), isFalse);
      },
    );
  });

  group('Métadonnées de session et journal personnel', () {
    Future<void> connexion() =>
        AuthRepositoryDrift(db).journaliserConnexion(admin);

    test('sans historique, « dernière connexion » vaut null, pas une date '
        'inventée', () async {
      expect(vm.metadonnees.derniereConnexion, isNull);
      expect(vm.metadonnees.nombreConnexions, 0);
    });

    test(
      'la dernière connexion est l\'AVANT-dernière ligne : la plus récente est '
      'la session en cours',
      () async {
        await connexion();
        await vm.charger();
        expect(
          vm.metadonnees.derniereConnexion,
          isNull,
          reason: 'Une seule connexion : il n\'y a pas de « fois précédente ».',
        );

        await connexion();
        await vm.charger();
        expect(vm.metadonnees.nombreConnexions, 2);
        expect(vm.metadonnees.derniereConnexion, isNotNull);
      },
    );

    test('une déconnexion ne compte pas comme une connexion', () async {
      await connexion();
      await AuthRepositoryDrift(db).journaliserDeconnexion(admin);
      await vm.charger();

      expect(
        vm.metadonnees.nombreConnexions,
        1,
        reason:
            'Les deux partagent l\'action `connexion` et se distinguent par '
            '`details` (contrainte de Doc D1).',
      );
      expect(vm.journal, hasLength(2));
      expect(vm.journal.first.action, 'Déconnexion');
      expect(vm.journal.last.action, 'Connexion réussie');
    });

    test('le journal traduit l\'entité technique en nom de module', () async {
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              horodatage: DateTime(2026, 8, 8, 16, 20),
              utilisateurId: '${admin.id}',
              action: 'creation',
              entiteConcernee: 'Vente',
              entiteId: 'V-2026-142',
            ),
          );
      await vm.charger();

      final ligne = vm.journal.first;
      expect(ligne.module, 'Point de Vente');
      expect(ligne.action, 'Vente V-2026-142 créé');
    });

    test('le journal d\'un autre utilisateur n\'apparaît pas', () async {
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              horodatage: DateTime(2026, 8, 8),
              utilisateurId: '999',
              action: 'creation',
              entiteConcernee: 'Vente',
              entiteId: 'V-2026-999',
            ),
          );
      await vm.charger();
      expect(vm.journal, isEmpty);
    });

    test('la correspondance entité → module couvre les modules livrés', () {
      expect(EntreeJournalPersonnel.modulePour('Session'), 'Authentification');
      expect(
        EntreeJournalPersonnel.modulePour('Achat'),
        'Achats & Fournisseurs',
      );
      expect(EntreeJournalPersonnel.modulePour('Ecriture'), 'Comptabilité');
      expect(
        EntreeJournalPersonnel.modulePour('Infirmerie'),
        'Doses & Vaccins',
      );
      expect(
        EntreeJournalPersonnel.modulePour('EntiteInconnue'),
        'EntiteInconnue',
        reason:
            'Jamais de cellule vide : le nom technique est un repli lisible.',
      );
    });
  });

  group('Foire Aux Questions', () {
    test('les 5 questions du prototype sont présentes', () {
      expect(CompteViewModel.faq, hasLength(5));
      expect(vm.faqFiltree, hasLength(5));
    });

    test('la recherche porte sur les mots-clés ET le texte visible', () {
      vm.definirRechercheFaq('vente');
      expect(vm.faqFiltree, hasLength(1));

      // « module » n'apparait que dans le `data-question` normalise du
      // prototype, pas dans le libelle affiche (« filière »).
      vm.definirRechercheFaq('module');
      expect(vm.faqFiltree, isNotEmpty);

      vm.definirRechercheFaq('xyz introuvable');
      expect(vm.faqFiltree, isEmpty);

      vm.definirRechercheFaq('');
      expect(vm.faqFiltree, hasLength(5));
    });
  });

  group('Contactez l\'Éditeur — le message est réellement conservé', () {
    test('une question est enregistrée et relue après rechargement', () async {
      final resultat = await vm.enregistrerMessage(
        type: 'question',
        sujet: 'Question sur le module Comptabilité',
        message: 'Comment clôturer un mois ?',
      );
      expect(resultat, isA<Succes<MessageEditeur>>());

      final relu = CompteViewModel(repository, vm.session);
      await relu.charger();
      expect(relu.messages, hasLength(1));
      expect(relu.messages.single.sujet, 'Question sur le module Comptabilité');
      expect(relu.messages.single.statut, MessageEditeurStatut.enAttente);
      expect(relu.messages.single.estBug, isFalse);
    });

    test('un signalement conserve ses étapes de reproduction', () async {
      await vm.enregistrerMessage(
        type: 'bug',
        sujet: 'Comptabilité',
        message: 'La balance affiche un écart.',
        etapes: '1. Ouvrir la Balance 2. Filtrer sur août',
      );
      final message = vm.messages.single;
      expect(message.estBug, isTrue);
      expect(message.etapes, contains('Ouvrir la Balance'));
    });

    test('des étapes vides ne sont pas stockées comme chaîne vide', () async {
      await vm.enregistrerMessage(
        type: 'bug',
        sujet: 'Autre',
        message: 'Problème divers.',
        etapes: '   ',
      );
      expect(vm.messages.single.etapes, isNull);
    });

    test('objet et message sont obligatoires', () async {
      expect(
        await vm.enregistrerMessage(
          type: 'question',
          sujet: '',
          message: 'Texte',
        ),
        isA<Echec<MessageEditeur>>(),
      );
      expect(
        await vm.enregistrerMessage(
          type: 'question',
          sujet: 'Objet',
          message: '   ',
        ),
        isA<Echec<MessageEditeur>>(),
      );
      expect(vm.messages, isEmpty);
    });

    test('le texte à envoyer est signé de l\'expéditrice réelle', () async {
      await vm.enregistrerMessage(
        type: 'bug',
        sujet: 'Ventes & Clients',
        message: 'Le total du panier est faux.',
        etapes: '1. Ajouter 2 produits',
      );
      final texte = vm.texteAEnvoyer(vm.messages.single);

      expect(texte, contains('Signalement de problème'));
      expect(texte, contains('LogiALVIA v1.0.0'));
      expect(texte, contains('admin'));
      expect(texte, contains('Module concerné : Ventes & Clients'));
      expect(texte, contains('Le total du panier est faux.'));
      expect(texte, contains('Étapes pour reproduire'));
    });

    test('une question n\'affiche pas de section « Étapes »', () async {
      await vm.enregistrerMessage(
        type: 'question',
        sujet: 'Objet',
        message: 'Texte de la question.',
      );
      final texte = vm.texteAEnvoyer(vm.messages.single);
      expect(texte, contains('Objet : Objet'));
      expect(texte.contains('Étapes pour reproduire'), isFalse);
    });

    test(
      'le statut passe à Transmis, puis le message peut être supprimé',
      () async {
        await vm.enregistrerMessage(
          type: 'question',
          sujet: 'Objet',
          message: 'Texte.',
        );

        expect(
          await vm.marquerTransmis(vm.messages.single),
          isA<Succes<void>>(),
        );
        expect(vm.messages.single.statut, MessageEditeurStatut.transmis);

        expect(
          await vm.supprimerMessage(vm.messages.single),
          isA<Succes<void>>(),
        );
        expect(vm.messages, isEmpty);
      },
    );

    test('les messages les plus récents apparaissent en premier', () async {
      await vm.enregistrerMessage(
        type: 'question',
        sujet: 'Premier',
        message: 'A',
      );
      await vm.enregistrerMessage(
        type: 'question',
        sujet: 'Second',
        message: 'B',
      );
      expect(vm.messages.first.sujet, 'Second');
    });
  });
}
