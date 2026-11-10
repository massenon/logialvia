import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/commercial/data/repositories/factures_mecef_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_factures_poste.dart';
import 'package:logialvia_app/commercial/domain/entities/facture_mecef.dart';
import 'package:logialvia_app/commercial/domain/services/transmission_mecef.dart';
import 'package:logialvia_app/commercial/presentation/viewmodels/factures_mecef_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';

import '../core/sync/faux_serveur_sync.dart';

/// `47a2_` — transmission, par un poste, d'une facture ÉMISE AU WEB.
///
/// Le web n'a ni jeton ni accès à e-MECeF : n'importe quel poste appairé peut
/// transmettre une facture « web », mais seulement après l'avoir RÉSERVÉE au serveur
/// (un seul poste à la fois), et seul le détenteur peut ensuite envoyer sa
/// normalisation. Aucun secret ne voyage.
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
      tables: [TableFacturesPoste(db)],
      client: serveur.client,
    );
    factures = FacturesMecefRepositoryDrift(db);
  }

  final FauxServeurSync serveur;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final FacturesMecefRepositoryDrift factures;
  int transmissions = 0;
  bool dgiRefuse = false;

  Future<void> demarrer({bool appaire = true}) async {
    await preferences.definirAdresseServeur('http://serveur.test');
    if (appaire) {
      await preferences.memoriserAppairage(
        codePoste: 'P2',
        compte: 'g',
        le: DateTime.now(),
      );
      await depot.ecrire('1|jeton');
    }
    await SeedInitial(db).executer();
    await db
        .into(db.parametresEntreprise)
        .insertOnConflictUpdate(
          ParametresEntrepriseCompanion.insert(
            raisonSociale: const Value('ALLMANY'),
            mecefUrl: const Value('https://mecef.test'),
          ),
        );
  }

  Future<FacturesMecefViewModel> vm({bool avecReservation = true}) async {
    final v = FacturesMecefViewModel(
      factures,
      db,
      jetons: _Jetons(),
      fabriqueClient: ({required urlBase, required jeton, ifuEmetteur}) =>
          _FauxDgi(this),
      reserverTransmission: avecReservation
          ? moteur.reserverTransmission
          : null,
    );
    await v.charger();
    return v;
  }

  Future<FactureRow> ligne(String ref) =>
      (db.select(db.factures)..where((f) => f.ref.equals(ref))).getSingle();

  Future<void> fermer() => db.close();
}

class _Jetons extends DepotJetonMecef {
  @override
  Future<bool> get renseigne async => true;
  @override
  Future<String?> lire() async => 'jeton-dgi';
}

class _FauxDgi implements ClientMecef {
  _FauxDgi(this.poste);
  final _Poste poste;

  @override
  Future<ReponseMecef> transmettre(FactureMecef facture) async {
    poste.transmissions++;
    if (poste.dgiRefuse) throw const EchecTransmission('IFU invalide');
    return ReponseMecef(
      codeMecef: 'CODE-${facture.reference}',
      nim: 'NIM-9',
      compteur: '1/9',
      lienVerification: 'https://dgi.example/v',
      dateNormalisation: DateTime.now(),
    );
  }
}

const _web = '00000000-0000-0000-0000-000000000000';
const _idFacture = 'f0000000-0000-4000-8000-0000000000aa';
const _ref = 'FV-WEB-2026-001';

Map<String, dynamic> factureWeb({
  String id = _idFacture,
  String ref = _ref,
  String statut = 'a_transmettre',
}) => {
  'id': id,
  'reference': ref,
  'type': 'FV',
  'vente_ref': 'V-P1-2026-001',
  'origine_ref': null,
  'date_facture': '2026-11-09T08:00:00.000Z',
  'client': 'DOSSOU Félicité',
  'client_ifu': null,
  'client_adresse': null,
  'total_ht': 10000,
  'total_taxe': 1800,
  'total_ttc': 11800,
  'motif': null,
  'statut': statut,
  'code_mecef': null,
  'nim': null,
  'compteur': null,
  'lien_verification': null,
  'date_normalisation': null,
  'erreur_transmission': null,
  'updated_at': '2026-11-09T09:00:00.000000Z',
  'lignes': [
    {
      'id': 'a${id.substring(1)}',
      'designation': 'Goliath mature',
      'quantite': 1,
      'unite': 'u',
      'prix_unitaire_ht': 10000,
      'groupe_taxe': 'B',
      'taux_taxe': 18,
      'montant_ht': 10000,
      'montant_taxe': 1800,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FauxServeurSync serveur;
  final postes = <_Poste>[];

  Future<_Poste> poste({bool appaire = true}) async {
    final p = _Poste(serveur);
    postes.add(p);
    await p.demarrer(appaire: appaire);
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

  Future<_Poste> posteAvecFactureWeb() async {
    serveur.ajouterFacture(factureWeb(), device: _web);
    final p = await poste();
    final r = await p.moteur.synchroniser();
    expect(r.reussie, isTrue, reason: r.message);
    return p;
  }

  group('réception d\'une facture web', () {
    test(
      'absorbée telle quelle : poste émetteur « web », transmissible d\'ici',
      () async {
        final p = await posteAvecFactureWeb();
        final f = (await p.factures.parReference(_ref))!;
        expect(f.origine, identifiantPosteWeb);
        expect(f.estWeb, isTrue);
        expect(
          f.estDUnAutrePoste,
          isFalse,
          reason:
              'sans poste émetteur : n\'importe quel poste peut la transmettre',
        );
        expect((await p.ligne(_ref)).syncStatus, 'synced');
        expect(f.statut, StatutFacture.aTransmettre);
      },
    );

    test('la facture d\'un autre POSTE reste intransmissible', () async {
      serveur.ajouterFacture(
        factureWeb(
          id: 'f0000000-0000-4000-8000-0000000000bb',
          ref: 'FV-P7-2026-001',
        ),
        device: 'poste-sept',
      );
      final p = await poste();
      await p.moteur.synchroniser();
      final f = (await p.factures.parReference('FV-P7-2026-001'))!;
      expect(f.estDUnAutrePoste, isTrue);
      final r = await (await p.vm()).transmettre('FV-P7-2026-001');
      expect(r, isA<Echec<void>>());
      expect(p.transmissions, 0);
      expect(
        serveur.demandesReservation,
        isEmpty,
        reason: 'on ne réserve pas ce qu\'on n\'a pas le droit de transmettre',
      );
    });

    test(
      'une référence FV-WEB-AAAA-NNN est valide, FV-WEBX est refusée',
      () async {
        final p = await poste();
        final table = TableFacturesPoste(p.db);
        expect(
          (await table.absorber([
            factureWeb(ref: 'FV-WEBX-2026-001'),
          ])).refusees,
          1,
        );
        expect((await table.absorber([factureWeb()])).absorbees, 1);
      },
    );
  });

  group('transmission avec réservation', () {
    test(
      'réserve, transmet, envoie la normalisation : le serveur la garde',
      () async {
        final p = await posteAvecFactureWeb();
        final r = await (await p.vm()).transmettre(_ref);

        expect(r, isA<Succes<void>>());
        expect(p.transmissions, 1);
        expect(serveur.demandesReservation, hasLength(1));
        expect(serveur.demandesReservation.single['facture_id'], _idFacture);
        expect(serveur.demandesReservation.single['device_id'], isNotEmpty);
        expect((await p.ligne(_ref)).statut, 'normalisee');
        expect((await p.ligne(_ref)).syncStatus, 'pending');

        final s = await p.moteur.synchroniser();
        expect(s.reussie, isTrue, reason: s.message);
        expect(serveur.factures[_idFacture]!['statut'], 'normalisee');
        expect(serveur.factures[_idFacture]!['code_mecef'], 'CODE-$_ref');
        expect(
          serveur.factures[_idFacture]!['device_id'],
          _web,
          reason: 'l\'émetteur reste le web',
        );
        expect((await p.ligne(_ref)).syncStatus, 'synced');
      },
    );

    test('réservation refusée : aucune transmission à la DGI', () async {
      final p = await posteAvecFactureWeb();
      serveur.refuserReservation =
          'En cours de transmission depuis le poste P3.';
      final r = await (await p.vm()).transmettre(_ref);

      expect(r, isA<Echec<void>>());
      expect((r as Echec<void>).message, contains('P3'));
      expect(
        p.transmissions,
        0,
        reason: 'jamais de transmission sans réservation',
      );
      expect((await p.ligne(_ref)).statut, 'a_transmettre');
    });

    test('hors ligne : pas de réservation, donc pas de transmission', () async {
      final p = await posteAvecFactureWeb();
      serveur.horsLigne = true;
      final r = await (await p.vm()).transmettre(_ref);
      expect(r, isA<Echec<void>>());
      expect((r as Echec<void>).message, contains('injoignable'));
      expect(p.transmissions, 0);
    });

    test('poste non appairé : refusé, aucune transmission', () async {
      final p = await poste(appaire: false);
      await p.db
          .into(p.db.factures)
          .insert(
            FacturesCompanion.insert(
              id: const Value(_idFacture),
              ref: _ref,
              type: 'FV',
              dateFacture: DateTime(2026, 11, 9),
              client: 'X',
              totalHt: 1,
              totalTaxe: 0,
              totalTtc: 1,
              statut: 'a_transmettre',
              origine: const Value(_web),
            ),
          );
      final r = await (await p.vm()).transmettre(_ref);
      expect(r, isA<Echec<void>>());
      expect(p.transmissions, 0);
    });

    test(
      'sans moyen de réserver (poste sans synchronisation) : refusé',
      () async {
        final p = await posteAvecFactureWeb();
        final r = await (await p.vm(avecReservation: false)).transmettre(_ref);
        expect(r, isA<Echec<void>>());
        expect(p.transmissions, 0);
      },
    );

    test(
      'deux postes : le second est refusé tant que le premier détient la réservation',
      () async {
        serveur.ajouterFacture(factureWeb(), device: _web);
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        expect(await (await a.vm()).transmettre(_ref), isA<Succes<void>>());
        // B n'a pas encore reçu la normalisation de A : il tente aussi.
        final r = await (await b.vm()).transmettre(_ref);
        expect(r, isA<Echec<void>>());
        expect((r as Echec<void>).message, contains('autre poste'));
        expect(b.transmissions, 0, reason: 'une seule transmission à la DGI');
        expect(a.transmissions, 1);
      },
    );

    test(
      'envoyer une normalisation SANS réservation : refusé par le serveur',
      () async {
        final p = await posteAvecFactureWeb();
        // Le poste normalise « à la main » en contournant la réservation.
        await p.factures.normaliser(reference: _ref, codeMecef: 'C', nim: 'N');
        final s = await p.moteur.synchroniser();
        expect(s.refusees, 1);
        expect(serveur.factures[_idFacture]!['statut'], 'a_transmettre');
        expect((await p.ligne(_ref)).syncStatus, 'conflict');
      },
    );

    test('saisie manuelle du code : réserve aussi', () async {
      final p = await posteAvecFactureWeb();
      final r = await (await p.vm()).normaliserManuellement(
        reference: _ref,
        codeMecef: 'CODE-MAN',
        nim: 'NIM-M',
      );
      expect(r, isA<Succes<void>>());
      expect(serveur.demandesReservation, hasLength(1));
      await p.moteur.synchroniser();
      expect(serveur.factures[_idFacture]!['code_mecef'], 'CODE-MAN');
    });

    test(
      'saisie manuelle refusée si la réservation l\'est : rien n\'est écrit',
      () async {
        final p = await posteAvecFactureWeb();
        serveur.refuserReservation = 'Occupée.';
        final r = await (await p.vm()).normaliserManuellement(
          reference: _ref,
          codeMecef: 'X',
          nim: 'Y',
        );
        expect(r, isA<Echec<void>>());
        expect((await p.ligne(_ref)).statut, 'a_transmettre');
      },
    );

    test(
      'rejet de la DGI : la facture est rejetée, jamais normalisée',
      () async {
        final p = await posteAvecFactureWeb();
        p.dgiRefuse = true;
        final r = await (await p.vm()).transmettre(_ref);
        expect(r, isA<Echec<void>>());
        expect((await p.ligne(_ref)).statut, 'rejetee');
        await p.moteur.synchroniser();
        expect(serveur.factures[_idFacture]!['statut'], 'rejetee');
        expect(serveur.factures[_idFacture]!['code_mecef'], isNull);
      },
    );

    test(
      'une facture normalisée ne se retransmet pas, d\'ici ni d\'un autre poste',
      () async {
        serveur.ajouterFacture(factureWeb(), device: _web);
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await (await a.vm()).transmettre(_ref);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        expect((await b.ligne(_ref)).statut, 'normalisee');
        expect(
          () => b.factures.normaliser(
            reference: _ref,
            codeMecef: 'AUTRE',
            nim: 'N',
          ),
          throwsStateError,
        );
        expect(b.transmissions, 0);
      },
    );

    test('aucun secret sur le fil : ni jeton DGI ni URL e-MECeF', () async {
      final p = await posteAvecFactureWeb();
      await (await p.vm()).transmettre(_ref);
      await p.moteur.synchroniser();
      final fil =
          serveur.envois.toString() + serveur.demandesReservation.toString();
      expect(fil, isNot(contains('jeton-dgi')));
      expect(fil, isNot(contains('mecef.test')));
    });
  });

  group('envoi', () {
    test(
      'une facture web normalisée ICI part ; la facture d\'un autre poste jamais',
      () async {
        final p = await posteAvecFactureWeb();
        serveur.ajouterFacture(
          factureWeb(
            id: 'f0000000-0000-4000-8000-0000000000bb',
            ref: 'FV-P7-2026-001',
          ),
          device: 'poste-sept',
        );
        await p.moteur.synchroniser();
        await p.db.customStatement(
          "UPDATE factures SET sync_status = 'pending'",
        );
        final partants = await TableFacturesPoste(p.db).aEnvoyer();
        expect(partants.map((l) => l.corps['reference']), [_ref]);
      },
    );
  });

  group('remise à zéro du serveur', () {
    test(
      'une facture web normalisée ici est conservée et repart ; les autres partent',
      () async {
        final p = await posteAvecFactureWeb();
        await (await p.vm()).transmettre(_ref);
        await p.moteur.synchroniser();
        serveur.ajouterFacture(
          factureWeb(
            id: 'f0000000-0000-4000-8000-0000000000cc',
            ref: 'FV-WEB-2026-002',
          ),
          device: _web,
        );
        await p.moteur.synchroniser(complet: true);

        final perdues = await TableFacturesPoste(p.db).purger();
        expect(perdues, 0);
        final restantes = await p.db.select(p.db.factures).get();
        expect(restantes.map((f) => f.ref), [
          _ref,
        ], reason: 'pièce fiscale conservée');
        expect(
          restantes.single.syncStatus,
          'pending',
          reason: 'le serveur remis à zéro la reçoit de nouveau',
        );
      },
    );
  });

  group('avoir : jamais plus que la facture', () {
    Future<(_Poste, String)> avecFacture() async {
      final p = await poste();
      final dossier = FacturesMecefRepositoryDrift(p.db);
      await p.db
          .into(p.db.factures)
          .insert(
            FacturesCompanion.insert(
              ref: 'FV-P2-2026-001',
              type: 'FV',
              dateFacture: DateTime(2026, 11, 9),
              client: 'DOSSOU',
              totalHt: 10000,
              totalTaxe: 1800,
              totalTtc: 11800,
              statut: 'a_transmettre',
            ),
          );
      await p.db
          .into(p.db.lignesFacture)
          .insert(
            LignesFactureCompanion.insert(
              factureRef: 'FV-P2-2026-001',
              designation: 'Goliath',
              quantite: 4,
              prixUnitaireHt: 2500,
              groupeTaxe: 'B',
              tauxTaxe: 18,
              montantHt: 10000,
              montantTaxe: 1800,
            ),
          );
      expect(dossier, isNotNull);
      return (p, 'FV-P2-2026-001');
    }

    LigneFacture lignes(double qte) => LigneFacture(
      designation: 'Goliath',
      quantite: qte,
      prixUnitaireHt: 2500,
      groupeTaxe: 'B',
      tauxTaxe: 18,
    );

    test('un second avoir total est refusé', () async {
      final (p, ref) = await avecFacture();
      await p.factures.emettreAvoir(factureOrigine: ref, motif: 'Retour');
      expect(
        () => p.factures.emettreAvoir(factureOrigine: ref, motif: 'Encore'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('dépasseraient'),
          ),
        ),
      );
    });

    test(
      'des avoirs partiels se cumulent jusqu\'au total, pas au-delà',
      () async {
        final (p, ref) = await avecFacture();
        await p.factures.emettreAvoir(
          factureOrigine: ref,
          motif: 'a',
          lignes: [lignes(1)],
        );
        await p.factures.emettreAvoir(
          factureOrigine: ref,
          motif: 'b',
          lignes: [lignes(2)],
        );
        // Reste 1 : 2 dépasserait.
        expect(
          () => p.factures.emettreAvoir(
            factureOrigine: ref,
            motif: 'c',
            lignes: [lignes(2)],
          ),
          throwsStateError,
        );
        await p.factures.emettreAvoir(
          factureOrigine: ref,
          motif: 'd',
          lignes: [lignes(1)],
        );
        expect(
          () => p.factures.emettreAvoir(
            factureOrigine: ref,
            motif: 'e',
            lignes: [lignes(0.5)],
          ),
          throwsStateError,
        );
      },
    );

    test('un seul avoir total reste possible', () async {
      final (p, ref) = await avecFacture();
      final a = await p.factures.emettreAvoir(
        factureOrigine: ref,
        motif: 'Annulation',
      );
      expect(a.totalTtc, closeTo(11800, 0.001));
      expect(nouvelUuid(), isNotEmpty);
    });
  });
}
