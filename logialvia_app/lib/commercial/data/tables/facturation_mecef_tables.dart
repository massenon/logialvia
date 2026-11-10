import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Les tables de la facturation normalisée MeCeF.
///
/// ## Ce que MeCeF exige, et ce que ce logiciel peut en faire
///
/// La MeCeF (Machine Électronique Certifiée Fiscalement) est le dispositif
/// béninois de facturation normalisée. Une facture n'est **normalisée** que
/// lorsque la DGI lui a attribué un code, un NIM et un compteur — ce qui
/// suppose une transmission. LogiALVIA fonctionne hors ligne : il ne peut donc
/// pas normaliser une facture tout seul.
///
/// Le choix retenu est de ne jamais faire semblant. Une facture naît « à
/// transmettre » ; elle ne devient « normalisée » que quand les champs rendus
/// par la DGI sont réellement présents. Le document imprimé porte la mention
/// correspondante, et rien d'autre.
///
/// ⚠️ **Les lettres des groupes de taxe ne sont pas codées en dur.** La grille
/// officielle relève de la DGI et n'a pas été vérifiée pièce en main : la
/// figer dans le code reviendrait à affirmer un barème fiscal sur la foi d'un
/// souvenir. Elle vit donc dans [GroupesTaxe], modifiable, et n'est amorcée
/// qu'avec ce dont on est certain — exonéré et 18 %.

/// Table `GROUPES_TAXE` — la grille de taxation appliquée aux lignes.
@DataClassName('GroupeTaxeRow')
class GroupesTaxe extends Table {
  /// Lettre du groupe : 'A', 'B', … telle qu'elle figure sur la facture.
  TextColumn get code => text()();

  /// Libellé lisible — « Exonéré », « Taux normal 18 % ».
  TextColumn get libelle => text()();

  /// Taux en pourcentage. `0` pour un groupe exonéré.
  RealColumn get taux => real()();

  /// Ordre d'affichage dans les sélecteurs.
  IntColumn get ordre => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {code};
}

/// Table `FACTURES` — factures de vente (FV) et factures d'avoir (FA).
///
/// Une facture d'avoir ne modifie **jamais** la facture qu'elle corrige : elle
/// la contrepasse, en la désignant par [origineRef]. C'est la même règle que
/// pour les écritures comptables, et pour la même raison — une pièce émise ne
/// se réécrit pas.
@DataClassName('FactureRow')
class Factures extends Table {
  /// UUID de la facture (DV-19) : l'identite SYNCHRONISEE. La cle primaire reste
  /// [ref] (les lignes et les ventes s'y rattachent par texte) ; `ref` est le
  /// numero OFFICIEL de la piece (`FV-P2-2026-001`, DV-21), jamais renumerote.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  /// `null` : facture emise sur CE poste. Sinon l'identifiant du poste qui l'a
  /// emise (facture absorbee du serveur). **Seul le poste emetteur transmet** a la
  /// DGI : une facture d'un autre poste n'offre ni transmission ni saisie
  /// manuelle, pour qu'elle ne soit pas normalisee deux fois (`46e_` §3).
  TextColumn get origine => text().nullable()();

  // --- Synchronisation (`46_` §1) ---

  /// `pending` · `synced` · `conflict`.
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get syncMotif => text().nullable()();

  /// Instant de SAISIE (UTC, ISO 8601, microsecondes) : emission, puis derniere
  /// transmission ou saisie du code. Jamais l'instant d'envoi.
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  /// 'FV-P2-2026-001' / 'FA-P2-2026-001' (poste appaire) ou 'FV-2026-001'.
  TextColumn get ref => text()();

  /// [TypeFacture.vente] ou [TypeFacture.avoir].
  TextColumn get type => text()();

  /// Vente d'origine. `null` pour une facture saisie sans passage en caisse.
  TextColumn get venteRef => text().nullable()();

  /// Facture corrigée — obligatoire sur un avoir, toujours nulle sur une
  /// facture de vente.
  TextColumn get origineRef => text().nullable()();

  DateTimeColumn get dateFacture => dateTime()();

  TextColumn get client => text()();

  /// IFU du client. Facultatif : un particulier n'en a pas.
  TextColumn get clientIfu => text().nullable()();

  TextColumn get clientAdresse => text().nullable()();

  RealColumn get totalHt => real()();
  RealColumn get totalTaxe => real()();
  RealColumn get totalTtc => real()();

  /// Motif de l'avoir — erreur de facturation, retour, annulation.
  TextColumn get motif => text().nullable()();

  /// `aTransmettre`, `normalisee` ou `rejetee`. Voir `StatutFacture`.
  TextColumn get statut => text()();

  // --- Champs rendus par la DGI, tous nuls tant qu'ils ne l'ont pas ete ---

  /// Code MeCeF/DGI de normalisation.
  TextColumn get codeMecef => text().nullable()();

  /// Numéro d'Identification de la Machine ayant normalisé la facture.
  TextColumn get nim => text().nullable()();

  /// Compteur de la DGI, tel quel : « 12/50 ».
  TextColumn get compteur => text().nullable()();

  /// Lien de vérification renvoyé par la DGI, imprimé en clair sous la
  /// facture. Aucun QR n'est dessiné tant qu'on n'a pas ce lien : un QR
  /// fabriqué localement ne vérifierait rien.
  TextColumn get lienVerification => text().nullable()();

  DateTimeColumn get dateNormalisation => dateTime().nullable()();

  /// Message d'erreur de la dernière tentative de transmission, s'il y en a
  /// eu une. Sert à expliquer un statut `rejetee` plutôt qu'à le subir.
  TextColumn get erreurTransmission => text().nullable()();

  DateTimeColumn get creeLe => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {ref};

  @override
  List<Set<Column>> get uniqueKeys => [
    {id},
  ];
}

/// Table `LIGNES_FACTURE`.
///
/// Les montants sont **figés à l'émission**. Une facture est une pièce : elle
/// ne doit pas changer parce que le tarif du catalogue a bougé depuis.
@DataClassName('LigneFactureRow')
class LignesFacture extends Table {
  /// UUID (DV-19) : une ligne de facture est un fait synchronise, et voyage DANS
  /// sa facture, jamais seule.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  TextColumn get factureRef => text()();

  TextColumn get designation => text()();

  RealColumn get quantite => real()();

  TextColumn get unite => text().nullable()();

  /// Prix unitaire hors taxe, tel que facturé.
  RealColumn get prixUnitaireHt => real()();

  /// Lettre du groupe de taxe appliqué, recopiée du produit à l'émission.
  TextColumn get groupeTaxe => text()();

  /// Taux appliqué, figé lui aussi : un barème qui change plus tard ne doit
  /// pas réécrire une facture déjà émise.
  RealColumn get tauxTaxe => real()();

  RealColumn get montantHt => real()();
  RealColumn get montantTaxe => real()();

  @override
  Set<Column> get primaryKey => {id};
}
