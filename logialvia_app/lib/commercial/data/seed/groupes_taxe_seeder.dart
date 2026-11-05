import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Amorce la grille de taxation des factures normalisées.
///
/// ## Pourquoi deux groupes seulement
///
/// La grille officielle de la DGI compte davantage de lettres. Elles ne
/// figurent pas ici parce qu'elles n'ont pas été vérifiées pièce en main :
/// inscrire un taux faux sous une lettre officielle produirait des factures
/// erronées qui **paraîtraient** justes — le pire des deux mondes.
///
/// Sont donc amorcés les deux seuls groupes dont l'usage ne fait pas de doute
/// pour ALLMANY : l'exonération, qui couvre les produits d'élevage non
/// transformés, et le taux normal de 18 %, qui couvre le reste. La table est
/// modifiable : compléter la grille se fait sans toucher au code, dès que la
/// documentation de la DGI est sous les yeux.
///
/// ✓ **ARBITRÉ PAR LA GÉRANTE** — la question lui a été posée, et la réponse
/// est celle-ci : deux groupes suffisent, et **l'élevage est exonéré**. Ce
/// n'était pas une valeur par défaut choisie faute de mieux ; c'est une
/// décision métier. Elle est consignée ici pour qu'on ne la « corrige » pas
/// plus tard par prudence, en taxant des produits qui ne doivent pas l'être.
class GroupesTaxeSeeder {
  const GroupesTaxeSeeder(this._db);

  final AppDatabase _db;

  static const List<({String code, String libelle, double taux, int ordre})>
  grille = [
    (code: 'A', libelle: 'Exonéré', taux: 0, ordre: 1),
    (code: 'B', libelle: 'Taux normal 18 %', taux: 18, ordre: 2),
  ];

  /// Idempotent : ne réécrit jamais un groupe déjà présent, dont le taux a pu
  /// être corrigé à la main.
  Future<void> executer() async {
    for (final g in grille) {
      final existe = await (_db.select(
        _db.groupesTaxe,
      )..where((t) => t.code.equals(g.code))).getSingleOrNull();
      if (existe != null) continue;

      await _db
          .into(_db.groupesTaxe)
          .insert(
            GroupesTaxeCompanion.insert(
              code: g.code,
              libelle: g.libelle,
              taux: g.taux,
              ordre: Value(g.ordre),
            ),
          );
    }
  }
}
