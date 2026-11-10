import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/compte_repository_drift.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/administration/data/sync/table_messages_editeur_poste.dart';
import 'package:logialvia_app/administration/domain/services/service_archivage.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import '../core/sync/faux_serveur_sync.dart';

/// Messages à l'éditeur (doc 47u §4, v45) : un fait synchronisé, dernier écrivain gagne,
/// pierre tombale à la suppression. Le faux serveur rejoue `MessagesEditeurTable`.
class _Poste {
  _Poste(this.serveur) : db = AppDatabase.enMemoire() {
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: serveur.client,
    );
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: appairage,
      demandes: DepotDemandesReferentiel(db),
      tables: [TableMessagesEditeurPoste(db)],
      client: serveur.client,
    );
    repo = CompteRepositoryDrift(db);
  }

  final FauxServeurSync serveur;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final CompteRepositoryDrift repo;

  Future<void> demarrer() async {
    await preferences.definirCatalogueAdopte();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }

  Future<void> ecrire({
    String type = 'question',
    String sujet = 'Comptabilité',
    String message = 'Comment clôturer ?',
    String? etapes,
    String auteur = 'Awa (awa) — Comptable',
  }) => repo.enregistrerMessage(
    type: type,
    sujet: sujet,
    message: message,
    etapes: etapes,
    utilisateurId: '1',
    auteurNom: auteur,
  );

  Future<List<MessageEditeurRow>> messages() => (db.select(
    db.messagesEditeur,
  )..orderBy([(m) => OrderingTerm.asc(m.horodatage)])).get();

  Future<MessageEditeurRow> premier() async => (await messages()).first;
}

void main() {
  late FauxServeurSync serveur;
  final postes = <_Poste>[];

  Future<_Poste> poste() async {
    final p = _Poste(serveur);
    postes.add(p);
    await p.demarrer();
    return p;
  }

  setUp(() {
    serveur = FauxServeurSync();
    postes.clear();
  });

  tearDown(() async {
    for (final p in postes) {
      await p.db.close();
    }
  });

  const idDistant = 'cccccccc-0000-4000-8000-000000000001';

  Map<String, dynamic> ligneServeur({
    String id = idDistant,
    String type = 'question',
    String sujet = 'Du web',
    String message = 'Écrit au web',
    String statut = 'En attente',
    String? supprimeLe,
    String instant = '2026-11-05T08:00:00.000000Z',
  }) => {
    'id': id,
    'device_id': '00000000-0000-0000-0000-000000000000',
    'horodatage': '2026-11-05T08:00:00.000000Z',
    'type': type,
    'sujet': sujet,
    'message': message,
    'etapes': null,
    'auteur': 'Gérante (gerante) — Administrateur',
    'statut': statut,
    'supprime_le': supprimeLe,
    'updated_at': instant,
    'serveur_modifie_le': instant,
  };

  group('envoi', () {
    test(
      'un message est envoyé au format du contrat, avec son auteur',
      () async {
        final a = await poste();
        await a.ecrire(
          type: 'bug',
          sujet: 'Ventes & Clients',
          message: 'Plante',
          etapes: '1. Ouvrir',
        );

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(r.refusees, 0);
        final m = await a.premier();
        expect(serveur.messagesEditeur.keys, [m.id]);
        final envoye = serveur.messagesEditeur[m.id]!;
        expect(envoye['type'], 'bug');
        expect(envoye['sujet'], 'Ventes & Clients');
        expect(envoye['etapes'], '1. Ouvrir');
        expect(envoye['auteur'], 'Awa (awa) — Comptable');
        expect(envoye['statut'], 'En attente');
        expect(envoye['supprime_le'], isNull);
        expect(m.syncStatus, 'synced');
      },
    );

    test('un second envoi n\'envoie rien', () async {
      final a = await poste();
      await a.ecrire();
      await a.moteur.synchroniser();
      final avant = serveur.envois.length;

      final r = await a.moteur.synchroniser();

      expect(r.envoyees, 0);
      expect(serveur.envois.length, avant);
    });

    test(
      'marquer transmis est une modification : le message repart, daté',
      () async {
        final a = await poste();
        await a.ecrire();
        await a.moteur.synchroniser();
        final m = await a.premier();
        await Future<void>.delayed(const Duration(milliseconds: 3));

        await a.repo.marquerTransmis(m.id);
        expect((await a.premier()).syncStatus, 'pending');
        await a.moteur.synchroniser();

        expect(serveur.messagesEditeur[m.id]!['statut'], 'Transmis');
        expect((await a.premier()).syncStatus, 'synced');
      },
    );

    test(
      'un refus du serveur place le message en conflit, motif français',
      () async {
        final a = await poste();
        await a.ecrire();
        final m = await a.premier();
        // Un type que le serveur ne connaît pas (corruption locale) : refusé, jamais lissé.
        await (a.db.update(a.db.messagesEditeur)
              ..where((x) => x.id.equals(m.id)))
            .write(const MessagesEditeurCompanion(type: Value('plainte')));

        final r = await a.moteur.synchroniser();

        expect(r.refusees, 1);
        final apres = await a.premier();
        expect(apres.syncStatus, 'conflict');
        expect(
          apres.syncMotif,
          'Le type du message est inconnu (question ou problème).',
        );
        expect(serveur.messagesEditeur, isEmpty);
      },
    );
  });

  group('réception', () {
    test(
      'un message écrit au web arrive au registre du poste, sans aucun effet de bord',
      () async {
        final a = await poste();
        serveur.messagesEditeur[idDistant] = ligneServeur();

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        final m = await a.premier();
        expect(m.id, idDistant);
        expect(m.sujet, 'Du web');
        expect(m.auteurNom, 'Gérante (gerante) — Administrateur');
        expect(m.syncStatus, 'synced');
        expect(
          m.utilisateurId,
          '',
          reason: 'l\'identifiant d\'utilisatrice est local',
        );
        expect(await a.db.select(a.db.corbeille).get(), isEmpty);
      },
    );

    test(
      'une ligne incohérente du serveur est refusée, jamais lissée',
      () async {
        final a = await poste();
        serveur.messagesEditeur[idDistant] = ligneServeur(type: 'plainte');
        serveur.messagesEditeur['cccccccc-0000-4000-8000-000000000002'] =
            ligneServeur(
              id: 'cccccccc-0000-4000-8000-000000000002',
              sujet: '  ',
            );
        serveur.messagesEditeur['cccccccc-0000-4000-8000-000000000003'] =
            ligneServeur(
              id: 'cccccccc-0000-4000-8000-000000000003',
              statut: 'Lu',
            );

        await a.moteur.synchroniser();

        expect(await a.messages(), isEmpty);
      },
    );

    test(
      'dernier écrivain gagne : la version plus récente du web remplace la mienne',
      () async {
        final a = await poste();
        await a.ecrire();
        await a.moteur.synchroniser();
        final m = await a.premier();
        serveur.messagesEditeur[m.id]!
          ..['statut'] = 'Transmis'
          ..['updated_at'] = '2099-01-01T00:00:00.000000Z'
          ..['serveur_modifie_le'] = '2099-01-01T00:00:01.000000Z';

        await a.moteur.synchroniser();

        expect((await a.premier()).statut, 'Transmis');
      },
    );

    test('une saisie locale plus récente non envoyée est conservée', () async {
      final a = await poste();
      await a.ecrire();
      await a.moteur.synchroniser();
      final m = await a.premier();
      await a.repo.marquerTransmis(m.id); // pending, plus récent que le serveur
      serveur.messagesEditeur[m.id]!
        ..['sujet'] = 'Autre sujet côté web'
        ..['updated_at'] = '2020-01-01T00:00:00.000000Z'
        ..['serveur_modifie_le'] = '2099-01-01T00:00:01.000000Z';

      await a.moteur.synchroniser();

      expect((await a.premier()).sujet, 'Comptabilité');
      expect(
        serveur.messagesEditeur[m.id]!['statut'],
        'Transmis',
        reason: 'la saisie locale part',
      );
    });
  });

  group('suppression', () {
    test('supprimer range en corbeille et envoie une pierre tombale', () async {
      final a = await poste();
      await a.ecrire(sujet: 'À effacer');
      await a.moteur.synchroniser();
      final m = await a.premier();

      await a.repo.supprimerMessage(
        m.id,
        utilisateurId: '1',
        utilisateurNom: 'Awa',
      );
      expect(await a.messages(), isEmpty);
      await a.moteur.synchroniser();

      final serveurLigne = serveur.messagesEditeur[m.id]!;
      expect(
        serveurLigne['supprime_le'],
        isNotNull,
        reason: 'jamais d\'effacement au serveur',
      );
      expect(serveurLigne['sujet'], 'À effacer');
      expect(serveurLigne['auteur'], 'Awa (awa) — Comptable');
    });

    test('une pierre tombale accusée n\'est plus renvoyée', () async {
      final a = await poste();
      await a.ecrire();
      await a.moteur.synchroniser();
      final m = await a.premier();
      await a.repo.supprimerMessage(m.id);
      await a.moteur.synchroniser();
      final avant = serveur.envois.length;

      final r = await a.moteur.synchroniser();

      expect(r.envoyees, 0);
      expect(serveur.envois.length, avant);
    });

    test(
      'la pierre tombale d\'un autre poste supprime le message ici',
      () async {
        final a = await poste();
        final b = await poste();
        await a.ecrire();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        expect(await b.messages(), hasLength(1));
        final m = await a.premier();

        await a.repo.supprimerMessage(m.id);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        expect(await b.messages(), isEmpty);
      },
    );

    test(
      'l\'écho du serveur ne ressuscite pas un message supprimé ici',
      () async {
        final a = await poste();
        await a.ecrire();
        await a.moteur.synchroniser();
        final m = await a.premier();
        await a.repo.supprimerMessage(m.id);

        await a.moteur
            .synchroniser(); // tirage (écho) puis envoi de la pierre tombale

        expect(await a.messages(), isEmpty);
        expect(serveur.messagesEditeur[m.id]!['supprime_le'], isNotNull);
      },
    );

    test(
      'restaurer un message lève la pierre tombale : il repart, daté de maintenant',
      () async {
        final a = await poste();
        final b = await poste();
        await a.ecrire();
        await a.moteur.synchroniser();
        final m = await a.premier();
        await a.repo.supprimerMessage(m.id);
        await a.moteur.synchroniser();
        await Future<void>.delayed(const Duration(milliseconds: 3));

        final archive = (await a.db.select(a.db.corbeille).get()).single;
        await ServiceArchivage(a.db).restaurer(archive.id, estAdmin: false);
        final restaure = await a.premier();
        expect(restaure.syncStatus, 'pending');
        await a.moteur.synchroniser();

        expect(serveur.messagesEditeur[m.id]!['supprime_le'], isNull);
        await b.moteur.synchroniser();
        expect(await b.messages(), hasLength(1));
      },
    );
  });

  test(
    'purger (remise à zéro du serveur) vide les messages et compte les non envoyés',
    () async {
      final a = await poste();
      await a.ecrire();
      await a.moteur.synchroniser();
      await a.ecrire(sujet: 'Local');

      final perdus = await TableMessagesEditeurPoste(a.db).purger();

      expect(perdus, 1);
      expect(await a.messages(), isEmpty);
    },
  );

  test('la table est branchée au moteur sous son nom serveur', () {
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    final t = TableMessagesEditeurPoste(db);
    expect(t.nom, 'messages_editeur');
    expect(t.referentiel, isFalse);
  });
}
