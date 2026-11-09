import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Table `FICHE_JOURNEE` — Doc D1 §2. Une ligne par espece et par jour.
///
/// `effectif` et les sous-effectifs `effCat*Day` sont **calcules, jamais
/// saisis** (BR-ELV-007) : le formulaire de saisie journaliere ne doit pas
/// exposer de champ editable pour eux (Doc E6 §3).
///
/// ## Synchronisation (schema v38, DV-19, `46a_`)
///
/// `id` est un UUID **deterministe** de (espece, date) : deux postes qui saisissent
/// le meme jour convergent sur la MEME ligne (dernier ecrivain gagne, ligne entiere),
/// jamais sur deux lignes qui violeraient `UNIQUE(espece, date)`. Voir
/// `FicheElevageRepositoryDrift.identifiantDuJour`.
@DataClassName('FicheJourneeRow')
class FicheJournee extends Table {
  TextColumn get id => text().clientDefault(nouvelUuid)();

  /// 'goliaths','pintades','lapins','poulets','pondeuses','poissons-chats','escargots','bovins'
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

  // ------------------------------------------------------- Synchronisation
  //
  // Colonnes communes a toute table synchronisee (`46_` §1). `device_id` n'est
  // PAS stocke : le serveur le deduit du jeton.

  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  TextColumn get syncMotif => text().nullable()();

  /// Instant de **saisie** (UTC, microsecondes) : il departage deux postes.
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  // ------------------------------------------------- Divergence (schema v47, `47e_`)
  //
  // « Dernier ecrivain gagne » perdait EN SILENCE la saisie de l'autre poste quand deux
  // postes saisissaient la meme fiche sans se voir. Desormais la divergence est detectee,
  // marquee et c'est l'utilisatrice qui choisit la version a garder.

  /// Instant (`updated_at` du serveur) de la version DONT CETTE FICHE EST PARTIE : celle
  /// qu'on a tiree ou envoyee en dernier. Il est envoye avec la fiche (`base_updated_at`) :
  /// le serveur sait ainsi si le poste avait vu la version courante (modification
  /// successive normale) ou non (divergence). `null` : aucune version du serveur connue.
  TextColumn get baseMaj => text().nullable()();

  /// Les AUTRES versions de la meme fiche (JSON : liste de `{origine, updated_at,
  /// contenu}`), tant que la divergence n'est pas resolue. Non `null` = « modifiee
  /// ailleurs ».
  TextColumn get variantes => text().nullable()();

  /// Vrai quand cette ecriture RESOUT une divergence (l'utilisatrice a choisi) : le
  /// serveur efface alors les variantes. Remis a faux a l'accuse.
  BoolColumn get resolution => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {espece, date},
  ];
}
