import 'package:drift/drift.dart';

/// Table `CYCLE_COUVEUSE` — Doc D1 §2.
@DataClassName('CycleCouveuseRow')
class CycleCouveuse extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Ex. 'C-2026-014'.
  TextColumn get codeIncubation => text().unique()();

  /// ⚠️ AJOUTEE — absente de Doc D1, alors que la modale « Déclarer un Nouveau
  /// Cycle » la demande en premier champ et qu'elle conditionne la duree
  /// d'incubation ('goliath' ou 'pintade', cycle-couveuse.html l.229-234).
  TextColumn get espece => text().withDefault(const Constant('goliath'))();

  /// ⚠️ RENDUE NULLABLE — Doc D1 la declarait NOT NULL, mais aucun champ du
  /// formulaire reel ne la saisit. La rendre obligatoire aurait bloque toute
  /// creation de cycle.
  TextColumn get bandeReproducteurs => text().nullable()();

  /// Jour 0 — « Date de Chargement » dans l'interface.
  DateTimeColumn get dateIncubation => dateTime()();

  IntColumn get oeufsCouves => integer()();

  /// Renseigne a l'eclosion — « Nombre de Poussins Éclos ».
  IntColumn get poussinsNes => integer().nullable()();

  /// ⚠️ AJOUTEE — « Nombre d'Œufs Non Éclos / Cassés », saisi dans la modale
  /// d'eclosion (cycle-couveuse.html l.276) et absent de Doc D1.
  IntColumn get oeufsPerdus => integer().nullable()();

  /// 'En Incubation', 'Éclosion Effectuée', 'Remplacé'
  TextColumn get statut => text()();

  // ------------------------------------------- suivi multi-ages (v21)
  //
  // La couveuse tourne en continu : plusieurs lots d'ages differents y
  // cohabitent, chacun avec son propre calendrier. Le prototype ne suivait
  // qu'une date de chargement et une eclosion, sans mirages ni machines.

  /// Incubateur occupe — le couvoir peut en compter plusieurs.
  /// Nullable : les lots anterieurs a la v21 n'en designent aucun.
  IntColumn get machineId =>
      integer().nullable().references(MachinesIncubateur, #id)();

  /// `B_i(7)` — oeufs clairs retires au **premier mirage**, a J+7.
  /// `null` tant que le mirage n'a pas ete fait : c'est ce qui distingue
  /// « pas encore mire » de « mire, zero oeuf clair ».
  IntColumn get oeufsBlancsJ7 => integer().nullable()();

  /// `M_i(14)` — oeufs gates retires au **second mirage**, a J+14.
  IntColumn get oeufsGatesJ14 => integer().nullable()();

  /// Lot d'origine si celui-ci le remplace apres eclosion.
  ///
  /// La date de remplacement et la quantite remplacee ne sont **pas** des
  /// colonnes : ce sont la date d'insertion et la quantite initiale du
  /// sous-lot lui-meme. Les stocker deux fois les laisserait diverger.
  ///
  /// L'historique des remplacements est la chaine de ces liens.
  IntColumn get lotParentId => integer().nullable()();
}

/// Un incubateur physique — table `MACHINES_INCUBATEUR`, ajoutee en v21.
///
/// Le cahier des charges de la couveuse multi-ages demande de « referencer
/// chaque machine incubateur, car il peut y en avoir plusieurs » : sans elle,
/// impossible de savoir quelle machine heberge quel lot, ni de mesurer son
/// occupation.
@DataClassName('MachineIncubateurRow')
class MachinesIncubateur extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Ex. 'INC-01'.
  TextColumn get code => text().unique()();

  TextColumn get libelle => text()();

  /// Capacite annoncee, `null` si inconnue. Sert a **signaler** une surcharge,
  /// pas a la bloquer : la Gerante sait ce que sa machine encaisse.
  IntColumn get capaciteOeufs => integer().nullable()();

  BoolColumn get active => boolean().withDefault(const Constant(true))();
}
