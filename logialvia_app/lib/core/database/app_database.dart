import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../administration/data/seed/modules_actifs_seeder.dart';
import '../../elevage/data/seed/parametres_elevage_seeder.dart';
import '../../administration/data/tables/audit_logs_table.dart';
import '../../administration/data/tables/messages_editeur_table.dart';
import '../../administration/data/tables/corbeille_table.dart';
import '../../administration/data/tables/preferences_poste_table.dart';
import '../../administration/data/tables/modules_actifs_table.dart';
import '../../administration/data/tables/parametres_entreprise_table.dart';
import '../../administration/data/tables/permissions_role_table.dart';
import '../../administration/data/tables/roles_table.dart';
import '../../administration/data/tables/security_logs_table.dart';
import '../../administration/data/tables/utilisateurs_table.dart';
import '../../approvisionnement/data/tables/achats_table.dart';
import '../../approvisionnement/data/tables/fournisseurs_table.dart';
import '../../approvisionnement/data/tables/intrants_table.dart';
import '../../approvisionnement/data/tables/mouvements_intrant_table.dart';
import '../../commercial/data/tables/clients_table.dart';
import '../../commercial/domain/entities/vente.dart';
import '../../comptabilite/data/tables/comptabilite_tables.dart';
import '../../commercial/data/tables/devis_table.dart';
import '../../commercial/data/tables/facturation_mecef_tables.dart';
import '../../commercial/data/tables/lignes_vente_table.dart';
import '../../commercial/data/tables/produits_vendables_table.dart';
import '../../commercial/data/tables/ventes_table.dart';
import '../../elevage/data/tables/bandes_table.dart';
import '../../elevage/data/tables/cycle_couveuse_table.dart';
import '../../elevage/data/tables/fiche_journee_table.dart';
import '../../elevage/data/tables/fiche_ventes_jour_table.dart';
import '../../elevage/data/tables/infirmerie_table.dart';
import '../../elevage/data/tables/parametres_elevage_tables.dart';
import '../../elevage/data/tables/soins_calendrier_table.dart';

part 'app_database.g.dart';

/// Base SQLite locale — equivalent Flutter de la couche `logialvia-store.js`
/// du prototype (Doc A1 §5, Doc D1).
///
/// La base est infrastructure transverse : elle est volontairement placee dans
/// `core/` et non dans un Bounded Context, chaque contexte y declarant ses
/// propres tables (Doc C1 §6).
///
/// PERIMETRE ACTUEL : les tables sont ajoutees module par module, chacune avec
/// une montee de `schemaVersion` et un bloc `if (from < N)` explicite dans
/// `onUpgrade` — jamais par recreation destructive de la base (Doc D1 §3).
/// - v1 : module Authentification (Doc F1) — Roles, Utilisateurs,
///        PermissionsRole, AuditLogs, SecurityLogs
/// - v2 : module Pilotage (Doc F2) — les 10 tables interrogees par les 2
///        tableaux de bord
/// - v3 : module Production Elevage (Doc F3) — colonnes de pesee et de
///        traitement manquantes a `FICHE_JOURNEE`
/// - v4 : Cycle Couveuse (Doc F3) — `espece` et `oeufsPerdus` manquants a
///        `CYCLE_COUVEUSE`, `bandeReproducteurs` rendue nullable
/// - v5 : Calendrier de Soins (Doc F3) — 6 colonnes manquantes a
///        `SOINS_CALENDRIER`, et table `INFIRMERIE` entierement absente de D1
@DriftDatabase(
  tables: [
    // Administration
    Roles, Utilisateurs, PermissionsRole, AuditLogs, SecurityLogs, ModulesActifs,
    ParametresEntreprise, MessagesEditeur, PreferencesPoste, Corbeille,
    // Commercial
    ProduitsVendables, Clients, Ventes, LignesVente, Devis,
    GroupesTaxe, Factures, LignesFacture,
    // Approvisionnement
    Intrants, Fournisseurs, Achats, LignesAchat, MouvementsIntrant,
    // Elevage
    FicheJournee, FicheVentesJour, CycleCouveuse, MachinesIncubateur,
    SoinsCalendrier, Infirmerie, Bandes,
    BaremesRation, CalendrierProphylaxie, TauxRationPoids,
    // Comptabilite
    ExerciceComptable, PlanComptable, EcritureComptable, NotesAnnexes,
    CloturesPeriodiques,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_ouvrirConnexion());

  /// Constructeur dedie aux tests : base en memoire, jamais de fichier sur disque
  /// (Strict Avoid §6).
  AppDatabase.enMemoire() : super(NativeDatabase.memory());

  /// Ouvre un fichier de base **existant**, sans le creer ni le migrer.
  ///
  /// Sert a relire une sauvegarde pour verifier qu'elle est exploitable — la
  /// seule chose qui compte vraiment d'une sauvegarde.
  AppDatabase.pourFichier(File fichier) : super(NativeDatabase(fichier));

  /// Version du schema, lisible **sans instancier la base**.
  ///
  /// Le controle d'une sauvegarde a besoin de savoir jusqu'ou ce logiciel sait
  /// lire, et il a lieu avant toute ouverture de base.
  static const int versionSchema = 28;

  @override
  int get schemaVersion => versionSchema;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Ajout non destructif : les comptes utilisateurs deja crees en v1
        // (et le mot de passe eventuellement deja change) sont preserves.
        await _creerTable(m, modulesActifs);
        await _creerTable(m, produitsVendables);
        await _creerTable(m, clients);
        await _creerTable(m, ventes);
        await _creerTable(m, lignesVente);
        await _creerTable(m, intrants);
        await _creerTable(m, ficheJournee);
        await _creerTable(m, ficheVentesJour);
        await _creerTable(m, cycleCouveuse);
        await _creerTable(m, soinsCalendrier);
      }
      if (from < 3) {
        // `addColumn` prealable a toute saisie : aucune fiche journaliere ne
        // peut encore exister, mais la migration reste additive par principe
        // (Doc D1 §3) — jamais de recreation de table.
        await _ajouterColonne(m, ficheJournee, ficheJournee.poidsGeneralG);
        await _ajouterColonne(m, ficheJournee, ficheJournee.traitementObs);
        await _ajouterColonne(m, ficheJournee, ficheJournee.traitementValide);
      }
      if (from < 4) {
        await _ajouterColonne(m, cycleCouveuse, cycleCouveuse.espece);
        await _ajouterColonne(m, cycleCouveuse, cycleCouveuse.oeufsPerdus);
        // `bandeReproducteurs` passe de NOT NULL a nullable : SQLite ne sait
        // pas assouplir une contrainte par `ALTER`, il faut recreer la table.
        // Aucun cycle ne peut encore exister (l'ecran n'existait pas), donc
        // l'operation est sans perte ici — a ne PAS reproduire telle quelle sur
        // une table contenant des donnees reelles (Doc D1 §3).
        await m.alterTable(TableMigration(cycleCouveuse));
      }
      if (from < 5) {
        await _ajouterColonne(m, soinsCalendrier, soinsCalendrier.produit);
        await _ajouterColonne(m, soinsCalendrier, soinsCalendrier.dose);
        await _ajouterColonne(m, soinsCalendrier, soinsCalendrier.remanenceJours);
        await _ajouterColonne(m, soinsCalendrier, soinsCalendrier.veterinaire);
        await _ajouterColonne(m, soinsCalendrier, soinsCalendrier.symptomes);
        await _ajouterColonne(m, soinsCalendrier, soinsCalendrier.coutFcfa);
        await _creerTable(m, infirmerie);
      }
      if (from < 6) {
        // Saisies du suivi du stock d'oeufs (Pondeuses) — Doc D1 ne stockait
        // que les resultats, pas les entrees. Voir Doc H2.
        await _ajouterColonne(m, ficheJournee, ficheJournee.oeufsPondus);
        await _ajouterColonne(m, ficheJournee, ficheJournee.oeufsCasses);
        await _ajouterColonne(m, ficheJournee, ficheJournee.sortiesPlateaux);
      }
      if (from < 7) {
        await _creerTable(m, parametresEntreprise);
      }
      if (from < 8) {
        await _creerTable(m, devis);
      }
      if (from < 9) {
        await _ajouterColonne(m, produitsVendables, produitsVendables.sku);
        await _ajouterColonne(m, clients, clients.dateNaissance);
        await _ajouterColonne(m, clients, clients.dernierContact);
      }
      if (from < 10) {
        await _creerTable(m, fournisseurs);
        await _creerTable(m, achats);
        await _creerTable(m, lignesAchat);
        await _creerTable(m, mouvementsIntrant);
      }
      if (from < 11) {
        await _creerTable(m, exerciceComptable);
        await _creerTable(m, planComptable);
        await _creerTable(m, ecritureComptable);
        await _creerTable(m, notesAnnexes);
        await _creerTable(m, cloturesPeriodiques);
      }
      if (from < 12) {
        // Doc F3 — Parametres Elevage. Les 2 tables sont absentes de Doc D1 :
        // le prototype garde ses baremes dans des tableaux JavaScript, remis a
        // zero a chaque rechargement de page.
        await _creerTable(m, baremesRation);
        await _creerTable(m, calendrierProphylaxie);
        // Numerotation des bandes et sujets, jusqu'ici dans `localStorage`.
        await _ajouterColonne(m, parametresEntreprise, parametresEntreprise.prefixeEnclos);
        await _ajouterColonne(m, parametresEntreprise, parametresEntreprise.prefixeCage);
        await _ajouterColonne(m, parametresEntreprise, parametresEntreprise.prefixeBande);
        await _ajouterColonne(m, parametresEntreprise, parametresEntreprise.prefixeBassin);
      }
      if (from < 13) {
        // Doc F9 — Contactez l'Editeur. Le prototype affiche un toast de
        // succes sans rien envoyer ni conserver ; le message est desormais
        // persiste (Master Prompt §2.3).
        await _creerTable(m, messagesEditeur);
      }
      if (from < 14) {
        // Doc H1 — la modale « Livraison » du point de vente n'ecrivait rien :
        // `validateSale()` ne lit aucun de ses champs (Master Prompt §2.3).
        await _ajouterColonne(m, ventes, ventes.livraisonMode);
        await _ajouterColonne(m, ventes, ventes.livraisonFrais);
        await _ajouterColonne(m, ventes, ventes.livraisonAdresse);
        await _ajouterColonne(m, ventes, ventes.livraisonContact);
      }
      if (from < 15) {
        // Arbitrage de la Gerante : « Avance » est une CONDITION de paiement,
        // pas un mode de reglement. `VENTES.mode` ne conserve donc que
        // l'instrument (Especes, Mobile Money) ; la condition se lit sur
        // `status`, ou elle etait deja stockee.
        //
        // Les ventes anterieures qui portaient la condition dans `mode` n'ont
        // JAMAIS enregistre leur instrument reel : il est inconnu. On ecrit
        // « Non precise » plutot que de choisir « Especes » a leur place —
        // inventer une donnee absente serait pire que l'admettre.
        // `status` reste intact : ces ventes demeurent des ventes a credit.
        await customStatement(
          'UPDATE ventes SET mode = ? WHERE mode = ?',
          [ModeReglement.nonPrecise, 'Avance (Solde Restant Du)'],
        );
        await customStatement(
          'UPDATE ventes SET mode = ? WHERE mode = ?',
          [ModeReglement.nonPrecise, ConditionPaiement.avance],
        );
      }
      if (from < 16) {
        // Doc K2 §B — la modale « Choisir la ligne Mobile Money » exigeait un
        // choix que `validateSale()` ne conservait nulle part. La colonne rend
        // l'information reelle ; les ventes anterieures restent a NULL, ce qui
        // est exact : leur ligne creditee n'a jamais ete enregistree.
        await _ajouterColonne(m, ventes, ventes.ligneMobileMoney);
      }
      if (from < 17) {
        // Echeances de paiement. Les rapports affichaient une colonne
        // « Echeance » remplie avec la date de vente (ou d'achat) : toute
        // creance nee la veille etait declaree « En Retard », et la lettre de
        // relance branchee sur ce tableau reclamait un paiement non echu.
        //
        // Les lignes existantes restent a NULL : leur delai n'a jamais ete
        // convenu, elles ne peuvent donc pas etre en retard. Ecrire une date
        // a leur place inventerait la dette de quelqu'un.
        await _ajouterColonne(m, ventes, ventes.echeance);
        await _ajouterColonne(m, achats, achats.echeance);
        await _ajouterColonne(m, 
          parametresEntreprise,
          parametresEntreprise.delaiPaiementJours,
        );
      }
      if (from < 18) {
        // Cout de revient des produits finis. Le Rapport de Stocks valorisait
        // le stock au PRIX DE VENTE — le prototype remplit sa colonne
        // « CMUP » avec le prix du catalogue, a l'identique. Un goliath encore
        // dans l'enclos y valait donc 6 000 F alors qu'il n'a rien rapporte.
        //
        // NULL sur les lignes existantes : le cout n'a jamais ete saisi. Leur
        // stock n'est simplement pas valorise, plutot que de reconduire la
        // surevaluation.
        await _ajouterColonne(m, produitsVendables, produitsVendables.coutRevient);
      }
      if (from < 19) {
        // Axe analytique. Sans lui, la Comptabilite Analytique ne pouvait
        // ventiler que ce que le numero de compte laissait deviner : tout
        // l'avicole en un seul bloc, et les charges de structure (electricite,
        // transport, assurances) hors de toute filiere.
        //
        // NULL sur les lignes existantes : elles retombent sur l'heuristique
        // du compte, exactement comme avant. Aucune reimputation retroactive
        // n'est faite — deviner ou une ancienne facture aurait du s'imputer
        // serait de l'invention.
        await _ajouterColonne(m, ecritureComptable, ecritureComptable.axeAnalytique);
      }
      if (from < 20) {
        // Preferences du poste. Deux reglages du prototype ne survivaient pas
        // au redemarrage : la barre laterale repliee (`localStorage
        // .logialvia_sidebar_hidden`) et « Se souvenir de moi », cette derniere
        // n'ecrivant meme rien du tout — une case a cocher qui ne pilotait
        // qu'elle-meme.
        await _creerTable(m, preferencesPoste);
      }
      if (from < 21) {
        // Couveuse multi-ages : lots et sous-lots, mirages, machines.
        //
        // La table des machines est creee AVANT la colonne qui la reference.
        await _creerTable(m, machinesIncubateur);
        await _ajouterColonne(m, cycleCouveuse, cycleCouveuse.machineId);
        await _ajouterColonne(m, cycleCouveuse, cycleCouveuse.oeufsBlancsJ7);
        await _ajouterColonne(m, cycleCouveuse, cycleCouveuse.oeufsGatesJ14);
        await _ajouterColonne(m, cycleCouveuse, cycleCouveuse.lotParentId);

        // Les lots existants restent a NULL sur les mirages : ils n'ont pas
        // ete mires, et leur inventer des zeros donnerait un TER egal au taux
        // brut en le presentant comme un taux reel.
      }
      if (from < 22) {
        // Corbeille : « supprimer » archive desormais, dans tous les modules.
        await _creerTable(m, corbeille);
      }
      if (from < 23) {
        // Verrou de l'onglet « Donnees de Test ». FAUX par defaut sur les
        // bases existantes : une exploitation deja en service ne doit pas
        // hériter d'un acces a la remise a zero.
        await _ajouterColonne(m, 
          parametresEntreprise,
          parametresEntreprise.modeDonneesTest,
        );
      }
      if (from < 24) {
        // Report d'un deces d'infirmerie dans la mortalite de la fiche.
        // NULL sur les entrees existantes : leur deces n'a pas ete reporte
        // par l'application, et pretendre le contraire fausserait un taux de
        // mortalite deja publie.
        await _ajouterColonne(m, infirmerie, infirmerie.categorieMortalite);
      }
      if (from < 25) {
        // Date de mise en bande : la donnee qui manquait pour projeter le
        // calendrier de prophylaxie sur des dates reelles.
        await _creerTable(m, bandes);
        await _ajouterColonne(m, soinsCalendrier, soinsCalendrier.bandeId);
        await _ajouterColonne(m, 
          soinsCalendrier,
          soinsCalendrier.echeanceProphylaxieId,
        );
      }
      if (from < 26) {
        // Facturation normalisee MeCeF. Les factures deja emises n'existent
        // pas : rien a reprendre, uniquement des tables a creer.
        await _creerTable(m, groupesTaxe);
        await _creerTable(m, factures);
        await _creerTable(m, lignesFacture);
        await _ajouterColonne(m, produitsVendables, produitsVendables.groupeTaxe);
        await _ajouterColonne(m, parametresEntreprise, parametresEntreprise.mecefUrl);
        await _ajouterColonne(m, parametresEntreprise, parametresEntreprise.mecefNim);
      }
      if (from < 27) {
        // Filieres escargots et bovins (DV-16, DV-17) et dose du calendrier de
        // prophylaxie.
        //
        // La colonne `dose` est NULL sur les echeances existantes : leur dose
        // n'a jamais ete saisie. Les modules, rations et echeances des deux
        // nouvelles filieres sont ajoutes SANS toucher a ce que l'animalier a
        // deja configure (chaque fonction ignore une filiere deja presente),
        // donc la migration converge meme rejouee.
        await _ajouterColonne(
          m,
          calendrierProphylaxie,
          calendrierProphylaxie.dose,
        );
        await ModulesActifsSeeder.ajouterModulesManquants(this);
        await ParametresElevageSeeder.ajouterNouvellesFilieres(this);
      }
      if (from < 28) {
        // Taux de ration par classe de poids vif (DV-17) : la ration d'un
        // bovin se calcule sur son poids, pas en grammes fixes par tete.
        // Table nouvelle : aucune donnee a reprendre ; les 3 classes
        // d'ouverture ne sont semees que si la filiere n'en a aucune.
        await _creerTable(m, tauxRationPoids);
        await ParametresElevageSeeder.ajouterTauxPoidsParDefaut(this);
      }
    },
    beforeOpen: (details) async {
      // Les cles etrangeres ne sont pas actives par defaut dans SQLite.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // ------------------------------------------------------------ idempotence
  //
  // ## Le jour ou l'application n'a plus demarre
  //
  // Un poste s'est retrouve avec un schema complet en v25 mais un
  // `user_version` reste a 16. Drift a donc rejoue les migrations 17 a 25, et
  // la premiere — `ALTER TABLE ventes ADD COLUMN echeance` — a leve
  // « duplicate column name: echeance ». L'application ne demarrait plus, et
  // le Splash annoncait un probleme de **droits d'acces** : le message
  // envoyait chercher la panne a l'oppose de sa cause.
  //
  // Un `user_version` faux n'est pas une hypothese d'ecole. Il arrive des
  // qu'une base est restauree depuis une sauvegarde, copiee depuis un autre
  // poste, ou qu'une migration s'interrompt en cours de route. Sur une
  // exploitation sans informaticien, une base illisible est une comptabilite
  // perdue.
  //
  // Les migrations verifient donc l'etat reel du schema avant d'agir, au lieu
  // de faire confiance au numero de version. Une colonne deja presente est
  // ignoree, une table deja creee aussi — la migration converge vers le bon
  // schema quel que soit le point de depart.

  /// Ajoute une colonne **si elle n'existe pas deja**.
  Future<void> _ajouterColonne(Migrator m, TableInfo table, GeneratedColumn colonne) async {
    if (await _colonneExiste(table.actualTableName, colonne.name)) return;
    await m.addColumn(table, colonne);
  }

  /// Cree une table **si elle n'existe pas deja**.
  Future<void> _creerTable(Migrator m, TableInfo table) async {
    if (await _tableExiste(table.actualTableName)) return;
    await m.createTable(table);
  }

  Future<bool> _colonneExiste(String table, String colonne) async {
    if (!await _tableExiste(table)) return false;
    final lignes = await customSelect('PRAGMA table_info("$table")').get();
    return lignes.any((l) => l.read<String>('name') == colonne);
  }

  Future<bool> _tableExiste(String nom) async {
    final lignes = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(nom)],
    ).get();
    return lignes.isNotEmpty;
  }
}

/// Doc K3 §5 : aucune fonction d'override SQLite n'est necessaire.
/// `NativeDatabase.createInBackground()` combine a `sqlite3_flutter_libs` suffit
/// sur Windows Desktop — le plugin resout seul `sqlite3.dll`.
/// Ne JAMAIS reintroduire `open.overrideFor(...)` ni `OperatingSystem`
/// (Doc K4 §1, Bug #2 — bug reellement rencontre et corrige sur AgriERP).
LazyDatabase _ouvrirConnexion() {
  return LazyDatabase(() async {
    final dossier = await getApplicationSupportDirectory();
    final fichier = File(p.join(dossier.path, 'logialvia.db'));
    return NativeDatabase.createInBackground(fichier);
  });
}
