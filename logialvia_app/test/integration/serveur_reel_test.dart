import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/commercial/data/repositories/clients_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

/// ESSAI CONTRE LE VRAI SERVEUR LARAVEL (`45_` §6c, dernière étape de P1/P2).
///
/// Désactivé par défaut : il exige un serveur qui tourne. Lancement :
///
/// ```bash
/// # dans logialvia_laravel/ (base jetable, administrateur sans mot de passe temporaire)
/// DB_DATABASE=/tmp/lv/essai.sqlite ADMIN_INITIAL_PASSWORD='EssaiPoste-2026!' \
///   php artisan migrate:fresh --seed --force
/// # puis des comptes admin1…admin8 (rôle admin, sans mot de passe temporaire) :
/// php artisan tinker --execute="foreach (range(1,8) as \$i) { \$u = App\Models\User::query()->create(['name'=>'Admin '.\$i,'username'=>'admin'.\$i,'password'=>'EssaiPoste-2026!','is_active'=>true,'must_change_password'=>false]); \$u->assignRole('admin'); }"
/// DB_DATABASE=/tmp/lv/essai.sqlite php artisan serve --port=8765
///
/// # dans logialvia_app/
/// LOGIALVIA_SERVEUR=http://127.0.0.1:8765 LOGIALVIA_MDP='EssaiPoste-2026!' \
///   flutter test test/integration/serveur_reel_test.dart
/// ```
///
/// Les faux serveurs des autres tests rejouent le contrat ; celui-ci prouve que
/// le contrat est bien celui que le serveur réel tient.
void main() {
  final adresse = Platform.environment['LOGIALVIA_SERVEUR'];
  final mdp = Platform.environment['LOGIALVIA_MDP'] ?? '';
  final saute = adresse == null
      ? 'LOGIALVIA_SERVEUR non défini : essai contre le vrai serveur ignoré.'
      : false;

  // Le limiteur de connexion (5 par minute et par identifiant) fait son travail :
  // chaque poste de l'essai se connecte donc avec son propre compte administrateur
  // (admin1, admin2… créés avant l'essai).
  var compte = 0;

  /// Un poste complet, HTTP réel.
  Future<_Poste> poste() async {
    final db = AppDatabase.enMemoire();
    final preferences = PreferencesPosteRepository(db);
    final depot = DepotJetonSyncMemoire();
    final appairage = ServiceAppairage(preferences: preferences, depot: depot);
    final r = await appairage.connecter(
      adresse: adresse!,
      identifiant: 'admin${++compte}',
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
        tables: [TableClientsPoste(db)],
        tailleLot: 2,
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
