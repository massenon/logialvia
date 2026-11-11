import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_etat_synchronisation.dart';

/// État de synchronisation par table, lignes refusées, « Remettre en file ».
void main() {
  late AppDatabase db;
  late DepotEtatSynchronisation depot;

  setUp(() {
    db = AppDatabase.enMemoire();
    depot = DepotEtatSynchronisation(db);
  });

  tearDown(() => db.close());

  Future<String> client(String nom, {String statut = 'pending'}) async {
    await db
        .into(db.clients)
        .insert(ClientsCompanion.insert(nom: nom, syncStatus: Value(statut)));
    return (await (db.select(
      db.clients,
    )..where((c) => c.nom.equals(nom))).getSingle()).id;
  }

  test('les tables synchronisées sont reconnues à leurs colonnes', () async {
    final tables = await depot.tablesSynchronisees();

    expect(
      tables,
      containsAll(['clients', 'ventes', 'fournisseurs', 'achats']),
    );
    expect(tables, isNot(contains('utilisateurs')), reason: 'comptes locaux');
    expect(tables, isNot(contains('journal_synchronisation')));
    expect(tables, isNot(contains('preferences_poste')));
  });

  test('parTable compte en attente, synchronisées et refusées', () async {
    await client('A');
    await client('B', statut: 'synced');
    await client('C', statut: 'synced');
    final refuse = await client('D');
    await TableClientsPoste(db).marquerConflit(refuse, 'Nom déjà utilisé');

    final etat = (await depot.parTable()).singleWhere(
      (e) => e.table == 'clients',
    );

    expect(
      [etat.enAttente, etat.synchronisees, etat.refusees, etat.total],
      [1, 2, 1, 4],
    );
    expect(etat.libelle, 'Clients');
    expect(etat.conforme, isFalse);
    expect(await depot.totalEnAttente(), 1);
  });

  test('les tables vides ne figurent pas dans le contrôle', () async {
    expect(await depot.parTable(), isEmpty);
  });

  test('refusees donne le motif et de quoi reconnaître la ligne', () async {
    final id = await client('Dupont');
    await TableClientsPoste(db).marquerConflit(id, 'Téléphone invalide');
    await client('Autre');

    final lignes = await depot.refusees();

    expect(lignes, hasLength(1));
    expect(lignes.single.table, 'clients');
    expect(lignes.single.libelleTable, 'Clients');
    expect(lignes.single.id, id);
    expect(lignes.single.designation, 'Dupont');
    expect(lignes.single.motif, 'Téléphone invalide');
    expect(await depot.refusees(table: 'ventes'), isEmpty);
  });

  test('remettreEnFile : une ligne, une table, ou tout', () async {
    final a = await client('A');
    final b = await client('B');
    final c = await client('C');
    for (final id in [a, b, c]) {
      await TableClientsPoste(db).marquerConflit(id, 'refus');
    }

    expect(await depot.remettreEnFile(table: 'clients', id: a), 1);
    var s = {
      for (final l in await db.select(db.clients).get()) l.id: l.syncStatus,
    };
    expect(s[a], 'pending');
    expect(s[b], 'conflict');
    expect(
      (await db.select(db.clients).get())
          .firstWhere((l) => l.id == a)
          .syncMotif,
      isNull,
    );

    expect(await depot.remettreEnFile(table: 'clients'), 2);
    expect(await depot.refusees(), isEmpty);
    expect(await depot.remettreEnFile(), 0);

    s = {for (final l in await db.select(db.clients).get()) l.id: l.syncStatus};
    expect(s.values.toSet(), {'pending'});
  });

  test(
    'remettre en file ne touche pas les lignes déjà synchronisées',
    () async {
      final synchro = await client('S', statut: 'synced');

      expect(await depot.remettreEnFile(table: 'clients', id: synchro), 0);
      expect((await db.select(db.clients).get()).single.syncStatus, 'synced');
    },
  );

  test(
    'un refus de clôture est listé (clé = année) sans « Remettre en file »',
    () async {
      await db
          .into(db.exerciceComptable)
          .insert(
            ExerciceComptableCompanion.insert(
              annee: const Value(2026),
              syncStatus: const Value('conflict'),
              syncMotif: const Value(
                'Clôture refusée : écritures déséquilibrées',
              ),
            ),
          );

      final lignes = await depot.refusees(table: 'exercice_comptable');

      expect(lignes, hasLength(1));
      expect(lignes.single.designation, '2026');
      expect(lignes.single.motif, contains('déséquilibrées'));
      expect(lignes.single.remisePossible, isFalse);
      expect(
        await depot.remettreEnFile(),
        0,
        reason: 'une clôture se refait, elle ne se renvoie pas',
      );
      expect(await depot.refusees(table: 'exercice_comptable'), hasLength(1));
    },
  );
}
