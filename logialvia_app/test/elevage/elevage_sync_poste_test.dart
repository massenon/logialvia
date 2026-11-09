import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/administration/domain/services/service_archivage.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:logialvia_app/elevage/data/repositories/parametres_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/soins_repository_drift.dart';
import 'package:logialvia_app/elevage/data/sync/identifiants_parametres_elevage.dart';
import 'package:logialvia_app/elevage/data/sync/table_infirmerie_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_parametres_elevage_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_soins_poste.dart';
import 'package:logialvia_app/elevage/domain/entities/soin.dart';

import '../core/sync/faux_serveur_sync.dart';

/// P7c — soins, infirmerie (FAITS) et barèmes, taux, calendrier de prophylaxie
/// (RÉFÉRENTIELS) : le poste face au faux serveur qui rejoue les règles du vrai.
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
      tables: [
        TableBaremesRationPoste(db),
        TableTauxRationPoidsPoste(db),
        TableCalendrierProphylaxiePoste(db),
        TableSoinsPoste(db),
        TableInfirmeriePoste(db),
      ],
      client: serveur.client,
    );
    parametres = ParametresElevageRepositoryDrift(db);
    soinsDepot = SoinsRepositoryDrift(db);
  }

  final FauxServeurSync serveur;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final ParametresElevageRepositoryDrift parametres;
  late final SoinsRepositoryDrift soinsDepot;

  Future<void> demarrer() async {
    await SeedInitial(db).executer();
    // Le catalogue et les intrants ont leurs propres tests : on isole ici l'élevage.
    await preferences.definirCatalogueAdopte();
    await preferences.definirIntrantsAdoptes();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }

  Future<List<BaremeRationRow>> baremes() => db.select(db.baremesRation).get();
  Future<BaremeRationRow> bareme(String espece, String stade) => (db.select(
    db.baremesRation,
  )..where((b) => b.espece.equals(espece) & b.stade.equals(stade))).getSingle();
  Future<List<EcheanceProphylaxieRow>> echeances() =>
      db.select(db.calendrierProphylaxie).get();
  Future<List<SoinCalendrierRow>> soins() =>
      db.select(db.soinsCalendrier).get();
  Future<List<InfirmerieRow>> entrees() => db.select(db.infirmerie).get();

  /// Compte les lignes des tables qu'une absorption ne doit JAMAIS toucher.
  Future<Map<String, int>> effetsDeBord() async {
    final compte = <String, int>{};
    for (final t in const [
      'fiche_journee',
      'bandes',
      'mouvements_intrant',
      'mouvements_produit',
      'ecriture_comptable',
      'ventes',
      'achats',
      'cycle_couveuse',
      'corbeille',
    ]) {
      final r = await db
          .customSelect('SELECT COUNT(*) AS n FROM $t')
          .getSingle();
      compte[t] = r.read<int>('n');
    }
    return compte;
  }
}

String _ilYA({int jours = 0, int heures = 0}) => DateTime.now()
    .toUtc()
    .subtract(Duration(days: jours, hours: heures))
    .toIso8601String();

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

  Map<String, dynamic> soinDuServeur(String id, {Map<String, dynamic>? sur}) =>
      {
        'id': id,
        'device_id': 'autre-poste',
        'espece': 'goliaths',
        'date_prevue': '2026-11-05',
        'type_soin': 'Vaccination',
        'statut': 'Planifié',
        'observations': null,
        'produit': 'ND-Lasota',
        'dose': '1 goutte',
        'remanence_jours': 0,
        'veterinaire': null,
        'symptomes': null,
        'cout_fcfa': 1500,
        'echeance_prophylaxie_id': null,
        'updated_at': _ilYA(),
        'serveur_modifie_le': serveur.instantServeur(),
        ...?sur,
      };

  Map<String, dynamic> entreeDuServeur(
    String id, {
    Map<String, dynamic>? sur,
  }) => {
    'id': id,
    'device_id': 'autre-poste',
    'date_entree': '2026-11-01',
    'sujet': 'Goliath #G-014',
    'motif': 'Boiterie',
    'niveau_isolement': 'Infirmerie',
    'statut': 'En cours',
    'date_sortie': null,
    'espece': 'goliaths',
    'categorie_mortalite': null,
    'updated_at': _ilYA(),
    'serveur_modifie_le': serveur.instantServeur(),
    ...?sur,
  };

  const uuidA = '11111111-1111-4111-8111-111111111111';
  const uuidB = '22222222-2222-4222-8222-222222222222';

  // ======================================================== référentiels

  group('référentiels : barèmes, taux, calendrier de prophylaxie', () {
    test(
      'la première synchronisation propose TOUT le seed, avec des UUID déterministes',
      () async {
        final a = await poste();
        final nb = (await a.baremes()).length;
        final nt = (await a.db.select(a.db.tauxRationPoids).get()).length;
        final ne = (await a.echeances()).length;
        expect(nb + nt + ne, greaterThan(40));

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(serveur.baremes, hasLength(nb));
        expect(serveur.taux, hasLength(nt));
        expect(serveur.echeances, hasLength(ne));
        expect(
          serveur.baremes.keys,
          contains(IdentifiantsParametresElevage.bareme('goliaths', 'Mature')),
        );
      },
    );

    test('adoption unique : rien n\'est reproposé ensuite', () async {
      final a = await poste();
      await a.moteur.synchroniser();
      serveur.demandesRecues.clear();

      await a.moteur.synchroniser();

      expect(serveur.demandesRecues, isEmpty);
    });

    test(
      'deux postes semés du même programme : aucun doublon au serveur',
      () async {
        final a = await poste();
        final b = await poste();
        final nb = (await a.baremes()).length;
        final ne = (await a.echeances()).length;

        for (final p in [a, b, a, b]) {
          final r = await p.moteur.synchroniser();
          expect(r.reussie, isTrue, reason: r.message);
          expect(r.demandesRefusees, 0, reason: r.message);
        }

        expect(serveur.baremes, hasLength(nb));
        expect(serveur.echeances, hasLength(ne));
        expect(await b.baremes(), hasLength(nb));
        expect(await b.echeances(), hasLength(ne));
      },
    );

    test('une ration modifiée en A arrive chez B', () async {
      final a = await poste();
      final b = await poste();
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();
      final ligne = await a.bareme('goliaths', 'Mature');
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await a.parametres.modifierRation(
        id: ligne.id,
        rationGrammesParJour: 125,
        confirme: true,
      );

      await a.moteur.synchroniser();
      final r = await b.moteur.synchroniser();

      expect(serveur.baremes[ligne.id]!['ration_grammes_par_jour'], 125);
      expect(r.referentielsMisAJour, greaterThan(0));
      final chezB = await b.bareme('goliaths', 'Mature');
      expect(chezB.rationGrammesParJour, 125);
      expect(chezB.confirme, isTrue);
    });

    test(
      'le même stade ajouté sur deux postes donne UN barème (identifiant déterministe)',
      () async {
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await a.parametres.creerBareme(
          espece: 'lapins',
          stade: 'Gestante',
          rationGrammesParJour: 150,
        );
        await b.parametres.creerBareme(
          espece: 'lapins',
          stade: 'Gestante',
          rationGrammesParJour: 150,
        );
        final avant = serveur.baremes.length;

        await a.moteur.synchroniser();
        final r = await b.moteur.synchroniser();

        expect(serveur.baremes, hasLength(avant + 1));
        expect(r.demandesRefusees, 0, reason: r.message);
        expect(
          (await b.baremes()).where((x) => x.stade == 'Gestante'),
          hasLength(1),
        );
      },
    );

    test('une échéance créée en A (UUID aléatoire) arrive chez B', () async {
      final a = await poste();
      final b = await poste();
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();
      await a.parametres.enregistrerEcheance(
        espece: 'goliaths',
        jourCycle: 40,
        traitement: 'Rappel Gumboro',
        produit: 'Bursine',
        remanenceJours: 3,
        dose: '1 dose par sujet',
      );

      await a.moteur.synchroniser();
      await b.moteur.synchroniser();

      final chezB = (await b.echeances()).where(
        (e) => e.traitement == 'Rappel Gumboro',
      );
      expect(chezB, hasLength(1));
      expect(chezB.single.dose, '1 dose par sujet');
      expect(chezB.single.remanenceJours, 3);
    });

    test(
      'le taux par classe de poids créé en A arrive chez B, clé déterministe',
      () async {
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await a.parametres.enregistrerTauxPoids(
          espece: 'bovins',
          poidsMinG: 500000,
          poidsMaxG: null,
          tauxPourcent: 2.0,
        );

        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        final id = IdentifiantsParametresElevage.taux('bovins', 500000);
        expect(serveur.taux[id]!['taux_pourcent'], 2.0);
        final chezB = await b.db.select(b.db.tauxRationPoids).get();
        expect(chezB.where((t) => t.id == id), hasLength(1));
      },
    );

    test(
      'supprimer en A pose la pierre tombale : B l\'archive dans SA corbeille, restaurable',
      () async {
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        final e = (await a.echeances()).first;

        await a.parametres.supprimerEcheance(e.id);
        await a.moteur.synchroniser();
        expect(serveur.echeances[e.id]!['archive_le'], isNotNull);
        await b.moteur.synchroniser();

        expect((await b.echeances()).where((x) => x.id == e.id), isEmpty);
        final corbeille = await ServiceArchivage(b.db).lister();
        expect(
          corbeille.where((c) => c.nomTable == 'calendrier_prophylaxie'),
          hasLength(1),
        );

        // Restaurer au poste B lève la pierre tombale au serveur.
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await ServiceArchivage(
          b.db,
        ).restaurer(corbeille.first.id, estAdmin: true);
        await b.moteur.synchroniser();
        expect(serveur.echeances[e.id]!['archive_le'], isNull);
        await a.moteur.synchroniser();
        expect((await a.echeances()).where((x) => x.id == e.id), hasLength(1));
      },
    );

    test('un poste neuf ne crée jamais une ligne archivée', () async {
      final c = await poste();
      await c.moteur.synchroniser();
      final x = serveur.baremes.values.first;
      x['archive_le'] = _ilYA();
      x['updated_at'] = serveur.instantServeur();
      final d = await poste();
      await d.db.delete(d.db.baremesRation).go();

      await d.moteur.synchroniser();

      expect(
        (await d.baremes()).where((b) => b.id == x['id']),
        isEmpty,
        reason: 'une ligne supprimée ne ressuscite pas sur un poste neuf',
      );
    });

    test(
      'une demande locale PLUS RÉCENTE n\'est pas défaite par le tirage, et part',
      () async {
        final a = await poste();
        await a.moteur.synchroniser();
        final ligne = await a.bareme('goliaths', 'Mature');
        serveur.baremes[ligne.id]!
          ..['ration_grammes_par_jour'] = 77
          ..['saisi_le'] = '2020-01-01T00:00:00.000000Z'
          ..['updated_at'] = serveur.instantServeur();
        await a.parametres.modifierRation(
          id: ligne.id,
          rationGrammesParJour: 130,
        );

        final r = await a.moteur.synchroniser();

        expect(r.conserveesLocalement, 1);
        expect(
          (await a.bareme('goliaths', 'Mature')).rationGrammesParJour,
          130,
        );
        expect(serveur.baremes[ligne.id]!['ration_grammes_par_jour'], 130);
      },
    );

    test(
      'une décision PLUS RÉCENTE du serveur l\'emporte, la demande tombe',
      () async {
        final a = await poste();
        await a.moteur.synchroniser();
        final ligne = await a.bareme('goliaths', 'Mature');
        await a.parametres.modifierRation(
          id: ligne.id,
          rationGrammesParJour: 130,
        );
        serveur.baremes[ligne.id]!
          ..['ration_grammes_par_jour'] = 99
          ..['saisi_le'] = DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String()
          ..['updated_at'] = serveur.instantServeur();

        final r = await a.moteur.synchroniser();

        expect(r.supplantees, 1);
        expect((await a.bareme('goliaths', 'Mature')).rationGrammesParJour, 99);
        expect(
          await DepotDemandesReferentiel(
            a.db,
          ).enAttente('bareme_ration', ligne.id),
          isNull,
        );
      },
    );

    final incoherentes = <String, Map<String, dynamic>>{
      'ration nulle': {'ration_grammes_par_jour': 0},
      'ration invraisemblable': {'ration_grammes_par_jour': 20001},
      'stade vide': {'stade': '  '},
      'statut absent': {'confirme': null},
      'identifiant qui n\'est pas un UUID': {'id': '42'},
    };
    incoherentes.forEach((nom, surcharge) {
      test(
        'barème incohérent du serveur refusé, rien d\'écrit : $nom',
        () async {
          final a = await poste();
          serveur.baremes['x'] = {
            'id': uuidA,
            'espece': 'lapins',
            'stade': 'Intrus',
            'ration_grammes_par_jour': 50,
            'confirme': false,
            'archive_le': null,
            'saisi_le': _ilYA(),
            'updated_at': serveur.instantServeur(),
            ...surcharge,
          };
          final avant = (await a.baremes()).length;
          await a.preferences.definirParametresElevageAdoptes();

          final r = await a.moteur.synchroniser();

          expect(r.refuseesALaReception, 1, reason: r.message);
          expect((await a.baremes()).length, avant);
        },
      );
    });

    test('taux et échéances incohérents du serveur refusés', () async {
      final a = await poste();
      await a.preferences.definirParametresElevageAdoptes();
      serveur.taux['t'] = {
        'id': uuidA,
        'espece': 'bovins',
        'poids_min_g': 5000,
        'poids_max_g': 4000, // max <= min
        'taux_pourcent': 3.0,
        'confirme': false,
        'archive_le': null,
        'saisi_le': _ilYA(),
        'updated_at': serveur.instantServeur(),
      };
      serveur.taux['t2'] = {
        'id': uuidB,
        'espece': 'bovins',
        'poids_min_g': 5000,
        'poids_max_g': null,
        'taux_pourcent': 0, // taux nul
        'confirme': false,
        'archive_le': null,
        'saisi_le': _ilYA(),
        'updated_at': serveur.instantServeur(),
      };
      serveur.echeances['e'] = {
        'id': '33333333-3333-4333-8333-333333333333',
        'espece': 'goliaths',
        'jour_cycle': 0, // hors 1..365
        'traitement': 'X',
        'produit': 'Y',
        'remanence_jours': 0,
        'dose': null,
        'archive_le': null,
        'saisi_le': _ilYA(),
        'updated_at': serveur.instantServeur(),
      };

      final r = await a.moteur.synchroniser();

      expect(r.refuseesALaReception, 3, reason: r.message);
    });

    test(
      'même clé naturelle sous un AUTRE identifiant : le serveur gagne si la ligne locale n\'attend rien',
      () async {
        final a = await poste();
        await a.preferences.definirParametresElevageAdoptes();
        serveur.baremes['x'] = {
          'id': uuidA,
          'espece': 'goliaths',
          'stade': 'Mature',
          'ration_grammes_par_jour': 140,
          'confirme': true,
          'archive_le': null,
          'saisi_le': _ilYA(),
          'updated_at': serveur.instantServeur(),
        };

        final r = await a.moteur.synchroniser();

        expect(r.refuseesALaReception, 0, reason: r.message);
        final lignes = (await a.baremes()).where(
          (b) => b.espece == 'goliaths' && b.stade == 'Mature',
        );
        expect(lignes, hasLength(1));
        expect(lignes.single.id, uuidA);
        expect(lignes.single.rationGrammesParJour, 140);
      },
    );

    test(
      'même clé naturelle, mais la ligne locale attend d\'être proposée : elle est conservée',
      () async {
        final a = await poste();
        await a.preferences.definirParametresElevageAdoptes();
        final locale = await a.bareme('goliaths', 'Mature');
        await a.parametres.modifierRation(
          id: locale.id,
          rationGrammesParJour: 111,
        );
        serveur.baremes['x'] = {
          'id': uuidA,
          'espece': 'goliaths',
          'stade': 'Mature',
          'ration_grammes_par_jour': 140,
          'confirme': true,
          'archive_le': null,
          'saisi_le': _ilYA(),
          'updated_at': serveur.instantServeur(),
        };

        final r = await a.moteur.synchroniser();

        expect(r.conserveesLocalement, 1, reason: r.message);
        expect((await a.bareme('goliaths', 'Mature')).id, locale.id);
        expect(
          (await a.bareme('goliaths', 'Mature')).rationGrammesParJour,
          111,
        );
      },
    );

    test(
      'le serveur refuse une demande : « conflict » avec SON motif, jamais d\'échec silencieux',
      () async {
        final a = await poste();
        await a.moteur.synchroniser();
        final ligne = await a.bareme('goliaths', 'Mature');
        serveur.baremes[ligne.id]!['saisi_le'] = DateTime.now()
            .toUtc()
            .add(const Duration(hours: 2))
            .toIso8601String();
        serveur.baremes[ligne.id]!['updated_at'] = serveur.instantServeur();
        await a.preferences.definirCurseurTirage(
          serveur.instantServeur(),
        ); // le tirage ne ramène pas la décision : on isole le refus
        await a.parametres.modifierRation(
          id: ligne.id,
          rationGrammesParJour: 128,
        );

        final r = await a.moteur.synchroniser();

        expect(r.demandesRefusees, 1, reason: r.message);
        final demandes = await a.db.select(a.db.demandesReferentiel).get();
        final refusee = demandes.firstWhere(
          (d) => d.cle == ligne.id && d.syncStatus == 'conflict',
        );
        expect(refusee.syncMotif, contains('plus récente'));
      },
    );

    test('hors ligne : la demande reste en attente, puis part', () async {
      final a = await poste();
      await a.moteur.synchroniser();
      final ligne = await a.bareme('goliaths', 'Mature');
      await a.parametres.modifierRation(id: ligne.id, rationGrammesParJour: 90);
      serveur.horsLigne = true;

      final hors = await a.moteur.synchroniser();
      expect(hors.issue, IssueSynchronisation.horsLigne);
      expect(
        await DepotDemandesReferentiel(
          a.db,
        ).enAttente('bareme_ration', ligne.id),
        isNotNull,
      );

      serveur.horsLigne = false;
      await a.moteur.synchroniser();
      expect(serveur.baremes[ligne.id]!['ration_grammes_par_jour'], 90);
    });

    test(
      'la remise à zéro du serveur préserve les référentiels du poste',
      () async {
        final a = await poste();
        await a.moteur.synchroniser();
        final avant = (await a.baremes()).length;

        serveur.remettreAZero();
        final r = await a.moteur.synchroniser();

        expect(r.remiseAZero, isTrue, reason: r.message);
        expect(await a.baremes(), hasLength(avant));
        expect(serveur.baremes, hasLength(avant));
      },
    );

    test('un référentiel ne s\'envoie jamais en push', () async {
      final a = await poste();
      await a.moteur.synchroniser();
      for (final envoi in serveur.envois) {
        final tables = (envoi['tables'] as Map).keys;
        expect(tables, isNot(contains('baremes_ration')));
        expect(tables, isNot(contains('taux_ration_poids')));
        expect(tables, isNot(contains('calendrier_prophylaxie')));
      }
    });
  });

  // ================================================================ soins

  group('soins du calendrier : un fait, dernier écrivain gagne', () {
    test(
      'un soin saisi part avec ses champs, sans bande, puis est marqué synchronisé',
      () async {
        final a = await poste();
        await a.moteur.synchroniser();
        const bande = 'bande-1';
        await a.db
            .into(a.db.bandes)
            .insert(
              BandesCompanion.insert(
                id: const Value(bande),
                espece: 'goliaths',
                code: 'B-2026-001',
                dateMiseEnBande: DateTime(2026, 8, 1),
              ),
            );
        final soin = await a.soinsDepot.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime(2026, 11, 5, 14, 30),
          typeSoin: 'Vaccination',
          statut: StatutSoin.planifie,
          produit: 'ND-Lasota',
          dose: '1 goutte',
          coutFcfa: 1500,
          bandeId: bande,
        );

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(r.refusees, 0, reason: r.message);
        final chez = serveur.soins[soin.id]!;
        expect(chez['date_prevue'], '2026-11-05', reason: 'date civile');
        expect(chez['type_soin'], 'Vaccination');
        expect(chez['cout_fcfa'], 1500);
        expect(chez.keys, isNot(contains('bande_id')));
        final corps =
            ((serveur.envois.last['tables'] as Map)['soins_calendrier'] as List)
                .cast<Map<String, dynamic>>()
                .single;
        expect(
          corps.keys,
          isNot(contains('bande_id')),
          reason: 'l\'identifiant de bande est local : il ne voyage pas',
        );
        expect((await a.soins()).single.syncStatus, 'synced');
        expect((await a.soins()).single.bandeId, bande);
      },
    );

    test(
      '« Planifier une Intervention » : un type d\'action en texte LIBRE voyage et est reçu tel quel',
      () async {
        final a = await poste();
        final b = await poste();
        final soin = await a.soinsDepot.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime(2026, 11, 20),
          typeSoin: 'Vaccin Newcastle (Rappel)',
          statut: StatutSoin.planifie,
        );

        for (final p in [a, b]) {
          final r = await p.moteur.synchroniser();
          expect(r.refusees, 0, reason: r.message);
          expect(r.refuseesALaReception, 0, reason: r.message);
        }

        expect(
          serveur.soins[soin.id]!['type_soin'],
          'Vaccin Newcastle (Rappel)',
        );
        expect((await b.soins()).single.typeSoin, 'Vaccin Newcastle (Rappel)');
      },
    );

    test(
      'confirmer l\'administration remet le soin à envoyer, avec un nouvel instant',
      () async {
        final a = await poste();
        final soin = await a.soinsDepot.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime(2026, 11, 5),
          typeSoin: 'Vermifuge',
          statut: StatutSoin.planifie,
        );
        await a.moteur.synchroniser();
        final avant = (await a.soins()).single.updatedAt;
        expect((await a.soins()).single.syncStatus, 'synced');
        await Future<void>.delayed(const Duration(milliseconds: 3));

        await a.soinsDepot.confirmerAdministration(soin.id);
        final apres = (await a.soins()).single;
        expect(apres.syncStatus, 'pending');
        expect(apres.updatedAt.compareTo(avant), greaterThan(0));

        await a.moteur.synchroniser();
        expect(serveur.soins[soin.id]!['statut'], StatutSoin.effectue);
        expect((await a.soins()).single.syncStatus, 'synced');
      },
    );

    test(
      'B reçoit le soin de A SANS aucun effet de bord, ni lien de bande',
      () async {
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        const bande = 'bande-1';
        await a.db
            .into(a.db.bandes)
            .insert(
              BandesCompanion.insert(
                id: const Value(bande),
                espece: 'goliaths',
                code: 'B-2026-001',
                dateMiseEnBande: DateTime(2026, 8, 1),
              ),
            );
        await a.soinsDepot.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime(2026, 11, 5),
          typeSoin: 'Vaccination',
          statut: StatutSoin.effectue,
          bandeId: bande,
          coutFcfa: 2500,
        );
        await a.moteur.synchroniser();
        final avant = await b.effetsDeBord();

        final r = await b.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        final recu = (await b.soins()).single;
        expect(recu.syncStatus, 'synced');
        expect(recu.coutFcfa, 2500);
        expect(
          recu.bandeId,
          isNull,
          reason: 'les bandes ne sont pas synchronisées',
        );
        expect(
          await b.effetsDeBord(),
          avant,
          reason: 'absorber le fait d\'un autre poste n\'a aucun effet de bord',
        );
      },
    );

    test(
      'un soin d\'un autre poste n\'est jamais renvoyé au serveur',
      () async {
        final a = await poste();
        final b = await poste();
        await a.soinsDepot.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime(2026, 11, 5),
          typeSoin: 'Vaccination',
          statut: StatutSoin.planifie,
        );
        await a.moteur.synchroniser();
        serveur.envois.clear();

        await b.moteur.synchroniser();
        await b.moteur.synchroniser();

        for (final e in serveur.envois) {
          expect((e['tables'] as Map).containsKey('soins_calendrier'), isFalse);
        }
      },
    );

    test(
      'le lien de bande local d\'un soin n\'est JAMAIS effacé par une version du serveur',
      () async {
        final a = await poste();
        const bande = 'bande-1';
        await a.db
            .into(a.db.bandes)
            .insert(
              BandesCompanion.insert(
                id: const Value(bande),
                espece: 'goliaths',
                code: 'B-2026-001',
                dateMiseEnBande: DateTime(2026, 8, 1),
              ),
            );
        final soin = await a.soinsDepot.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime(2026, 11, 5),
          typeSoin: 'Vaccination',
          statut: StatutSoin.planifie,
          bandeId: bande,
        );
        await a.moteur.synchroniser();
        serveur.soins[soin.id]!
          ..['statut'] = StatutSoin.effectue
          ..['updated_at'] = DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String()
          ..['serveur_modifie_le'] = serveur.instantServeur();

        await a.moteur.synchroniser();

        final apres = (await a.soins()).single;
        expect(apres.statut, StatutSoin.effectue);
        expect(apres.bandeId, bande);
      },
    );

    test('deux postes saisissent, se croisent, et convergent', () async {
      final a = await poste();
      final b = await poste();
      await a.soinsDepot.enregistrerSoin(
        espece: 'goliaths',
        date: DateTime(2026, 11, 5),
        typeSoin: 'Vaccination',
        statut: StatutSoin.planifie,
      );
      await b.soinsDepot.enregistrerSoin(
        espece: 'lapins',
        date: DateTime(2026, 11, 6),
        typeSoin: 'Vermifuge',
        statut: StatutSoin.planifie,
      );

      for (final p in [a, b, a, b]) {
        await p.moteur.synchroniser();
      }

      expect(serveur.soins, hasLength(2));
      expect(
        (await a.soins()).map((s) => s.id).toSet(),
        (await b.soins()).map((s) => s.id).toSet(),
      );
      for (final s in [...await a.soins(), ...await b.soins()]) {
        expect(s.syncStatus, 'synced');
      }
    });

    test(
      'saisie locale plus récente que la version du serveur : conservée, puis envoyée',
      () async {
        final a = await poste();
        final soin = await a.soinsDepot.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime(2026, 11, 5),
          typeSoin: 'Vaccination',
          statut: StatutSoin.planifie,
        );
        serveur.soins[soin.id] = soinDuServeur(
          soin.id,
          sur: {
            'statut': 'En retard',
            'updated_at': '2020-01-01T00:00:00.000000Z',
          },
        );

        final r = await a.moteur.synchroniser();

        expect(r.conserveesLocalement, 1, reason: r.message);
        expect((await a.soins()).single.statut, StatutSoin.planifie);
        expect(serveur.soins[soin.id]!['statut'], StatutSoin.planifie);
      },
    );

    test(
      'à instant de saisie ÉGAL, la saisie locale non envoyée est conservée (strictement supérieur seulement)',
      () async {
        final a = await poste();
        final soin = await a.soinsDepot.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime(2026, 11, 5),
          typeSoin: 'Vaccination',
          statut: StatutSoin.planifie,
        );
        final instant = (await a.soins()).single.updatedAt;
        serveur.soins[soin.id] = soinDuServeur(
          soin.id,
          sur: {'statut': 'En retard', 'updated_at': instant},
        );

        final r = await a.moteur.synchroniser();

        expect(r.conserveesLocalement, 1, reason: r.message);
        expect(r.supplantees, 0);
        expect((await a.soins()).single.statut, StatutSoin.planifie);
      },
    );

    test(
      'version du serveur STRICTEMENT plus récente : elle remplace la saisie non envoyée, et le poste le dit',
      () async {
        final a = await poste();
        final soin = await a.soinsDepot.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime(2026, 11, 5),
          typeSoin: 'Vaccination',
          statut: StatutSoin.planifie,
        );
        serveur.soins[soin.id] = soinDuServeur(
          soin.id,
          sur: {
            'statut': 'En retard',
            'updated_at': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );

        final r = await a.moteur.synchroniser();

        expect(r.supplantees, 1, reason: r.message);
        expect((await a.soins()).single.statut, StatutSoin.enRetard);
      },
    );

    final incoherents = <String, Map<String, dynamic>>{
      'type d\'action vide': {'type_soin': '  '},
      'statut inconnu': {'statut': 'Peut-être'},
      'date invalide': {'date_prevue': 'demain'},
      'rémanence négative': {'remanence_jours': -1},
      'coût négatif': {'cout_fcfa': -5},
      'espèce vide': {'espece': ' '},
      'échéance qui n\'est pas un UUID': {'echeance_prophylaxie_id': 'abc'},
      'identifiant qui n\'est pas un UUID': {'id': 'abc'},
      'instant illisible': {'updated_at': 'hier'},
    };
    incoherents.forEach((nom, surcharge) {
      test('soin incohérent du serveur refusé et compté : $nom', () async {
        final a = await poste();
        serveur.soins['x'] = soinDuServeur(uuidA, sur: surcharge);

        final r = await a.moteur.synchroniser();

        expect(r.refuseesALaReception, 1, reason: r.message);
        expect(await a.soins(), isEmpty);
      });
    });

    test(
      'le serveur refuse un soin dont l\'échéance lui est inconnue : « conflict » avec le motif',
      () async {
        final a = await poste();
        serveur.demandesAccepteesParLeServeur =
            false; // il n'apprend pas l'échéance
        final e = (await a.echeances()).first;
        await a.soinsDepot.enregistrerSoin(
          espece: e.espece,
          date: DateTime(2026, 11, 5),
          typeSoin: 'Vaccination',
          statut: StatutSoin.planifie,
          echeanceProphylaxieId: e.id,
        );

        final r = await a.moteur.synchroniser();

        expect(r.refusees, 1, reason: r.message);
        final s = (await a.soins()).single;
        expect(s.syncStatus, 'conflict');
        expect(s.syncMotif, contains('Échéance de prophylaxie inconnue'));
      },
    );

    test(
      'un soin planifié depuis le calendrier part avec son échéance (UUID) et arrive chez B',
      () async {
        final a = await poste();
        final b = await poste();
        final e = (await a.echeances()).first;
        await a.soinsDepot.enregistrerSoin(
          espece: e.espece,
          date: DateTime(2026, 11, 5),
          typeSoin: 'Vaccination',
          statut: StatutSoin.planifie,
          echeanceProphylaxieId: e.id,
        );

        for (final p in [a, b, a, b]) {
          final r = await p.moteur.synchroniser();
          expect(r.refusees, 0, reason: r.message);
        }

        expect((await b.soins()).single.echeanceProphylaxieId, e.id);
        expect(serveur.soins, hasLength(1), reason: 'aucun doublon');
      },
    );

    test('hors ligne : le soin reste « à envoyer », puis part', () async {
      final a = await poste();
      await a.soinsDepot.enregistrerSoin(
        espece: 'goliaths',
        date: DateTime(2026, 11, 5),
        typeSoin: 'Vaccination',
        statut: StatutSoin.planifie,
      );
      serveur.horsLigne = true;
      expect(
        (await a.moteur.synchroniser()).issue,
        IssueSynchronisation.horsLigne,
      );
      expect((await a.soins()).single.syncStatus, 'pending');

      serveur.horsLigne = false;
      await a.moteur.synchroniser();

      expect((await a.soins()).single.syncStatus, 'synced');
    });

    test(
      'une saisie faite PENDANT l\'envoi repart au prochain envoi (accusé conditionnel)',
      () async {
        final a = await poste();
        final soin = await a.soinsDepot.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime(2026, 11, 5),
          typeSoin: 'Vaccination',
          statut: StatutSoin.planifie,
        );
        serveur.pendantEnvoi = () async {
          await Future<void>.delayed(const Duration(milliseconds: 3));
          await a.soinsDepot.confirmerAdministration(soin.id);
        };

        await a.moteur.synchroniser();
        expect((await a.soins()).single.syncStatus, 'pending');

        await a.moteur.synchroniser();
        expect((await a.soins()).single.syncStatus, 'synced');
        expect(serveur.soins[soin.id]!['statut'], StatutSoin.effectue);
      },
    );

    test(
      'remise à zéro : les soins partent, les non envoyés sont comptés, les référentiels restent',
      () async {
        final a = await poste();
        final b = await poste();
        await a.soinsDepot.enregistrerSoin(
          espece: 'goliaths',
          date: DateTime(2026, 11, 5),
          typeSoin: 'Vaccination',
          statut: StatutSoin.planifie,
        );
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await b.soinsDepot.enregistrerSoin(
          espece: 'lapins',
          date: DateTime(2026, 11, 6),
          typeSoin: 'Vermifuge',
          statut: StatutSoin.planifie,
        );
        final nbBaremes = (await b.baremes()).length;

        serveur.remettreAZero();
        final r = await b.moteur.synchroniser();

        expect(r.remiseAZero, isTrue, reason: r.message);
        expect(await b.soins(), isEmpty);
        expect(r.saisiesPerdues, 1, reason: 'le soin non envoyé est compté');
        expect(await b.baremes(), hasLength(nbBaremes));
      },
    );
  });

  // ============================================================ infirmerie

  group('infirmerie : un fait, dernier écrivain gagne', () {
    test('une entrée part, se clôture, et repart', () async {
      final a = await poste();
      final entree = await a.soinsDepot.enregistrerEntreeInfirmerie(
        sujet: 'Goliath #G-014',
        motif: 'Boiterie',
        niveauIsolement: NiveauIsolement.infirmerie,
        dateEntree: DateTime(2026, 11, 1, 9),
        espece: 'goliaths',
      );
      await a.moteur.synchroniser();
      expect(
        serveur.infirmerie[entree.id]!['statut'],
        StatutInfirmerie.enCours,
      );
      expect(serveur.infirmerie[entree.id]!['date_entree'], '2026-11-01');
      await Future<void>.delayed(const Duration(milliseconds: 3));

      await a.soinsDepot.cloturerEntree(
        entreeId: entree.id,
        statut: StatutInfirmerie.reintegre,
        dateSortie: DateTime(2026, 11, 4),
      );
      expect((await a.entrees()).single.syncStatus, 'pending');
      await a.moteur.synchroniser();

      expect(
        serveur.infirmerie[entree.id]!['statut'],
        StatutInfirmerie.reintegre,
      );
      expect(serveur.infirmerie[entree.id]!['date_sortie'], '2026-11-04');
      expect((await a.entrees()).single.syncStatus, 'synced');
    });

    test(
      'un décès venu d\'un autre poste n\'est PAS reporté dans la fiche d\'ici, mais sa marque est absorbée',
      () async {
        final a = await poste();
        final b = await poste();
        final entree = await a.soinsDepot.enregistrerEntreeInfirmerie(
          sujet: 'Pintade #P-003',
          motif: 'Suspicion Newcastle',
          niveauIsolement: NiveauIsolement.quarantaineStricte,
          dateEntree: DateTime(2026, 11, 1),
          espece: 'pintades',
        );
        await a.soinsDepot.cloturerEntree(
          entreeId: entree.id,
          statut: StatutInfirmerie.decede,
          dateSortie: DateTime(2026, 11, 3),
        );
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await a.soinsDepot.marquerDecesReporte(
          entreeId: entree.id,
          categorieMortalite: 1,
        );
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        final avant = await b.effetsDeBord();

        final r = await b.moteur.synchroniser();
        expect(r.reussie, isTrue, reason: r.message);

        final recu = (await b.entrees()).single;
        expect(recu.statut, StatutInfirmerie.decede);
        expect(recu.categorieMortalite, 1);
        expect(
          await b.effetsDeBord(),
          avant,
          reason: 'aucune fiche d\'élevage touchée, aucun compteur',
        );
        expect(
          await b.db.select(b.db.ficheJournee).get(),
          isEmpty,
          reason: 'le décès est compté par le poste qui l\'a déclaré',
        );
      },
    );

    final incoherentes = <String, Map<String, dynamic>>{
      'statut inconnu': {'statut': 'Envolé'},
      'niveau d\'isolement inconnu': {'niveau_isolement': 'Villégiature'},
      'sujet vide': {'sujet': ''},
      'motif vide': {'motif': ' '},
      'sortie avant l\'entrée': {
        'statut': 'Réintégré',
        'date_sortie': '2026-10-01',
      },
      'clôturée sans date de sortie': {'statut': 'Réintégré'},
      'en cours avec une date de sortie': {'date_sortie': '2026-11-03'},
      'mortalité sur un sujet vivant': {'categorie_mortalite': 2},
      'date d\'entrée invalide': {'date_entree': '??'},
    };
    incoherentes.forEach((nom, surcharge) {
      test('entrée incohérente du serveur refusée et comptée : $nom', () async {
        final a = await poste();
        serveur.infirmerie['x'] = entreeDuServeur(uuidA, sur: surcharge);

        final r = await a.moteur.synchroniser();

        expect(r.refuseesALaReception, 1, reason: r.message);
        expect(await a.entrees(), isEmpty);
      });
    });

    test('dernier écrivain gagne : locale plus récente conservée', () async {
      final a = await poste();
      final entree = await a.soinsDepot.enregistrerEntreeInfirmerie(
        sujet: 'Lapin #L-1',
        motif: 'Diarrhée',
        niveauIsolement: NiveauIsolement.surveillance,
        dateEntree: DateTime(2026, 11, 1),
      );
      serveur.infirmerie[entree.id] = entreeDuServeur(
        entree.id,
        sur: {
          'motif': 'Ancien motif',
          'updated_at': '2020-01-01T00:00:00.000000Z',
        },
      );

      final r = await a.moteur.synchroniser();

      expect(r.conserveesLocalement, 1, reason: r.message);
      expect((await a.entrees()).single.motif, 'Diarrhée');
      expect(serveur.infirmerie[entree.id]!['motif'], 'Diarrhée');
    });

    test(
      'à instant égal, l\'entrée locale non envoyée est conservée',
      () async {
        final a = await poste();
        final entree = await a.soinsDepot.enregistrerEntreeInfirmerie(
          sujet: 'Lapin #L-1',
          motif: 'Diarrhée',
          niveauIsolement: NiveauIsolement.surveillance,
          dateEntree: DateTime(2026, 11, 1),
        );
        final instant = (await a.entrees()).single.updatedAt;
        serveur.infirmerie[entree.id] = entreeDuServeur(
          entree.id,
          sur: {'motif': 'Autre motif', 'updated_at': instant},
        );

        final r = await a.moteur.synchroniser();

        expect(r.conserveesLocalement, 1, reason: r.message);
        expect((await a.entrees()).single.motif, 'Diarrhée');
      },
    );

    test(
      'dernier écrivain gagne : version serveur strictement plus récente',
      () async {
        final a = await poste();
        final entree = await a.soinsDepot.enregistrerEntreeInfirmerie(
          sujet: 'Lapin #L-1',
          motif: 'Diarrhée',
          niveauIsolement: NiveauIsolement.surveillance,
          dateEntree: DateTime(2026, 11, 1),
        );
        serveur.infirmerie[entree.id] = entreeDuServeur(
          entree.id,
          sur: {
            'motif': 'Motif corrigé ailleurs',
            'updated_at': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );

        final r = await a.moteur.synchroniser();

        expect(r.supplantees, 1, reason: r.message);
        expect((await a.entrees()).single.motif, 'Motif corrigé ailleurs');
      },
    );

    test(
      'hors ligne puis remise à zéro : l\'infirmerie repart à vide',
      () async {
        final a = await poste();
        await a.soinsDepot.enregistrerEntreeInfirmerie(
          sujet: 'Lapin #L-1',
          motif: 'Diarrhée',
          niveauIsolement: NiveauIsolement.surveillance,
          dateEntree: DateTime(2026, 11, 1),
        );
        serveur.horsLigne = true;
        await a.moteur.synchroniser();
        expect((await a.entrees()).single.syncStatus, 'pending');
        serveur.horsLigne = false;
        await a.moteur.synchroniser();
        expect((await a.entrees()).single.syncStatus, 'synced');

        serveur.remettreAZero();
        final r = await a.moteur.synchroniser();

        expect(r.remiseAZero, isTrue, reason: r.message);
        expect(await a.entrees(), isEmpty);
      },
    );
  });
}
