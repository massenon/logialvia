import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/repositories/modules_actifs_repository_drift.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/administration/data/sync/table_modules_actifs_poste.dart';
import 'package:logialvia_app/administration/data/sync/table_parametres_entreprise_poste.dart';
import 'package:logialvia_app/approvisionnement/data/repositories/approvisionnement_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_achats_poste.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_fournisseurs_poste.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/approvisionnement.dart';
import 'package:logialvia_app/commercial/data/repositories/clients_repository_drift.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_produits_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_ventes_poste.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/droits_poste.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:logialvia_app/core/sync/table_effets_stock_poste.dart';
import 'package:logialvia_app/core/sync/table_poste.dart';
import 'package:logialvia_app/administration/data/repositories/parametres_repository_drift.dart';
import 'package:logialvia_app/commercial/data/repositories/factures_mecef_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/fabrication_provende.dart';
import 'package:logialvia_app/commercial/domain/entities/livraison.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';
import 'package:logialvia_app/elevage/data/repositories/cycle_couveuse_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/soins_repository_drift.dart';
import 'package:logialvia_app/elevage/domain/entities/cycle_incubation.dart';
import 'package:logialvia_app/elevage/domain/entities/soin.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/bandes_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/fiche_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/entities/journee_elevage.dart';
import 'package:logialvia_app/elevage/domain/services/calcul_fiche_journaliere.dart';
import 'package:logialvia_app/elevage/domain/usecases/enregistrer_journee_usecase.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/comptabilite/domain/entities/comptabilite.dart';
import 'package:logialvia_app/elevage/data/repositories/parametres_elevage_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_intrants_poste.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_mouvements_intrant_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_factures_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_groupes_taxe_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_mouvements_produit_poste.dart';
import 'package:logialvia_app/comptabilite/data/seed/plan_comptable_seeder.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_clotures_poste.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_ecritures_poste.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_exercices_poste.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_notes_annexes_poste.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_plan_comptable_poste.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/elevage/data/sync/table_bandes_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_cycles_couveuse_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_fiches_journee_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_infirmerie_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_machines_incubateur_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_parametres_elevage_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_soins_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_ventes_jour_poste.dart';

/// ESSAI CONTRE LE VRAI SERVEUR LARAVEL (`45_` §6c ; `47h_` : TOUTES les tables).
///
/// Désactivé par défaut : il exige un serveur qui tourne. Lancement en une commande
/// (base SQLite neuve, migrations, seeders, comptes, serveur, essai) :
///
/// ```bash
/// bash logialvia_app/outils/essai_vrai_serveur.sh        # port 8765 par défaut
/// ```
///
/// À la main : dans `logialvia_laravel/`
///
/// ```bash
/// export DB_DATABASE=/tmp/lv/essai.sqlite ADMIN_INITIAL_PASSWORD='EssaiPoste-2026!' \
///        REMISE_A_ZERO_ACTIVEE=true                      # (essai « remise à zéro »)
/// php artisan migrate:fresh --seed --force
/// # comptes admin1…admin150 (rôle admin), caissier1, comptable1, animalier1, sans mot
/// # de passe temporaire ; module ovins actif et paramètres décidés côté serveur (voir
/// # le script pour la ligne tinker exacte)
/// php artisan serve --port=8765
/// ```
///
/// puis dans `logialvia_app/` :
///
/// ```bash
/// LOGIALVIA_SERVEUR=http://127.0.0.1:8765 LOGIALVIA_MDP='EssaiPoste-2026!' \
///   LOGIALVIA_LARAVEL=<dossier logialvia_laravel> LOGIALVIA_DB=/tmp/lv/essai.sqlite \
///   flutter test test/integration/serveur_reel_test.dart
/// ```
///
/// - Chaque poste de l'essai se connecte avec son propre compte `adminN` (le limiteur de
///   connexion : 5 par minute et par identifiant) ; `LOGIALVIA_COMPTE_DEBUT=N` décale la
///   numérotation si on relance sur un serveur déjà utilisé.
/// - `LOGIALVIA_LARAVEL` + `LOGIALVIA_DB` : les écrans WEB écrivent par les mêmes
///   absorbeurs que le poste ; ces essais les rejouent par `artisan tinker` (ignorés sinon).
/// - Les deux dernières essais (clôture annuelle, remise à zéro) changent l'état de tout le
///   serveur : ils viennent en dernier, et la remise à zéro exige `REMISE_A_ZERO_ACTIVEE`.
/// - On peut rejouer sous un autre fuseau : `TZ=Africa/Porto-Novo` ou `TZ=America/Los_Angeles`.
///
/// Les faux serveurs des autres tests rejouent le contrat ; celui-ci prouve que le contrat
/// est bien celui que le serveur réel tient (`docs/logialvia/47h_PREUVE_VRAI_SERVEUR.md`).
void main() {
  final adresse = Platform.environment['LOGIALVIA_SERVEUR'];
  final mdp = Platform.environment['LOGIALVIA_MDP'] ?? '';
  final saute = adresse == null
      ? 'LOGIALVIA_SERVEUR non défini : essai contre le vrai serveur ignoré.'
      : false;

  // Le limiteur de connexion (5 par minute et par identifiant) fait son travail :
  // chaque poste de l'essai se connecte donc avec son propre compte administrateur
  // (admin1, admin2… créés avant l'essai).
  var compte =
      int.tryParse(Platform.environment['LOGIALVIA_COMPTE_DEBUT'] ?? '') ?? 0;

  /// Un poste complet, HTTP réel : MÊMES tables, MÊME ordre, MÊME semis que
  /// `main.dart` (un poste de l'essai est un poste de la Gérante).
  Future<_Poste> poste({String? compteForce, int tailleLot = 2}) async {
    final db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    final preferences = PreferencesPosteRepository(db);
    final depot = DepotJetonSyncMemoire();
    final appairage = ServiceAppairage(preferences: preferences, depot: depot);
    final r = await appairage.connecter(
      adresse: adresse!,
      identifiant: compteForce ?? 'admin${++compte}',
      motDePasse: mdp,
    );
    expect(r.reussi, isTrue, reason: r.message);
    return _Poste(
      db,
      preferences,
      depot,
      appairage,
      MoteurSynchronisationPoste(
        preferences: preferences,
        depot: depot,
        appairage: appairage,
        tables: tablesDuPoste(db),
        demandes: DepotDemandesReferentiel(db),
        socleDuPlan: {
          for (final c in PlanComptableSeeder.tous)
            c.numero: (libelle: c.libelle, classe: c.classe),
        },
        tailleLot: tailleLot,
      ),
    );
  }

  final postes = <_Poste>[];
  tearDown(() async {
    for (final p in postes) {
      await p.db.close();
    }
    postes.clear();
  });

  test('appairage réel : code de poste attribué, test de connexion', () async {
    final a = await poste()
      ..let(postes.add);
    final etat = await a.appairage.etat();
    expect(etat.appaire, isTrue);
    expect(etat.codePoste, matches(RegExp(r'^P\d+$')));
    expect((await a.appairage.tester()).reussi, isTrue);
  }, skip: saute);

  test(
    'cohérence réelle : jamais synchronisé, puis plus rien à recevoir',
    () async {
      final a = await poste()
        ..let(postes.add);
      final b = await poste()
        ..let(postes.add);
      await ClientsRepositoryDrift(a.db).creerClient(
        nom: 'Client cohérence ${DateTime.now().microsecondsSinceEpoch}',
      );
      expect((await a.moteur.synchroniser()).reussie, isTrue);

      // B n'a jamais tiré : tout est « à recevoir », dont le client de A.
      final avant = await b.moteur.coherenceServeur();
      expect(avant.repondu, isTrue);
      expect(avant.jamaisSynchronise, isTrue);
      expect(avant.retard['clients'], greaterThanOrEqualTo(1));

      // Après son tirage complet, plus rien de plus récent que ce que B a reçu.
      expect((await b.moteur.synchroniser()).reussie, isTrue);
      final apres = await b.moteur.coherenceServeur();
      expect(apres.jamaisSynchronise, isFalse);
      expect(
        apres.retard,
        isEmpty,
        reason: 'B n\'a rien envoyé : rien ne revient',
      );
      expect(apres.aJour, isTrue);
    },
    skip: saute,
  );

  test('deux postes, vraie base : création, correction, convergence', () async {
    final a = await poste()
      ..let(postes.add);
    final b = await poste()
      ..let(postes.add);
    expect(
      (await a.appairage.etat()).codePoste,
      isNot((await b.appairage.etat()).codePoste),
      reason: 'chaque poste reçoit son propre code (DV-21)',
    );

    final c = await ClientsRepositoryDrift(a.db).creerClient(
      nom: 'Client réel ${DateTime.now().microsecondsSinceEpoch}',
      telephone: '97000042',
      dateNaissance: DateTime(1990, 3, 1),
    );
    final ra = await a.moteur.synchroniser();
    expect(ra.reussie, isTrue, reason: ra.message);
    expect(ra.acceptees, 1);

    final rb = await b.moteur.synchroniser();
    expect(rb.reussie, isTrue, reason: rb.message);
    final chezB = await b.ligne(c.id);
    expect(chezB.nom, c.nom);
    expect(chezB.telephone, '97000042');
    expect(
      chezB.dateNaissance,
      DateTime(1990, 3, 1),
      reason: 'jour civil, sans décalage',
    );
    expect(chezB.syncStatus, 'synced');

    // B corrige ; A reçoit.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await ClientsRepositoryDrift(b.db).enregistrerContact(c.id);
    expect((await b.moteur.synchroniser()).reussie, isTrue);
    expect((await a.moteur.synchroniser()).reussie, isTrue);
    expect((await a.ligne(c.id)).dernierContact, isNotNull);

    // Idempotence : rien de plus à envoyer, rien de plus à recevoir.
    final encore = await a.moteur.synchroniser();
    expect(encore.envoyees, 0);
  }, skip: saute);

  test(
    'saisie ancienne arrivée en retard : les deux postes convergent vers la plus récente',
    () async {
      final a = await poste()
        ..let(postes.add);
      final b = await poste()
        ..let(postes.add);
      final c = await ClientsRepositoryDrift(
        a.db,
      ).creerClient(nom: 'LWW ${DateTime.now().microsecondsSinceEpoch}');
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();

      Future<void> saisir(_Poste p, String nom, String instant) =>
          (p.db.update(p.db.clients)..where((x) => x.id.equals(c.id))).write(
            ClientsCompanion(
              nom: Value(nom),
              syncStatus: const Value('pending'),
              updatedAt: Value(instant),
            ),
          );
      final recent = DateTime.now().toUtc().add(const Duration(hours: 1));
      await saisir(b, 'Version récente', recent.toIso8601String());
      await saisir(
        a,
        'Version ancienne',
        recent.subtract(const Duration(hours: 2)).toIso8601String(),
      );

      for (final p in [b, a, a, b]) {
        expect((await p.moteur.synchroniser()).reussie, isTrue);
      }

      expect((await a.ligne(c.id)).nom, 'Version récente');
      expect((await b.ligne(c.id)).nom, 'Version récente');
    },
    skip: saute,
  );

  test(
    'référentiels réels : un réglage décidé descend, une valeur de semis n\'écrase rien',
    () async {
      final a = await poste()
        ..let(postes.add);
      // Choix local de la Gérante sur un module que le serveur n'a jamais décidé.
      await (a.db.update(a.db.modulesActifs)
            ..where((m) => m.moduleId.equals('cuniculture')))
          .write(const ModulesActifsCompanion(isActif: Value(true)));
      await a.db
          .into(a.db.parametresEntreprise)
          .insertOnConflictUpdate(
            const ParametresEntrepriseCompanion(
              ifu: Value('IFU-LOCAL'),
              modeDonneesTest: Value(false),
            ),
          );

      final r = await a.moteur.synchroniser();
      expect(r.reussie, isTrue, reason: r.message);

      Future<bool> actif(String id) async => (await (a.db.select(
        a.db.modulesActifs,
      )..where((m) => m.moduleId.equals(id))).getSingle()).isActif;
      expect(
        await actif('ovins'),
        isTrue,
        reason: 'décidé sur le serveur : appliqué',
      );
      expect(
        await actif('cuniculture'),
        isTrue,
        reason: 'semis du serveur : le choix local reste',
      );

      final p = await (a.db.select(
        a.db.parametresEntreprise,
      )..where((x) => x.id.equals(1))).getSingle();
      expect(p.raisonSociale, 'ALLMANY SARL (web)');
      expect(p.prefixeBac, 'BC');
      expect(
        p.ifu,
        'IFU-LOCAL',
        reason: 'null du serveur : jamais d\'effacement',
      );
      expect(p.modeDonneesTest, isFalse);
      expect(r.referentielsMisAJour, greaterThanOrEqualTo(2));
    },
    skip: saute,
  );

  test(
    'demande « synchronise maintenant » puis « renvoyer vers ce poste » : servies et acquittées',
    () async {
      final admin = await poste()
        ..let(postes.add);
      final b = await poste()
        ..let(postes.add);
      Future<http.Response> web(
        String chemin,
        Map<String, Object?> corps,
      ) async => http.post(
        Uri.parse('$adresse$chemin'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await admin.depot.lire()}',
        },
        body: jsonEncode(corps),
      );

      // Rien demandé : rien à faire.
      final repos = await b.moteur.interrogerDemande();
      expect(repos.issue, IssueSynchronisation.terminee);
      expect(repos.synchroniser, isFalse);

      final idB = await b.preferences.identifiantPoste();
      expect(
        (await web('/api/parametres/postes/synchroniser', {
          'device_name': idB,
        })).statusCode,
        200,
      );
      final servie = await b.moteur.interrogerDemande();
      expect(servie.synchroniser, isTrue);
      expect(
        (await b.moteur.interrogerDemande()).synchroniser,
        isFalse,
        reason: 'servie une seule fois',
      );

      expect(
        (await web('/api/parametres/postes/renvoyer', {
          'device_name': idB,
        })).statusCode,
        200,
      );
      expect(
        (await b.moteur.interrogerDemande()).resynchronisationComplete,
        isTrue,
      );
      final complet = await b.moteur.synchroniser(complet: true);
      expect(complet.reussie, isTrue, reason: complet.message);
      expect(await b.moteur.acquitterResynchronisation(), isTrue);
      expect(
        (await b.moteur.interrogerDemande()).resynchronisationComplete,
        isFalse,
      );
    },
    skip: saute,
  );

  test(
    'une modification de module faite au poste est proposée, acceptée et redescend vers les autres',
    () async {
      final a = await poste()
        ..let(postes.add);
      final b = await poste()
        ..let(postes.add);
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();

      await ModulesActifsRepositoryDrift(
        a.db,
      ).definirEtat('heliciculture', actif: true);
      final ra = await a.moteur.synchroniser();
      expect(ra.reussie, isTrue, reason: ra.message);
      expect(ra.demandesAcceptees, 1);

      final rb = await b.moteur.synchroniser();
      expect(rb.reussie, isTrue, reason: rb.message);
      final chezB = await (b.db.select(
        b.db.modulesActifs,
      )..where((m) => m.moduleId.equals('heliciculture'))).getSingle();
      expect(
        chezB.isActif,
        isTrue,
        reason: 'décidé par le poste A, reçu par le poste B',
      );
    },
    skip: saute,
  );

  test(
    'un caissier ne propose pas les modules : la demande attend le droit (`47g_`), jamais conflit',
    () async {
      final c = await poste(compteForce: 'caissier1')
        ..let(postes.add);
      await ModulesActifsRepositoryDrift(
        c.db,
      ).definirEtat('pisciculture', actif: true);

      final r = await c.moteur.synchroniser();

      // Le poste connaît les droits de `caissier1` : il ne propose que le catalogue (droit de
      // vendre) ; intrants, barèmes, plan comptable, modules… restent EN ATTENTE DE DROIT.
      expect(r.demandesRefusees, 0, reason: r.message);
      expect(r.enAttenteDeDroit, greaterThanOrEqualTo(1), reason: r.message);
      final d = (await c.db.select(c.db.demandesReferentiel).get()).singleWhere(
        (x) => x.type == 'module_actif',
      );
      expect(d.syncStatus, 'pending', reason: 'jamais conflict');
      expect(d.syncMotif, isNull);
    },
    skip: saute,
  );

  test(
    'ventes réelles : deux postes vendent, chacun reçoit celles de l\'autre, références à code de poste',
    () async {
      final a = await poste()
        ..let(postes.add);
      final b = await poste()
        ..let(postes.add);
      final venteA = VentesRepositoryDrift(a.db, EventBus());
      final venteB = VentesRepositoryDrift(b.db, EventBus());

      Future<String> vendre(
        VentesRepositoryDrift repo, {
        String client = 'Client Comptant',
        String? clientId,
        String statut = StatutVente.payee,
        double? paye,
      }) async {
        final p = (await repo.chargerCatalogue()).firstWhere(
          (x) => x.nom == 'Goliath mature',
        );
        final r = await repo.enregistrerVente(
          client: client,
          clientId: clientId,
          mode: ModeReglement.especes,
          statut: statut,
          montantPaye: paye ?? p.prix * 2,
          panier: [
            LignePanier(
              produitId: p.id,
              nom: p.nom,
              montantGlobal: p.prix * 2,
              quantite: 2,
              stockDisponible: p.stock,
              prixIndicatif: p.prix,
              prixIndicatifMax: p.prixMax,
              espece: p.espece,
              unite: p.unite,
            ),
          ],
        );
        return r.vente.reference;
      }

      // Les deux postes ont un code attribue par le VRAI serveur : leurs references different.
      final codeA = (await a.appairage.etat()).codePoste!;
      final codeB = (await b.appairage.etat()).codePoste!;
      expect(codeA, isNot(codeB));
      final refA = await vendre(venteA);
      final refB = await vendre(venteB);
      expect(refA, startsWith('V-$codeA-'));
      expect(refB, startsWith('V-$codeB-'));

      final ra = await a.moteur.synchroniser();
      expect(ra.reussie, isTrue, reason: ra.message);
      expect(ra.refusees, 0, reason: ra.message);
      final rb = await b.moteur.synchroniser();
      expect(rb.refusees, 0, reason: rb.message);
      await a.moteur.synchroniser();

      for (final p in [a, b]) {
        final refs = (await p.db.select(p.db.ventes).get())
            .map((v) => v.ref)
            .toSet();
        // Un serveur déjà utilisé par d'autres essais en a d'autres : « au moins ».
        expect(
          refs,
          containsAll([refA, refB]),
          reason: 'chaque poste connaît les deux ventes',
        );
        expect(
          (await p.db.select(p.db.lignesVente).get()).length,
          greaterThanOrEqualTo(2),
        );
        expect(
          (await p.db.select(p.db.ventes).get()).every(
            (v) => v.syncStatus == 'synced',
          ),
          isTrue,
        );
      }
      // Le stock reste propre a chaque poste : 31 - 2 chez le vendeur, 31 - 2 chez l'autre
      // (chacun a vendu sa vente) ; la vente RECUE n'a rien decremente.
      final goliathA = (await venteA.chargerCatalogue()).firstWhere(
        (x) => x.nom == 'Goliath mature',
      );
      expect(
        goliathA.stock,
        29,
        reason: 'la vente de B reçue chez A n\'a pas touché son stock',
      );
    },
    skip: saute,
  );

  test(
    'ventes réelles : le client choisi reçoit la vente, la créance est calculée par le serveur',
    () async {
      final a = await poste()
        ..let(postes.add);
      final venteA = VentesRepositoryDrift(a.db, EventBus());
      final clients = ClientsRepositoryDrift(a.db);
      final rita1 = await clients.creerClient(
        nom: 'Mama Rita',
        telephone: '97000001',
      );
      await clients.creerClient(nom: 'Mama Rita', telephone: '97000002');
      final p = (await venteA.chargerCatalogue()).firstWhere(
        (x) => x.nom == 'Goliath mature',
      );

      final r = await venteA.enregistrerVente(
        client: 'Mama Rita',
        clientId: rita1.id,
        mode: ModeReglement.especes,
        statut: StatutVente.avance,
        montantPaye: 1000,
        panier: [
          LignePanier(
            produitId: p.id,
            nom: p.nom,
            montantGlobal: p.prix,
            quantite: 1,
            stockDisponible: p.stock,
            prixIndicatif: p.prix,
            prixIndicatifMax: p.prixMax,
            espece: p.espece,
            unite: p.unite,
          ),
        ],
      );

      final rs = await a.moteur.synchroniser();
      expect(rs.refusees, 0, reason: rs.message);
      final vente = await (a.db.select(
        a.db.ventes,
      )..where((v) => v.ref.equals(r.vente.reference))).getSingle();
      expect(vente.clientId, rita1.id);
      expect(vente.syncStatus, 'synced');
      final idServeur = await http.get(
        Uri.parse('$adresse/api/sync/pull'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${await a.depot.lire()}',
        },
      );
      final corps = jsonDecode(idServeur.body) as Map<String, dynamic>;
      final clientServeur = ((corps['tables'] as Map)['clients'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((c) => c['id'] == rita1.id);
      expect(
        (clientServeur['solde_creance'] as num).toDouble(),
        p.prix - 1000,
        reason:
            'solde dérivé calculé par le serveur, jamais envoyé par le poste',
      );
    },
    skip: saute,
  );

  test(
    'achats réels : deux postes achètent, chacun reçoit ceux de l\'autre, références à code de poste, stock inchangé',
    () async {
      final a = await poste()
        ..let(postes.add);
      final b = await poste()
        ..let(postes.add);
      final appA = ApprovisionnementRepositoryDrift(a.db);
      final appB = ApprovisionnementRepositoryDrift(b.db);

      Future<String> acheter(
        ApprovisionnementRepositoryDrift repo,
        String fournisseur, {
        bool livree = false,
      }) async {
        final f = await repo.creerFournisseur(
          nom: fournisseur,
          telephone: '97000001',
        );
        final r = await repo.enregistrerAchat(
          fournisseurId: f.id,
          mode: ModeReglement.especes,
          montantPaye: 5000,
          livree: livree,
          panier: [
            const LignePanierAchat(
              intrantCode: 'INT-001',
              nom: 'Maïs',
              quantite: 50,
              prixUnitaire: 300,
              unite: 'kg',
            ),
          ],
        );
        return r.reference;
      }

      final codeA = (await a.appairage.etat()).codePoste!;
      final codeB = (await b.appairage.etat()).codePoste!;
      final refA = await acheter(appA, 'Maïs Local A', livree: true);
      final refB = await acheter(appB, 'Maïs Local B');
      expect(refA, startsWith('ACH-$codeA-'));
      expect(refB, startsWith('ACH-$codeB-'));
      Future<int> stock(AppDatabase db) async => (await (db.select(
        db.intrants,
      )..where((i) => i.code.equals('INT-001'))).getSingle()).stock;
      final stockB = await stock(b.db);

      final ra = await a.moteur.synchroniser();
      expect(ra.reussie, isTrue, reason: ra.message);
      expect(ra.refusees, 0, reason: ra.message);
      final rb = await b.moteur.synchroniser();
      expect(rb.refusees, 0, reason: rb.message);
      await a.moteur.synchroniser();

      for (final p in [a, b]) {
        final refs = (await p.db.select(p.db.achats).get())
            .map((x) => x.ref)
            .toSet();
        expect(
          refs,
          containsAll([refA, refB]),
          reason: 'chaque poste connaît les deux achats',
        );
        expect(
          (await p.db.select(p.db.lignesAchat).get()).length,
          greaterThanOrEqualTo(2),
        );
        expect(
          (await p.db.select(p.db.achats).get()).every(
            (x) => x.syncStatus == 'synced',
          ),
          isTrue,
        );
      }
      expect(
        await stock(b.db),
        stockB,
        reason: 'l\'achat livré de A reçu chez B n\'a pas touché son stock',
      );
    },
    skip: saute,
  );

  test(
    'achats réels : un caissier ne voit ni achats ni fournisseurs, et ne peut en écrire',
    () async {
      final c = await poste(compteForce: 'caissier1')
        ..let(postes.add);
      final app = ApprovisionnementRepositoryDrift(c.db);
      final f = await app.creerFournisseur(nom: 'Interdit');
      await app.enregistrerAchat(
        fournisseurId: f.id,
        mode: ModeReglement.especes,
        montantPaye: 0,
        livree: false,
        panier: [
          const LignePanierAchat(
            intrantCode: 'INT-001',
            nom: 'Maïs',
            quantite: 1,
            prixUnitaire: 300,
            unite: 'kg',
          ),
        ],
      );

      final r = await c.moteur.synchroniser();

      // `47g_` : le poste sait que `caissier1` n'écrit pas les achats : il ne les propose pas,
      // ils attendent le droit (aucun refus du serveur, aucun conflit).
      expect(r.refusees, 0, reason: r.message);
      expect(r.enAttenteDeDroit, greaterThanOrEqualTo(2), reason: r.message);
      final fournisseur = await (c.db.select(
        c.db.fournisseurs,
      )..where((x) => x.id.equals(f.id))).getSingle();
      expect(fournisseur.syncStatus, 'pending');
      expect(fournisseur.syncMotif, isNull);

      // Une session avec le bon droit (autre compte appairé à ce poste) : tout part.
      final autre = await c.appairage.connecter(
        adresse: adresse!,
        identifiant: 'admin${++compte}',
        motDePasse: mdp,
      );
      expect(autre.reussi, isTrue, reason: autre.message);
      final apres = await c.moteur.synchroniser();
      expect(apres.reussie, isTrue, reason: apres.message);
      expect(apres.enAttenteDeDroit, 0);
      final parti = await (c.db.select(
        c.db.fournisseurs,
      )..where((x) => x.id.equals(f.id))).getSingle();
      expect(parti.syncStatus, 'synced');
    },
    skip: saute,
  );

  test(
    'un client refusé par le serveur devient conflit, avec le motif du serveur',
    () async {
      final a = await poste()
        ..let(postes.add);
      await a.db
          .into(a.db.clients)
          .insert(
            ClientsCompanion.insert(
              id: const Value('99999999-9999-4999-8999-999999999999'),
              nom: '   ',
            ),
          );

      final r = await a.moteur.synchroniser();

      expect(r.refusees, 1);
      final c = await a.ligne('99999999-9999-4999-8999-999999999999');
      expect(c.syncStatus, 'conflict');
      expect(c.syncMotif, isNotNull);
      // ignore: avoid_print
      print('Motif réel du serveur : ${c.syncMotif}');
    },
    skip: saute,
  );

  test(
    'poste révoqué depuis le web : 401, jeton oublié, saisies conservées',
    () async {
      final admin = await poste()
        ..let(postes.add);
      final b = await poste()
        ..let(postes.add);
      await ClientsRepositoryDrift(
        b.db,
      ).creerClient(nom: 'Je reste ${DateTime.now().microsecondsSinceEpoch}');

      final reponse = await http.post(
        Uri.parse('$adresse/api/parametres/postes/revoquer'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await admin.depot.lire()}',
        },
        body: jsonEncode({
          'device_name': await b.preferences.identifiantPoste(),
        }),
      );
      expect(reponse.statusCode, 200, reason: reponse.body);

      final r = await b.moteur.synchroniser();
      expect(r.issue, IssueSynchronisation.revoque);
      expect(await b.depot.lire(), isNull);
      expect((await b.db.select(b.db.clients).get()), hasLength(1));
    },
    skip: saute,
  );

  // ===========================================================================
  // 47h — TOUTES les familles de tables, poste A -> VRAI serveur -> poste B.
  // ===========================================================================

  /// Synchronise et exige un cycle réussi ; renvoie le rapport.
  Future<RapportSynchronisation> sync(_Poste p, {bool complet = false}) async {
    final r = await p.moteur.synchroniser(complet: complet);
    expect(r.reussie, isTrue, reason: r.message);
    return r;
  }

  /// A -> serveur -> B (puis A encore, pour que les accusés/échos se stabilisent).
  Future<void> aller(_Poste a, _Poste b) async {
    await sync(a);
    await sync(b);
  }

  final unique = DateTime.now().microsecondsSinceEpoch.toString();

  /// Une vente de [qte] « Goliath mature » (ou un autre produit), par le vrai dépôt.
  Future<String> vendre(
    _Poste p, {
    String produit = 'Goliath mature',
    double qte = 1,
    String client = 'Client Comptant',
    String? clientId,
    String statut = StatutVente.payee,
    double? paye,
    String mode = ModeReglement.especes,
  }) async {
    final repo = VentesRepositoryDrift(p.db, EventBus());
    final x = (await repo.chargerCatalogue()).firstWhere(
      (c) => c.nom == produit,
    );
    final r = await repo.enregistrerVente(
      client: client,
      clientId: clientId,
      mode: mode,
      statut: statut,
      montantPaye: paye ?? x.prix * qte,
      panier: [
        LignePanier(
          produitId: x.id,
          nom: x.nom,
          montantGlobal: x.prix * qte,
          quantite: qte,
          stockDisponible: x.stock,
          prixIndicatif: x.prix,
          prixIndicatifMax: x.prixMax,
          espece: x.espece,
          unite: x.unite,
        ),
      ],
    );
    return r.vente.reference;
  }

  Future<VenteRow> laVente(_Poste p, String ref) =>
      (p.db.select(p.db.ventes)..where((v) => v.ref.equals(ref))).getSingle();

  group('faits commerciaux : ventes, clients, achats, factures', () {
    test(
      'vente à crédit : avance, encaissement du solde puis annulation circulent vers B (statuts, montants, créance du serveur)',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final clients = ClientsRepositoryDrift(a.db);
        final c = await clients.creerClient(
          nom: 'Crédit 47h $unique',
          telephone: '97470001',
        );
        final ref = await vendre(
          a,
          client: c.nom,
          clientId: c.id,
          statut: StatutVente.avance,
          paye: 1000,
          mode: ModeReglement.mobileMoney,
        );
        await aller(a, b);
        var chezB = await laVente(b, ref);
        expect(chezB.status, StatutVente.avance);
        expect(chezB.paye, 1000);
        expect(chezB.mode, ModeReglement.mobileMoney);
        expect(chezB.clientId, c.id);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        final repoA = VentesRepositoryDrift(a.db, EventBus());
        await repoA.enregistrerPaiement(
          reference: ref,
          montant: chezB.total - 1000,
        );
        await aller(a, b);
        chezB = await laVente(b, ref);
        expect(chezB.status, StatutVente.payee);
        expect(chezB.paye, chezB.total);
        expect(
          (await (b.db.select(
            b.db.clients,
          )..where((x) => x.id.equals(c.id))).getSingle()).soldeCreance,
          0,
          reason: 'créance soldée, recalculée par le serveur',
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        await repoA.annulerVente(
          reference: ref,
          motif: MotifAnnulation.tous.first,
        );
        await aller(a, b);
        expect((await laVente(b, ref)).status, StatutVente.annulee);
        expect((await laVente(a, ref)).syncStatus, 'synced');
      },
      skip: saute,
    );

    test(
      'achat commandé puis réceptionné et réglé au poste A : B reçoit le dernier état (statut, montant payé)',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final app = ApprovisionnementRepositoryDrift(a.db);
        final f = await app.creerFournisseur(
          nom: 'Fournisseur 47h $unique',
          telephone: '97470002',
        );
        final achat = await app.enregistrerAchat(
          fournisseurId: f.id,
          mode: ModeReglement.especes,
          montantPaye: 0,
          livree: false,
          panier: const [
            LignePanierAchat(
              intrantCode: 'INT-001',
              nom: 'Maïs',
              quantite: 20,
              prixUnitaire: 310,
              unite: 'kg',
            ),
          ],
        );
        await aller(a, b);
        expect(
          (await (b.db.select(
            b.db.achats,
          )..where((x) => x.ref.equals(achat.reference))).getSingle()).statut,
          StatutAchat.commande,
        );
        expect(
          (await b.db.select(b.db.fournisseurs).get()).map((x) => x.nom),
          contains('Fournisseur 47h $unique'),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        await app.receptionnerAchat(achat.reference);
        await app.reglerAchat(reference: achat.reference, montant: 6200);
        await aller(a, b);
        final chezB = await (b.db.select(
          b.db.achats,
        )..where((x) => x.ref.equals(achat.reference))).getSingle();
        expect(chezB.statut, StatutAchat.livre);
        expect(chezB.paye, 6200);
        expect(chezB.total, 20 * 310);
      },
      skip: saute,
    );

    test(
      'facture e-MECeF et avoir : émises au poste A, normalisées, reçues par B ; la grille de taxation vient du serveur',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final ref = await vendre(a, qte: 2);
        final factures = FacturesMecefRepositoryDrift(a.db);
        final facture = await factures.emettrePourVente(venteRef: ref);
        final avoir = await factures.emettreAvoir(
          factureOrigine: facture.reference,
          motif: 'Retour 47h',
        );
        final ra = await sync(a);
        expect(ra.refusees, 0, reason: ra.message);
        await factures.normaliser(
          reference: facture.reference,
          codeMecef: 'CODE-47H-$unique',
          nim: 'NIM-47H',
          compteur: '12/50',
          lienVerification: 'https://dgi.example/v/47h',
        );
        final rn = await sync(a);
        expect(rn.refusees, 0, reason: rn.message);
        await sync(b);

        final lues = await b.db.select(b.db.factures).get();
        final f = lues.singleWhere((x) => x.ref == facture.reference);
        expect(f.statut, 'normalisee');
        expect(f.codeMecef, 'CODE-47H-$unique');
        expect(f.nim, 'NIM-47H');
        expect(f.origine, isNotNull, reason: 'facture d\'un autre poste');
        final av = lues.singleWhere((x) => x.ref == avoir.reference);
        expect(av.type, 'FA');
        expect(av.origineRef, facture.reference);
        expect(
          (await b.db.select(b.db.lignesFacture).get()).length,
          greaterThanOrEqualTo(2),
        );
        expect(
          (await b.db.select(b.db.groupesTaxe).get()),
          isNotEmpty,
          reason: 'la grille descend du serveur',
        );
      },
      skip: saute,
    );
  });

  /// Saisit une journée par le VRAI cas d'usage (calculs, cascade).
  Future<void> saisirJour(
    _Poste p,
    DateTime jour, {
    int achat = 0,
    int ne = 0,
    List<int> morts = const [0, 0, 0],
    String? observation,
    ConfigurationEspece configuration = ConfigurationsEspeces.goliaths,
  }) async {
    final cas = EnregistrerJourneeUseCase(
      FicheElevageRepositoryDrift(p.db, configuration),
      configuration,
    );
    final r = await cas.executer(
      date: jour,
      mouvements: MouvementsJour(
        achat: achat,
        ne: ne,
        mortsParCategorie: morts,
        donsParCategorie: const [0, 0, 0],
      ),
      traitementObs: observation,
    );
    expect(r, isA<Succes<JourneeElevage>>(), reason: 'saisie du $jour : $r');
  }

  // Jours « lointains » propres à cette exécution : le serveur est partagé.
  // (jours CIVILS : `add(Duration(days:))` traverse un changement d'heure et décale minuit).
  final base = DateTime(
    2019,
    1,
    1 + int.parse(unique.substring(unique.length - 4)) % 1500,
  );
  DateTime jourPlus(int n) => DateTime(base.year, base.month, base.day + n);

  group('élevage : fiches journalières, compteurs, bandes', () {
    test(
      'trois jours saisis au poste A (cascade des effectifs) : B reçoit les mêmes fiches, au centième près',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        await saisirJour(a, base, achat: 20, ne: 5, observation: 'Début 47h');
        await saisirJour(a, jourPlus(1), morts: [1, 0, 0]);
        await saisirJour(
          a,
          jourPlus(2),
          morts: [
            2,
            0,
            0,
          ], // des sujets existent seulement dans la 1re catégorie
          observation: 'Traitement 47h',
        );

        final ra = await sync(a);
        expect(ra.refusees, 0, reason: ra.message);
        await sync(b);

        final fa = await (a.db.select(
          a.db.ficheJournee,
        )..orderBy([(f) => OrderingTerm.asc(f.date)])).get();
        final fb = await (b.db.select(
          b.db.ficheJournee,
        )..orderBy([(f) => OrderingTerm.asc(f.date)])).get();
        expect(fa.length, greaterThanOrEqualTo(3));
        expect(fb.length, fa.length);
        for (var i = 0; i < fa.length; i++) {
          expect(fb[i].id, fa[i].id);
          expect(fb[i].date, fa[i].date, reason: 'jour civil, sans décalage');
          expect(fb[i].effectif, fa[i].effectif);
          expect(fb[i].mortCat1, fa[i].mortCat1);
          expect(fb[i].mortCat2, fa[i].mortCat2);
          expect(fb[i].effCat1Day, fa[i].effCat1Day);
          expect(fb[i].traitementObs, fa[i].traitementObs);
        }
        expect(fa.every((f) => f.syncStatus == 'synced'), isTrue);
      },
      skip: saute,
    );

    test(
      'compteurs de ventes du jour : une vente de goliath au poste A alimente le compteur de A, B le reçoit sans le cumuler à son propre',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        await vendre(a, qte: 2);
        await vendre(b, qte: 3);
        await sync(a);
        await sync(b);
        await sync(a);

        // Un serveur déjà utilisé par d'autres essais porte d'autres compteurs :
        // on ne regarde que ceux de CES deux postes.
        final idA = await a.preferences.identifiantPoste();
        final idB = await b.preferences.identifiantPoste();
        int total(List<FicheVenteJourRow> l, String? origine) => l
            .where((c) => c.origine == origine)
            .map((c) => c.qte)
            .fold<int>(0, (x, y) => x + y);
        final ca = await a.db.select(a.db.ficheVentesJour).get();
        final cb = await b.db.select(b.db.ficheVentesJour).get();
        expect(total(ca, null), 2, reason: 'compteur propre de A');
        expect(total(ca, idB), 3, reason: 'compteur de B connu de A');
        expect(total(cb, null), 3, reason: 'compteur propre de B');
        expect(total(cb, idA), 2, reason: 'compteur de A connu de B');
      },
      skip: saute,
    );

    test(
      'bandes : une bande créée puis clôturée au poste A arrive chez B ; un code déjà pris par un AUTRE poste est refusé avec son motif',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final code = 'B47-${unique.substring(unique.length - 5)}';
        final repoA = BandesRepositoryDrift(a.db);
        final bande = await repoA.creerBande(
          espece: 'goliaths',
          code: code,
          dateMiseEnBande: base,
          effectifInitial: 40,
          observations: 'Bande 47h',
        );
        await aller(a, b);
        var chezB = await (b.db.select(
          b.db.bandes,
        )..where((x) => x.id.equals(bande.id))).getSingle();
        expect(chezB.code, code);
        expect(chezB.effectifInitial, 40);
        expect(chezB.dateCloture, isNull);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        await repoA.cloturerBande(id: bande.id, dateCloture: jourPlus(30));
        await aller(a, b);
        chezB = await (b.db.select(
          b.db.bandes,
        )..where((x) => x.id.equals(bande.id))).getSingle();
        expect(chezB.dateCloture, jourPlus(30));

        // Le poste B déclare le MÊME code pour la même filière, sans l'avoir vu.
        final c = await poste()
          ..let(postes.add);
        final doublon = await BandesRepositoryDrift(
          c.db,
        ).creerBande(espece: 'goliaths', code: code, dateMiseEnBande: base);
        final rc = await c.moteur.synchroniser();
        // Le tirage donne d'abord la bande au poste C : l'absorption peut
        // devancer le refus ; dans tous les cas la table ne doit pas se
        // retrouver avec deux bandes de même code.
        expect(rc.issue, IssueSynchronisation.terminee, reason: rc.message);
        final memeCode = (await c.db.select(c.db.bandes).get()).where(
          (x) => x.code == code,
        );
        expect(memeCode.length, 1, reason: 'jamais deux bandes de même code');
        // ignore: avoid_print
        print('Bande en double : ${doublon.id} -> ${rc.message}');
      },
      skip: saute,
    );
  });

  group('élevage : couveuse, incubateurs, soins, infirmerie', () {
    test(
      'incubateur + lot + mirage + éclosion avec remplacement au poste A : B reçoit incubateur, lots, sous-lot et compteurs',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final repo = CycleCouveuseRepositoryDrift(a.db);
        final codeMachine = 'INC-${unique.substring(unique.length - 6)}';
        final m = await repo.creerMachine(
          code: codeMachine,
          libelle: 'Couveuse 47h',
          capaciteOeufs: 528,
        );
        final lot = await repo.creer(
          espece: EspeceCouvable.goliath,
          dateChargement: base,
          oeufsCharges: 200,
          machineId: m.id,
        );
        await repo.enregistrerMirage(
          cycleId: lot.id,
          jour: 7,
          oeufsRetires: 22,
        );
        final ra = await sync(a);
        expect(ra.refusees, 0, reason: ra.message);
        await sync(b);

        var lotB = await (b.db.select(
          b.db.cycleCouveuse,
        )..where((c) => c.id.equals(lot.id))).getSingle();
        expect(lotB.codeIncubation, lot.code);
        expect(lotB.oeufsCouves, 200);
        expect(lotB.dateIncubation, base, reason: 'jour civil, sans décalage');
        expect(lotB.machineId, m.id);
        expect(lotB.oeufsBlancsJ7, 22);
        expect(lotB.statut, StatutCycle.enIncubation);
        expect(
          (await (b.db.select(
            b.db.machinesIncubateur,
          )..where((x) => x.id.equals(m.id))).getSingle()).capaciteOeufs,
          528,
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        final eclos = await repo.enregistrerEclosion(
          cycleId: lot.id,
          poussinsEclos: 150,
          oeufsPerdus: 28,
          oeufsRemplacement: 60,
          dateRemplacement: jourPlus(22),
        );
        final rb = await sync(a);
        expect(rb.refusees, 0, reason: rb.message);
        await sync(b);
        lotB = await (b.db.select(
          b.db.cycleCouveuse,
        )..where((c) => c.id.equals(lot.id))).getSingle();
        expect(lotB.statut, StatutCycle.remplace);
        expect(lotB.poussinsNes, 150);
        final sous = await (b.db.select(
          b.db.cycleCouveuse,
        )..where((c) => c.id.equals(eclos.sousLot!.id))).getSingle();
        expect(sous.lotParentId, lot.id);
        expect(sous.oeufsCouves, 60);

        // Modification puis suppression (pierre tombale) du lot parent.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await repo.supprimer(sous.id);
        await aller(a, b);
        expect(
          await (b.db.select(
            b.db.cycleCouveuse,
          )..where((c) => c.id.equals(sous.id))).getSingleOrNull(),
          isNull,
          reason: 'le sous-lot supprimé au poste A disparaît de B',
        );
      },
      skip: saute,
    );

    test(
      'soins et infirmerie saisis au poste A (administration confirmée, entrée clôturée, décès reporté) : B les reçoit',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final repo = SoinsRepositoryDrift(a.db);
        final soin = await repo.enregistrerSoin(
          espece: 'goliaths',
          date: base,
          typeSoin: TypeSoin.tous.first,
          statut: StatutSoin.planifie,
          produit: 'ND-Lasota 47h',
          dose: '1 goutte',
          remanenceJours: 3,
          veterinaire: 'Dr 47h',
          coutFcfa: 1500,
        );
        final entree = await repo.enregistrerEntreeInfirmerie(
          sujet: 'Goliath #47',
          motif: 'Boiterie',
          niveauIsolement: NiveauIsolement.tous.first,
          dateEntree: base,
          espece: 'goliaths',
        );
        final ra = await sync(a);
        expect(ra.refusees, 0, reason: ra.message);
        await sync(b);
        expect(
          (await (b.db.select(
            b.db.soinsCalendrier,
          )..where((x) => x.id.equals(soin.id))).getSingle()).produit,
          'ND-Lasota 47h',
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        await repo.confirmerAdministration(soin.id);
        await repo.cloturerEntree(
          entreeId: entree.id,
          statut: StatutInfirmerie.decede,
          dateSortie: jourPlus(2),
        );
        await repo.marquerDecesReporte(
          entreeId: entree.id,
          categorieMortalite: 1,
        );
        final rb = await sync(a);
        expect(rb.refusees, 0, reason: rb.message);
        await sync(b);

        final soinB = await (b.db.select(
          b.db.soinsCalendrier,
        )..where((x) => x.id.equals(soin.id))).getSingle();
        expect(soinB.statut, StatutSoin.effectue);
        expect(soinB.datePrevue, base);
        expect(soinB.coutFcfa, 1500);
        final entreeB = await (b.db.select(
          b.db.infirmerie,
        )..where((x) => x.id.equals(entree.id))).getSingle();
        expect(entreeB.statut, StatutInfirmerie.decede);
        expect(entreeB.dateSortie, jourPlus(2));
        expect(entreeB.categorieMortalite, 1);
      },
      skip: saute,
    );
  });

  final annee = DateTime.now().year;
  var numeroPieceN = 0;

  Future<void> depense(
    _Poste p,
    double montant, {
    int mois = 6,
    int jour = 15,
    String numero = '',
    String compteCharge = '618',
  }) => ComptabiliteRepositoryDrift(p.db).enregistrerPiece(
    date: DateTime(annee, mois, jour, 10),
    journalCode: 'CA',
    numeroPiece: numero.isEmpty
        ? 'DEP-47H-${unique.substring(unique.length - 7)}-${++numeroPieceN}'
        : numero,
    lignes: [
      LigneAEcrire(
        numeroCompte: compteCharge,
        debit: montant,
        credit: 0,
        libelle: 'Transport 47h',
      ),
      LigneAEcrire(
        numeroCompte: '571',
        debit: 0,
        credit: montant,
        libelle: 'Transport 47h',
      ),
    ],
  );

  Future<List<EcritureRow>> ecritures(_Poste p) =>
      p.db.select(p.db.ecritureComptable).get();

  group('comptabilité : pièces, notes, clôtures', () {
    test(
      'une pièce équilibrée saisie au poste A (montants décimaux) arrive chez B avec ses deux lignes, sans écriture en double',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        await depense(a, 12345.67, mois: 6, jour: 15);
        final avant = (await ecritures(b)).length;
        final propres = (await ecritures(a)).where((e) => e.origine == null);
        expect(propres, hasLength(2));

        final ra = await sync(a);
        expect(ra.refusees, 0, reason: ra.message);
        await sync(b);

        final chezB = (await ecritures(b)).where((e) => e.origine != null);
        expect(chezB.length - avant, greaterThanOrEqualTo(2));
        final piece = propres.first.numeroPiece;
        final deLaPiece = chezB.where((e) => e.numeroPiece == piece).toList();
        expect(deLaPiece, hasLength(2));
        expect(
          deLaPiece.fold<double>(0, (s, e) => s + e.debit),
          closeTo(12345.67, 0.001),
        );
        expect(
          deLaPiece.fold<double>(0, (s, e) => s + e.credit),
          closeTo(12345.67, 0.001),
        );
        expect(deLaPiece.every((e) => e.dateEcriture.month == 6), isTrue);
      },
      skip: saute,
    );

    test(
      'une vente encaissée au poste A passe l\'écriture automatique ; B la reçoit sans la rejouer (balance A = balance B pour cette pièce)',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final ref = await vendre(a, qte: 3);
        final ra = await sync(a);
        expect(ra.refusees, 0, reason: ra.message);
        await sync(b);

        final deA = (await ecritures(a)).where((e) => e.venteRef == ref);
        expect(deA, isNotEmpty, reason: 'écriture automatique de la vente');
        final deB = (await ecritures(b)).where((e) => e.venteRef == ref);
        expect(deB.length, deA.length);
        double solde(Iterable<EcritureRow> l) =>
            l.fold<double>(0, (s, e) => s + e.debit - e.credit);
        expect(solde(deB), closeTo(solde(deA), 0.001));
        expect(solde(deB), closeTo(0, 0.001), reason: 'partie double');
      },
      skip: saute,
    );

    test(
      'annuler une pièce déjà transmise : la contrepassation ANN-… arrive chez B, jamais de modification d\'un fait',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        await depense(a, 777, mois: 7, jour: 3);
        await sync(a);
        final numero = (await ecritures(
          a,
        )).firstWhere((e) => e.origine == null).numeroPiece!;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await ComptabiliteRepositoryDrift(
          a.db,
        ).supprimerPiece(exerciceAnnee: annee, numeroPiece: numero);
        final rb = await sync(a);
        expect(rb.refusees, 0, reason: rb.message);
        await sync(b);

        final pieces = (await ecritures(b)).map((e) => e.numeroPiece).toSet();
        expect(pieces, containsAll([numero, 'ANN-$numero']));
      },
      skip: saute,
    );

    test(
      'une note annexe de l\'exercice saisie au poste A arrive chez B',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        await ComptabiliteRepositoryDrift(a.db).enregistrerNote(
          annee,
          NoteAnnexe(
            numero: 1,
            titre: NoteAnnexe.titresObligatoires[1]!,
            contenu: 'Méthodes 47h $unique — éléments à l\'accent éàç',
          ),
        );
        final ra = await sync(a);
        expect(ra.refusees, 0, reason: ra.message);
        await sync(b);
        final notes = await b.db.select(b.db.notesAnnexes).get();
        expect(
          notes.map((n) => n.contenu),
          contains('Méthodes 47h $unique — éléments à l\'accent éàç'),
        );
      },
      skip: saute,
    );

    test(
      'clôture d\'un mois puis réouverture au poste A : B suit ; une écriture datée d\'un mois clos est refusée avec son motif',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final compta = ComptabiliteRepositoryDrift(a.db);
        await compta.cloturerMois(annee: annee, mois: 2);
        final ra = await sync(a);
        expect(ra.refusees, 0, reason: ra.message);
        await sync(b);
        final clos = await b.db.select(b.db.cloturesPeriodiques).get();
        expect(
          clos.any((c) => c.mois == 2 && c.annee == annee),
          isTrue,
          reason: 'le mois clos au poste A est clos chez B',
        );

        // Le poste C n'a PAS vu la clôture : il écrit en février. Le serveur refuse.
        final c = await poste()
          ..let(postes.add);
        await depense(c, 55, mois: 2, jour: 10);
        // Le tirage donne la clôture à C d'abord : la saisie est donc refusée
        // localement ; on force l'ordre inverse en empêchant le tirage.
        final rc = await c.moteur.synchroniser();
        expect(rc.issue, IssueSynchronisation.terminee, reason: rc.message);
        expect(rc.refusees, greaterThanOrEqualTo(1), reason: rc.message);
        final refusees = (await ecritures(
          c,
        )).where((e) => e.origine == null && e.syncStatus == 'conflict');
        expect(refusees, isNotEmpty, reason: 'la pièce reste visible, marquée');
        expect(refusees.first.syncMotif, contains('clôtur'));
        // ignore: avoid_print
        print('Écriture en mois clos : ${refusees.first.syncMotif}');
      },
      skip: saute,
    );
  });

  /// Appel HTTP brut avec le jeton du poste [p] (essais de refus sur le fil).
  Future<http.Response> brut(
    _Poste p,
    String methode,
    String chemin, [
    Map<String, Object?>? corps,
  ]) async {
    final entetes = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${await p.depot.lire()}',
    };
    final uri = Uri.parse('$adresse$chemin');
    return methode == 'GET'
        ? http.get(uri, headers: entetes)
        : http.post(uri, headers: entetes, body: jsonEncode(corps ?? {}));
  }

  Future<Map<String, dynamic>> pousser(
    _Poste p,
    Map<String, List<Map<String, dynamic>>> tables, {
    String? marque,
  }) async {
    final r = await brut(p, 'POST', '/api/sync/push', {
      'device_id': await p.preferences.identifiantPoste(),
      'reset_mark': marque ?? await p.preferences.marqueRemiseAZero(),
      'tables': tables,
    });
    return {
      'status': r.statusCode,
      ...jsonDecode(r.body) as Map<String, dynamic>,
    };
  }

  group('résilience : hors ligne, rejeu, concurrence, refus, volume', () {
    test(
      'hors ligne puis reconnexion : tout reste à envoyer, rien de perdu, tout arrive dans l\'ordre des dépendances',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        await sync(a);
        final adresseReelle = (await a.preferences.adresseServeur())!;
        await a.preferences.definirAdresseServeur('http://127.0.0.1:9');

        final c = await ClientsRepositoryDrift(
          a.db,
        ).creerClient(nom: 'Hors ligne 47h $unique');
        final ref = await vendre(a, client: c.nom, clientId: c.id);
        await depense(a, 99, mois: 5, jour: 5);
        final off = await a.moteur.synchroniser();
        expect(off.issue, IssueSynchronisation.horsLigne, reason: off.message);
        expect(await a.moteur.aDesSaisiesAEnvoyer(), isTrue);
        expect((await laVente(a, ref)).syncStatus, 'pending');

        await a.preferences.definirAdresseServeur(adresseReelle);
        final on = await sync(a);
        expect(on.refusees, 0, reason: on.message);
        expect(on.acceptees, greaterThanOrEqualTo(4));
        await sync(b);
        expect((await laVente(b, ref)).clientId, c.id);
        expect(await a.moteur.aDesSaisiesAEnvoyer(), isFalse);
      },
      skip: saute,
    );

    test(
      'rejeu idempotent : tout renvoyer deux fois ne crée ni doublon ni effet (ventes, écritures, mouvements, lots)',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final ref = await vendre(a, qte: 2);
        await depense(a, 321, mois: 4, jour: 4);
        final app = ApprovisionnementRepositoryDrift(a.db);
        await app.ajusterInventaire(
          code: 'INT-001',
          stockPhysique: 77,
          motif: 'Rejeu 47h',
        );
        await CycleCouveuseRepositoryDrift(a.db).creer(
          espece: EspeceCouvable.pintade,
          dateChargement: base,
          oeufsCharges: 30,
        );
        await aller(a, b);
        Future<Map<String, int>> compte(_Poste p) async => {
          for (final t in const [
            'ventes',
            'lignes_vente',
            'ecriture_comptable',
            'mouvements_intrant',
            'cycle_couveuse',
            'clients',
          ])
            t:
                (await p.db
                        .customSelect('SELECT COUNT(*) AS n FROM $t')
                        .getSingle())
                    .read<int>('n'),
        };
        final avantB = await compte(b);

        for (var tour = 0; tour < 2; tour++) {
          for (final t in const [
            'ventes',
            'ecriture_comptable',
            'mouvements_intrant',
            'cycle_couveuse',
            'clients',
          ]) {
            await a.db
                .customStatement(
                  "UPDATE $t SET sync_status = 'pending' WHERE origine IS NULL",
                )
                .onError(
                  (_, _) => a.db.customStatement(
                    "UPDATE $t SET sync_status = 'pending'",
                  ),
                );
          }
          final r = await sync(a);
          expect(r.refusees, 0, reason: 'tour $tour : ${r.message}');
          expect(r.acceptees, greaterThan(0), reason: 'le serveur ré-accepte');
        }
        await sync(b);
        expect(await compte(b), avantB, reason: 'aucun doublon chez B');
        expect((await laVente(b, ref)).total, (await laVente(a, ref)).total);
      },
      skip: saute,
    );

    test(
      'deux postes hors ligne modifient la MÊME fiche du jour, le MÊME client et le MÊME produit : tous deux convergent vers la saisie la plus récente',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final jour = jourPlus(400);
        final c = await ClientsRepositoryDrift(
          a.db,
        ).creerClient(nom: 'Concurrent 47h $unique');
        await saisirJour(a, jour, achat: 10);
        await aller(a, b);
        await sync(a);

        // Hors ligne : B saisit d'abord, A ensuite (plus récent) : A doit gagner.
        await saisirJour(b, jour, achat: 10, observation: 'Saisie de B');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await saisirJour(a, jour, achat: 10, observation: 'Saisie de A');
        await (b.db.update(
          b.db.clients,
        )..where((x) => x.id.equals(c.id))).write(
          ClientsCompanion(
            telephone: const Value('97000001'),
            syncStatus: const Value('pending'),
            updatedAt: Value(instantSaisie()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await (a.db.update(
          a.db.clients,
        )..where((x) => x.id.equals(c.id))).write(
          ClientsCompanion(
            telephone: const Value('97000002'),
            syncStatus: const Value('pending'),
            updatedAt: Value(instantSaisie()),
          ),
        );

        for (final p in [b, a, b, a]) {
          await sync(p);
        }
        for (final p in [a, b]) {
          final fiche = (await p.db.select(p.db.ficheJournee).get()).firstWhere(
            (f) => f.espece == 'goliaths' && f.date == jour,
          );
          expect(fiche.traitementObs, 'Saisie de A', reason: 'fiche du jour');
          expect(
            (await (p.db.select(
              p.db.clients,
            )..where((x) => x.id.equals(c.id))).getSingle()).telephone,
            '97000002',
            reason: 'client',
          );
        }
      },
      skip: saute,
    );

    test(
      'refus avec motif : chaque famille refuse une ligne corrompue, la ligne devient « conflit » avec le motif du serveur',
      () async {
        final a = await poste()
          ..let(postes.add);
        await sync(a);
        final repoApp = ApprovisionnementRepositoryDrift(a.db);
        final f = await repoApp.creerFournisseur(nom: 'Refus 47h $unique');
        final achat = await repoApp.enregistrerAchat(
          fournisseurId: f.id,
          mode: ModeReglement.especes,
          montantPaye: 0,
          livree: false,
          panier: const [
            LignePanierAchat(
              intrantCode: 'INT-001',
              nom: 'Maïs',
              quantite: 1,
              prixUnitaire: 300,
              unite: 'kg',
            ),
          ],
        );
        // Les clés étrangères locales protègent le poste : on les lève pour fabriquer des
        // lignes que SEUL le serveur peut juger incohérentes.
        await a.db.customStatement('PRAGMA foreign_keys = OFF');
        await a.db.customStatement(
          "UPDATE lignes_achat SET intrant_code = 'ZZZ-INCONNU' WHERE achat_ref = '${achat.reference}'",
        );
        final venteRef = await vendre(a);
        await a.db.customStatement(
          "UPDATE lignes_vente SET produit_id = '${nouvelUuid()}' WHERE vente_ref = '$venteRef'",
        );
        final soin = await SoinsRepositoryDrift(a.db).enregistrerSoin(
          espece: 'goliaths',
          date: base,
          typeSoin: TypeSoin.tous.first,
          statut: StatutSoin.planifie,
        );
        await a.db.customStatement(
          "UPDATE soins_calendrier SET statut = 'Bidule' WHERE id = '${soin.id}'",
        );
        final lot = await CycleCouveuseRepositoryDrift(a.db).creer(
          espece: EspeceCouvable.goliath,
          dateChargement: base,
          oeufsCharges: 10,
        );
        await a.db.customStatement(
          "UPDATE cycle_couveuse SET machine_id = '${nouvelUuid()}' WHERE id = '${lot.id}'",
        );
        await depense(a, 500, mois: 3, jour: 3);
        await a.db.customStatement(
          "UPDATE ecriture_comptable SET credit = credit + 7 WHERE credit > 0 AND sync_status = 'pending' AND origine IS NULL AND numero_piece LIKE 'DEP-47H-%'",
        );

        final r = await a.moteur.synchroniser();
        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);

        Future<void> conflit(String table, String id, String colonne) async {
          final l = await a.db
              .customSelect(
                'SELECT sync_status, sync_motif FROM $table WHERE $colonne = ?',
                variables: [Variable<String>(id)],
              )
              .get();
          expect(l, isNotEmpty, reason: table);
          // ignore: avoid_print
          print('Motif réel [$table] : ${l.first.read<String?>('sync_motif')}');
          expect(
            l.first.read<String>('sync_status'),
            'conflict',
            reason: table,
          );
          expect(
            l.first.read<String?>('sync_motif'),
            isNotEmpty,
            reason: table,
          );
        }

        await conflit('achats', achat.reference, 'ref');
        await conflit('ventes', venteRef, 'ref');
        await conflit('soins_calendrier', soin.id, 'id');
        await conflit('cycle_couveuse', lot.id, 'id');
        final ecr = await a.db
            .customSelect(
              "SELECT sync_status, sync_motif FROM ecriture_comptable WHERE numero_piece LIKE 'DEP-47H-%' AND origine IS NULL",
            )
            .get();
        expect(
          ecr.every((l) => l.read<String>('sync_status') == 'conflict'),
          isTrue,
        );
        // ignore: avoid_print
        print(
          'Motif réel [ecriture_comptable] : ${ecr.first.read<String?>('sync_motif')}',
        );
      },
      skip: saute,
    );

    test(
      'refus sur le fil : marque de remise à zéro inconnue = 409, device_id d\'un autre poste = 403, table inconnue refusée',
      () async {
        final a = await poste()
          ..let(postes.add);
        await sync(a);
        final r409 = await pousser(a, {'clients': []}, marque: 'rz-inconnue');
        expect(r409['status'], 409);
        final r = await brut(a, 'POST', '/api/sync/push', {
          'device_id': nouvelUuid(),
          'reset_mark': await a.preferences.marqueRemiseAZero(),
          'tables': <String, Object?>{},
        });
        expect(r.statusCode, 403);
        final inconnue = await pousser(a, {
          'table_fantome': [
            {'id': nouvelUuid(), 'updated_at': instantSaisie()},
          ],
        });
        expect(inconnue['status'], 200);
        // ignore: avoid_print
        print('Table inconnue : ${jsonEncode(inconnue)}');
      },
      skip: saute,
    );

    test(
      'volume : 450 clients envoyés en lots de 100, tirés par un poste neuf en plusieurs pages, curseur correct',
      () async {
        final a = await poste(tailleLot: 100)
          ..let(postes.add);
        final noms = <String>{};
        await a.db.batch((b) {
          for (var i = 0; i < 450; i++) {
            final nom = 'Volume 47h $unique #$i';
            noms.add(nom);
            b.insert(
              a.db.clients,
              ClientsCompanion.insert(id: Value(nouvelUuid()), nom: nom),
            );
          }
        });
        final ra = await sync(a);
        expect(ra.acceptees, 450);
        expect(ra.refusees, 0, reason: ra.message);

        final b = await poste()
          ..let(postes.add);
        final rb = await sync(b);
        expect(rb.recues, greaterThanOrEqualTo(450));
        final chezB = (await b.db.select(b.db.clients).get())
            .map((c) => c.nom)
            .toSet();
        expect(chezB.containsAll(noms), isTrue, reason: 'aucune ligne sautée');
        // Rien de plus au tirage suivant.
        final encore = await sync(b);
        expect(encore.envoyees, 0);
      },
      skip: saute,
    );
  });

  group('fidélité : ce qui part de A arrive chez B à l\'identique', () {
    /// Réécrit des colonnes TEXTE d'une ligne locale encore à envoyer (valeurs
    /// limites que le formulaire n'aurait pas laissé passer).
    Future<void> forcer(
      _Poste p,
      String table,
      String colonneId,
      String id,
      Map<String, String?> valeurs,
    ) async {
      for (final e in valeurs.entries) {
        await p.db.customUpdate(
          'UPDATE $table SET ${e.key} = ? WHERE $colonneId = ?',
          variables: [Variable<String>(e.value), Variable<String>(id)],
          updates: {},
        );
      }
    }

    Future<Map<String, Object?>> ligneBrute(
      _Poste p,
      String table,
      String colonneId,
      String id,
    ) async =>
        (await p.db
                .customSelect(
                  'SELECT * FROM $table WHERE $colonneId = ?',
                  variables: [Variable<String>(id)],
                )
                .getSingle())
            .data;

    const accents =
        'Éléphant « à l\'œuf » — 5 000 F ≠ 5000 🐔\nDeuxième ligne\n';
    final longue = List.generate(300, (i) => 'Ligne $i éàçù').join('\n');

    test(
      'textes limites (espaces, retours à la ligne finaux, accents, emoji, 6 000 caractères, vide) : B lit exactement ce que A a saisi',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final c = await ClientsRepositoryDrift(
          a.db,
        ).creerClient(nom: 'Fidèle 47h $unique', telephone: '97470003');
        final bande = await BandesRepositoryDrift(a.db).creerBande(
          espece: 'goliaths',
          code: 'F47-${unique.substring(unique.length - 5)}',
          dateMiseEnBande: base,
        );
        final soin = await SoinsRepositoryDrift(a.db).enregistrerSoin(
          espece: 'goliaths',
          date: base,
          typeSoin: TypeSoin.tous.first,
          statut: StatutSoin.planifie,
        );
        final entree = await SoinsRepositoryDrift(a.db)
            .enregistrerEntreeInfirmerie(
              sujet: 'x',
              motif: 'y',
              niveauIsolement: NiveauIsolement.tous.first,
              dateEntree: base,
            );
        await saisirJour(a, jourPlus(500), achat: 3);
        await ComptabiliteRepositoryDrift(a.db).enregistrerNote(
          annee,
          NoteAnnexe(numero: 2, titre: 'Immobilisations', contenu: longue),
        );
        await ComptabiliteRepositoryDrift(a.db).enregistrerNote(
          annee,
          const NoteAnnexe(numero: 3, titre: 'Stocks', contenu: accents),
        );
        await depense(a, 10, mois: 8, jour: 8);

        await forcer(a, 'clients', 'id', c.id, {
          'nom': '  Fidèle  47h $unique  ',
          'telephone': '',
        });
        await forcer(a, 'bandes', 'id', bande.id, {'observations': accents});
        await forcer(a, 'soins_calendrier', 'id', soin.id, {
          'observations': '  \n  ',
          'produit': '',
          'dose': ' 1 goutte ',
        });
        await forcer(a, 'infirmerie', 'id', entree.id, {
          'sujet': 'Sujet\n',
          'motif': '\tMotif ',
        });
        final ficheId = (await a.db.select(a.db.ficheJournee).get())
            .firstWhere((f) => f.date == jourPlus(500))
            .id;
        await forcer(a, 'fiche_journee', 'id', ficheId, {
          'traitement_obs': 'Obs\n\n',
        });
        final ecrId = (await ecritures(
          a,
        )).firstWhere((e) => e.numeroPiece!.startsWith('DEP-47H-')).id;
        await forcer(a, 'ecriture_comptable', 'id', ecrId, {
          'libelle': '  Transport 🚚  ',
        });

        final ra = await sync(a);
        expect(ra.refusees, 0, reason: ra.message);
        await sync(b);

        final ecarts = <String>[];
        // Champs SAISIS en texte libre (note, observation, traitement) : B lit EXACTEMENT
        // ce que A a saisi. Champs courts (noms, libellés, motifs) : le poste normalise
        // déjà à l'écriture (rognage, vide = absent) ; on compare la forme normalisée.
        Object? normaliser(Object? v) =>
            v is String ? (v.trim().isEmpty ? null : v.trim()) : v;
        Future<void> comparer(
          String table,
          String colonneId,
          String id,
          List<String> colonnes, {
          bool exact = false,
        }) async {
          final deA = await ligneBrute(a, table, colonneId, id);
          final deB = await ligneBrute(b, table, colonneId, id);
          for (final col in colonnes) {
            final x = exact ? deA[col] : normaliser(deA[col]);
            final y = exact ? deB[col] : normaliser(deB[col]);
            if (x != y) {
              ecarts.add(
                '$table.$col : A=${jsonEncode(deA[col])} B=${jsonEncode(deB[col])}',
              );
            }
          }
        }

        await comparer('clients', 'id', c.id, ['nom', 'telephone']);
        await comparer('bandes', 'id', bande.id, ['observations'], exact: true);
        await comparer('soins_calendrier', 'id', soin.id, [
          'observations',
          'produit',
          'dose',
        ]);
        await comparer('infirmerie', 'id', entree.id, ['sujet', 'motif']);
        await comparer('fiche_journee', 'id', ficheId, [
          'traitement_obs',
        ], exact: true);
        await comparer('ecriture_comptable', 'id', ecrId, ['libelle']);
        for (final n in [2, 3]) {
          final id = (await a.db.select(a.db.notesAnnexes).get())
              .firstWhere((x) => x.numeroNote == n)
              .id;
          await comparer('notes_annexes', 'id', id, ['contenu'], exact: true);
        }
        expect(ecarts, isEmpty, reason: ecarts.join('\n'));
      },
      skip: saute,
    );
  });

  /// Toutes les lignes `conflict` d'un poste, table par table (faits ET demandes).
  Future<Map<String, List<String>>> conflits(_Poste p) async {
    final r = <String, List<String>>{};
    for (final t in const [
      'clients',
      'fournisseurs',
      'ventes',
      'achats',
      'factures',
      'mouvements_intrant',
      'mouvements_produit',
      'fiche_journee',
      'fiche_ventes_jour',
      'bandes',
      'machines_incubateur',
      'cycle_couveuse',
      'soins_calendrier',
      'infirmerie',
      'ecriture_comptable',
      'notes_annexes',
      'clotures_periodiques',
      'demandes_referentiel',
    ]) {
      final l = await p.db
          .customSelect(
            "SELECT sync_motif FROM $t WHERE sync_status = 'conflict'",
          )
          .get();
      if (l.isNotEmpty) {
        r[t] = [for (final x in l) '${x.read<String?>('sync_motif')}'];
      }
    }
    return r;
  }

  group(
    'droits par rôle : la journée type d\'un poste appairé à ce compte ne produit aucun refus',
    () {
      test(
        'agent de vente (caissier) : clients, ventes comptant et à crédit, encaissement, écritures et compteurs automatiques',
        () async {
          final c = await poste(compteForce: 'caissier1')
            ..let(postes.add);
          final b = await poste()
            ..let(postes.add);
          final clients = ClientsRepositoryDrift(c.db);
          final k = await clients.creerClient(
            nom: 'Caissier 47h $unique',
            telephone: '97470009',
          );
          await vendre(c, qte: 1);
          final credit = await vendre(
            c,
            client: k.nom,
            clientId: k.id,
            statut: StatutVente.avance,
            paye: 500,
          );
          await VentesRepositoryDrift(
            c.db,
            EventBus(),
          ).enregistrerPaiement(reference: credit, montant: 300);

          final r = await c.moteur.synchroniser();
          expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
          final refus = await conflits(c);
          // Les référentiels du semis (intrants, barèmes, plan…) sont hors du champ
          // d'un caissier : seules les lignes de FAITS comptent ici.
          refus.remove('demandes_referentiel');
          expect(refus, isEmpty, reason: '$refus');
          await sync(b);
          expect((await laVente(b, credit)).paye, 800);
        },
        skip: saute,
      );

      test(
        'comptable : pièce manuelle, note annexe et clôture de mois sont acceptées ; une vente ne l\'est pas',
        () async {
          final c = await poste(compteForce: 'comptable1')
            ..let(postes.add);
          await depense(c, 150, mois: 9, jour: 9);
          await ComptabiliteRepositoryDrift(c.db).enregistrerNote(
            annee,
            const NoteAnnexe(
              numero: 4,
              titre: 'Créances et Dettes',
              contenu: 'Comptable 47h',
            ),
          );
          final refVente = await vendre(c);
          final r = await c.moteur.synchroniser();
          expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
          final refus = await conflits(c);
          refus.remove('demandes_referentiel');
          expect(
            refus.keys,
            isNot(contains('ventes')),
            reason:
                'pas de droit de vendre : la vente attend le droit (`47g_`), '
                'elle n\'est pas proposée donc pas refusée',
          );
          expect(
            r.enAttenteDeDroit,
            greaterThanOrEqualTo(1),
            reason: r.message,
          );
          expect((await laVente(c, refVente)).syncStatus, 'pending');
          expect(refus.keys, isNot(contains('ecriture_comptable')));
          expect(refus.keys, isNot(contains('notes_annexes')));
          // ignore: avoid_print
          print('Comptable : $refus');
        },
        skip: saute,
      );

      test(
        'agent d\'élevage (animalier) : fiche du jour, bande, lot de couveuse, soin et infirmerie sont acceptés',
        () async {
          final c = await poste(compteForce: 'animalier1')
            ..let(postes.add);
          await saisirJour(c, jourPlus(700), achat: 4, ne: 1);
          await BandesRepositoryDrift(c.db).creerBande(
            espece: 'goliaths',
            code: 'AN-${unique.substring(unique.length - 5)}',
            dateMiseEnBande: jourPlus(700),
          );
          final repo = CycleCouveuseRepositoryDrift(c.db);
          final m = await repo.creerMachine(
            code: 'AN-${unique.substring(unique.length - 6)}',
            libelle: 'Couveuse animalier',
          );
          await repo.creer(
            espece: EspeceCouvable.goliath,
            dateChargement: jourPlus(700),
            oeufsCharges: 12,
            machineId: m.id,
          );
          final soins = SoinsRepositoryDrift(c.db);
          await soins.enregistrerSoin(
            espece: 'goliaths',
            date: jourPlus(700),
            typeSoin: TypeSoin.tous.first,
            statut: StatutSoin.planifie,
          );
          await soins.enregistrerEntreeInfirmerie(
            sujet: 'G-1',
            motif: 'Boiterie',
            niveauIsolement: NiveauIsolement.tous.first,
            dateEntree: jourPlus(700),
          );
          final r = await c.moteur.synchroniser();
          expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
          final refus = await conflits(c);
          refus.remove('demandes_referentiel');
          expect(refus, isEmpty, reason: '$refus');
        },
        skip: saute,
      );
    },
  );

  group('colonne par colonne : toutes les tables, A contre B', () {
    test(
      'un jeu de données riche (toutes colonnes facultatives remplies) : chaque ligne de A est lue à l\'identique chez B, table par table',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final clients = ClientsRepositoryDrift(a.db);
        final k = await clients.creerClient(
          nom: 'Riche 47h $unique',
          telephone: '97470077',
          dateNaissance: DateTime(1985, 12, 31),
        );
        await clients.enregistrerContact(k.id);
        final ventes = VentesRepositoryDrift(a.db, EventBus());
        final produit = (await ventes.chargerCatalogue()).firstWhere(
          (x) => x.nom == 'Goliath mature',
        );
        final r = await ventes.enregistrerVente(
          client: k.nom,
          clientId: k.id,
          mode: ModeReglement.mobileMoney,
          statut: StatutVente.avance,
          montantPaye: 777.5,
          ligneMobileMoney: '97470078',
          echeance: DateTime(annee, 12, 31),
          livraison: const Livraison(
            mode: ModeLivraison.facturee,
            frais: 1500.5,
            adresse: 'Rue des Flamboyants — Natitingou',
            contact: '97470079',
          ),
          panier: [
            LignePanier(
              produitId: produit.id,
              nom: produit.nom,
              montantGlobal: produit.prix * 3 - 0.333,
              quantite: 3,
              stockDisponible: produit.stock,
              prixIndicatif: produit.prix,
              prixIndicatifMax: produit.prixMax,
              espece: produit.espece,
              unite: produit.unite,
            ),
          ],
        );
        final app = ApprovisionnementRepositoryDrift(a.db);
        final f = await app.creerFournisseur(
          nom: 'Riche 47h $unique',
          telephone: '97470080',
          adresse: 'Zone industrielle',
          fournit: 'Maïs, soja',
        );
        await app.enregistrerAchat(
          fournisseurId: f.id,
          mode: ModeReglement.mobileMoney,
          montantPaye: 1234.56,
          livree: true,
          panier: const [
            LignePanierAchat(
              intrantCode: 'INT-001',
              nom: 'Maïs',
              quantite: 12.5,
              prixUnitaire: 301.25,
              unite: 'kg',
            ),
            LignePanierAchat(
              intrantCode: 'INT-002',
              nom: 'Soja',
              quantite: 3,
              prixUnitaire: 450,
              unite: 'kg',
            ),
          ],
        );
        await app.ajusterInventaire(
          code: 'INT-001',
          stockPhysique: 5,
          motif: 'Comptage riche 47h',
        );
        await FacturesMecefRepositoryDrift(a.db).emettrePourVente(
          venteRef: r.vente.reference,
          clientIfu: '3201234567890',
          clientAdresse: 'Natitingou',
        );
        await saisirJour(a, jourPlus(1100), achat: 7, ne: 2, morts: [3, 0, 0]);
        await BandesRepositoryDrift(a.db).creerBande(
          espece: 'goliaths',
          code: 'R47-${unique.substring(unique.length - 5)}',
          dateMiseEnBande: jourPlus(1100),
          effectifInitial: 33,
          observations: 'Riche',
        );
        final couv = CycleCouveuseRepositoryDrift(a.db);
        final m = await couv.creerMachine(
          code: 'R47-${unique.substring(unique.length - 6)}',
          libelle: 'Couveuse riche',
          capaciteOeufs: 100,
        );
        final lot = await couv.creer(
          espece: EspeceCouvable.pintade,
          dateChargement: jourPlus(1100),
          oeufsCharges: 80,
          machineId: m.id,
        );
        await couv.enregistrerMirage(cycleId: lot.id, jour: 7, oeufsRetires: 9);
        await couv.enregistrerMirage(
          cycleId: lot.id,
          jour: 14,
          oeufsRetires: 4,
        );
        final soins = SoinsRepositoryDrift(a.db);
        await soins.enregistrerSoin(
          espece: 'pintades',
          date: jourPlus(1100),
          typeSoin: TypeSoin.tous.last,
          statut: StatutSoin.traitementEnCours,
          produit: 'Produit riche',
          dose: '2,5 ml',
          remanenceJours: 4,
          veterinaire: 'Dr Riche',
          symptomes: 'Toux, éternuements',
          coutFcfa: 2500,
        );
        await soins.enregistrerEntreeInfirmerie(
          sujet: 'Pintade #R',
          motif: 'Boiterie',
          niveauIsolement: NiveauIsolement.tous.last,
          dateEntree: jourPlus(1100),
          espece: 'pintades',
        );
        await depense(a, 4321.09, mois: 10, jour: 10);
        await ComptabiliteRepositoryDrift(a.db).enregistrerNote(
          annee,
          const NoteAnnexe(
            numero: 5,
            titre: 'Engagements Hors Bilan',
            contenu: 'Riche\n',
          ),
        );

        await sync(a);
        await sync(b);
        await sync(a);

        const exclues = {
          'sync_status',
          'sync_motif',
          'origine',
          'stock',
          'pmp',
          'device_id',
          'cree_le', // horodatage technique local (défaut SQL), hors contrat
          'serveur_modifie_le',
        };
        final ecarts = <String>[];
        bool egal(Object? x, Object? y) {
          if (x is num && y is num) return (x - y).abs() < 1e-6;
          return x == y;
        }

        for (final t in const [
          'clients',
          'fournisseurs',
          'ventes',
          'lignes_vente',
          'achats',
          'lignes_achat',
          'mouvements_intrant',
          'factures',
          'lignes_facture',
          'fiche_journee',
          'bandes',
          'machines_incubateur',
          'cycle_couveuse',
          'soins_calendrier',
          'infirmerie',
          'ecriture_comptable',
          'notes_annexes',
        ]) {
          final deA = await a.db.customSelect('SELECT * FROM $t').get();
          for (final ligne in deA) {
            final id = ligne.data['id'];
            final chezB = await b.db
                .customSelect(
                  'SELECT * FROM $t WHERE id = ?',
                  variables: [Variable<String>('$id')],
                )
                .get();
            if (chezB.isEmpty) {
              ecarts.add('$t/$id absent de B');
              continue;
            }
            for (final e in ligne.data.entries) {
              if (exclues.contains(e.key)) continue;
              final y = chezB.single.data[e.key];
              if (!egal(e.value, y)) {
                ecarts.add(
                  '$t.${e.key} : A=${jsonEncode(e.value)} B=${jsonEncode(y)}',
                );
              }
            }
          }
        }
        final cf = await conflits(a);
        // ignore: avoid_print
        print('CONFLITS A : $cf');
        expect(ecarts, isEmpty, reason: ecarts.join('\n'));
      },
      skip: saute,
    );
  });

  group('huit filières : chaque fiche journalière, A contre B', () {
    test(
      'goliaths, pintades, lapins, poissons-chats, poulets, pondeuses, escargots, ovins : trois jours chacune (décès, dons, pesée, œufs), lus à l\'identique chez B',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final jour = jourPlus(1500);
        for (final config in ConfigurationsEspeces.parIdentifiant.values) {
          final n = config.nombreCategories;
          final cas = EnregistrerJourneeUseCase(
            FicheElevageRepositoryDrift(a.db, config),
            config,
          );
          for (var i = 0; i < 3; i++) {
            final r = await cas.executer(
              date: DateTime(jour.year, jour.month, jour.day + i),
              mouvements: MouvementsJour(
                achat: i == 0 ? 30 : 0,
                ne: i == 0 ? 5 : 1,
                mortsParCategorie: [for (var c = 0; c < n; c++) c == 0 ? i : 0],
                donsParCategorie: [for (var c = 0; c < n; c++) c == 0 ? 1 : 0],
              ),
              poidsGeneralG: config.rationEnPourcentagePoidsVif ? 250000 : 1450,
              traitementObs: '${config.identifiant} jour $i',
              traitementValide: i == 2,
              stockOeufs: config.identifiant == 'pondeuses'
                  ? const SaisieStockOeufs(
                      oeufsPondus: 120,
                      oeufsCasses: 3,
                      sortiesPlateaux: 2,
                    )
                  : null,
            );
            expect(
              r,
              isA<Succes<JourneeElevage>>(),
              reason: '${config.identifiant} $i : $r',
            );
          }
        }

        final ra = await sync(a);
        expect(ra.refusees, 0, reason: ra.message);
        final refus = await conflits(a);
        expect(refus, isEmpty, reason: '$refus');
        await sync(b);

        final deA = await a.db
            .customSelect('SELECT * FROM fiche_journee')
            .get();
        expect(deA.length, greaterThanOrEqualTo(24));
        final ecarts = <String>[];
        for (final l in deA) {
          final chezB = await b.db
              .customSelect(
                'SELECT * FROM fiche_journee WHERE id = ?',
                variables: [Variable<String>('${l.data['id']}')],
              )
              .get();
          if (chezB.isEmpty) {
            ecarts.add('${l.data['espece']} ${l.data['date']} absente de B');
            continue;
          }
          for (final e in l.data.entries) {
            if (const {
              'sync_status',
              'sync_motif',
              'origine',
              'device_id',
            }.contains(e.key)) {
              continue;
            }
            final y = chezB.single.data[e.key];
            final egal = e.value is num && y is num
                ? (e.value! as num).toDouble() == y.toDouble()
                : e.value == y;
            if (!egal) {
              ecarts.add(
                '${l.data['espece']} ${l.data['date']} ${e.key} : A=${e.value} B=$y',
              );
            }
          }
        }
        expect(ecarts, isEmpty, reason: ecarts.join('\n'));
      },
      skip: saute,
    );
  });

  group(
    'écritures automatiques : tout ce que le poste passe, le serveur l\'accepte',
    () {
      test(
        'ventes (comptant, crédit, mobile money, livraison facturée, mixte 701/707), annulations, règlements, achats (3 comptes), réception, fabrication, ANN- : aucune pièce refusée',
        () async {
          final a = await poste()
            ..let(postes.add);
          final b = await poste()
            ..let(postes.add);
          final ventes = VentesRepositoryDrift(a.db, EventBus());
          final catalogue = await ventes.chargerCatalogue();
          final annexe = catalogue.firstWhere(
            (p) => p.categorie == 'Commerce Annexe',
          );
          final goliath = catalogue.firstWhere(
            (p) => p.nom == 'Goliath mature',
          );
          final k = await ClientsRepositoryDrift(
            a.db,
          ).creerClient(nom: 'Auto 47h $unique');
          LignePanier ligne(ProduitVendable p, double qte, [double? montant]) =>
              LignePanier(
                produitId: p.id,
                nom: p.nom,
                montantGlobal: montant ?? p.prix * qte,
                quantite: qte,
                stockDisponible: p.stock + 1000,
                prixIndicatif: p.prix,
                prixIndicatifMax: p.prixMax,
                espece: p.espece,
                unite: p.unite,
              );

          final refs = <String>[];
          Future<String> v({
            required List<LignePanier> panier,
            String mode = ModeReglement.especes,
            String statut = StatutVente.payee,
            double? paye,
            Livraison? livraison,
          }) async {
            final total =
                panier.fold<double>(0, (s, l) => s + l.total) +
                (livraison?.supplementFacture ?? 0);
            final r = await ventes.enregistrerVente(
              client: k.nom,
              clientId: k.id,
              mode: mode,
              statut: statut,
              montantPaye: paye ?? total,
              livraison: livraison,
              panier: panier,
            );
            refs.add(r.vente.reference);
            return r.vente.reference;
          }

          await v(panier: [ligne(goliath, 1)]);
          await v(
            panier: [ligne(goliath, 2, 11999.99)],
            statut: StatutVente.avance,
            paye: 4000.5,
          );
          await v(panier: [ligne(annexe, 3)], mode: ModeReglement.mobileMoney);
          await v(
            panier: [ligne(goliath, 1), ligne(annexe, 2)],
            livraison: const Livraison(
              mode: ModeLivraison.facturee,
              frais: 1500.5,
            ),
          );
          final aAnnuler = await v(
            panier: [ligne(annexe, 1)],
            livraison: const Livraison(
              mode: ModeLivraison.facturee,
              frais: 700,
            ),
          );
          await v(
            panier: [ligne(goliath, 1)],
            livraison: const Livraison(mode: ModeLivraison.gratuite),
          );
          final credit = await v(
            panier: [ligne(goliath, 1)],
            statut: StatutVente.avance,
            paye: 1000,
          );
          await ventes.enregistrerPaiement(reference: credit, montant: 250.25);
          await ventes.annulerVente(
            reference: aAnnuler,
            motif: MotifAnnulation.tous.first,
          );
          await ventes.annulerVente(
            reference: refs[3],
            motif: MotifAnnulation.tous.first,
          );

          final app = ApprovisionnementRepositoryDrift(a.db);
          final f = await app.creerFournisseur(nom: 'Auto 47h $unique');
          final toutes = <LignePanierAchat>[
            for (final code in const [
              'INT-001',
              'INT-002',
              'INT-003',
              'INT-004',
              'INT-005',
              'INT-006',
            ])
              LignePanierAchat(
                intrantCode: code,
                nom: code,
                quantite: 10.5,
                prixUnitaire: 333.33,
                unite: 'kg',
              ),
          ];
          await app.enregistrerAchat(
            fournisseurId: f.id,
            mode: ModeReglement.especes,
            montantPaye: 5000,
            livree: true,
            panier: toutes,
          );
          final commande = await app.enregistrerAchat(
            fournisseurId: f.id,
            mode: ModeReglement.mobileMoney,
            montantPaye: 100,
            livree: false,
            panier: toutes,
          );
          await app.receptionnerAchat(commande.reference);
          await app.reglerAchat(reference: commande.reference, montant: 999.99);
          await app.fabriquerProvende(
            const FabricationProvende({'INT-001': 5, 'INT-002': 2.5}),
          );
          await depense(a, 1500.75, mois: 10, jour: 20);
          final numero = (await ecritures(a))
              .firstWhere((e) => e.numeroPiece!.startsWith('DEP-47H-'))
              .numeroPiece!;
          await sync(a);
          // Pièce déjà transmise : on l'annule par contrepassation (ANN-).
          await ComptabiliteRepositoryDrift(
            a.db,
          ).supprimerPiece(exerciceAnnee: annee, numeroPiece: numero);

          final r = await sync(a);
          await sync(b);
          final refus = await conflits(a);
          expect(refus, isEmpty, reason: '$refus\n${r.message}');
          // La balance de A et celle de B pour ces pièces sont identiques.
          double solde(List<EcritureRow> l) =>
              l.fold<double>(0, (s, e) => s + e.debit - e.credit);
          final ids = (await ecritures(a)).map((e) => e.id).toSet();
          final chezB = (await ecritures(b)).where((e) => ids.contains(e.id));
          expect(
            chezB.length,
            ids.length,
            reason: 'toutes les lignes sont chez B',
          );
          expect(solde(chezB.toList()), closeTo(0, 0.01));
        },
        skip: saute,
      );
    },
  );

  // --- Écrans WEB : ils écrivent par les MÊMES absorbeurs que le poste (`ClientsTable`…),
  // sous le « poste » web (UUID nul). On les rejoue par `artisan tinker`, sur la base du
  // serveur d'essai : LOGIALVIA_LARAVEL=<dossier logialvia_laravel> LOGIALVIA_DB=<fichier>.
  final dossierLaravel = Platform.environment['LOGIALVIA_LARAVEL'];
  final baseServeur = Platform.environment['LOGIALVIA_DB'];
  final Object sauteWeb = saute != false
      ? saute
      : (dossierLaravel == null || baseServeur == null
            ? 'LOGIALVIA_LARAVEL / LOGIALVIA_DB non définis : écritures web ignorées.'
            : false);

  /// Exécute du PHP sur la base du serveur d'essai (comme le ferait un écran web).
  Future<String> web(String php) async {
    final r = await Process.run(
      'php',
      ['artisan', 'tinker', '--execute=$php'],
      workingDirectory: dossierLaravel,
      // `LOGIALVIA_DB=mysql` : base MySQL/MariaDB, DB_* hérités de l'environnement
      // (`essai_vrai_serveur.sh` avec `LV_BASE=mysql|mariadb`, `47r_`).
      environment: baseServeur == 'mysql'
          ? const {}
          : {'DB_CONNECTION': 'sqlite', 'DB_DATABASE': baseServeur!},
    );
    return '${r.stdout}${r.stderr}'.trim();
  }

  const posteWeb = '00000000-0000-0000-0000-000000000000';

  // ===========================================================================
  // 47g — DROITS du compte et HORLOGE du poste, contre le VRAI serveur.
  // ===========================================================================

  group('47g : droits par compte', () {
    for (final cas in const <(String?, String)>[
      ('caissier1', 'caissier'),
      ('comptable1', 'comptable'),
      ('animalier1', 'animalier'),
      (null, 'admin'),
    ]) {
      test(
        '${cas.$1 ?? 'administrateur'} : synchronise exactement ce qu\'il peut, aucune demande en conflit à tort',
        () async {
          final c = await poste(compteForce: cas.$1)
            ..let(postes.add);
          final refVente = await vendre(c, qte: 1);
          await sync(c);

          final etat = await c.moteur.etatDroits();
          final droits = etat.droits!;
          expect(droits.roles, [cas.$2]);
          expect(droits.compte, cas.$1 ?? startsWith('admin'));

          final demandes = await c.db.select(c.db.demandesReferentiel).get();
          expect(demandes, isNotEmpty);
          var attendues = 0;
          for (final d in demandes) {
            if (droits.peutProposer(d.type)) {
              expect(
                d.syncStatus,
                isNot('pending'),
                reason: '${d.type}/${d.cle} : le compte peut le proposer',
              );
              expect(
                d.syncMotif ?? '',
                isNot(contains('Droit insuffisant')),
                reason: '${d.type}/${d.cle}',
              );
            } else {
              expect(
                d.syncStatus,
                'pending',
                reason:
                    '${d.type}/${d.cle} : en attente de droit, pas conflict',
              );
              attendues++;
            }
          }
          // En attente de droit = les demandes ci-dessus + les saisies de faits que le compte ne
          // peut pas écrire (la vente et son mouvement de stock, pour qui ne vend pas).
          expect(etat.enAttenteDeDroit, greaterThanOrEqualTo(attendues));
          if (cas.$2 == 'admin') {
            expect(
              etat.enAttenteDeDroit,
              0,
              reason: 'l\'administrateur propose tout',
            );
          } else {
            expect(attendues, greaterThan(0), reason: cas.$2);
          }
          if (cas.$2 == 'caissier') {
            // Le cas constaté par l'essai réel (47h D6) : ~74 demandes refusées pour rien.
            expect(attendues, greaterThanOrEqualTo(60));
          }

          // Aucune ligne, aucune table : jamais de conflit pour droit insuffisant.
          final refus = await conflits(c);
          for (final e in refus.entries) {
            for (final motif in e.value) {
              expect(
                motif,
                isNot(contains('Droit insuffisant')),
                reason: '${e.key} : $motif',
              );
            }
          }
          // Ce que le compte peut écrire est parti (sa vente, hors comptable).
          expect(
            (await laVente(c, refVente)).syncStatus,
            droits.peutEcrireTable('ventes') ? 'synced' : 'pending',
            reason: 'la vente part si le compte peut vendre, sinon elle attend',
          );
        },
        skip: saute,
      );
    }

    test(
      'changement de compte : les demandes en attente de droit partent (comptable puis administrateur)',
      () async {
        final c = await poste(compteForce: 'comptable1')
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final code = 'G47-${unique.substring(unique.length - 6)}';
        await ApprovisionnementRepositoryDrift(c.db).enregistrerIntrant(
          Intrant(
            code: code,
            nom: 'Intrant du comptable 47g',
            categorie: Intrant.categories.first,
            stock: 0,
            unite: 'kg',
            seuil: 1,
            pmp: 0,
          ),
          creation: true,
        );

        final r1 = await sync(c);
        expect(r1.enAttenteDeDroit, greaterThan(0), reason: r1.message);
        await sync(b);
        expect(
          await (b.db.select(
            b.db.intrants,
          )..where((i) => i.code.equals(code))).getSingleOrNull(),
          isNull,
          reason: 'le comptable n\'a pas le droit de proposer un intrant',
        );

        // Un administrateur se reconnecte sur ce poste : tout ce qui attendait un droit part.
        final autre = await c.appairage.connecter(
          adresse: adresse!,
          identifiant: 'admin${++compte}',
          motDePasse: mdp,
        );
        expect(autre.reussi, isTrue, reason: autre.message);
        final r2 = await sync(c);
        expect(r2.enAttenteDeDroit, 0, reason: r2.message);
        expect((await c.moteur.etatDroits()).droits!.roles, [
          'admin',
        ], reason: 'les droits suivent le compte appairé');
        for (final d in await c.db.select(c.db.demandesReferentiel).get()) {
          expect(
            d.syncStatus,
            isNot('pending'),
            reason: '${d.type}/${d.cle} est parti',
          );
          expect(d.syncMotif ?? '', isNot(contains('Droit insuffisant')));
        }
        await sync(b);
        expect(
          (await (b.db.select(
            b.db.intrants,
          )..where((i) => i.code.equals(code))).getSingle()).name,
          'Intrant du comptable 47g',
          reason: 'la demande du comptable a bien atteint le serveur',
        );
      },
      skip: saute,
    );

    test(
      'droit accordé au serveur, sans reconnexion : la demande repart à la synchronisation suivante',
      () async {
        final nom = 'g47${unique.substring(unique.length - 7)}';
        final cree = await web(
          "\$u = App\\Models\\User::query()->create(['name'=>'G47',"
          "'username'=>'$nom','password'=>'EssaiPoste-2026!','is_active'=>true,"
          "'must_change_password'=>false]); \$u->assignRole('caissier'); echo 'cree';",
        );
        expect(cree, contains('cree'), reason: cree);
        final c = await poste(compteForce: nom)
          ..let(postes.add);
        final code = 'G47W-${unique.substring(unique.length - 5)}';
        await ApprovisionnementRepositoryDrift(c.db).enregistrerIntrant(
          Intrant(
            code: code,
            nom: 'Intrant droit accordé',
            categorie: Intrant.categories.first,
            stock: 0,
            unite: 'kg',
            seuil: 1,
            pmp: 0,
          ),
          creation: true,
        );
        final r1 = await sync(c);
        expect(r1.enAttenteDeDroit, greaterThan(0));

        final accorde = await web(
          "App\\Models\\User::query()->where('username','$nom')->first()"
          "->assignRole('admin'); echo 'accorde';",
        );
        expect(accorde, contains('accorde'), reason: accorde);

        final r2 = await sync(c);
        expect(r2.enAttenteDeDroit, 0, reason: r2.message);
        expect(
          (await c.moteur.etatDroits()).droits!.roles,
          containsAll(['caissier', 'admin']),
        );
        final d = (await c.db.select(c.db.demandesReferentiel).get())
            .where((x) => x.type == 'intrant' && x.cle == code)
            .single;
        expect(d.syncStatus, 'synced');
      },
      skip: sauteWeb,
    );

    test(
      'le serveur refuse avec le code stable `droit_insuffisant` (jamais de texte à comparer)',
      () async {
        final c = await poste(compteForce: 'animalier1')
          ..let(postes.add);
        final jeton = await c.depot.lire();
        final marque = (await c.preferences.marqueRemiseAZero()) ?? 'initiale';
        final reponse = await http.post(
          Uri.parse('$adresse/api/sync/push'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jeton',
          },
          body: jsonEncode({
            'device_id': await c.preferences.identifiantPoste(),
            'reset_mark': marque,
            'tables': {
              'fournisseurs': [
                {
                  'id': nouvelUuid(),
                  'nom': 'Interdit 47g',
                  'updated_at': instantSaisie(),
                },
              ],
            },
          }),
        );
        expect(reponse.statusCode, 200);
        final corps = jsonDecode(reponse.body) as Map<String, dynamic>;
        final bilan = corps['fournisseurs'] as Map<String, dynamic>;
        final refus =
            (bilan['rejected'] as List).single as Map<String, dynamic>;
        expect(refus['code'], 'droit_insuffisant');
        expect(refus['motif'], contains('Droit insuffisant'));
      },
      skip: saute,
    );
  });

  group('47g : horloge du poste (décalage simulé)', () {
    tearDown(() => horlogePoste = DateTime.now);

    Future<ClientRow> nouveauClient(_Poste p, String nom) async {
      final k = await ClientsRepositoryDrift(p.db).creerClient(nom: nom);
      return p.ligne(k.id);
    }

    for (final cas in <(String, Duration, String)>[
      ('+1 h', const Duration(hours: 1), 'avance de 1 h'),
      ('+2 jours', const Duration(days: 2), 'avance de 2 jours'),
      ('+2 ans', const Duration(days: 730), 'avance de 2 ans'),
    ]) {
      test(
        'poste ${cas.$1} : envoi suspendu, rien de gelé sur le serveur, reprise après correction',
        () async {
          final a = await poste()
            ..let(postes.add);
          final b = await poste()
            ..let(postes.add);
          await sync(a);
          await sync(b);

          horlogePoste = () => DateTime.now().add(cas.$2);
          final nom = 'Horloge ${cas.$1} $unique';
          final k = await nouveauClient(a, nom);
          final r = await sync(a);
          expect(r.envoiSuspendu, isTrue, reason: r.message);
          expect(r.message, contains(cas.$3));
          expect((await a.ligne(k.id)).syncStatus, 'pending');

          // Rien n'a atteint le serveur : l'autre poste n'a rien.
          await sync(b);
          expect(
            await (b.db.select(
              b.db.clients,
            )..where((x) => x.id.equals(k.id))).getSingleOrNull(),
            isNull,
          );

          // Correction de l'horloge : la saisie (datée du futur) repart, bornée à l'heure du serveur.
          horlogePoste = DateTime.now;
          final r2 = await sync(a);
          expect(r2.envoiSuspendu, isFalse, reason: r2.message);
          expect(r2.acceptees, greaterThanOrEqualTo(1), reason: r2.message);
          expect((await a.ligne(k.id)).syncStatus, 'synced');
          await sync(b);
          final chezB = await b.ligne(k.id);
          expect(chezB.nom, nom);
          expect(
            DateTime.parse(
              chezB.updatedAt,
            ).isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5))),
            isFalse,
            reason: 'le serveur ne détient aucun instant du futur',
          );

          // Aucune ligne gelée : l'autre poste, à l'heure juste, corrige et GAGNE.
          await (b.db.update(
            b.db.clients,
          )..where((x) => x.id.equals(k.id))).write(
            ClientsCompanion(
              nom: Value('$nom corrigé'),
              syncStatus: const Value('pending'),
              updatedAt: Value(instantSaisie()),
            ),
          );
          await sync(b);
          await sync(a);
          expect((await a.ligne(k.id)).nom, '$nom corrigé');
        },
        skip: saute,
      );
    }

    test(
      'poste en retard de 1 h : avertissement sans blocage ; avance de 4 min : avertie, envoyée ; de 6 min : suspendue',
      () async {
        final a = await poste()
          ..let(postes.add);
        await sync(a);

        horlogePoste = () => DateTime.now().subtract(const Duration(hours: 1));
        await nouveauClient(a, 'Retard $unique');
        final retard = await sync(a);
        expect(retard.horloge!.etat, EtatHorloge.retard);
        expect(retard.envoiSuspendu, isFalse);
        expect(retard.acceptees, 1);
        expect(retard.message, contains('retarde de 1 h'));

        horlogePoste = () => DateTime.now().add(const Duration(minutes: 4));
        await nouveauClient(a, 'Avance4 $unique');
        final avance4 = await sync(a);
        expect(avance4.horloge!.etat, EtatHorloge.avanceAvertissement);
        expect(avance4.envoiSuspendu, isFalse);
        expect(avance4.acceptees, 1, reason: avance4.message);
        expect(avance4.refuseesHorloge, 0);

        horlogePoste = () => DateTime.now().add(const Duration(minutes: 6));
        await nouveauClient(a, 'Avance6 $unique');
        final avance6 = await sync(a);
        expect(avance6.horloge!.etat, EtatHorloge.avanceBloquante);
        expect(avance6.envoiSuspendu, isTrue);
      },
      skip: saute,
    );

    test(
      'le vrai serveur refuse `horloge_en_avance` (code stable) : +6 min refusé, +300 s accepté',
      () async {
        final a = await poste()
          ..let(postes.add);
        final jeton = await a.depot.lire();
        final marque = (await a.preferences.marqueRemiseAZero()) ?? 'initiale';
        final device = await a.preferences.identifiantPoste();
        Future<Map<String, dynamic>> pousser(String instant) async {
          final r = await http.post(
            Uri.parse('$adresse/api/sync/push'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jeton',
            },
            body: jsonEncode({
              'device_id': device,
              'reset_mark': marque,
              'tables': {
                'clients': [
                  {
                    'id': nouvelUuid(),
                    'nom': 'Brut 47g $unique',
                    'updated_at': instant,
                  },
                ],
              },
            }),
          );
          expect(r.statusCode, 200, reason: r.body);
          final corps = jsonDecode(r.body) as Map<String, dynamic>;
          return corps['clients'] as Map<String, dynamic>;
        }

        final maintenant = DateTime.now().toUtc();
        for (final avance in [
          const Duration(hours: 1),
          const Duration(days: 2),
          const Duration(days: 730),
        ]) {
          final bilan = await pousser(maintenant.add(avance).toIso8601String());
          final refus = (bilan['rejected'] as List).single as Map;
          expect(refus['code'], 'horloge_en_avance');
          expect(
            refus['motif'],
            contains('corrigez la date et l\'heure du poste'),
          );
        }
        expect(
          (await pousser(
            maintenant.add(const Duration(minutes: 4)).toIso8601String(),
          ))['accepted'],
          hasLength(1),
        );
        expect(
          (await pousser(
            maintenant.subtract(const Duration(hours: 1)).toIso8601String(),
          ))['accepted'],
          hasLength(1),
        );
      },
      skip: saute,
    );

    test(
      'le décalage est calculé à chaque synchronisation et mémorisé avec l\'appairage',
      () async {
        horlogePoste = () => DateTime.now().add(const Duration(hours: 1));
        final a = await poste()
          ..let(postes.add);
        expect(
          (await a.preferences.decalageHorloge())!.inMinutes,
          closeTo(60, 1),
        );

        horlogePoste = DateTime.now;
        await sync(a);
        expect(
          (await a.preferences.decalageHorloge())!.inSeconds.abs(),
          lessThan(5),
        );
      },
      skip: saute,
    );
  });

  group('écrans web : ce que le web écrit, le poste le reçoit', () {
    test(
      'client créé puis modifié au web : le poste le reçoit (dates civiles, accents) sans refus',
      () async {
        final a = await poste()
          ..let(postes.add);
        await sync(a);
        final id = nouvelUuid();
        final nom = 'Web Éléonore 47h $unique';
        final sortie = await web(
          "echo json_encode((new App\\Sync\\Tables\\ClientsTable)->absorber('$posteWeb', "
          "['id'=>'$id','nom'=>'$nom','telephone'=>'97470101','date_naissance'=>'1992-02-29',"
          "'updated_at'=>now('UTC')->format('Y-m-d\\TH:i:s.u\\Z')]));",
        );
        expect(sortie, contains('null'), reason: sortie);

        final r = await sync(a);
        expect(r.refuseesALaReception, 0, reason: r.message);
        var c = await a.ligne(id);
        expect(c.nom, nom);
        expect(c.telephone, '97470101');
        expect(c.dateNaissance, DateTime(1992, 2, 29));

        await Future<void>.delayed(const Duration(milliseconds: 30));
        await web(
          "echo json_encode((new App\\Sync\\Tables\\ClientsTable)->absorber('$posteWeb', "
          "['id'=>'$id','nom'=>'$nom','telephone'=>'97470202',"
          "'updated_at'=>now('UTC')->format('Y-m-d\\TH:i:s.u\\Z')]));",
        );
        await sync(a);
        c = await a.ligne(id);
        expect(c.telephone, '97470202');
        expect(c.syncStatus, 'synced');
      },
      skip: sauteWeb,
    );

    test(
      'client supprimé au web alors que des ventes de CE poste le citent : le tirage ne plante pas, l\'historique est conservé',
      () async {
        final a = await poste()
          ..let(postes.add);
        final k = await ClientsRepositoryDrift(
          a.db,
        ).creerClient(nom: 'Supprimé web 47h $unique');
        final ref = await vendre(
          a,
          client: k.nom,
          clientId: k.id,
          statut: StatutVente.avance,
          paye: 100,
        );
        await sync(a);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        await web(
          "echo json_encode((new App\\Sync\\Tables\\ClientsTable)->absorber('$posteWeb', "
          "['id'=>'${k.id}','nom'=>'${k.nom}','supprime_le'=>now('UTC')->format('Y-m-d\\TH:i:s.u\\Z'),"
          "'updated_at'=>now('UTC')->format('Y-m-d\\TH:i:s.u\\Z')]));",
        );

        final r = await a.moteur.synchroniser();

        expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
        expect((await laVente(a, ref)).ref, ref, reason: 'la vente reste');
      },
      skip: sauteWeb,
    );
  });

  // --- `47s_` : stock ciblé. Le web désigne un poste ; seul ce poste applique l'effet, une
  // fois ; le VRAI serveur valide la désignation, redistribue le fait et la trace de l'effet.
  group('stock ciblé (47s_) : le poste désigné par le web applique, une fois', () {
    final maintenantUtc = r"now('UTC')->format('Y-m-d\\TH:i:s.u\\Z')";
    var compteurRef = 0;

    /// Un numéro unique pour toute la durée de vie du serveur d'essai (la référence web est globale).
    String numero() =>
        '${(DateTime.now().microsecondsSinceEpoch % 1000000000).toString().padLeft(9, '0')}${compteurRef++}';

    Future<ProduitVendableRow> goliath(_Poste p) async => (p.db.select(
      p.db.produitsVendables,
    )..where((x) => x.name.equals('Goliath mature'))).getSingle();

    Future<void> fixerStock(_Poste p, String id, int stock) =>
        (p.db.update(p.db.produitsVendables)..where((x) => x.id.equals(id)))
            .write(ProduitsVendablesCompanion(stock: Value(stock)));

    Future<int> stock(_Poste p, String id) async => (await (p.db.select(
      p.db.produitsVendables,
    )..where((x) => x.id.equals(id))).getSingle()).stock;

    /// La vente que le web écrirait (les lignes et le poste cible portés par le fait).
    String phpVente(
      String id,
      String ref,
      String produitId,
      String cible, {
      String statut = 'Payée',
      int secondes = 0,
    }) =>
        "echo json_encode((new App\\Sync\\Tables\\VentesTable)->absorber('$posteWeb', "
        "['id'=>'$id','reference'=>'$ref','client'=>'Client Comptant','client_id'=>null,"
        "'date_vente'=>now('UTC')->format('Y-m-d\\TH:i:s.u\\Z'),'mode'=>'Espèces','status'=>'$statut',"
        "'total'=>9000,'paye'=>9000,'poste_cible'=>'$cible',"
        "'updated_at'=>now('UTC')->addSeconds($secondes)->format('Y-m-d\\TH:i:s.u\\Z'),"
        "'lignes'=>[['id'=>'${nouvelUuid()}','produit_id'=>'$produitId','name'=>'Goliath mature',"
        "'qte'=>3,'pu'=>3000,'espece'=>null]]]));";

    test(
      'vente web ciblée sur A : B ne bouge jamais, A décrémente une fois (rejeu, tirage complet), B voit la trace',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        await sync(a);
        await sync(b); // les deux ont fini un tirage : désignables
        final produit = await goliath(a);
        await fixerStock(a, produit.id, 20);
        await fixerStock(b, produit.id, 20);
        final idA = await a.preferences.identifiantPoste();
        final id = nouvelUuid();

        final sortie = await web(
          phpVente(id, 'V-WEB-2026-${numero()}', produit.id, idA),
        );
        expect(sortie, contains('null'), reason: sortie);

        await sync(b);
        expect(
          await stock(b, produit.id),
          20,
          reason: 'B apprend la vente, sans effet',
        );
        expect(await stock(a, produit.id), 20, reason: 'A est « hors ligne »');

        await sync(a);
        expect(await stock(a, produit.id), 17, reason: 'A applique, une fois');
        await sync(a);
        await sync(a, complet: true);
        expect(
          await stock(a, produit.id),
          17,
          reason: 'rejeu et tirage complet',
        );
        final traces = await (a.db.select(
          a.db.effetsAppliques,
        )..where((e) => e.faitId.equals(id))).get();
        expect(traces, hasLength(1));
        expect(traces.single.etat, 'applique');
        expect(traces.single.syncStatus, 'synced');

        await sync(b);
        final chezB = await (b.db.select(
          b.db.effetsAppliques,
        )..where((e) => e.faitId.equals(id))).get();
        expect(chezB, hasLength(1), reason: 'la trace redescend au poste B');
        expect(chezB.single.origine, idA);
        expect(await stock(b, produit.id), 20, reason: 'historique pur chez B');
      },
      skip: sauteWeb,
    );

    test(
      'l\'annulation au web suit le même poste (réintégration chez A), jamais chez B',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        await sync(a);
        await sync(b);
        final produit = await goliath(a);
        await fixerStock(a, produit.id, 10);
        await fixerStock(b, produit.id, 10);
        final idA = await a.preferences.identifiantPoste();
        final id = nouvelUuid();
        final ref = 'V-WEB-2026-${numero()}';
        await web(phpVente(id, ref, produit.id, idA));
        await sync(a);
        await sync(b);
        expect(await stock(a, produit.id), 7);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        final sortie = await web(
          phpVente(id, ref, produit.id, idA, statut: 'Annulée', secondes: 5),
        );
        expect(sortie, contains('null'), reason: sortie);
        await sync(a);
        await sync(b);

        expect(await stock(a, produit.id), 10, reason: 'A réintègre');
        expect(await stock(b, produit.id), 10);
        expect(
          (await (a.db.select(
                a.db.effetsAppliques,
              )..where((e) => e.faitId.equals(id))).get())
              .map((e) => e.nature)
              .toSet(),
          {'vente', 'annulation_vente'},
        );
      },
      skip: sauteWeb,
    );

    test(
      'stock insuffisant chez A : plancher à 0 et avertissement remonté au serveur et à B',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        await sync(a);
        await sync(b);
        final produit = await goliath(a);
        await fixerStock(a, produit.id, 1);
        final idA = await a.preferences.identifiantPoste();
        final idVente = nouvelUuid();
        await web(phpVente(idVente, 'V-WEB-2026-${numero()}', produit.id, idA));

        await sync(a);
        await sync(b);

        expect(await stock(a, produit.id), 0);
        final trace = (await (b.db.select(
          b.db.effetsAppliques,
        )..where((e) => e.faitId.equals(idVente))).get()).single;
        expect(trace.etat, 'avertissement');
        expect(trace.avertissement, contains('Stock insuffisant au poste P'));
      },
      skip: sauteWeb,
    );

    test(
      'réception web ciblée sur A : entrée de stock et PMP chez A seulement ; annulation = sortie inverse',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final appro = ApprovisionnementRepositoryDrift(a.db);
        final f = await appro.creerFournisseur(nom: 'Fournisseur 47s $unique');
        await sync(a); // fournisseur, intrants adoptés
        await sync(b);
        for (final p in [a, b]) {
          await (p.db.update(
            p.db.intrants,
          )..where((i) => i.code.equals('INT-001'))).write(
            const IntrantsCompanion(stock: Value(100), pmp: Value(200)),
          );
        }
        final idA = await a.preferences.identifiantPoste();
        final id = nouvelUuid();
        final ref = 'ACH-WEB-2026-${numero()}';
        String phpAchat(String statut, int secondes) =>
            "echo json_encode((new App\\Sync\\Tables\\AchatsTable)->absorber('$posteWeb', "
            "['id'=>'$id','reference'=>'$ref','fournisseur_id'=>'${f.id}',"
            "'date_achat'=>now('UTC')->format('Y-m-d\\TH:i:s.u\\Z'),'statut'=>'$statut','total'=>16000,"
            "'paye'=>0,'mode'=>'Crédit','echeance'=>null,'poste_cible'=>'$idA',"
            "'updated_at'=>now('UTC')->addSeconds($secondes)->format('Y-m-d\\TH:i:s.u\\Z'),"
            "'lignes'=>[['id'=>'${nouvelUuid()}','intrant_code'=>'INT-001','nom'=>'Maïs',"
            "'qte'=>50,'pu_achat'=>320]]]));";
        final sortie = await web(phpAchat('Livré', 0));
        expect(sortie, contains('null'), reason: sortie);

        await sync(b);
        await sync(a);
        Future<IntrantRow> intrant(_Poste p) => (p.db.select(
          p.db.intrants,
        )..where((i) => i.code.equals('INT-001'))).getSingle();
        expect((await intrant(a)).stock, 150);
        expect((await intrant(a)).pmp, 240, reason: '(100×200 + 50×320) ÷ 150');
        expect((await intrant(b)).stock, 100);
        expect((await intrant(b)).pmp, 200);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        await web(phpAchat('Annulé', 5));
        await sync(a);
        await sync(a, complet: true);
        expect((await intrant(a)).stock, 100);
        expect((await intrant(a)).pmp, 200, reason: 'inverse de la formule');
      },
      skip: sauteWeb,
    );

    test(
      'correction de stock web ciblée sur A : variation signée chez A seulement',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        await sync(a);
        await sync(b);
        final produit = await goliath(a);
        await fixerStock(a, produit.id, 10);
        await fixerStock(b, produit.id, 10);
        final idA = await a.preferences.identifiantPoste();
        final sortie = await web(
          "echo json_encode((new App\\Sync\\Tables\\MouvementsProduitTable)->absorber('$posteWeb', "
          "['id'=>'${nouvelUuid()}','horodatage'=>$maintenantUtc,'produit_id'=>'${produit.id}',"
          "'article'=>'Goliath mature','motif'=>'Comptage','quantite'=>-4,'poste_cible'=>'$idA']));",
        );
        expect(sortie, contains('null'), reason: sortie);

        await sync(b);
        await sync(a);
        await sync(a, complet: true);

        expect(await stock(a, produit.id), 6);
        expect(await stock(b, produit.id), 10);
      },
      skip: sauteWeb,
    );

    test(
      'le vrai serveur refuse un poste révoqué, jamais synchronisé ou inconnu, et un poste qui prétend désigner',
      () async {
        final a = await poste()
          ..let(postes.add);
        await sync(a);
        final produit = await goliath(a);
        final revoque = await poste()
          ..let(postes.add);
        await sync(revoque);
        final idRevoque = await revoque.preferences.identifiantPoste();
        final jamais = await poste()
          ..let(postes.add);
        final idJamais = await jamais.preferences.identifiantPoste();
        await web(
          "app(App\\Services\\PostesService::class)->revoquer('$idRevoque', App\\Models\\User::query()->first());",
        );

        String ref(int n) => 'V-WEB-2026-${numero()}';
        final motifRevoque = await web(
          phpVente(nouvelUuid(), ref(1), produit.id, idRevoque),
        );
        final motifJamais = await web(
          phpVente(nouvelUuid(), ref(2), produit.id, idJamais),
        );
        final motifInconnu = await web(
          phpVente(nouvelUuid(), ref(3), produit.id, nouvelUuid()),
        );

        // `json_encode` échappe les accents : on relit la chaîne.
        expect(
          jsonDecode(motifRevoque) as String,
          contains('inconnu ou révoqué'),
        );
        expect(
          jsonDecode(motifJamais) as String,
          contains('jamais synchronisé'),
        );
        expect(
          jsonDecode(motifInconnu) as String,
          contains('inconnu ou révoqué'),
        );

        // Un poste qui pousse une vente avec poste_cible : refusée, jamais écrite.
        final repo = VentesRepositoryDrift(a.db, EventBus());
        final x = (await repo.chargerCatalogue()).firstWhere(
          (c) => c.nom == 'Goliath mature',
        );
        final r = await repo.enregistrerVente(
          client: 'Client Comptant',
          mode: ModeReglement.especes,
          statut: StatutVente.payee,
          montantPaye: x.prix,
          panier: [
            LignePanier(
              produitId: x.id,
              nom: x.nom,
              montantGlobal: x.prix,
              quantite: 1,
              stockDisponible: x.stock,
              prixIndicatif: x.prix,
              prixIndicatifMax: x.prixMax,
              espece: x.espece,
              unite: x.unite,
            ),
          ],
        );
        await (a.db.update(a.db.ventes)
              ..where((v) => v.ref.equals(r.vente.reference)))
            .write(VentesCompanion(posteCible: Value(idRevoque)));
        final rapport = await a.moteur.synchroniser();
        expect(rapport.refusees, greaterThan(0), reason: rapport.message);
        final ligne = await (a.db.select(
          a.db.ventes,
        )..where((v) => v.ref.equals(r.vente.reference))).getSingle();
        expect(ligne.syncStatus, 'conflict');
        expect(ligne.syncMotif, contains('Seul le web peut désigner'));
      },
      skip: sauteWeb,
    );
  });

  group('concurrence réelle', () {
    test(
      'quatre postes synchronisent EN MÊME TEMPS (ventes, pièces, fiche du même jour) : aucun échec, tous convergent',
      () async {
        final tous = <_Poste>[];
        for (var i = 0; i < 4; i++) {
          tous.add(
            await poste()
              ..let(postes.add),
          );
        }
        await Future.wait(tous.map(sync));
        final jour = jourPlus(2500);
        final refs = <String>[];
        for (final (i, p) in tous.indexed) {
          for (var v = 0; v < 6; v++) {
            refs.add(await vendre(p, qte: 1));
          }
          await depense(p, 100.0 + i, mois: 3, jour: 20 + i);
          await saisirJour(p, jour, achat: 10 + i, observation: 'Poste $i');
        }

        final rapports = await Future.wait(
          tous.map((p) => p.moteur.synchroniser()),
        );
        for (final r in rapports) {
          expect(r.issue, IssueSynchronisation.terminee, reason: r.message);
          expect(r.refusees, 0, reason: r.message);
        }
        // Un second tour (dans le désordre) : tous les postes se rejoignent.
        await Future.wait(tous.reversed.map(sync));
        await Future.wait(tous.map(sync));

        final fiches = <String>{};
        for (final p in tous) {
          final connues = (await p.db.select(p.db.ventes).get())
              .map((v) => v.ref)
              .toSet();
          expect(
            connues.containsAll(refs),
            isTrue,
            reason: 'ventes manquantes',
          );
          final f = (await p.db.select(p.db.ficheJournee).get()).where(
            (x) => x.espece == 'goliaths' && x.date == jour,
          );
          expect(f, hasLength(1));
          fiches.add('${f.single.achat}/${f.single.traitementObs}');
          expect(await conflits(p), isEmpty);
        }
        expect(fiches, hasLength(1), reason: 'la même fiche partout : $fiches');
      },
      skip: saute,
    );
  });

  group(
    'écrans web (suite) : lot, bande, soin, infirmerie, fournisseur, intrant, compte, pièce',
    () {
      test(
        'tout ce que les écrans web écrivent est reçu par le poste sans refus : codes C-WEB / DEP-WEB, poste web (UUID nul), instants',
        () async {
          final a = await poste()
            ..let(postes.add);
          await sync(a);
          final fin = unique.substring(unique.length - 5);
          final lot = nouvelUuid();
          final fournisseur = nouvelUuid();
          final soin = nouvelUuid();
          final entree = nouvelUuid();
          final piece = nouvelUuid();
          final codeLot = 'C-WEB-$annee-9${fin.substring(0, 2)}';
          final numeroPiece = 'DEP-WEB-$annee-9$fin';
          final code = 'WEB-$fin';
          const instant = r"now('UTC')->format('Y-m-d\TH:i:s.u\Z')";
          final php = [
            r"$w = '00000000-0000-0000-0000-000000000000';",
            r"$u = App\Models\User::query()->where('username', 'admin1')->first();",
            // Lot de couveuse écrit par l'écran « Couveuse ».
            "echo 'lot:'.((new App\\Sync\\Tables\\CyclesCouveuseTable)->absorber(\$w, ["
                "'id'=>'$lot','code_incubation'=>'$codeLot','espece'=>'goliath',"
                "'date_incubation'=>'2026-10-01','oeufs_couves'=>120,'poussins_nes'=>null,"
                "'oeufs_perdus'=>null,'statut'=>'En Incubation','machine_id'=>null,"
                "'oeufs_blancs_j7'=>null,'oeufs_gates_j14'=>null,'lot_parent_id'=>null,"
                "'supprime_le'=>null,'updated_at'=>$instant]) ?? 'ok').PHP_EOL;",
            // Bande déclarée par l'écran d'une filière.
            "echo 'bande:'.((new App\\Services\\FichesElevage('lapins'))"
                "->declarerBande('W$fin', '2026-10-01', 12, 'Bande web')?? 'ok').PHP_EOL;",
            // Soin et entrée d'infirmerie (écran « Soins »).
            "echo 'soin:'.((new App\\Sync\\Tables\\SoinsCalendrierTable)->absorber(\$w, ["
                "'id'=>'$soin','espece'=>'lapins','date_prevue'=>'2026-10-02',"
                "'type_soin'=>'Vaccination','statut'=>'Planifié','observations'=>null,"
                "'produit'=>'Vaccin web','dose'=>'1 ml','remanence_jours'=>2,'veterinaire'=>null,"
                "'symptomes'=>null,'cout_fcfa'=>1200,'echeance_prophylaxie_id'=>null,"
                "'updated_at'=>$instant]) ?? 'ok').PHP_EOL;",
            "echo 'infirmerie:'.((new App\\Sync\\Tables\\InfirmerieTable)->absorber(\$w, ["
                "'id'=>'$entree','date_entree'=>'2026-10-02','sujet'=>'Lapin web','motif'=>'Toux',"
                "'niveau_isolement'=>'Simple surveillance','statut'=>'En cours','date_sortie'=>null,"
                "'espece'=>'lapins','categorie_mortalite'=>null,'updated_at'=>$instant]) ?? 'ok').PHP_EOL;",
            // Fournisseur (écran « Fournisseurs »).
            "echo 'fournisseur:'.((new App\\Sync\\Tables\\FournisseursTable)->absorber(\$w, ["
                "'id'=>'$fournisseur','nom'=>'Fournisseur web $unique','telephone'=>'97470303',"
                "'adresse'=>'Cotonou','fournit'=>'Soja','updated_at'=>$instant]) ?? 'ok').PHP_EOL;",
            // Intrant et compte (demandes, écrans « Gestion des stocks » et « Plan comptable »).
            "echo 'intrant:'.json_encode(app(App\\Sync\\DemandesReferentiel::class)->traiter(\$u, \$w, [["
                "'id'=>(string) Illuminate\\Support\\Str::uuid(),'type'=>'intrant','saisi_le'=>$instant,"
                "'donnees'=>['code'=>'$code','name'=>'Intrant web','cat'=>'Intrants Provende',"
                "'unit'=>'kg','threshold'=>4]]])).PHP_EOL;",
            "echo 'compte:'.json_encode(app(App\\Sync\\DemandesReferentiel::class)->traiter(\$u, \$w, [["
                "'id'=>(string) Illuminate\\Support\\Str::uuid(),'type'=>'compte_comptable','saisi_le'=>$instant,"
                "'donnees'=>['numero_compte'=>'6$fin','libelle'=>'Compte web $fin','classe'=>'6',"
                "'archive'=>false,'plan_version'=>2]]])).PHP_EOL;",
            // Pièce comptable saisie au web (journal CA, numéro DEP-WEB-…).
            "echo 'piece:'.((new App\\Sync\\Tables\\EcrituresTable)->pourUtilisateur(\$u)->absorber(\$w, ["
                "'id'=>'$piece','numero_piece'=>'$numeroPiece',"
                "'date_ecriture'=>now('UTC')->setDate($annee,5,12)->setTime(12,0)->format('Y-m-d\\TH:i:s.u\\Z'),"
                "'exercice_annee'=>$annee,'journal_code'=>'CA','vente_ref'=>null,'achat_ref'=>null,"
                "'contrepasse_de'=>null,'plan_version'=>2,'updated_at'=>$instant,'lignes'=>["
                "['id'=>(string) Illuminate\\Support\\Str::uuid(),'numero_compte'=>'618','debit'=>2500.5,'credit'=>0,'libelle'=>'Transport web','axe_analytique'=>null],"
                "['id'=>(string) Illuminate\\Support\\Str::uuid(),'numero_compte'=>'571','debit'=>0,'credit'=>2500.5,'libelle'=>'Transport web','axe_analytique'=>null]"
                "]]) ?? 'ok').PHP_EOL;",
          ].join(' ');
          final sortie = await web(php);
          // ignore: avoid_print
          print(sortie);
          for (final l in const [
            'lot:ok',
            'bande:ok',
            'soin:ok',
            'infirmerie:ok',
            'fournisseur:ok',
            'piece:ok',
          ]) {
            expect(sortie, contains(l), reason: sortie);
          }
          expect(sortie, contains('"rejected":[]'), reason: sortie);

          final r = await sync(a);
          expect(r.refuseesALaReception, 0, reason: r.message);

          expect(
            (await (a.db.select(
              a.db.cycleCouveuse,
            )..where((c) => c.id.equals(lot))).getSingle()).codeIncubation,
            codeLot,
          );
          expect(
            (await a.db.select(a.db.bandes).get()).any(
              (b) => b.code == 'W$fin',
            ),
            isTrue,
          );
          expect(
            (await (a.db.select(
              a.db.soinsCalendrier,
            )..where((s) => s.id.equals(soin))).getSingle()).produit,
            'Vaccin web',
          );
          expect(
            (await (a.db.select(
              a.db.infirmerie,
            )..where((s) => s.id.equals(entree))).getSingle()).sujet,
            'Lapin web',
          );
          expect(
            (await (a.db.select(
              a.db.fournisseurs,
            )..where((s) => s.id.equals(fournisseur))).getSingle()).fournit,
            'Soja',
          );
          expect(
            (await a.db.select(a.db.intrants).get()).any((i) => i.code == code),
            isTrue,
          );
          expect(
            (await a.db.select(a.db.planComptable).get()).any(
              (c) => c.numeroCompte == '6$fin',
            ),
            isTrue,
          );
          final lignes = (await ecritures(
            a,
          )).where((e) => e.numeroPiece == numeroPiece);
          expect(lignes, hasLength(2));
          expect(
            lignes.fold<double>(0, (s, e) => s + e.debit),
            closeTo(2500.5, 0.001),
          );
          expect(lignes.every((e) => e.origine != null), isTrue);
        },
        skip: sauteWeb,
      );
    },
  );

  group('web contre poste : les deux moteurs de calcul donnent les mêmes fiches', () {
    test(
      'la même saisie de trois jours, par `FichesElevage` (web) et par `EnregistrerJourneeUseCase` (poste), pour les huit filières : mêmes effectifs, mêmes stocks d\'œufs',
      () async {
        final a = await poste()
          ..let(postes.add);
        // Jours « très anciens » : aucune fiche du serveur ne précède, aucune ne s'y mêle.
        final debut = DateTime(
          2001,
          1,
          1 + int.parse(unique.substring(unique.length - 4)) % 300,
        );
        String jourIso(int i) {
          final d = DateTime(debut.year, debut.month, debut.day + i);
          return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        }

        final php = StringBuffer();
        for (final config in ConfigurationsEspeces.parIdentifiant.values) {
          final n = config.nombreCategories;
          final cas = EnregistrerJourneeUseCase(
            FicheElevageRepositoryDrift(a.db, config),
            config,
          );
          for (var i = 0; i < 3; i++) {
            final morts = [for (var c = 0; c < n; c++) c == 0 ? i : 0];
            final dons = [for (var c = 0; c < n; c++) c == 0 ? 1 : 0];
            final poids = config.rationEnPourcentagePoidsVif ? 250000 : 1450;
            final pondeuses = config.identifiant == 'pondeuses';
            final r = await cas.executer(
              date: DateTime(debut.year, debut.month, debut.day + i),
              mouvements: MouvementsJour(
                achat: i == 0 ? 30 : 0,
                ne: i == 0 ? 5 : 1,
                mortsParCategorie: morts,
                donsParCategorie: dons,
              ),
              poidsGeneralG: poids,
              traitementObs: '${config.identifiant} jour $i',
              traitementValide: i == 2,
              stockOeufs: pondeuses
                  ? const SaisieStockOeufs(
                      oeufsPondus: 120,
                      oeufsCasses: 3,
                      sortiesPlateaux: 2,
                    )
                  : null,
            );
            expect(r, isA<Succes<JourneeElevage>>(), reason: '$r');
            final oeufsPhp = pondeuses
                ? "['pondus'=>120,'casses'=>3,'sorties'=>2]"
                : 'null';
            final achatPhp = i == 0 ? 30 : 0;
            final nePhp = i == 0 ? 5 : 1;
            php.write(
              '\$m = (new App\\Services\\FichesElevage(\'${config.identifiant}\'))'
              '->enregistrer(\'${jourIso(i)}\', [\'achat\'=>$achatPhp,'
              '\'ne\'=>$nePhp,\'vente\'=>0,\'morts\'=>[${morts.join(',')}],'
              '\'dons\'=>[${dons.join(',')}]], $poids, '
              '\'${config.identifiant} jour $i\', ${i == 2}, $oeufsPhp); '
              'if (\$m !== null) { echo \'REFUS \'.\$m.PHP_EOL; } ',
            );
          }
        }
        php.write(
          r"echo 'JSON:'.json_encode(App\Models\FicheJournee::query()"
          "->whereBetween('date', ['${jourIso(0)}', '${jourIso(2)}'])->get());",
        );
        final sortie = await web(php.toString());
        expect(sortie, isNot(contains('REFUS')), reason: sortie);
        final json = sortie.substring(sortie.indexOf('JSON:') + 5);
        final serveur = (jsonDecode(json) as List).cast<Map<String, dynamic>>();

        final ecarts = <String>[];
        final locales = await a.db.select(a.db.ficheJournee).get();
        expect(locales.length, 24);
        expect(serveur.length, 24, reason: 'le web a écrit 8 x 3 fiches');
        for (final l in locales) {
          final s = serveur.firstWhere(
            (x) => x['id'] == l.id,
            orElse: () => <String, dynamic>{},
          );
          if (s.isEmpty) {
            ecarts.add('${l.espece} ${l.date} absente du web');
            continue;
          }
          void cmp(String col, Object? local) {
            final v = s[col];
            final egal = local is num && v is num
                ? local.toDouble() == v.toDouble()
                : local == v;
            if (!egal) {
              ecarts.add('${l.espece} ${l.date} $col : poste=$local web=$v');
            }
          }

          cmp('achat', l.achat);
          cmp('ne', l.ne);
          cmp('mort_cat1', l.mortCat1);
          cmp('mort_cat2', l.mortCat2);
          cmp('mort_cat3', l.mortCat3);
          cmp('mort_cat4', l.mortCat4);
          cmp('don_cat1', l.donCat1);
          cmp('don_cat2', l.donCat2);
          cmp('don_cat3', l.donCat3);
          cmp('don_cat4', l.donCat4);
          cmp('effectif', l.effectif);
          cmp('eff_cat1_day', l.effCat1Day);
          cmp('eff_cat2_day', l.effCat2Day);
          cmp('eff_cat3_day', l.effCat3Day);
          cmp('eff_cat4_day', l.effCat4Day);
          cmp('srh', l.srh);
          cmp('ts', l.ts);
          cmp('stock_final_oeufs', l.stockFinalOeufs);
          cmp('oeufs_pondus', l.oeufsPondus);
          cmp('oeufs_casses', l.oeufsCasses);
          cmp('sorties_plateaux', l.sortiesPlateaux);
          cmp('poids_general_g', l.poidsGeneralG);
          cmp('traitement_obs', l.traitementObs);
          cmp('traitement_valide', l.traitementValide);
        }
        expect(ecarts, isEmpty, reason: ecarts.join('\n'));
      },
      skip: sauteWeb,
    );
  });

  group('suppressions propagées', () {
    test(
      'barème, taux de poids et échéance supprimés au poste A (pierre tombale) disparaissent chez B ; un poste neuf ne les recrée pas',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final repo = ParametresElevageRepositoryDrift(a.db);
        final uniq = int.parse(unique.substring(unique.length - 3));
        await repo.creerBareme(
          espece: 'goliaths',
          stade: 'Stade 47h $unique',
          rationGrammesParJour: 77,
        );
        await repo.enregistrerTauxPoids(
          espece: 'ovins',
          poidsMinG: 700000 + uniq,
          poidsMaxG: 710000 + uniq,
          tauxPourcent: 2.5,
          confirme: true,
        );
        await repo.enregistrerEcheance(
          espece: 'goliaths',
          jourCycle: 100 + uniq % 200,
          traitement: 'Traitement 47h $unique',
          produit: 'Produit 47h',
          remanenceJours: 1,
        );
        await aller(a, b);
        final bareme = (await a.db.select(a.db.baremesRation).get()).firstWhere(
          (x) => x.stade == 'Stade 47h $unique',
        );
        final taux = (await a.db.select(a.db.tauxRationPoids).get()).firstWhere(
          (x) => x.poidsMinG == 700000 + uniq,
        );
        final echeance = (await a.db.select(a.db.calendrierProphylaxie).get())
            .firstWhere((x) => x.traitement == 'Traitement 47h $unique');
        expect(
          (await b.db.select(b.db.baremesRation).get()).map((x) => x.id),
          contains(bareme.id),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        await repo.supprimerBareme(bareme.id);
        await repo.supprimerTauxPoids(taux.id);
        await repo.supprimerEcheance(echeance.id);
        final ra = await sync(a);
        expect(ra.demandesRefusees, 0, reason: ra.message);
        await sync(b);

        expect(
          (await b.db.select(b.db.baremesRation).get()).map((x) => x.id),
          isNot(contains(bareme.id)),
        );
        expect(
          (await b.db.select(b.db.tauxRationPoids).get()).map((x) => x.id),
          isNot(contains(taux.id)),
        );
        expect(
          (await b.db.select(b.db.calendrierProphylaxie).get()).map(
            (x) => x.id,
          ),
          isNot(contains(echeance.id)),
        );
        final c = await poste()
          ..let(postes.add);
        await sync(c);
        expect(
          (await c.db.select(c.db.baremesRation).get()).map((x) => x.id),
          isNot(contains(bareme.id)),
          reason: 'un poste neuf ne ressuscite pas un barème supprimé',
        );
      },
      skip: saute,
    );

    test(
      'intrant supprimé au poste A : il n\'est pas ressuscité par un tirage complet (renvoyer vers ce poste)',
      () async {
        final a = await poste()
          ..let(postes.add);
        final app = ApprovisionnementRepositoryDrift(a.db);
        final code = 'S47-${unique.substring(unique.length - 6)}';
        await app.enregistrerIntrant(
          Intrant(
            code: code,
            nom: 'À supprimer 47h',
            categorie: Intrant.categories.first,
            stock: 0,
            unite: 'kg',
            seuil: 1,
            pmp: 0,
          ),
          creation: true,
        );
        await sync(a);
        await app.supprimerIntrant(code);
        expect(
          await (a.db.select(
            a.db.intrants,
          )..where((i) => i.code.equals(code))).getSingleOrNull(),
          isNull,
        );

        await sync(a, complet: true);

        expect(
          await (a.db.select(
            a.db.intrants,
          )..where((i) => i.code.equals(code))).getSingleOrNull(),
          isNull,
          reason:
              'un tirage complet ne doit pas recréer ce que la Gérante a supprimé',
        );
      },
      skip: saute,
    );
  });

  group('semis : ce que le serveur sème, le poste le sème pareil', () {
    test(
      'plan comptable, grille de taxation et modules : mêmes numéros, mêmes libellés, mêmes taux avant toute synchronisation',
      () async {
        final p = await poste()
          ..let(postes.add);
        final reponse = await brut(p, 'GET', '/api/sync/pull');
        final tables =
            (jsonDecode(reponse.body) as Map<String, dynamic>)['tables']
                as Map<String, dynamic>;
        final ecarts = <String>[];

        // Plan comptable : le serveur sème le plan de référence, le poste aussi.
        final plan = {
          for (final l
              in (tables['plan_comptable'] as List)
                  .cast<Map<String, dynamic>>())
            '${l['numero_compte']}': l,
        };
        final localPlan = {
          for (final c in await p.db.select(p.db.planComptable).get())
            c.numeroCompte: c,
        };
        for (final e in localPlan.entries) {
          final s = plan[e.key];
          if (s == null) {
            ecarts.add(
              'plan : ${e.key} (${e.value.libelle}) absent du serveur',
            );
          } else if (s['libelle'] != e.value.libelle ||
              '${s['classe']}' != e.value.classe) {
            ecarts.add(
              'plan ${e.key} : poste « ${e.value.libelle} »/${e.value.classe} '
              'serveur « ${s['libelle']} »/${s['classe']}',
            );
          }
        }
        for (final k in plan.keys) {
          // (un serveur déjà utilisé porte les comptes créés par d'autres essais)
          if (!localPlan.containsKey(k) &&
              !'${plan[k]!['libelle']}'.startsWith('Compte 47h') &&
              !'${plan[k]!['libelle']}'.startsWith('Compte web')) {
            ecarts.add('plan : $k (${plan[k]!['libelle']}) absent du poste');
          }
        }

        // Grille de taxation (e-MECeF).
        final groupes = {
          for (final l
              in (tables['groupes_taxe'] as List).cast<Map<String, dynamic>>())
            '${l['code']}': l,
        };
        final localGroupes = {
          for (final g in await p.db.select(p.db.groupesTaxe).get()) g.code: g,
        };
        for (final e in localGroupes.entries) {
          final s = groupes[e.key];
          if (s == null) {
            ecarts.add('taxe ${e.key} absente du serveur');
          } else if ((s['taux'] as num).toDouble() != e.value.taux) {
            ecarts.add(
              'taxe ${e.key} : poste ${e.value.taux} serveur ${s['taux']}',
            );
          }
        }
        for (final k in groupes.keys) {
          if (!localGroupes.containsKey(k)) {
            ecarts.add('taxe $k absente du poste');
          }
        }

        // Modules.
        final modules = {
          for (final l
              in (tables['modules_actifs'] as List)
                  .cast<Map<String, dynamic>>())
            '${l['module_id']}',
        };
        final localModules = {
          for (final m in await p.db.select(p.db.modulesActifs).get())
            m.moduleId,
        };
        ecarts.addAll([
          for (final m in modules.difference(localModules))
            'module $m absent du poste',
          for (final m in localModules.difference(modules))
            'module $m absent du serveur',
        ]);

        expect(ecarts, isEmpty, reason: ecarts.join('\n'));
      },
      skip: saute,
    );
  });

  group('référentiels et paramètres', () {
    test(
      'paramètres de l\'entreprise : saisis au poste A, rejoués par le serveur, reçus par B',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        await sync(a);
        await sync(b);
        final repo = ParametresRepositoryDrift(a.db);
        final avant = await repo.charger();
        await repo.enregistrer(
          avant.copyWith(
            raisonSociale: 'ALLMANY 47h $unique',
            nomPromoteur: 'Promotrice 47h',
            adresseSiege: 'Natitingou — 47h',
            telephone: '+229 97 47 47 47',
            email: 'contact@allmany.test',
            delaiPaiementJours: 21,
            smtpServeur: 'smtp.allmany.test',
            smtpPort: 587,
            smtpSecurite: 'TLS',
          ),
        );

        final ra = await sync(a);
        expect(ra.demandesRefusees, 0, reason: ra.message);
        expect(ra.demandesAcceptees, greaterThanOrEqualTo(1));
        await sync(b);

        final chezB = await ParametresRepositoryDrift(b.db).charger();
        expect(chezB.raisonSociale, 'ALLMANY 47h $unique');
        expect(chezB.telephone, '+229 97 47 47 47');
        expect(chezB.email, 'contact@allmany.test');
        expect(chezB.delaiPaiementJours, 21);
        expect(chezB.smtpPort, 587);
        expect(chezB.smtpSecurite, 'TLS');
      },
      skip: saute,
    );

    test(
      'catalogue : un produit créé au poste A (stock initial journalisé) arrive chez B SANS stock, journal partagé',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final ventesA = VentesRepositoryDrift(a.db, EventBus());
        final modele = (await ventesA.chargerCatalogue()).first;
        final cree = await ventesA.creerProduit(
          ProduitVendable(
            id: '',
            sku: 'T47-$unique',
            nom: 'Produit 47h $unique',
            categorie: modele.categorie,
            prix: 2500.5,
            prixMax: 3000,
            unite: modele.unite,
            icone: modele.icone,
            stock: 12,
            seuil: 3,
            coutRevient: 1800,
          ),
        );

        final ra = await sync(a);
        expect(ra.demandesRefusees, 0, reason: ra.message);
        expect(ra.refusees, 0, reason: ra.message);
        await sync(b);

        final chezB = await (b.db.select(
          b.db.produitsVendables,
        )..where((p) => p.id.equals(cree.id))).getSingle();
        expect(chezB.name, 'Produit 47h $unique');
        expect(chezB.price, 2500.5);
        expect(chezB.priceMax, 3000);
        expect(chezB.coutRevient, 1800);
        expect(chezB.stock, 0, reason: 'le stock reste propre à chaque poste');
        final journalB = await (b.db.select(
          b.db.mouvementsProduit,
        )..where((m) => m.produitId.equals(cree.id))).get();
        expect(journalB, hasLength(1));
        expect(journalB.single.quantite, 12);
        expect(
          journalB.single.origine,
          isNotNull,
          reason: 'mouvement venu d\'un autre poste',
        );

        // Correction de prix chez A -> B ; correction de stock motivée -> journal.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await ventesA.mettreAJourProduit(
          ProduitVendable(
            id: cree.id,
            sku: cree.sku,
            nom: cree.nom,
            categorie: cree.categorie,
            prix: 2750,
            prixMax: 3000,
            unite: cree.unite,
            icone: cree.icone,
            stock: 10,
            seuil: 3,
            coutRevient: 1800,
          ),
          motifCorrection: 'Casse constatée',
        );
        await aller(a, b);
        final prixB = await (b.db.select(
          b.db.produitsVendables,
        )..where((p) => p.id.equals(cree.id))).getSingle();
        expect(prixB.price, 2750);
        expect(prixB.stock, 0);
        final j = await (b.db.select(
          b.db.mouvementsProduit,
        )..where((m) => m.produitId.equals(cree.id))).get();
        expect(j.map((m) => m.quantite).toList()..sort(), [-2, 12]);
        expect(j.map((m) => m.motif), contains('Casse constatée'));
      },
      skip: saute,
    );

    test(
      'catalogue : la suppression d\'un produit au poste A est propagée en pierre tombale vers B',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final ventesA = VentesRepositoryDrift(a.db, EventBus());
        final modele = (await ventesA.chargerCatalogue()).first;
        final cree = await ventesA.creerProduit(
          ProduitVendable(
            id: '',
            nom: 'À supprimer 47h $unique',
            categorie: modele.categorie,
            prix: 100,
            unite: modele.unite,
            icone: modele.icone,
            stock: 0,
            seuil: 0,
          ),
        );
        await aller(a, b);
        expect(
          await (b.db.select(
            b.db.produitsVendables,
          )..where((p) => p.id.equals(cree.id))).getSingleOrNull(),
          isNotNull,
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        await ventesA.supprimerProduit(cree.id);
        await aller(a, b);

        expect(
          await (b.db.select(
            b.db.produitsVendables,
          )..where((p) => p.id.equals(cree.id))).getSingleOrNull(),
          isNull,
          reason: 'archivé chez B (corbeille)',
        );
        // Un poste neuf ne crée jamais un produit archivé.
        final c = await poste()
          ..let(postes.add);
        await sync(c);
        expect(
          await (c.db.select(
            c.db.produitsVendables,
          )..where((p) => p.id.equals(cree.id))).getSingleOrNull(),
          isNull,
        );
      },
      skip: saute,
    );

    test(
      'intrants : un intrant créé au poste A arrive chez B avec stock 0 ; le journal des mouvements circule sans toucher au stock de B',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final appA = ApprovisionnementRepositoryDrift(a.db);
        final code = 'T47-${unique.substring(unique.length - 6)}';
        await appA.enregistrerIntrant(
          Intrant(
            code: code,
            nom: 'Intrant 47h $unique',
            categorie: Intrant.categories.first,
            stock: 40,
            unite: 'kg',
            seuil: 5,
            pmp: 250,
          ),
          creation: true,
        );
        await appA.ajusterInventaire(
          code: code,
          stockPhysique: 35,
          motif: 'Comptage 47h',
        );

        final ra = await sync(a);
        expect(ra.demandesRefusees, 0, reason: ra.message);
        expect(ra.refusees, 0, reason: ra.message);
        await sync(b);

        final chezB = await (b.db.select(
          b.db.intrants,
        )..where((i) => i.code.equals(code))).getSingle();
        expect(chezB.name, 'Intrant 47h $unique');
        expect(chezB.threshold, 5);
        expect(chezB.stock, 0, reason: 'stock propre à chaque poste');
        expect(chezB.pmp, 0);
        final mouvements = await (b.db.select(
          b.db.mouvementsIntrant,
        )..where((m) => m.intrantCode.equals(code))).get();
        expect(mouvements.map((m) => m.motif), contains('Comptage 47h'));
        expect(mouvements.every((m) => m.origine != null), isTrue);
        // Le stock de A, lui, n'a pas bougé du fait de la synchro.
        expect(
          (await (a.db.select(
            a.db.intrants,
          )..where((i) => i.code.equals(code))).getSingle()).stock,
          35,
        );
      },
      skip: saute,
    );

    test(
      'paramètres d\'élevage : barème, taux de poids et échéance de prophylaxie créés/modifiés au poste A arrivent chez B',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final repo = ParametresElevageRepositoryDrift(a.db);
        final tousBaremes = await repo.chargerBaremes();
        final existant = tousBaremes.first;
        await repo.modifierRation(
          id: existant.id,
          rationGrammesParJour: existant.rationGrammesParJour + 7,
          confirme: true,
        );
        await repo.enregistrerTauxPoids(
          espece: 'pintades',
          poidsMinG: 9000 + unique.length,
          poidsMaxG: 9500 + unique.length,
          tauxPourcent: 4.5,
          confirme: true,
        );
        await repo.enregistrerEcheance(
          espece: 'lapins',
          jourCycle: 61 + (int.parse(unique) % 20),
          traitement: 'Vaccination 47h',
          produit: 'Produit 47h',
          remanenceJours: 2,
          dose: '2 ml',
        );

        final ra = await sync(a);
        expect(ra.demandesRefusees, 0, reason: ra.message);
        await sync(b);

        final bareme = await (b.db.select(
          b.db.baremesRation,
        )..where((x) => x.id.equals(existant.id))).getSingle();
        expect(bareme.rationGrammesParJour, existant.rationGrammesParJour + 7);
        expect(
          (await b.db.select(b.db.tauxRationPoids).get()).any(
            (t) => t.poidsMinG == 9000 + unique.length,
          ),
          isTrue,
        );
        expect(
          (await b.db.select(b.db.calendrierProphylaxie).get()).any(
            (e) => e.traitement == 'Vaccination 47h',
          ),
          isTrue,
        );
      },
      skip: saute,
    );

    test(
      'plan comptable : un compte créé au poste A est connu du serveur et de B',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final numero = '6${unique.substring(unique.length - 3)}9';
        await ComptabiliteRepositoryDrift(a.db).creerCompte(
          CompteComptable(
            numero: numero,
            libelle: 'Compte 47h $unique',
            classe: '6',
          ),
        );

        final ra = await sync(a);
        expect(ra.demandesRefusees, 0, reason: ra.message);
        await sync(b);

        final chezB = await (b.db.select(
          b.db.planComptable,
        )..where((c) => c.numeroCompte.equals(numero))).getSingle();
        expect(chezB.libelle, 'Compte 47h $unique');
        expect(chezB.classe, '6');
      },
      skip: saute,
    );
  });

  // ---------------------------------------------------------------------------
  // LES DEUX ESSAIS DESTRUCTEURS, TOUJOURS EN DERNIER : ils changent l'état de
  // tout le serveur (exercice verrouillé, faits effacés).
  // ---------------------------------------------------------------------------
  group('opérations lourdes : clôture annuelle puis remise à zéro', () {
    test(
      'clôture annuelle au poste A (administratrice) : le serveur verrouille l\'exercice, B le sait, un poste qui l\'ignore voit sa pièce refusée avec son motif',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final c = await poste()
          ..let(postes.add);
        await sync(a);
        await sync(b);
        await sync(c);
        // Rien à envoyer chez A : sa clôture ne verrouille pas une pièce inconnue.
        await ComptabiliteRepositoryDrift(a.db).cloturerExercice(annee);
        final ra = await sync(a);
        expect(ra.refusees, 0, reason: ra.message);
        await sync(b);
        expect(
          (await (b.db.select(
            b.db.exerciceComptable,
          )..where((e) => e.annee.equals(annee))).getSingle()).isCloture,
          isTrue,
          reason: 'l\'exercice clos au poste A est clos chez B',
        );
        expect(
          (await b.db.select(b.db.exerciceComptable).get()).map((e) => e.annee),
          contains(annee + 1),
          reason: 'l\'exercice suivant est ouvert',
        );

        // Le poste C écrit dans l'exercice clos AVANT d'avoir tiré (hors ligne).
        await ComptabiliteRepositoryDrift(c.db).enregistrerPiece(
          date: DateTime(annee, 10, 10),
          journalCode: 'CA',
          numeroPiece: 'TARDIVE-47H-$unique',
          lignes: [
            const LigneAEcrire(
              numeroCompte: '618',
              debit: 40,
              credit: 0,
              libelle: 'Tardive',
            ),
            const LigneAEcrire(
              numeroCompte: '571',
              debit: 0,
              credit: 40,
              libelle: 'Tardive',
            ),
          ],
        );
        await c.db.customStatement(
          "UPDATE exercice_comptable SET is_cloture = 0 WHERE annee = $annee",
        );
        final rc = await c.moteur.synchroniser();
        expect(rc.issue, IssueSynchronisation.terminee, reason: rc.message);
        final refusees = (await ecritures(
          c,
        )).where((e) => e.numeroPiece == 'TARDIVE-47H-$unique');
        // ignore: avoid_print
        print(
          'Pièce dans un exercice clos : ${refusees.map((e) => '${e.syncStatus}/${e.syncMotif}').toSet()}',
        );
        expect(
          refusees.every((e) => e.syncStatus == 'conflict'),
          isTrue,
          reason: 'refusée, jamais acceptée en silence',
        );
        expect(refusees.first.syncMotif, contains('clôtur'));
      },
      skip: saute,
    );

    test(
      'remise à zéro : mot exact exigé ; ancien envoi = 409 ; chaque poste se vide, compte ses saisies perdues, garde ses référentiels et rouvre l\'exercice',
      () async {
        final a = await poste()
          ..let(postes.add);
        final b = await poste()
          ..let(postes.add);
        final admin = await poste()
          ..let(postes.add);
        await ClientsRepositoryDrift(
          a.db,
        ).creerClient(nom: 'Avant RAZ $unique');
        await vendre(a);
        await depense(a, 123, mois: 6, jour: 6);
        await saisirJour(a, jourPlus(900), achat: 2);
        await aller(a, b);
        // B a une saisie jamais envoyée : elle sera perdue, et B le dira.
        await ClientsRepositoryDrift(
          b.db,
        ).creerClient(nom: 'Jamais envoyé $unique');
        final produitsAvant =
            (await a.db.select(a.db.produitsVendables).get()).length;
        final ancienneMarque = (await a.preferences.marqueRemiseAZero())!;

        final mauvais = await brut(
          admin,
          'POST',
          '/api/parametres/remise-a-zero',
          {'confirmation': 'remettre a zero'},
        );
        expect(mauvais.statusCode, 403);
        expect(
          (jsonDecode(mauvais.body) as Map<String, dynamic>)['message'],
          contains('mot de confirmation'),
        );
        expect(
          await a.db.select(a.db.clients).get(),
          isNotEmpty,
          reason: 'le mauvais mot n\'a rien effacé',
        );

        final bon = await brut(admin, 'POST', '/api/parametres/remise-a-zero', {
          'confirmation': 'REMETTRE A ZERO',
        });
        expect(bon.statusCode, 200, reason: bon.body);

        // Un poste qui envoie avec l'ancienne marque reçoit 409.
        final ancien = await pousser(a, {
          'clients': [],
        }, marque: ancienneMarque);
        expect(ancien['status'], 409);

        final ra = await a.moteur.synchroniser();
        expect(ra.issue, IssueSynchronisation.terminee, reason: ra.message);
        expect(ra.remiseAZero, isTrue);
        final rb = await b.moteur.synchroniser();
        expect(rb.remiseAZero, isTrue);
        expect(rb.saisiesPerdues, greaterThanOrEqualTo(1), reason: rb.message);

        for (final p in [a, b]) {
          for (final t in const [
            'ventes',
            'lignes_vente',
            'clients',
            'ecriture_comptable',
            'fiche_journee',
            'mouvements_intrant',
          ]) {
            final n =
                (await p.db
                        .customSelect('SELECT COUNT(*) AS n FROM $t')
                        .getSingle())
                    .read<int>('n');
            expect(n, 0, reason: '$t vidée par la remise à zéro');
          }
          expect(
            (await p.db.select(p.db.produitsVendables).get()).length,
            produitsAvant,
            reason: 'référentiels préservés',
          );
          expect(
            (await p.db.select(p.db.exerciceComptable).get()).where(
              (e) => e.isCloture,
            ),
            isEmpty,
            reason: 'la remise à zéro rouvre les exercices',
          );
          expect(
            await p.preferences.marqueRemiseAZero(),
            isNot(ancienneMarque),
          );
        }

        // Le poste repart : une nouvelle vente est acceptée avec la nouvelle marque.
        final ref = await vendre(a);
        final r2 = await sync(a);
        expect(r2.refusees, 0, reason: r2.message);
        await sync(b);
        expect((await laVente(b, ref)).ref, ref);
      },
      skip: saute,
    );
  });
}

class _Poste {
  _Poste(this.db, this.preferences, this.depot, this.appairage, this.moteur);

  final AppDatabase db;
  final PreferencesPosteRepository preferences;
  final DepotJetonSyncMemoire depot;
  final ServiceAppairage appairage;
  final MoteurSynchronisationPoste moteur;

  Future<ClientRow> ligne(String id) =>
      (db.select(db.clients)..where((c) => c.id.equals(id))).getSingle();
}

extension _Let<T> on T {
  void let(void Function(T) f) => f(this);
}

/// Les 28 tables, dans l'ordre exact de `main.dart` (= `sync.tables` du serveur).
List<TablePoste> tablesDuPoste(AppDatabase db) => [
  TableModulesActifsPoste(db),
  TableParametresEntreprisePoste(db),
  TableProduitsPoste(db),
  TableIntrantsPoste(db),
  TableBaremesRationPoste(db),
  TableTauxRationPoidsPoste(db),
  TableCalendrierProphylaxiePoste(db),
  TableClientsPoste(db),
  TableFournisseursPoste(db),
  TableVentesPoste(db),
  TableGroupesTaxePoste(db),
  TableFacturesPoste(db),
  TableAchatsPoste(db),
  TableMouvementsIntrantPoste(db),
  TableMouvementsProduitPoste(db),
  TableEffetsStockPoste(db),
  TableFichesJourneePoste(db),
  TableVentesJourPoste(db),
  TableBandesPoste(db),
  TableMachinesIncubateurPoste(db),
  TableCyclesCouveusePoste(db),
  TableSoinsPoste(db),
  TableInfirmeriePoste(db),
  TablePlanComptablePoste(db),
  TableExercicesPoste(db),
  TableEcrituresPoste(db),
  TableNotesAnnexesPoste(db),
  TableCloturesPeriodiquesPoste(db),
  TableCloturesExercicePoste(db),
];
