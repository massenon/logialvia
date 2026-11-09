import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Table `EXERCICE_COMPTABLE` — Doc D1 §2.
@DataClassName('ExerciceRow')
class ExerciceComptable extends Table {
  /// Ex. 2026.
  IntColumn get annee => integer()();

  /// BR-CPT-001 — verrouillage **définitif**, aucun mécanisme de déclôture.
  BoolColumn get isCloture => boolean().withDefault(const Constant(false))();

  DateTimeColumn get dateCloture => dateTime().nullable()();

  // --- Synchronisation (`46d_` §2) ---
  //
  // La clé reste l'**année** (clé naturelle, partagée par tous les postes : deux
  // postes qui ouvrent 2026 ouvrent le MÊME exercice). `sync_status` ne parle que
  // de la **clôture** : `pending` = clôture faite ici, pas encore acceptée par le
  // serveur ; `synced` = rien à envoyer (exercice ouvert, ou clôture acceptée) ;
  // `conflict` = clôture refusée par le serveur (l'exercice est alors rouvert ici,
  // le motif est gardé).
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  TextColumn get syncMotif => text().nullable()();
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {annee};
}

/// Table `PLAN_COMPTABLE` — Doc D1 §2.
@DataClassName('CompteRow')
class PlanComptable extends Table {
  /// Ex. '531' (Caisse), '701' (Ventes de Produits Avicoles).
  TextColumn get numeroCompte => text()();

  TextColumn get libelle => text()();

  /// Classe SYSCOHADA, 1 caractère de '1' à '7'.
  TextColumn get classe => text()();

  /// Un compte archivé n'est plus proposé à la saisie mais reste dans
  /// l'historique — l'écran Plan Comptable propose « Archiver », pas
  /// « Supprimer ».
  BoolColumn get archive => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {numeroCompte};
}

/// Table `ECRITURE_COMPTABLE` — Doc D1 §2.
///
/// **Partie double** : exactement un des deux champs `debit`/`credit` est
/// strictement positif, l'autre vaut 0. La contrainte est appliquée par le
/// domaine (`EcritureValidator`), pas seulement par convention.
@DataClassName('EcritureRow')
class EcritureComptable extends Table {
  /// UUID (DV-19) : une ligne d'écriture est un FAIT synchronisé, immuable une fois
  /// transmis.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  /// UUID commun à toutes les lignes d'une **pièce** (partie double). La pièce est
  /// l'unité de synchronisation : elle voyage entière, équilibrée ou refusée.
  /// Le numéro de pièce, lui, n'est PAS unique (`REG-V-…` revient à chaque
  /// règlement partiel d'une même vente).
  TextColumn get pieceId => text().clientDefault(nouvelUuid)();

  IntColumn get exerciceAnnee =>
      integer().references(ExerciceComptable, #annee)();

  TextColumn get numeroCompte =>
      text().references(PlanComptable, #numeroCompte)();

  DateTimeColumn get dateEcriture => dateTime()();

  RealColumn get debit => real().withDefault(const Constant(0))();
  RealColumn get credit => real().withDefault(const Constant(0))();

  TextColumn get libelle => text()();

  /// ⚠️ AJOUTEE — code journal (VT ventes, AC achats, CA caisse, OD opérations
  /// diverses). Absent de Doc D1, mais un journal comptable sans code journal
  /// n'est pas un journal : c'est la colonne qui permet de produire les
  /// journaux auxiliaires exigés par SYSCOHADA.
  TextColumn get journalCode => text().withDefault(const Constant('OD'))();

  /// Référence de pièce — n° de vente, d'achat, ou pièce interne.
  TextColumn get numeroPiece => text().nullable()();

  /// Origine automatique (BR-CPT-003).
  TextColumn get venteRef => text().nullable()();
  TextColumn get achatRef => text().nullable()();

  /// Centre analytique auquel la ligne est imputée — « Goliaths », « Pintades »,
  /// « Commerce Annexe »…
  ///
  /// ⚠️ Absent du modèle jusqu'ici, ce qui limitait la Comptabilité Analytique
  /// à ce qu'on pouvait **deviner depuis le numéro de compte** : 601 et 622
  /// pour l'avicole, 602 pour le commerce annexe. Une facture d'électricité
  /// (628) ou un transport (624) restait donc en « charges non affectées », et
  /// la marge par filière était incomplète. Pire : l'avicole n'était qu'un
  /// bloc, alors que `comptabilite-analytique.html` l.146-149 ventile bien
  /// **Goliaths** et **Pintades** séparément.
  ///
  /// `null` = non imputé. La ligne retombe alors sur l'heuristique du numéro
  /// de compte, et à défaut dans les charges non affectées — jamais répartie
  /// au prorata de quoi que ce soit : une clé de répartition inventée
  /// donnerait des marges par filière fausses avec l'air d'être exactes.
  TextColumn get axeAnalytique => text().nullable()();

  /// Vrai si l'exercice parent est clôturé.
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();

  /// `piece_id` de la pièce que celle-ci **contrepasse** (annulation d'une pièce
  /// déjà transmise : un fait synchronisé ne se modifie ni ne se supprime, il
  /// s'annule par l'écriture inverse). `null` pour une pièce ordinaire.
  TextColumn get contrepasseDe => text().nullable()();

  /// D'où vient cette ligne : `null` = CE poste ; sinon l'identifiant du poste
  /// qui l'a saisie. La ligne d'un autre poste compte au grand livre (le grand
  /// livre de chaque poste est la somme de TOUS les faits) mais ne se modifie
  /// jamais ici, et son arrivée n'a engendré AUCUNE écriture locale.
  TextColumn get origine => text().nullable()();

  // --- Synchronisation (`46d_` §2) ---

  /// `pending` · `synced` · `conflict` (refusée par le serveur, voir `syncMotif`).
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get syncMotif => text().nullable()();

  /// Instant de SAISIE de la pièce (UTC, ISO 8601, microsecondes).
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Table `NOTES_ANNEXES` — Doc D1 §2, obligatoire en SYSCOHADA (Doc F6 §4).
@DataClassName('NoteAnnexeRow')
class NotesAnnexes extends Table {
  /// UUID **déterministe** de (exercice, numéro) : deux postes qui rédigent la
  /// note 1 de 2026 la désignent par le même identifiant (« dernier écrivain
  /// gagne »), sans doublon.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  IntColumn get exerciceAnnee =>
      integer().references(ExerciceComptable, #annee)();

  /// 1 à 5 — voir Doc F6 §4 Onglet 4 pour le contenu attendu de chacune.
  IntColumn get numeroNote => integer()();

  TextColumn get titre => text()();
  TextColumn get contenu => text()();

  // --- Synchronisation (`46d_` §2) ---
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get syncMotif => text().nullable()();
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {exerciceAnnee, numeroNote},
  ];
}

/// Table `CLOTURES_PERIODIQUES` — Doc D1 §2, BR-CPT-006.
@DataClassName('CloturePeriodiqueRow')
class CloturesPeriodiques extends Table {
  IntColumn get annee => integer()();
  IntColumn get mois => integer()();

  BoolColumn get isCloture => boolean().withDefault(const Constant(false))();
  DateTimeColumn get dateCloture => dateTime().nullable()();

  /// Traçabilité du déblocage exceptionnel (BR-ADM-003), rôle `admin`
  /// uniquement.
  TextColumn get declotureParUtilisateurId => text().nullable()();

  // --- Synchronisation (`46d_` §2) ---
  // Clé naturelle (année, mois) : l'identifiant du fil est dérivé
  // (`uuidDeterministe('cloture-periodique:AAAA-M')`), jamais stocké.
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get syncMotif => text().nullable()();
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {annee, mois};
}
