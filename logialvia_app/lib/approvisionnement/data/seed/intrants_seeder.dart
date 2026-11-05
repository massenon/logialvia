import '../../../core/database/app_database.dart';

/// Peuplement initial des intrants (provende + veterinaire).
///
/// Transcription **litterale** de `DEFAULT_INTRANTS` dans
/// `prototype_html/assets/js/logialvia-store.js` (l.63-70).
///
/// Consequence directe et verifiable : INT-001 (Maïs) a un stock de 18 kg pour
/// un seuil de 25 — c'est le seul intrant sous son seuil. Le KPI « Stock
/// Critique » du tableau de bord affiche donc « 1 intrant / Maïs sous le seuil
/// d'alerte », exactement comme `dashboard.html` l.162-163, **par calcul reel
/// sur ces donnees** et non par recopie du chiffre affiche dans le HTML.
class IntrantsSeeder {
  const IntrantsSeeder(this._db);

  final AppDatabase _db;

  static const List<({
    String code,
    String name,
    String cat,
    int stock,
    String unit,
    int threshold,
    int pmp,
  })>
  intrants = [
    (
      code: 'INT-001',
      name: 'Maïs',
      cat: 'Intrants Provende',
      stock: 18,
      unit: 'kg',
      threshold: 25,
      pmp: 600,
    ),
    (
      code: 'INT-002',
      name: 'Soja',
      cat: 'Intrants Provende',
      stock: 42,
      unit: 'kg',
      threshold: 15,
      pmp: 700,
    ),
    (
      code: 'INT-003',
      name: 'Coquille d\'huître',
      cat: 'Intrants Provende',
      stock: 22,
      unit: 'kg',
      threshold: 8,
      pmp: 300,
    ),
    (
      code: 'INT-004',
      name: 'Poudre de poisson',
      cat: 'Intrants Provende',
      stock: 9,
      unit: 'kg',
      threshold: 5,
      pmp: 1500,
    ),
    (
      code: 'INT-005',
      name: 'Tourteau de palmiste',
      cat: 'Intrants Provende',
      stock: 31,
      unit: 'kg',
      threshold: 10,
      pmp: 500,
    ),
    (
      code: 'INT-006',
      name: 'Anti-coccidien',
      cat: 'Vétérinaire',
      stock: 7,
      unit: 'dose(s)',
      threshold: 5,
      pmp: 1500,
    ),
  ];

  Future<bool> executer() async {
    if (await _contientDejaDesLignes()) return false;

    await _db.batch((batch) {
      batch.insertAll(
        _db.intrants,
        intrants.map(
          (i) => IntrantsCompanion.insert(
            code: i.code,
            name: i.name,
            cat: i.cat,
            stock: i.stock,
            unit: i.unit,
            threshold: i.threshold,
            pmp: i.pmp,
          ),
        ),
      );
    });
    return true;
  }

  /// `LIMIT 1` plutot qu'un `COUNT(*)` : on veut seulement savoir si la table
  /// est vide, pas combien elle contient de lignes.
  Future<bool> _contientDejaDesLignes() async {
    final premiere = await (_db.select(
      _db.intrants,
    )..limit(1)).getSingleOrNull();
    return premiere != null;
  }
}
