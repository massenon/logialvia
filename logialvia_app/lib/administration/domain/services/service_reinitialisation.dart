import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/seed/seed_initial.dart';

/// Ce qu'une réinitialisation efface, et ce qu'elle préserve.
class BilanReinitialisation {
  const BilanReinitialisation({
    required this.lignesEffacees,
    required this.tablesEffacees,
  });

  final int lignesEffacees;
  final List<String> tablesEffacees;
}

/// Réinitialisation des **données de test** — onglet des Paramètres Généraux.
///
/// ## Ce qu'elle efface, et ce qu'elle ne touche jamais
///
/// La distinction n'est pas « données du seeder / données saisies » : ce
/// serait intenable, puisque la Gérante modifie le catalogue semé dès le
/// premier jour. Elle est **fonctionnelle** :
///
/// | Effacé | Préservé |
/// |---|---|
/// | ce qui décrit une **activité** — ventes, achats, écritures, fiches, lots, soins, mouvements | ce qui décrit l'**exploitation** — comptes, rôles, paramètres, plan comptable, barèmes, catalogue, intrants |
///
/// Autrement dit : après une réinitialisation, l'application est prête à
/// travailler, elle n'a simplement rien fait encore. C'est exactement l'état
/// qu'on veut après une période d'essai.
///
/// **Ne sont jamais touchés** : `utilisateurs`, `roles`, `permissions_role`,
/// `parametres_entreprise`, `modules_actifs`, `preferences_poste`,
/// `baremes_ration`, `calendrier_prophylaxie`, `produits_vendables`,
/// `intrants`, `groupes_taxe`, et les journaux `audit_logs` /
/// `security_logs`.
///
/// ## Le référentiel comptable SYSCOHADA survit toujours
///
/// `plan_comptable` et `exercice_comptable` ne sont **jamais** vidés. Ce sont
/// la configuration comptable de l'exploitation, pas son activité : les
/// effacer rendrait le logiciel incapable d'enregistrer la moindre écriture
/// tant que quelqu'un n'aurait pas re-semé le plan de comptes.
///
/// ## Pourquoi les écritures, elles, partent
///
/// Elles décrivent l'activité, et **une dépense n'existe que sous forme
/// d'écriture** : il n'y a pas de table des dépenses. Effacer les ventes et
/// les dépenses en conservant leurs écritures laisserait un journal qui
/// affirme un chiffre d'affaires derrière lequel il n'y a plus aucune vente —
/// des livres faux, ce qui est pire que des livres vides.
///
/// ⚠️ Les **journaux d'audit sont conservés** délibérément. Une opération qui
/// efface l'activité *et* la trace de qui l'a effacée n'est pas une
/// réinitialisation, c'est un effacement de preuves.
class ServiceReinitialisation {
  const ServiceReinitialisation(this._db);

  final AppDatabase _db;

  /// Tables vidées, dans un ordre qui respecte les clés étrangères : les
  /// enfants avant les parents.
  static const List<String> tablesOperationnelles = [
    // Commercial
    'lignes_vente',
    'ventes',
    'devis',
    'clients',
    // Approvisionnement
    'lignes_achat',
    'achats',
    // ✓ ARBITRE PAR LA GERANTE : les fournisseurs partent avec l'activite,
    // comme les clients. Ils etaient preserves au motif qu'un fournisseur
    // ressemble a du referentiel ; un fournisseur saisi pendant l'essai n'en
    // est pas un. L'ordre compte : `achats.fournisseurId` les reference, donc
    // les achats d'abord.
    'fournisseurs',
    'mouvements_intrant',
    // Palier 6 : le journal des corrections de stock des produits.
    'mouvements_produit',
    // Comptabilite
    'ecriture_comptable',
    'notes_annexes',
    'clotures_periodiques',
    // Elevage
    'fiche_ventes_jour',
    'fiche_journee',
    'cycle_couveuse',
    'machines_incubateur',
    // Ajoutee en v25, apres l'ecriture de ce service : sans elle, une remise a
    // zero laissait les bandes en place et les fiches repartaient sur un cycle
    // dont plus aucune journee ne temoignait.
    'bandes',
    'soins_calendrier',
    'infirmerie',
    // Corbeille : son contenu ne designe plus rien apres la remise a zero.
    'corbeille',
  ];

  /// Compte ce qui serait effacé, **sans rien effacer**.
  ///
  /// C'est ce que la modale d'avertissement affiche : « 412 lignes seront
  /// effacées » se refuse autrement que sur un chiffre réel.
  Future<Map<String, int>> apercu() async {
    final compte = <String, int>{};
    for (final table in tablesOperationnelles) {
      final ligne = await _db
          .customSelect('SELECT COUNT(*) AS n FROM $table')
          .getSingle();
      final n = ligne.read<int>('n');
      if (n > 0) compte[table] = n;
    }
    return compte;
  }

  /// Vide les tables d'activité, puis rejoue les seeders de référence.
  ///
  /// Tout dans **une transaction** : une réinitialisation à moitié faite
  /// laisserait des écritures comptables sans les ventes qui les justifient.
  /// [parIdentifiant] — qui déclenche la remise à zéro. L'opération est
  /// tracée sous ce nom.
  Future<BilanReinitialisation> executer({String parIdentifiant = ''}) async {
    final avant = await apercu();

    await _db.transaction(() async {
      // Les cles etrangeres sont desactivees le temps du vidage : l'ordre
      // suffit dans le cas nominal, mais une base ayant traverse plusieurs
      // migrations peut porter des references qu'on ne veut pas voir bloquer
      // une remise a zero volontaire.
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final table in tablesOperationnelles) {
        await _db.customStatement('DELETE FROM $table');
      }
    });

    // Hors transaction : les seeders ouvrent leurs propres transactions, et
    // les imbriquer bloquerait SQLite.
    //
    // Ils sont idempotents et **completifs** : ils ne reecrivent pas ce que la
    // Gerante a modifie. Leur role ici est de garantir qu'un exercice
    // comptable est ouvert et que le plan est complet — sans quoi aucune
    // ecriture ne pourrait plus etre saisie apres la remise a zero.
    await SeedInitial(_db).executer();

    final lignes = avant.values.fold(0, (s, n) => s + n);

    // La trace de l'opération elle-même.
    //
    // Le journal d'audit était bien préservé, mais rien n'y était inscrit :
    // après une remise à zéro, il ne restait aucune trace disant qu'elle avait
    // eu lieu, ni qui l'avait lancée. Constaté sur une base réelle — treize
    // tables vides, quarante-quatre entrées d'audit, toutes des connexions.
    //
    // Elle est écrite **après** le vidage : inscrite avant, elle aurait été
    // effacée par le `DELETE` si `audit_logs` venait un jour à rejoindre les
    // tables opérationnelles.
    await _db
        .into(_db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            horodatage: DateTime.now(),
            utilisateurId: parIdentifiant,
            action: 'reinitialisation',
            entiteConcernee: 'Donnees de test',
            entiteId: '${avant.keys.length} tables',
            details: Value(
              '{"lignes_effacees":$lignes,'
              '"tables":"${avant.keys.join(',')}"}',
            ),
          ),
        );

    return BilanReinitialisation(
      lignesEffacees: lignes,
      tablesEffacees: avant.keys.toList(),
    );
  }
}
