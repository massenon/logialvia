import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v15 — « Avance » quitte `VENTES.mode`.
///
/// On ne peut pas rejouer une vraie montée de version sur une base en mémoire
/// sans reconstruire le schéma v14 à la main ; on vérifie donc la **règle**
/// appliquée par la migration, sur des lignes écrites directement en SQL comme
/// le faisait l'ancien code.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.enMemoire());
  tearDown(() => db.close());

  /// La commande exacte du bloc `if (from < 15)`.
  Future<void> rejouerMigration() async {
    await db.customStatement('UPDATE ventes SET mode = ? WHERE mode = ?', [
      ModeReglement.nonPrecise,
      ConditionPaiement.avance,
    ]);
  }

  Future<void> insererVente({
    required String ref,
    required String mode,
    required String status,
    double total = 12000,
    double paye = 5000,
  }) => db.customStatement(
    'INSERT INTO ventes (ref, client, date_vente, mode, status, total, paye) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      ref,
      'AGOSSOU Prudence',
      DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
      mode,
      status,
      total,
      paye,
    ],
  );

  Future<String> modeDe(String ref) async {
    final ligne = await db
        .customSelect(
          'SELECT mode FROM ventes WHERE ref = ?',
          variables: [Variable.withString(ref)],
        )
        .getSingle();
    return ligne.read<String>('mode');
  }

  test(
    'une ancienne vente « Avance » perd un mode qu\'elle n\'a jamais eu',
    () async {
      await insererVente(
        ref: 'V-2026-001',
        mode: ConditionPaiement.avance,
        status: StatutVente.avance,
      );

      await rejouerMigration();

      expect(
        await modeDe('V-2026-001'),
        ModeReglement.nonPrecise,
        reason:
            'Choisir « Especes » a sa place serait inventer une donnee qui n\'a '
            'jamais ete saisie.',
      );
    },
  );

  test('son statut reste « Avance » : elle demeure une créance', () async {
    await insererVente(
      ref: 'V-2026-001',
      mode: ConditionPaiement.avance,
      status: StatutVente.avance,
    );

    await rejouerMigration();

    final ligne = await db
        .customSelect(
          'SELECT status, total, paye FROM ventes WHERE ref = ?',
          variables: [Variable.withString('V-2026-001')],
        )
        .getSingle();

    expect(ligne.read<String>('status'), StatutVente.avance);
    expect(
      ligne.read<double>('total') - ligne.read<double>('paye'),
      7000,
      reason:
          'La condition de paiement n\'est pas perdue : elle etait deja sur '
          '`status`, ou elle reste. Rien a recalculer, rien a recouvrer en '
          'moins.',
    );
  });

  test('les ventes en espèces et Mobile Money ne sont pas touchées', () async {
    await insererVente(
      ref: 'V-2026-002',
      mode: ModeReglement.especes,
      status: StatutVente.payee,
      paye: 12000,
    );
    await insererVente(
      ref: 'V-2026-003',
      mode: ModeReglement.mobileMoney,
      status: StatutVente.avance,
    );

    await rejouerMigration();

    expect(await modeDe('V-2026-002'), ModeReglement.especes);
    expect(
      await modeDe('V-2026-003'),
      ModeReglement.mobileMoney,
      reason:
          'Une avance dont l\'instrument etait connu le reste — seules les '
          'lignes ou `mode` portait la condition sont reecrites.',
    );
  });

  test('rejouer la migration deux fois ne change rien de plus', () async {
    await insererVente(
      ref: 'V-2026-001',
      mode: ConditionPaiement.avance,
      status: StatutVente.avance,
    );

    await rejouerMigration();
    await rejouerMigration();

    expect(await modeDe('V-2026-001'), ModeReglement.nonPrecise);
  });

  test('la v15 est bien franchie sur une base neuve', () async {
    // `schemaVersion` a continue de monter depuis (v16 : ligne Mobile Money).
    // Ce qui compte ici est que le palier v15 soit derriere nous, donc que la
    // migration s'execute sur toute installation anterieure.
    expect(db.schemaVersion, greaterThanOrEqualTo(15));
  });
}
