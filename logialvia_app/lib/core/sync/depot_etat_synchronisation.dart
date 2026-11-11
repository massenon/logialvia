import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// État de synchronisation d'une table du poste.
class EtatTableSynchro {
  const EtatTableSynchro({
    required this.table,
    required this.libelle,
    required this.enAttente,
    required this.synchronisees,
    required this.refusees,
  });

  /// Nom de la table dans la base du poste.
  final String table;
  final String libelle;

  /// `pending` : saisies pas encore envoyées.
  final int enAttente;

  /// `synced` : lignes que le serveur a.
  final int synchronisees;

  /// `conflict` : lignes que le serveur a refusées.
  final int refusees;

  int get total => enAttente + synchronisees + refusees;

  bool get conforme => refusees == 0;
}

/// Une ligne que le serveur a refusée.
class LigneRefusee {
  const LigneRefusee({
    required this.table,
    required this.libelleTable,
    required this.id,
    required this.designation,
    required this.motif,
    required this.remisePossible,
  });

  final String table;
  final String libelleTable;
  final String id;

  /// Ce qui permet de reconnaître la ligne (référence, nom, désignation…), sinon son identifiant.
  final String designation;
  final String motif;

  /// « Remettre en file » a un sens pour cette ligne. Faux pour les clôtures : un refus y a déjà
  /// rouvert la période ici ; il faut la REFAIRE depuis Comptabilité, pas renvoyer l'ancien état.
  final bool remisePossible;
}

/// Ce que le poste sait, table par table, de l'état de ses lignes (`pending`,
/// `synced`, `conflict`) — sans rien demander au serveur.
///
/// Générique : une table est « synchronisée » dès qu'elle porte `sync_status`
/// et `sync_motif` ; sa clé est `id`, ou à défaut `rowid` (les clôtures ont pour clé l'année) (comme la remise en attente des refus de droit, `47g_`).
class DepotEtatSynchronisation {
  DepotEtatSynchronisation(this._db);

  final AppDatabase _db;

  /// Tables dont un refus se règle autrement qu'en renvoyant la ligne (clôtures).
  static const Set<String> _sansRemiseEnFile = {
    'exercice_comptable',
    'clotures_periodiques',
  };

  /// Colonnes qui aident à reconnaître une ligne refusée, par ordre de préférence.
  static const List<String> _colonnesDesignation = [
    'annee',
    'reference',
    'designation',
    'nom',
    'libelle',
    'intitule',
    'sujet',
  ];

  /// Libellés des tables que l'utilisatrice connaît ; les autres : le nom lisible.
  static const Map<String, String> _libelles = {
    'clients': 'Clients',
    'fournisseurs': 'Fournisseurs',
    'achats': 'Achats',
    'intrants': 'Intrants',
    'mouvements_intrant': 'Mouvements d\'intrants',
    'produits_vendables': 'Produits',
    'mouvements_produit': 'Mouvements de produits',
    'ventes': 'Ventes',
    'devis': 'Devis',
    'factures': 'Factures MeCeF',
    'groupes_taxe': 'Groupes de taxe',
    'ecriture_comptable': 'Écritures comptables',
    'exercice_comptable': 'Exercices comptables',
    'plan_comptable': 'Plan comptable',
    'notes_annexes': 'Notes annexes',
    'clotures_periodiques': 'Clôtures mensuelles',
    'clotures_exercice': 'Clôtures annuelles',
    'bandes': 'Bandes',
    'fiche_journee': 'Fiches journalières',
    'fiche_ventes_jour': 'Ventes du jour (fiches)',
    'cycle_couveuse': 'Cycles de couveuse',
    'machines_incubateur': 'Machines d\'incubation',
    'soins_calendrier': 'Soins et calendrier',
    'infirmerie': 'Infirmerie',
    'baremes_ration': 'Barèmes de ration',
    'taux_ration_poids': 'Taux de ration',
    'calendrier_prophylaxie': 'Calendrier de prophylaxie',
    'messages_editeur': 'Messages à l\'éditeur',
    'modules_actifs': 'Modules actifs',
    'parametres_entreprise': 'Paramètres de l\'entreprise',
    'effets_stock': 'Effets de stock',
    'effets_appliques': 'Effets de stock appliqués',
    'demandes_referentiel': 'Demandes de réglages',
  };

  static String libelleTable(String table) =>
      _libelles[table] ??
      () {
        final lisible = table.replaceAll('_', ' ');
        return lisible.isEmpty
            ? table
            : '${lisible[0].toUpperCase()}${lisible.substring(1)}';
      }();

  Future<Set<String>> _colonnes(String table) async {
    final lignes = await _db.customSelect('PRAGMA table_info("$table")').get();
    return {for (final l in lignes) l.read<String>('name')};
  }

  /// Tables du poste qui portent l'état de synchronisation.
  Future<List<String>> tablesSynchronisees() async {
    final noms = <String>[];
    for (final t in _db.allTables) {
      final colonnes = await _colonnes(t.actualTableName);
      if (colonnes.contains('sync_status') && colonnes.contains('sync_motif')) {
        noms.add(t.actualTableName);
      }
    }
    noms.sort();
    return noms;
  }

  /// Une ligne par table synchronisée qui contient quelque chose.
  Future<List<EtatTableSynchro>> parTable() async {
    final etats = <EtatTableSynchro>[];
    for (final table in await tablesSynchronisees()) {
      final ligne = await _db
          .customSelect(
            'SELECT '
            "COALESCE(SUM(sync_status = 'pending'), 0) AS en_attente, "
            "COALESCE(SUM(sync_status = 'synced'), 0) AS synchronisees, "
            "COALESCE(SUM(sync_status = 'conflict'), 0) AS refusees "
            'FROM "$table"',
          )
          .getSingle();
      final etat = EtatTableSynchro(
        table: table,
        libelle: libelleTable(table),
        enAttente: ligne.read<int>('en_attente'),
        synchronisees: ligne.read<int>('synchronisees'),
        refusees: ligne.read<int>('refusees'),
      );
      if (etat.total > 0) etats.add(etat);
    }
    etats.sort((a, b) => a.libelle.compareTo(b.libelle));
    return etats;
  }

  /// Saisies en attente d'envoi, toutes tables confondues.
  Future<int> totalEnAttente() async {
    var total = 0;
    for (final e in await parTable()) {
      total += e.enAttente;
    }
    return total;
  }

  /// Lignes refusées par le serveur (toutes les tables, ou [table]).
  Future<List<LigneRefusee>> refusees({String? table}) async {
    final lignes = <LigneRefusee>[];
    for (final t in await tablesSynchronisees()) {
      if (table != null && t != table) continue;
      final colonnes = await _colonnes(t);
      final cle = colonnes.contains('id') ? 'id' : 'rowid';
      final designation = _colonnesDesignation.firstWhere(
        colonnes.contains,
        orElse: () => cle,
      );
      final resultat = await _db
          .customSelect(
            'SELECT CAST($cle AS TEXT) AS cle, '
            'CAST("$designation" AS TEXT) AS designation, sync_motif '
            'FROM "$t" WHERE sync_status = \'conflict\' ORDER BY $cle',
          )
          .get();
      for (final r in resultat) {
        final id = r.read<String>('cle');
        lignes.add(
          LigneRefusee(
            table: t,
            libelleTable: libelleTable(t),
            id: id,
            designation: r.readNullable<String>('designation') ?? id,
            motif: r.readNullable<String>('sync_motif') ?? 'Motif non précisé',
            remisePossible: !_sansRemiseEnFile.contains(t),
          ),
        );
      }
    }
    return lignes;
  }

  /// Remet « en attente » des lignes refusées : [id] (avec [table]), toute une
  /// [table], ou toutes. Elles repartent à la prochaine synchronisation. Renvoie
  /// le nombre de lignes remises en file.
  Future<int> remettreEnFile({String? table, String? id}) async {
    var remises = 0;
    for (final t in await tablesSynchronisees()) {
      if (table != null && t != table) continue;
      if (_sansRemiseEnFile.contains(t)) continue;
      final where = id == null ? '' : ' AND id = ?';
      final n = await _db.customUpdate(
        'UPDATE "$t" SET sync_status = \'pending\', sync_motif = NULL '
        'WHERE sync_status = \'conflict\'$where',
        variables: [if (id != null) Variable<String>(id)],
        updates: {_db.allTables.firstWhere((x) => x.actualTableName == t)},
      );
      remises += n;
    }
    return remises;
  }
}
