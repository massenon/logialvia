import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/commercial/data/repositories/devis_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_devis_poste.dart';
import 'package:logialvia_app/commercial/domain/entities/devis_emis.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:logialvia_app/core/sync/table_poste.dart';

import '../core/sync/faux_serveur_sync.dart';

/// Devis de prestations (`47a2_`) : dépôt (numérotation, cycle de vie, pierre tombale)
/// et synchronisation entre postes, contre un faux serveur qui rejoue `DevisTable`.
class _Poste {
  _Poste(this.serveur, this.code) : db = AppDatabase.enMemoire() {
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: serveur.client,
    );
    table = TableDevisPoste(db);
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: appairage,
      tables: [table],
      client: serveur.client,
    );
    devis = DevisRepositoryDrift(db);
  }

  final FauxServeurSync serveur;
  final String? code;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final TableDevisPoste table;
  late final DevisRepositoryDrift devis;

  Future<void> demarrer() async {
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: code ?? 'P0',
      compte: 'g',
      le: DateTime.now(),
    );
    if (code == null) {
      await (db.delete(
        db.preferencesPoste,
      )..where((p) => p.cle.equals('poste.code_attribue'))).go();
    }
    await depot.ecrire('1|jeton');
  }

  Future<DevisEmis> creer({
    String client = 'DOSSOU',
    String objet = 'Poulailler',
    double montant = 150000,
    int validite = 15,
  }) async {
    final r = await devis.creer(
      client: client,
      objet: objet,
      montant: montant,
      validiteJours: validite,
    );
    return (r as Succes<DevisEmis>).valeur;
  }

  Future<DevisRow> ligne(String id) =>
      (db.select(db.devis)..where((d) => d.id.equals(id))).getSingle();

  Future<void> fermer() => db.close();
}

/// Un devis tel que le serveur le sert (ou le reçoit).
Map<String, dynamic> unDevis({
  String id = 'd0000000-0000-4000-8000-000000000001',
  String ref = 'DV-WEB-2026-001',
  String client = 'Mama Rita',
  String objet = 'Formation',
  Object? montant = 25000,
  Object? validite = 15,
  String statut = 'emis',
  String? supprimeLe,
  String updatedAt = '2026-11-09T09:00:00.000000Z',
}) => {
  'id': id,
  'reference': ref,
  'client': client,
  'objet': objet,
  'montant_estime': montant,
  'validite_jours': validite,
  'date_emission': '2026-11-09T08:00:00.000000Z',
  'statut': statut,
  'supprime_le': supprimeLe,
  'updated_at': updatedAt,
  'device_id': '00000000-0000-0000-0000-000000000000',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FauxServeurSync serveur;
  final postes = <_Poste>[];

  Future<_Poste> poste(String? code) async {
    final p = _Poste(serveur, code);
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
      await p.fermer();
    }
  });

  final annee = DateTime.now().year;

  group('numérotation à préfixe de poste', () {
    test('poste appairé : DV-P2-AAAA-001, puis 002', () async {
      final a = await poste('P2');
      expect((await a.creer()).reference, 'DV-P2-$annee-001');
      expect((await a.creer()).reference, 'DV-P2-$annee-002');
    });

    test('poste jamais appairé : ancien format DV-AAAA-001', () async {
      final a = await poste(null);
      expect((await a.creer()).reference, 'DV-$annee-001');
    });

    test('après 999 : le maximum est NUMÉRIQUE (1000 suit 999)', () async {
      final a = await poste('P2');
      await a.creer();
      await a.db.customStatement(
        "UPDATE devis SET reference = 'DV-P2-$annee-999'",
      );
      expect((await a.creer()).reference, 'DV-P2-$annee-1000');
    });

    test('P1 et P12 ne se mélangent pas ; le web n\'est pas un poste', () async {
      final a = await poste('P1');
      await a.creer();
      await a.db.customStatement(
        "UPDATE devis SET reference = 'DV-P12-$annee-007'",
      );
      expect((await a.creer()).reference, 'DV-P1-$annee-001');
      await a.db.customStatement(
        "UPDATE devis SET reference = 'DV-WEB-$annee-050' WHERE reference LIKE 'DV-P1-%'",
      );
      expect((await a.creer()).reference, 'DV-P1-$annee-001');
    });

    test('le maximum est celui de TOUS les devis, pas du dernier lu', () async {
      final a = await poste('P2');
      await a.creer();
      await a.creer();
      await a.creer();
      await a.db.customStatement(
        "UPDATE devis SET reference = 'DV-P2-$annee-009' "
        "WHERE reference = 'DV-P2-$annee-001'",
      );
      await a.db.customStatement(
        "UPDATE devis SET reference = 'DV-P2-$annee-005' "
        "WHERE reference = 'DV-P2-$annee-003'",
      );
      expect((await a.creer()).reference, 'DV-P2-$annee-010');
    });

    test('un devis supprimé ne libère jamais son numéro', () async {
      final a = await poste('P2');
      final d = await a.creer();
      await a.devis.supprimer(d.id);
      expect((await a.creer()).reference, 'DV-P2-$annee-002');
    });

    test('jamais renumérotée par la synchronisation', () async {
      final a = await poste('P2');
      final d = await a.creer();
      await a.moteur.synchroniser();
      expect(serveur.devis.values.single['reference'], d.reference);
      expect((await a.devis.tous()).single.reference, d.reference);
    });
  });

  group('cycle de vie', () {
    test('un devis naît « émis », à envoyer, avec un UUID', () async {
      final a = await poste('P2');
      final d = await a.creer();
      expect(d.statut, StatutDevis.emis);
      expect(d.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect((await a.ligne(d.id)).syncStatus, 'pending');
    });

    test('validations : client, objet, montant > 0, validité >= 1', () async {
      final a = await poste('P2');
      Future<String?> essai({
        String client = 'X',
        String objet = 'Y',
        double? montant = 1,
        int? validite = 15,
      }) async {
        final r = await a.devis.creer(
          client: client,
          objet: objet,
          montant: montant,
          validiteJours: validite,
        );
        return r is Echec<DevisEmis> ? r.message : null;
      }

      expect(await essai(client: '  '), contains('client'));
      expect(await essai(objet: ''), contains('objet'));
      expect(await essai(montant: 0), contains('montant'));
      expect(await essai(montant: null), contains('montant'));
      expect(await essai(validite: 0), contains('validité'));
      expect(await essai(), isNull);
      expect((await a.devis.tous()), hasLength(1));
    });

    test(
      'modifier : contenu changé, référence et émission inchangées, à renvoyer',
      () async {
        final a = await poste('P2');
        final d = await a.creer();
        await a.moteur.synchroniser();
        expect((await a.ligne(d.id)).syncStatus, 'synced');

        final r = await a.devis.modifier(
          id: d.id,
          client: 'NOUVEAU',
          objet: 'Autre',
          montant: 99,
          validiteJours: 7,
        );
        final m = (r as Succes<DevisEmis>).valeur;
        expect(m.reference, d.reference);
        expect(m.dateEmission, d.dateEmission);
        expect(m.client, 'NOUVEAU');
        expect(m.validiteJours, 7);
        expect((await a.ligne(d.id)).syncStatus, 'pending');
      },
    );

    test('un devis accepté ou refusé ne se modifie plus', () async {
      final a = await poste('P2');
      final d = await a.creer();
      for (final s in [StatutDevis.accepte, StatutDevis.refuse]) {
        await a.devis.changerStatut(d.id, s);
        final r = await a.devis.modifier(
          id: d.id,
          client: 'X',
          objet: 'Y',
          montant: 1,
          validiteJours: 1,
        );
        expect(r, isA<Echec<DevisEmis>>());
        expect((await a.devis.parId(d.id))!.client, 'DOSSOU');
      }
    });

    test('un devis accepté ne se supprime pas ; un refusé, oui', () async {
      final a = await poste('P2');
      final d = await a.creer();
      await a.devis.changerStatut(d.id, StatutDevis.accepte);
      expect(await a.devis.supprimer(d.id), isA<Echec<void>>());
      expect(await a.devis.tous(), hasLength(1));

      await a.devis.changerStatut(d.id, StatutDevis.refuse);
      expect(await a.devis.supprimer(d.id), isA<Succes<void>>());
      expect(await a.devis.tous(), isEmpty);
    });

    test(
      'supprimer = pierre tombale : la ligne reste, cachée, à envoyer',
      () async {
        final a = await poste('P2');
        final d = await a.creer();
        await a.devis.supprimer(d.id);
        final l = await a.ligne(d.id);
        expect(l.supprimeLe, isNotNull);
        expect(l.syncStatus, 'pending');
        expect(await a.devis.tous(), isEmpty);
        expect(await a.devis.parId(d.id), isNull);
        // Un devis supprimé ne se modifie ni ne change de statut.
        expect(
          await a.devis.changerStatut(d.id, StatutDevis.refuse),
          isA<Echec<DevisEmis>>(),
        );
      },
    );

    test('dupliquer : nouveau numéro, émis, même contenu', () async {
      final a = await poste('P2');
      final d = await a.creer(montant: 777);
      await a.devis.changerStatut(d.id, StatutDevis.accepte);
      final copie = (await a.devis.dupliquer(d.id) as Succes<DevisEmis>).valeur;
      expect(copie.id, isNot(d.id));
      expect(copie.reference, 'DV-P2-$annee-002');
      expect(copie.statut, StatutDevis.emis);
      expect(copie.montant, 777);
      expect(copie.objet, d.objet);
    });

    test('« Expiré » se déduit de la date, jamais d\'un statut stocké', () {
      final d = DevisEmis(
        reference: 'DV-1',
        client: 'c',
        objet: 'o',
        montant: 1,
        validiteJours: 10,
        dateEmission: DateTime(2026, 1, 1),
      );
      expect(d.estExpire(DateTime(2026, 1, 11)), isFalse);
      expect(d.estExpire(DateTime(2026, 1, 12)), isTrue);
      expect(d.libelleStatut(DateTime(2026, 2, 1)), 'Expiré');
      // Un devis accepté n'expire pas.
      final accepte = DevisEmis(
        reference: 'DV-1',
        client: 'c',
        objet: 'o',
        montant: 1,
        validiteJours: 10,
        dateEmission: DateTime(2026, 1, 1),
        statut: StatutDevis.accepte,
      );
      expect(accepte.estExpire(DateTime(2027, 1, 1)), isFalse);
      expect(accepte.libelleStatut(DateTime(2027, 1, 1)), 'Accepté');
    });
  });

  group('envoi', () {
    test('le corps est celui attendu, sans rien d\'autre', () async {
      final a = await poste('P1');
      final d = await a.creer();
      final r = await a.moteur.synchroniser();

      expect(r.reussie, isTrue, reason: r.message);
      final envoye = (serveur.envois.last['tables'] as Map)['devis'] as List;
      expect((envoye.single as Map).keys.toSet(), {
        'id',
        'reference',
        'client',
        'objet',
        'montant_estime',
        'validite_jours',
        'date_emission',
        'statut',
        'supprime_le',
        'updated_at',
      });
      expect(serveur.devis[d.id]!['reference'], d.reference);
      expect((await a.ligne(d.id)).syncStatus, 'synced');
    });

    test('statut et suppression voyagent ; rien à renvoyer après', () async {
      final a = await poste('P1');
      final d = await a.creer();
      await a.moteur.synchroniser();
      await a.devis.changerStatut(d.id, StatutDevis.refuse);
      await a.moteur.synchroniser();
      expect(serveur.devis[d.id]!['statut'], 'refuse');
      await a.devis.supprimer(d.id);
      await a.moteur.synchroniser();
      expect(serveur.devis[d.id]!['supprime_le'], isNotNull);
      expect(await a.table.aEnvoyer(), isEmpty);
    });

    test(
      'refus du serveur : le devis passe en conflit avec son motif',
      () async {
        final a = await poste('P1');
        final d = await a.creer();
        serveur.ajouterDevis(
          'd1111111-1111-4111-8111-111111111111',
          d.reference,
          device: 'autre',
        );
        // Référence à code de poste : globale.
        await a.db.customStatement(
          "UPDATE devis SET reference = 'DV-P1-$annee-001'",
        );
        serveur.devis.clear();
        serveur.ajouterDevis(
          'd1111111-1111-4111-8111-111111111111',
          'DV-P1-$annee-001',
        );
        await a.moteur.synchroniser();
        final l = await a.ligne(d.id);
        expect(l.syncStatus, 'conflict');
        expect(l.syncMotif, contains('référence'));
      },
    );
  });

  group('réception', () {
    test('un devis web est absorbé tel quel, sans effet de bord', () async {
      final a = await poste('P2');
      serveur.devis['d0000000-0000-4000-8000-000000000001'] = {
        ...unDevis(),
        'serveur_modifie_le': '2026-11-09T10:00:01.000000Z',
      };
      final r = await a.moteur.synchroniser();
      expect(r.reussie, isTrue, reason: r.message);
      final tous = await a.devis.tous();
      expect(tous.single.reference, 'DV-WEB-2026-001');
      expect(tous.single.montant, 25000);
      expect((await a.ligne(tous.single.id)).syncStatus, 'synced');
      // Un devis n'est ni une vente ni une écriture comptable.
      expect(
        await a.db
            .customSelect('SELECT COUNT(*) AS n FROM ecriture_comptable')
            .getSingle()
            .then((x) => x.read<int>('n')),
        0,
      );
      expect(await a.db.select(a.db.ventes).get(), isEmpty);
    });

    test('statut et pierre tombale du serveur sont appliqués', () async {
      final a = await poste('P2');
      final d = await a.creer();
      await a.moteur.synchroniser();
      serveur.devis[d.id]!
        ..['statut'] = 'refuse'
        ..['updated_at'] = '2099-01-01T00:00:00.000000Z'
        ..['serveur_modifie_le'] = '2099-01-01T00:00:00.000000Z';
      await a.moteur.synchroniser(complet: true);
      expect((await a.devis.parId(d.id))!.statut, StatutDevis.refuse);

      serveur.devis[d.id]!
        ..['supprime_le'] = '2099-01-02T00:00:00.000000Z'
        ..['updated_at'] = '2099-01-02T00:00:00.000000Z'
        ..['serveur_modifie_le'] = '2099-01-02T00:00:00.000000Z';
      await a.moteur.synchroniser(complet: true);
      expect(await a.devis.tous(), isEmpty);
      expect((await a.ligne(d.id)).supprimeLe, isNotNull);
    });

    test('une saisie locale plus récente n\'est pas écrasée', () async {
      final a = await poste('P2');
      final d = await a.creer();
      await a.moteur.synchroniser();
      await a.devis.modifier(
        id: d.id,
        client: 'LOCAL',
        objet: 'o',
        montant: 5,
        validiteJours: 5,
      );
      final r = await a.table.absorber([
        unDevis(
          id: d.id,
          ref: d.reference,
          client: 'SERVEUR',
          updatedAt: '2000-01-01T00:00:00.000000Z',
        ),
      ]);
      expect(r.conservees, 1);
      expect((await a.devis.parId(d.id))!.client, 'LOCAL');
    });

    test(
      'un devis accepté ici est figé : contenu ou pierre tombale refusés',
      () async {
        final a = await poste('P2');
        final d = await a.creer();
        await a.devis.changerStatut(d.id, StatutDevis.accepte);
        await a.moteur.synchroniser();

        var r = await a.table.absorber([
          unDevis(
            id: d.id,
            ref: d.reference,
            client: 'AUTRE',
            statut: 'accepte',
            updatedAt: '2099-01-01T00:00:00.000000Z',
          ),
        ]);
        expect(r.refusees, 1);
        r = await a.table.absorber([
          unDevis(
            id: d.id,
            ref: d.reference,
            client: 'DOSSOU',
            objet: 'Poulailler',
            montant: 150000,
            validite: 15,
            statut: 'accepte',
            supprimeLe: '2099-01-01T00:00:00.000000Z',
            updatedAt: '2099-01-01T00:00:00.000000Z',
          ),
        ]);
        expect(r.refusees, 1);
        expect((await a.devis.parId(d.id))!.client, 'DOSSOU');
      },
    );

    test(
      'une référence déjà prise par un AUTRE devis n\'est jamais écrasée',
      () async {
        final a = await poste('P2');
        final d = await a.creer();
        final r = await a.table.absorber([
          unDevis(id: 'd9999999-9999-4999-8999-999999999999', ref: d.reference),
        ]);
        expect(r.refusees, 1);
        expect(await a.devis.tous(), hasLength(1));
        expect((await a.devis.tous()).single.client, 'DOSSOU');
      },
    );

    test('la référence d\'un même UUID ne change jamais', () async {
      final a = await poste('P2');
      final d = await a.creer();
      final r = await a.table.absorber([
        unDevis(
          id: d.id,
          ref: 'DV-P9-$annee-001',
          updatedAt: '2099-01-01T00:00:00.000000Z',
        ),
      ]);
      expect(r.refusees, 1);
      expect((await a.devis.parId(d.id))!.reference, d.reference);
    });

    test('lignes incohérentes refusées, jamais lissées', () async {
      final a = await poste('P2');
      final mauvaises = <Map<String, dynamic>>[
        unDevis(id: 'x'),
        unDevis(ref: 'DV-2026'),
        unDevis(ref: 'FV-P1-2026-001'),
        unDevis(client: '  '),
        unDevis(objet: ''),
        unDevis(montant: 0),
        unDevis(montant: 'beaucoup'),
        unDevis(validite: 0),
        unDevis(validite: 1.5),
        unDevis(statut: 'expire'),
        unDevis(supprimeLe: 'hier'),
        unDevis(updatedAt: 'jamais'),
      ];
      final r = await a.table.absorber(mauvaises);
      expect(r.refusees, mauvaises.length);
      expect(r.absorbees, 0);
      expect(await a.db.select(a.db.devis).get(), isEmpty);
    });

    test(
      'deux postes : le devis de l\'un arrive chez l\'autre, statut compris',
      () async {
        final a = await poste('P2');
        final b = await poste('P3');
        final d = await a.creer();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        expect((await b.devis.tous()).single.reference, d.reference);

        await b.devis.changerStatut(d.id, StatutDevis.accepte);
        await b.moteur.synchroniser();
        await a.moteur.synchroniser();
        expect((await a.devis.parId(d.id))!.statut, StatutDevis.accepte);

        // Aucun secret, aucune colonne de synchronisation locale sur le fil.
        final fil = jsonEncode(serveur.envois);
        expect(fil, isNot(contains('sync_status')));
      },
    );
  });

  group('remise à zéro du serveur', () {
    test('purger vide les devis et compte les saisies non envoyées', () async {
      final a = await poste('P2');
      await a.creer();
      await a.moteur.synchroniser();
      await a.creer();
      expect(await a.table.purger(), 1);
      expect(await a.db.select(a.db.devis).get(), isEmpty);
    });
  });

  test(
    'la table s\'appelle « devis » côté serveur et n\'est pas un référentiel',
    () async {
      final a = await poste('P2');
      expect(a.table.nom, 'devis');
      expect(a.table.referentiel, isFalse);
      expect(ResultatAbsorption, isNotNull);
    },
  );
}
