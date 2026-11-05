import 'package:drift/drift.dart';

/// Table `FICHE_JOURNEE` — Doc D1 §2. Une ligne par espece et par jour.
///
/// `effectif` et les sous-effectifs `effCat*Day` sont **calcules, jamais
/// saisis** (BR-ELV-007) : le formulaire de saisie journaliere ne doit pas
/// exposer de champ editable pour eux (Doc E6 §3).
@DataClassName('FicheJourneeRow')
class FicheJournee extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'goliaths','pintades','lapins','poulets','pondeuses','poissons-chats'
  TextColumn get espece => text()();

  DateTimeColumn get date => dateTime()();

  IntColumn get achat => integer().withDefault(const Constant(0))();
  IntColumn get ne => integer().withDefault(const Constant(0))();
  IntColumn get vente => integer().withDefault(const Constant(0))();

  IntColumn get mortCat1 => integer().withDefault(const Constant(0))();
  IntColumn get mortCat2 => integer().withDefault(const Constant(0))();
  IntColumn get mortCat3 => integer().withDefault(const Constant(0))();

  /// Categorie 4 : Pondeuses uniquement.
  IntColumn get mortCat4 => integer().nullable()();

  IntColumn get donCat1 => integer().withDefault(const Constant(0))();
  IntColumn get donCat2 => integer().withDefault(const Constant(0))();
  IntColumn get donCat3 => integer().withDefault(const Constant(0))();
  IntColumn get donCat4 => integer().nullable()();

  IntColumn get effectif => integer().withDefault(const Constant(0))();

  IntColumn get effCat1Day => integer().withDefault(const Constant(0))();
  IntColumn get effCat2Day => integer().withDefault(const Constant(0))();
  IntColumn get effCat3Day => integer().withDefault(const Constant(0))();
  IntColumn get effCat4Day => integer().nullable()();

  /// Pondeuses uniquement — voir BR-ELV-008. Ces 3 colonnes sont des
  /// **resultats calcules**, jamais des saisies.
  IntColumn get srh => integer().nullable()();
  IntColumn get ts => integer().nullable()();
  IntColumn get stockFinalOeufs => integer().nullable()();

  // ⚠️ COLONNES AJOUTEES — Doc D1 ne stockait que les 3 resultats ci-dessus,
  // et AUCUNE des 3 saisies qui les produisent. Sans elles :
  //   - rouvrir un jour deja saisi perdait les valeurs entrees ;
  //   - la cascade de Doc 05 §5, qui doit recalculer SRH/TS/Stock Final des
  //     jours suivants, n'avait pas les entrees necessaires pour le faire.
  // C'est precisement le scenario du bug le plus grave du projet.
  IntColumn get oeufsPondus => integer().nullable()();
  IntColumn get oeufsCasses => integer().nullable()();

  /// Sorties en plateaux de 30 oeufs.
  IntColumn get sortiesPlateaux => integer().nullable()();

  /// Pesee totale du lot, en grammes (`day-pesee-total` du prototype,
  /// persiste sous `day.poidsGeneralG`, fiche-goliaths.html l.709).
  ///
  /// ⚠️ Colonne ABSENTE de Doc D1, ajoutee ici apres verification du JS reel :
  /// le prototype sauvegarde bien ce champ. Sans elle, ni le poids moyen ni le
  /// GMQ du Dashboard Élevage (Doc F2) ne sont calculables.
  IntColumn get poidsGeneralG => integer().nullable()();

  /// Observation de traitement du jour (`day-traitement-obs`).
  TextColumn get traitementObs => text().nullable()();

  /// Traitement du jour valide (`day-traitement-validated`).
  BoolColumn get traitementValide =>
      boolean().withDefault(const Constant(false))();

  /// Distingue un jour reellement saisi d'un jour projete/vide.
  BoolColumn get isRecorded => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {espece, date},
  ];
}
