import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

import 'fournisseurs_table.dart';
import 'intrants_table.dart';

/// Table `ACHATS` — Doc D1 §2, « structure symétrique à VENTES ».
@DataClassName('AchatRow')
class Achats extends Table {
  /// UUID de l'achat (DV-19) : l'identite SYNCHRONISEE. La cle primaire reste [ref]
  /// (les lignes, les ecritures et les mouvements s'y rattachent par texte) ; `ref`
  /// est le numero OFFICIEL (`ACH-P2-2026-001`, DV-21), jamais renumerote.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  /// Format 'ACH-AAAA-NNN'.
  TextColumn get ref => text()();

  TextColumn get fournisseurId => text().references(Fournisseurs, #id)();

  DateTimeColumn get dateAchat => dateTime()();

  /// 'Commandé', 'Livré', 'Annulé'
  TextColumn get statut => text()();

  RealColumn get total => real()();

  /// ⚠️ AJOUTEE — symetrique de `VENTES.paye`, indispensable au tableau des
  /// dettes fournisseurs (« Déjà Réglé » / « Solde Dû », fournisseurs.html
  /// l.162-163). Doc D1 ne la prevoyait pas, rendant ce tableau incalculable.
  RealColumn get paye => real().withDefault(const Constant(0))();

  /// ⚠️ AJOUTEE — colonne « Mode » du tableau des achats
  /// (`achats-commandes.html` l.190), symetrique de `VENTES.mode`.
  TextColumn get mode => text().nullable()();

  /// Date d'exigibilité d'une dette fournisseur.
  ///
  /// ⚠️ Même défaut que côté ventes : les rapports datent l'échéance au jour
  /// de l'achat. Le prototype fait pire — sa seule dette est datée de la
  /// **veille** de l'achat qu'elle règle. `null` = aucun délai convenu.
  DateTimeColumn get echeance => dateTime().nullable()();

  // --- Synchronisation (`46_` §1) ---

  /// `pending` · `synced` · `conflict`.
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get syncMotif => text().nullable()();

  /// Instant de SAISIE (UTC, ISO 8601, microsecondes).
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {ref};

  @override
  List<Set<Column>> get uniqueKeys => [
    {id},
  ];
}

/// Table `LIGNES_ACHAT` — Doc D1 §2.
@DataClassName('LigneAchatRow')
class LignesAchat extends Table {
  /// UUID (DV-19) : une ligne d'achat est un fait synchronise.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  TextColumn get achatRef =>
      text().references(Achats, #ref, onDelete: KeyAction.cascade)();

  TextColumn get intrantCode => text().references(Intrants, #code)();

  /// Nom de l'intrant **au moment de l'achat** — meme denormalisation
  /// volontaire que `LIGNES_VENTE.name` (Doc D1).
  TextColumn get nom => text()();

  RealColumn get qte => real()();
  RealColumn get puAchat => real()();

  @override
  Set<Column> get primaryKey => {id};
}
