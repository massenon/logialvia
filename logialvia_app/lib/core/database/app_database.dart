import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../administration/data/seed/modules_actifs_seeder.dart';
import '../../elevage/data/seed/parametres_elevage_seeder.dart';
import '../../elevage/data/sync/identifiants_elevage.dart';
import '../../administration/data/repositories/preferences_poste_repository.dart';
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
import '../sync/effets_appliques_table.dart';
import '../../approvisionnement/data/tables/fournisseurs_table.dart';
import '../../approvisionnement/data/tables/intrants_table.dart';
import '../../approvisionnement/data/tables/mouvements_intrant_table.dart';
import '../../commercial/data/tables/clients_table.dart';
import '../../commercial/domain/entities/vente.dart';
import '../../comptabilite/data/tables/comptabilite_tables.dart';
import '../../commercial/data/tables/devis_table.dart';
import '../../commercial/data/tables/facturation_mecef_tables.dart';
import '../../commercial/data/tables/lignes_vente_table.dart';
import '../../commercial/data/tables/mouvements_produit_table.dart';
import '../../commercial/data/tables/produits_vendables_table.dart';
import '../../commercial/data/tables/ventes_table.dart';
import '../../elevage/data/tables/bandes_table.dart';
import '../../elevage/data/tables/cycle_couveuse_table.dart';
import '../../elevage/data/tables/fiche_journee_table.dart';
import '../../elevage/data/tables/fiche_ventes_jour_table.dart';
import '../../elevage/data/tables/infirmerie_table.dart';
import '../../elevage/data/tables/parametres_elevage_tables.dart';
import '../../elevage/data/tables/soins_calendrier_table.dart';
import '../../elevage/data/sync/identifiants_parametres_elevage.dart';
import '../sync/identifiant_poste.dart';
import '../../administration/data/tables/demandes_referentiel_table.dart';

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
    DemandesReferentiel,
    // Effets de stock délégués par le web (`47s_`)
    EffetsAppliques,
    // Commercial
    ProduitsVendables, MouvementsProduit, Clients, Ventes, LignesVente, Devis,
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
  static const int versionSchema = 50;

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
      if (from < 29) {
        // Numerotation des bacs (escargots) et des parcs (bovins). Les valeurs
        // par defaut (BAC, PARC) s'appliquent a la ligne de parametres
        // existante : aucun prefixe deja choisi n'est touche.
        await _ajouterColonne(
          m,
          parametresEntreprise,
          parametresEntreprise.prefixeBac,
        );
        await _ajouterColonne(
          m,
          parametresEntreprise,
          parametresEntreprise.prefixeParc,
        );
      }
      if (from < 30) {
        // Poissons-chats rationnes en % de la biomasse (DV-01) : leurs classes
        // de poids rejoignent la table creee en v28. Une base qui a deja des
        // classes pour cette filiere n'est pas touchee.
        await ParametresElevageSeeder.ajouterTauxPoidsParDefaut(this);
      }
      if (from < 31) {
        // DV-19, palier 1 : `clients` passe en UUID et recoit les colonnes de
        // synchronisation. Aucune autre table ne reference `clients.id`
        // (les ventes retiennent le NOM du client), la reconstruction est donc
        // sans cascade. Les clients existants deviennent `pending` : le serveur
        // ne les a jamais vus, ils partent au premier envoi.
        await _clientsEnUuid(m);
      }
      if (from < 32) {
        // File des demandes de modification de referentiel (`46_` §4.3) : table
        // nouvelle, aucune donnee a reprendre.
        await _creerTable(m, demandesReferentiel);
      }
      if (from < 33) {
        // DV-19, palier 3a : `produits_vendables` et `lignes_vente` passent en
        // UUID ; `lignes_vente.produit_id` suit. Les lignes d'une vente
        // d'hier pointent vers le NOUVEL identifiant de leur produit.
        await _produitsEtLignesEnUuid(m);
      }
      if (from < 34) {
        // DV-19, palier 3b : `ventes` recoit son UUID, son `client_id` et les
        // colonnes de synchronisation. La cle primaire reste `ref`.
        await _ventesEnUuid(m);
      }
      if (from < 35) {
        // DV-19, palier 4 : fournisseurs, achats et lignes d'achat en UUID.
        // `achats.fournisseur_id` suit, chaque achat garde son fournisseur.
        await _achatsEnUuid(m);
      }
      if (from < 36) {
        // DV-19, palier 5 : le journal des mouvements d'intrants en UUID, avec son
        // origine et ses colonnes de synchronisation. Les mouvements d'hier sont
        // LOCAUX (origine NULL) et a envoyer.
        await _mouvementsEnUuid(m);
      }
      if (from < 37) {
        // Palier 6 : journal des corrections de stock des produits vendables.
        await _creerTable(m, mouvementsProduit);
      }
      if (from < 38) {
        // DV-19, palier 7a : fiches journalieres, compteurs de ventes du jour et
        // bandes en UUID, avec leurs colonnes de synchronisation. `soins_calendrier`
        // suit (`bande_id`). Voir `46a_`.
        await _elevageEnUuid(m);
      }
      // v38 : reserve a une autre tranche de la synchronisation.
      if (from < 39) {
        // DV-19, palier 7b : lots de couveuse et incubateurs en UUID, avec leurs
        // colonnes de synchronisation. Chaque lot garde son incubateur et son lot
        // d'origine ; aucun lot n'est perdu.
        await _couveuseEnUuid(m);
      }
      if (from < 40) {
        // DV-19, palier P7c : soins, infirmerie, baremes de ration, taux par classe de
        // poids et calendrier de prophylaxie passent en UUID (les lignes semees en UUID
        // DETERMINISTE), avec les colonnes de synchronisation des faits.
        await _soinsEtParametresElevageEnUuid(m);
      }
      if (from < 41) {
        // P8 : la comptabilite SYSCOHADA entre dans la synchronisation (ecritures
        // en UUID groupees par piece, notes annexes, clotures). Les versions 38 a 40
        // appartiennent a d'autres paliers.
        await _comptabiliteEnUuid(m);
      }
      if (from < 42) {
        // DV-19, palier P9 : factures et lignes de facture en UUID, avec leurs
        // colonnes de synchronisation. Les references (`FV-2026-001`) ne changent
        // JAMAIS (DV-21) ; les factures d'hier sont a envoyer, normalisees ou non.
        await _facturesEnUuid(m);
      }
      if (from < 43) {
        // `47a2_` : les devis de prestations passent en UUID avec leur statut, leur
        // pierre tombale et les colonnes de synchronisation. Les references (`DV-2026-001`)
        // ne changent JAMAIS ; les devis d'hier sont a envoyer, au statut « emis ».
        await _devisEnUuid(m);
      }
      if (from < 44) {
        // Report à nouveau (`47c_`) : la décision d'affectation du résultat est gardée avec
        // la clôture de l'exercice.
        await _ajouterColonne(m, exerciceComptable, exerciceComptable.affectation);
      }
      if (from < 45) {
        // Doc 47u §4 : les messages à l'éditeur entrent dans la synchronisation (UUID,
        // auteur, colonnes de synchronisation). Aucun message n'est perdu ; ceux d'hier
        // sont à envoyer au serveur.
        await _messagesEditeurEnUuid(m);
      }
      if (from < 47) {
        // Elevage expert (`47e_`) : une fiche journaliere garde la version dont elle est
        // partie (`base_maj`), les versions divergentes d'un autre poste (`variantes`)
        // et le drapeau de resolution. Additif, idempotent
        await _ajouterColonne(m, ficheJournee, ficheJournee.baseMaj);
        await _ajouterColonne(m, ficheJournee, ficheJournee.variantes);
        await _ajouterColonne(m, ficheJournee, ficheJournee.resolution);
      }
      if (from < 49) {
        // `47s_` : stock ciblé. Une opération web désigne le poste dont le stock subit son
        // effet (`poste_cible`, immuable) ; le journal `effets_appliques` garde ce que CE poste
        // a appliqué (idempotence + trace). Additif, idempotent ; aucune ligne existante n'est
        // touchée : sans poste cible, aucun effet n'a jamais lieu (comportement d'hier).
        await _ajouterColonne(m, achats, achats.posteCible);
        await _ajouterColonne(m, ventes, ventes.posteCible);
        await _ajouterColonne(m, mouvementsIntrant, mouvementsIntrant.posteCible);
        await _ajouterColonne(m, mouvementsProduit, mouvementsProduit.posteCible);
        await _creerTable(m, effetsAppliques);
      }
      if (from < 50) {
        // Droits et horloge (`47g_`) : un refus « Droit insuffisant » n'est JAMAIS définitif.
        // Les demandes et saisies que d'anciennes versions ont laissées en `conflict` pour ce
        // motif repassent « en attente » (elles repartent dès qu'une session avec le droit
        // synchronise). Seul endroit où le texte du motif est comparé : les refus d'aujourd'hui
        // portent un code stable (`droit_insuffisant`). Idempotent.
        await _rearmerRefusDeDroit();
      }
    },
    beforeOpen: (details) async {
      // Les cles etrangeres ne sont pas actives par defaut dans SQLite.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Remet « en attente » toute ligne restée en `conflict` pour droit insuffisant (`47g_`),
  /// dans toutes les tables qui portent des colonnes de synchronisation.
  Future<void> _rearmerRefusDeDroit() async {
    for (final table in allTables) {
      final nom = table.actualTableName;
      if (!await _colonneExiste(nom, 'sync_status') ||
          !await _colonneExiste(nom, 'sync_motif')) {
        continue;
      }
      await customStatement(
        'UPDATE "$nom" SET sync_status = \'pending\', sync_motif = NULL '
        'WHERE sync_status = \'conflict\' AND sync_motif LIKE \'Droit insuffisant%\'',
      );
    }
  }

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

  /// Expression SQLite d'un UUID v4 (une valeur distincte par ligne).
  static const String _uuidSql =
      "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || "
      "'-4' || substr(lower(hex(randomblob(2))), 2) || '-' || "
      "substr('89ab', abs(random()) % 4 + 1, 1) || "
      "substr(lower(hex(randomblob(2))), 2) || '-' || "
      "lower(hex(randomblob(6)))";

  /// Reconstruit `produits_vendables` et `lignes_vente` en UUID, en gardant le
  /// lien entre chaque ligne de vente et son produit. Idempotent.
  Future<void> _produitsEtLignesEnUuid(Migrator m) async {
    final colonnes = await customSelect(
      'PRAGMA table_info("produits_vendables")',
    ).get();
    final id = colonnes.where((l) => l.read<String>('name') == 'id');
    if (id.isNotEmpty && id.first.read<String>('type').toUpperCase() == 'TEXT') {
      return;
    }

    // Table de correspondance ancien entier -> nouvel UUID, le temps de la
    // migration : les lignes de vente la consultent pour retrouver leur produit.
    await customStatement('DROP TABLE IF EXISTS _map_produits');
    await customStatement(
      'CREATE TABLE _map_produits (ancien INTEGER NOT NULL, nouveau TEXT NOT NULL)',
    );
    // UUID DETERMINISTE depuis `sku|designation` : deux postes qui portent le meme
    // produit (catalogue seme, ou meme produit saisi a l'identique) lui donnent le
    // meme identifiant. Un doublon exact sur CE poste se departage par son ancien
    // entier, pour ne pas violer la cle primaire.
    final vus = <String>{};
    final produits = await customSelect(
      'SELECT id, sku, name FROM produits_vendables ORDER BY id',
    ).get();
    for (final p in produits) {
      final ancien = p.read<int>('id');
      var cle = 'produit:${p.readNullable<String>('sku') ?? ''}|${p.read<String>('name')}';
      if (!vus.add(cle)) cle = '$cle#$ancien';
      vus.add(cle);
      await customStatement(
        'INSERT INTO _map_produits (ancien, nouveau) VALUES (?, ?)',
        [ancien, uuidDeterministe(cle)],
      );
    }

    await m.alterTable(
      TableMigration(
        produitsVendables,
        columnTransformer: {
          produitsVendables.id: const CustomExpression<String>(
            '(SELECT nouveau FROM _map_produits WHERE ancien = id)',
          ),
        },
      ),
    );
    await m.alterTable(
      TableMigration(
        lignesVente,
        columnTransformer: {
          lignesVente.id: const CustomExpression<String>(_uuidSql),
          lignesVente.produitId: const CustomExpression<String>(
            '(SELECT nouveau FROM _map_produits WHERE ancien = produit_id)',
          ),
        },
      ),
    );

    // Les produits deja archives en corbeille portent leur ancien entier dans
    // leur instantane : restaures tels quels, ils reviendraient sans UUID.
    final archives = await customSelect(
      "SELECT id, donnees_json FROM corbeille WHERE nom_table = 'produits_vendables'",
    ).get();
    for (final a in archives) {
      final donnees = jsonDecode(a.read<String>('donnees_json')) as Map<String, Object?>;
      final ancien = donnees['id'];
      final nouveau = await customSelect(
        'SELECT nouveau FROM _map_produits WHERE ancien = ?',
        variables: [Variable(ancien)],
      ).getSingleOrNull();
      // Un produit archive n'est plus dans `produits_vendables` : pas de
      // correspondance, on lui en donne un neuf.
      donnees['id'] = nouveau?.read<String>('nouveau') ?? nouvelUuid();
      await customStatement(
        'UPDATE corbeille SET donnees_json = ? WHERE id = ?',
        [jsonEncode(donnees), a.read<int>('id')],
      );
    }

    await customStatement('DROP TABLE IF EXISTS _map_produits');
  }

  /// Vrai si `id` est deja du texte (migration deja jouee, restauration).
  Future<bool> _idEstTexte(String table) async {
    final colonnes = await customSelect('PRAGMA table_info("$table")').get();
    final id = colonnes.where((l) => l.read<String>('name') == 'id');
    return id.isNotEmpty && id.first.read<String>('type').toUpperCase() == 'TEXT';
  }

  /// Palier 7a : les trois tables d'elevage en UUID. Idempotent.
  Future<void> _elevageEnUuid(Migrator m) async {
    await _fichesJourneeEnUuid(m);
    await _ventesJourEnUuid(m);
    await _bandesEnUuid(m);
  }

  /// `fiche_journee` : UUID DETERMINISTE de (espece, date), pour que deux postes
  /// convergent sur la meme ligne. Jamais de perte : meme nombre de lignes, memes
  /// valeurs. Une fiche d'hier a ete SAISIE le jour qu'elle decrit : c'est son instant
  /// de saisie (celui de la migration la ferait gagner contre une correction faite
  /// ailleurs). Toutes sont `pending` : le serveur ne les a jamais vues.
  Future<void> _fichesJourneeEnUuid(Migrator m) async {
    if (await _idEstTexte('fiche_journee')) return;

    await customStatement('DROP TABLE IF EXISTS _map_fiches');
    await customStatement(
      'CREATE TABLE _map_fiches (ancien INTEGER NOT NULL, nouveau TEXT NOT NULL)',
    );
    final lignes = await customSelect(
      'SELECT id, espece, date FROM fiche_journee ORDER BY id',
    ).get();
    for (final l in lignes) {
      final jour = DateTime.fromMillisecondsSinceEpoch(l.read<int>('date') * 1000);
      await customStatement(
        'INSERT INTO _map_fiches (ancien, nouveau) VALUES (?, ?)',
        [l.read<int>('id'), identifiantFicheJournee(l.read<String>('espece'), jour)],
      );
    }

    await m.alterTable(
      TableMigration(
        ficheJournee,
        columnTransformer: {
          ficheJournee.id: const CustomExpression<String>(
            '(SELECT nouveau FROM _map_fiches WHERE ancien = id)',
          ),
          ficheJournee.updatedAt: const CustomExpression<String>(
            "strftime('%Y-%m-%dT%H:%M:%fZ', date, 'unixepoch')",
          ),
        },
        newColumns: [
          ficheJournee.syncStatus,
          ficheJournee.syncMotif,
          ficheJournee.updatedAt,
          // Colonnes de la v47 : absentes de la base v37, a creer ici (`47e_`).
          ficheJournee.baseMaj,
          ficheJournee.variantes,
          ficheJournee.resolution,
        ],
      ),
    );
    await customStatement('DROP TABLE IF EXISTS _map_fiches');
  }

  /// `fiche_ventes_jour` : un compteur par POSTE. Les lignes existantes sont celles
  /// de CE poste (`origine` vide) ; leur UUID depend de (espece, date, identifiant du
  /// poste), que la migration cree s'il n'existe pas encore.
  Future<void> _ventesJourEnUuid(Migrator m) async {
    if (await _idEstTexte('fiche_ventes_jour')) return;

    final poste = await PreferencesPosteRepository(this).identifiantPoste();
    await customStatement('DROP TABLE IF EXISTS _map_ventes_jour');
    await customStatement(
      'CREATE TABLE _map_ventes_jour (ancien INTEGER NOT NULL, nouveau TEXT NOT NULL)',
    );
    final lignes = await customSelect(
      'SELECT id, espece, date FROM fiche_ventes_jour ORDER BY id',
    ).get();
    for (final l in lignes) {
      final jour = DateTime.fromMillisecondsSinceEpoch(l.read<int>('date') * 1000);
      await customStatement(
        'INSERT INTO _map_ventes_jour (ancien, nouveau) VALUES (?, ?)',
        [l.read<int>('id'), identifiantVentesJour(l.read<String>('espece'), jour, poste)],
      );
    }

    await m.alterTable(
      TableMigration(
        ficheVentesJour,
        columnTransformer: {
          ficheVentesJour.id: const CustomExpression<String>(
            '(SELECT nouveau FROM _map_ventes_jour WHERE ancien = id)',
          ),
          ficheVentesJour.updatedAt: const CustomExpression<String>(
            "strftime('%Y-%m-%dT%H:%M:%fZ', date, 'unixepoch')",
          ),
        },
        newColumns: [
          ficheVentesJour.origine,
          ficheVentesJour.syncStatus,
          ficheVentesJour.syncMotif,
          ficheVentesJour.updatedAt,
        ],
      ),
    );
    await customStatement('DROP TABLE IF EXISTS _map_ventes_jour');
  }

  /// `bandes` en UUID aleatoire (donnee saisie par l'utilisatrice) ; chaque soin
  /// injecte garde sa bande (`soins_calendrier.bande_id` suit la table de
  /// correspondance).
  Future<void> _bandesEnUuid(Migrator m) async {
    if (await _idEstTexte('bandes')) return;

    await customStatement('DROP TABLE IF EXISTS _map_bandes');
    await customStatement(
      'CREATE TABLE _map_bandes AS SELECT id AS ancien, $_uuidSql AS nouveau FROM bandes',
    );
    await m.alterTable(
      TableMigration(
        bandes,
        columnTransformer: {
          bandes.id: const CustomExpression<String>(
            '(SELECT nouveau FROM _map_bandes WHERE ancien = id)',
          ),
          // Dernier geste connu sur une bande : sa cloture, sinon sa mise en place.
          bandes.updatedAt: const CustomExpression<String>(
            "strftime('%Y-%m-%dT%H:%M:%fZ', COALESCE(date_cloture, date_mise_en_bande), 'unixepoch')",
          ),
        },
        newColumns: [bandes.syncStatus, bandes.syncMotif, bandes.updatedAt],
      ),
    );
    if (await _colonneExiste('soins_calendrier', 'bande_id')) {
      // La table courante porte aussi les colonnes de synchronisation des soins (v40) :
      // sur une base d'avant la v40, la reconstruction doit les creer, sinon la copie
      // cherche des colonnes qui n'existent pas encore.
      final sansSync = !await _colonneExiste('soins_calendrier', 'sync_status');
      await m.alterTable(
        TableMigration(
          soinsCalendrier,
          columnTransformer: {
            soinsCalendrier.bandeId: const CustomExpression<String>(
              '(SELECT nouveau FROM _map_bandes WHERE ancien = bande_id)',
            ),
            if (sansSync)
              soinsCalendrier.updatedAt: const CustomExpression<String>(
                "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')",
              ),
          },
          newColumns: [
            if (sansSync) ...[
              soinsCalendrier.syncStatus,
              soinsCalendrier.syncMotif,
              soinsCalendrier.updatedAt,
            ],
          ],
        ),
      );
    }
    await customStatement('DROP TABLE IF EXISTS _map_bandes');
  }

  /// Le journal des mouvements d'intrants en UUID. Idempotent.
  Future<void> _mouvementsEnUuid(Migrator m) async {
    final colonnes = await customSelect('PRAGMA table_info("mouvements_intrant")').get();
    final id = colonnes.where((l) => l.read<String>('name') == 'id');
    if (id.isNotEmpty && id.first.read<String>('type').toUpperCase() == 'TEXT') {
      return;
    }
    await m.alterTable(
      TableMigration(
        mouvementsIntrant,
        columnTransformer: {
          mouvementsIntrant.id: const CustomExpression<String>(_uuidSql),
        },
        newColumns: [
          mouvementsIntrant.origine,
          // Colonne de la v49 : la reconstruction copie le schéma COURANT, elle doit la créer.
          mouvementsIntrant.posteCible,
          mouvementsIntrant.syncStatus,
          mouvementsIntrant.syncMotif,
        ],
      ),
    );
  }

  /// Fournisseurs, achats et lignes d'achat en UUID. Idempotent.
  ///
  /// Les achats gardent leur fournisseur (table de correspondance ancien entier ->
  /// UUID le temps de la migration) et leur numero officiel (`ref`, cle primaire,
  /// ne change JAMAIS). Le fournisseur recoit un UUID ALEATOIRE : ce sont des
  /// donnees saisies par l'utilisatrice, jamais semees identiquement.
  Future<void> _achatsEnUuid(Migrator m) async {
    final colonnes = await customSelect('PRAGMA table_info("fournisseurs")').get();
    final id = colonnes.where((l) => l.read<String>('name') == 'id');
    if (id.isNotEmpty && id.first.read<String>('type').toUpperCase() == 'TEXT') {
      return;
    }

    await customStatement('DROP TABLE IF EXISTS _map_fournisseurs');
    await customStatement(
      'CREATE TABLE _map_fournisseurs AS '
      'SELECT id AS ancien, $_uuidSql AS nouveau FROM fournisseurs',
    );

    await m.alterTable(
      TableMigration(
        fournisseurs,
        columnTransformer: {
          fournisseurs.id: const CustomExpression<String>(
            '(SELECT nouveau FROM _map_fournisseurs WHERE ancien = id)',
          ),
          // Un fournisseur d'hier a ete saisi AVANT la migration : on ne sait pas
          // quand ; l'instant de la migration est le seul disponible, et comme
          // aucun autre poste ne le connait encore, il ne peut battre personne.
          fournisseurs.updatedAt: const CustomExpression<String>(
            "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')",
          ),
        },
        newColumns: [
          fournisseurs.syncStatus,
          fournisseurs.syncMotif,
          fournisseurs.updatedAt,
        ],
      ),
    );
    await m.alterTable(
      TableMigration(
        achats,
        columnTransformer: {
          achats.id: const CustomExpression<String>(_uuidSql),
          achats.fournisseurId: const CustomExpression<String>(
            '(SELECT nouveau FROM _map_fournisseurs WHERE ancien = fournisseur_id)',
          ),
          // Un achat d'hier a ete saisi le jour de son achat.
          achats.updatedAt: const CustomExpression<String>(
            "strftime('%Y-%m-%dT%H:%M:%fZ', date_achat, 'unixepoch')",
          ),
        },
        newColumns: [
          achats.id,
          // Colonne de la v49 : la reconstruction copie le schéma COURANT, elle doit la créer.
          achats.posteCible,
          achats.syncStatus,
          achats.syncMotif,
          achats.updatedAt,
        ],
      ),
    );
    await m.alterTable(
      TableMigration(
        lignesAchat,
        columnTransformer: {lignesAchat.id: const CustomExpression<String>(_uuidSql)},
      ),
    );

    await customStatement('DROP TABLE IF EXISTS _map_fournisseurs');
  }

  /// Lots de couveuse et incubateurs en UUID. Idempotent.
  ///
  /// - Un incubateur recoit un UUID DETERMINISTE depuis son code (deux postes qui
  ///   declarent « INC-01 » designent le meme incubateur) ; un doublon de code a la
  ///   casse pres se departage par son ancien entier.
  /// - Un lot garde son incubateur et son lot d'origine (tables de correspondance
  ///   ancien entier -> UUID, supprimees en fin de migration).
  /// - Son instant de saisie est sa date de chargement (pas l'instant de la
  ///   migration, qui le ferait gagner contre une correction faite ailleurs).
  /// - Les lots deja SUPPRIMES (corbeille) voient leur instantane reecrit : sinon
  ///   ils reviendraient avec leurs anciens entiers.
  Future<void> _couveuseEnUuid(Migrator m) async {
    final colonnes = await customSelect('PRAGMA table_info("cycle_couveuse")').get();
    final id = colonnes.where((l) => l.read<String>('name') == 'id');
    if (id.isNotEmpty && id.first.read<String>('type').toUpperCase() == 'TEXT') {
      return;
    }

    await customStatement('DROP TABLE IF EXISTS _map_machines');
    await customStatement(
      'CREATE TABLE _map_machines (ancien INTEGER NOT NULL, nouveau TEXT NOT NULL)',
    );
    final vus = <String>{};
    final machines = await customSelect(
      'SELECT id, code FROM machines_incubateur ORDER BY id',
    ).get();
    for (final machine in machines) {
      final ancien = machine.read<int>('id');
      var cle = 'machine:${machine.read<String>('code').trim().toLowerCase()}';
      if (!vus.add(cle)) cle = '$cle#$ancien';
      vus.add(cle);
      await customStatement(
        'INSERT INTO _map_machines (ancien, nouveau) VALUES (?, ?)',
        [ancien, uuidDeterministe(cle)],
      );
    }

    await customStatement('DROP TABLE IF EXISTS _map_cycles');
    await customStatement(
      'CREATE TABLE _map_cycles AS '
      'SELECT id AS ancien, $_uuidSql AS nouveau FROM cycle_couveuse',
    );

    await m.alterTable(
      TableMigration(
        machinesIncubateur,
        columnTransformer: {
          machinesIncubateur.id: const CustomExpression<String>(
            '(SELECT nouveau FROM _map_machines WHERE ancien = id)',
          ),
          // Saisi avant la migration, a une date inconnue : l'instant de la
          // migration, qu'aucun autre poste ne peut contredire.
          machinesIncubateur.updatedAt: const CustomExpression<String>(
            "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')",
          ),
        },
        newColumns: [
          machinesIncubateur.syncStatus,
          machinesIncubateur.syncMotif,
          machinesIncubateur.updatedAt,
        ],
      ),
    );
    await m.alterTable(
      TableMigration(
        cycleCouveuse,
        columnTransformer: {
          cycleCouveuse.id: const CustomExpression<String>(
            '(SELECT nouveau FROM _map_cycles WHERE ancien = id)',
          ),
          cycleCouveuse.machineId: const CustomExpression<String>(
            '(SELECT nouveau FROM _map_machines WHERE ancien = machine_id)',
          ),
          cycleCouveuse.lotParentId: const CustomExpression<String>(
            '(SELECT nouveau FROM _map_cycles WHERE ancien = lot_parent_id)',
          ),
          cycleCouveuse.updatedAt: const CustomExpression<String>(
            "strftime('%Y-%m-%dT%H:%M:%fZ', date_incubation, 'unixepoch')",
          ),
        },
        newColumns: [
          cycleCouveuse.syncStatus,
          cycleCouveuse.syncMotif,
          cycleCouveuse.updatedAt,
        ],
      ),
    );

    final archives = await customSelect(
      "SELECT id, donnees_json FROM corbeille WHERE nom_table = 'cycle_couveuse'",
    ).get();
    for (final a in archives) {
      final donnees = jsonDecode(a.read<String>('donnees_json')) as Map<String, Object?>;
      final machine = donnees['machine_id'];
      final parent = donnees['lot_parent_id'];
      final nouvelleMachine = machine == null
          ? null
          : await customSelect(
              'SELECT nouveau FROM _map_machines WHERE ancien = ?',
              variables: [Variable(machine)],
            ).getSingleOrNull();
      final nouveauParent = parent == null
          ? null
          : await customSelect(
              'SELECT nouveau FROM _map_cycles WHERE ancien = ?',
              variables: [Variable(parent)],
            ).getSingleOrNull();
      donnees['id'] = nouvelUuid();
      donnees['machine_id'] = nouvelleMachine?.read<String>('nouveau');
      donnees['lot_parent_id'] = nouveauParent?.read<String>('nouveau');
      await customStatement(
        'UPDATE corbeille SET donnees_json = ? WHERE id = ?',
        [jsonEncode(donnees), a.read<int>('id')],
      );
    }

    await customStatement('DROP TABLE IF EXISTS _map_machines');
    await customStatement('DROP TABLE IF EXISTS _map_cycles');
  }

  /// Donne a `ventes` un UUID, un `client_id` et les colonnes de synchronisation.
  /// Idempotent : une base qui a deja la colonne `id` est laissee telle quelle.
  Future<void> _ventesEnUuid(Migrator m) async {
    if (await _colonneExiste('ventes', 'id')) return;

    await m.alterTable(
      TableMigration(
        ventes,
        columnTransformer: {
          ventes.id: const CustomExpression<String>(_uuidSql),
          // Une vente d'hier a ete SAISIE le jour de sa vente : c'est son instant
          // de saisie (pas celui de la migration, qui la ferait gagner contre
          // une correction faite ailleurs).
          ventes.updatedAt: const CustomExpression<String>(
            "strftime('%Y-%m-%dT%H:%M:%fZ', date_vente, 'unixepoch')",
          ),
        },
        newColumns: [
          ventes.id,
          ventes.clientId,
          // Colonne de la v49 : la reconstruction copie le schéma COURANT, elle doit la créer.
          ventes.posteCible,
          ventes.syncStatus,
          ventes.syncMotif,
          ventes.updatedAt,
        ],
      ),
    );

    // Rattache chaque vente a son client quand le NOM ne designe qu'UN client.
    // Deux clients homonymes : on ne devine pas, `client_id` reste vide.
    await customStatement(
      'UPDATE ventes SET client_id = ('
      'SELECT c.id FROM clients c '
      'WHERE lower(trim(c.nom)) = lower(trim(ventes.client))) '
      'WHERE (SELECT COUNT(*) FROM clients c '
      'WHERE lower(trim(c.nom)) = lower(trim(ventes.client))) = 1',
    );
  }

  /// Donne a `factures` un UUID, une origine et les colonnes de synchronisation,
  /// et passe `lignes_facture` en UUID. Idempotent, **chaque table sa garde** :
  /// une migration interrompue entre les deux reprend la ou elle s'est arretee.
  ///
  /// - La cle primaire reste `ref` (numero officiel, jamais renumerote).
  /// - Aucune cle etrangere ne pointe sur `factures` : la reconstruction n'emporte
  ///   aucune ligne (verifie par test).
  /// - Une facture d'hier a ete SAISIE le jour de sa derniere modification : sa
  ///   normalisation si elle en a une, sinon son emission (pas l'instant de la
  ///   migration, qui la ferait gagner contre une correction faite ailleurs).
  /// - `groupes_taxe` ne bouge pas : sa cle est la lettre du groupe, deja
  ///   deterministe et identique sur tous les postes.
  Future<void> _facturesEnUuid(Migrator m) async {
    if (!await _colonneExiste('factures', 'id')) {
      await m.alterTable(
        TableMigration(
          factures,
          columnTransformer: {
            factures.id: const CustomExpression<String>(_uuidSql),
            factures.updatedAt: const CustomExpression<String>(
              "strftime('%Y-%m-%dT%H:%M:%fZ', COALESCE(date_normalisation, date_facture), 'unixepoch')",
            ),
          },
          newColumns: [
            factures.id,
            factures.origine,
            factures.syncStatus,
            factures.syncMotif,
            factures.updatedAt,
          ],
        ),
      );
    }

    final colonnes = await customSelect('PRAGMA table_info("lignes_facture")').get();
    final id = colonnes.where((l) => l.read<String>('name') == 'id');
    if (id.isNotEmpty && id.first.read<String>('type').toUpperCase() != 'TEXT') {
      await m.alterTable(
        TableMigration(
          lignesFacture,
          columnTransformer: {lignesFacture.id: const CustomExpression<String>(_uuidSql)},
        ),
      );
    }
  }

  /// `devis` en UUID, avec statut, pierre tombale et colonnes de synchronisation
  /// (`47a2_`). Idempotent : une table deja convertie n'est pas retouchee, et une
  /// colonne manquante (migration interrompue, base restauree) est ajoutee seule.
  /// L'instant de saisie d'un devis d'hier est sa DATE D'EMISSION, jamais celui de
  /// la migration (il ferait gagner un vieux devis contre une correction faite ailleurs).
  Future<void> _devisEnUuid(Migrator m) async {
    if (!await _tableExiste('devis')) {
      await m.createTable(devis);
      return;
    }
    if (await _idEstEntier('devis')) {
      await m.alterTable(
        TableMigration(
          devis,
          columnTransformer: {
            devis.id: const CustomExpression<String>(_uuidSql),
            devis.updatedAt: const CustomExpression<String>(
              "strftime('%Y-%m-%dT%H:%M:%fZ', date_emission, 'unixepoch')",
            ),
          },
          newColumns: [
            devis.statut,
            devis.supprimeLe,
            devis.syncStatus,
            devis.syncMotif,
            devis.updatedAt,
          ],
        ),
      );
    }
    await _ajouterColonne(m, devis, devis.statut);
    await _ajouterColonne(m, devis, devis.supprimeLe);
    await _ajouterColonne(m, devis, devis.syncStatus);
    await _ajouterColonne(m, devis, devis.syncMotif);
    await _ajouterColonne(m, devis, devis.updatedAt);
  }

  /// Reconstruit `clients` en UUID. Idempotent : une base dont `clients.id` est
  /// deja du texte (version estampillee a tort, restauration) est laissee telle
  /// quelle.
  Future<void> _clientsEnUuid(Migrator m) async {
    final colonnes = await customSelect('PRAGMA table_info("clients")').get();
    final id = colonnes.where((l) => l.read<String>('name') == 'id');
    if (id.isNotEmpty && id.first.read<String>('type').toUpperCase() == 'TEXT') {
      return;
    }

    // UUID v4 calcule par SQLite : une ligne = un UUID distinct.
    const uuidSql =
        "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || "
        "'-4' || substr(lower(hex(randomblob(2))), 2) || '-' || "
        "substr('89ab', abs(random()) % 4 + 1, 1) || "
        "substr(lower(hex(randomblob(2))), 2) || '-' || "
        "lower(hex(randomblob(6)))";

    await m.alterTable(
      TableMigration(
        clients,
        columnTransformer: {
          clients.id: const CustomExpression<String>(uuidSql),
          clients.updatedAt: const CustomExpression<String>(
            "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')",
          ),
        },
        newColumns: [clients.syncStatus, clients.syncMotif, clients.updatedAt],
      ),
    );
  }

  /// `messages_editeur` en UUID (doc 47u §4, v45). Idempotent. Les messages existants
  /// gardent leur date (leur instant de saisie) et deviennent `pending` ; les instantanés
  /// de la corbeille (messages supprimés) reçoivent un UUID et sont déclarés `synced` : la
  /// pierre tombale d'un message que le serveur n'a jamais vu serait sans objet.
  Future<void> _messagesEditeurEnUuid(Migrator m) async {
    if (await _idEstTexte('messages_editeur')) return;

    await m.alterTable(
      TableMigration(
        messagesEditeur,
        columnTransformer: {
          messagesEditeur.id: const CustomExpression<String>(_uuidSql),
          messagesEditeur.updatedAt: const CustomExpression<String>(
            "strftime('%Y-%m-%dT%H:%M:%fZ', horodatage, 'unixepoch')",
          ),
        },
        newColumns: [
          messagesEditeur.auteurNom,
          messagesEditeur.syncStatus,
          messagesEditeur.syncMotif,
          messagesEditeur.updatedAt,
        ],
      ),
    );

    final archives = await customSelect(
      "SELECT id, donnees_json FROM corbeille WHERE nom_table = 'messages_editeur'",
    ).get();
    for (final a in archives) {
      final donnees = jsonDecode(a.read<String>('donnees_json')) as Map<String, Object?>;
      donnees['id'] = nouvelUuid();
      donnees['sync_status'] = 'synced';
      donnees['sync_motif'] = null;
      donnees['auteur_nom'] = null;
      donnees['updated_at'] = instantSaisie();
      await customStatement(
        'UPDATE corbeille SET donnees_json = ? WHERE id = ?',
        [jsonEncode(donnees), a.read<int>('id')],
      );
    }
  }

  /// Soins, infirmerie, barèmes, taux et calendrier de prophylaxie en UUID
  /// (DV-19, P7c). Idempotent et **rejouable** : chaque table est testée
  /// séparément, et l'ordre (correspondance des échéances, soins, infirmerie,
  /// barèmes, taux, échéances) garantit qu'une reprise après interruption retrouve
  /// les MÊMES identifiants (déterministes) — aucun lien soin -> échéance ne se perd.
  ///
  /// Aucune ligne n'est perdue : `soins_calendrier` ne référence rien par clé
  /// étrangère, et `bande_id` reste un entier LOCAL (les bandes ne sont pas encore
  /// synchronisées). Les lignes de référentiel reçoivent leur UUID DÉTERMINISTE (clé
  /// naturelle) : deux postes migrés donnent le même identifiant à la même ration.
  Future<void> _soinsEtParametresElevageEnUuid(Migrator m) async {
    // 1. Correspondance ancien entier -> UUID des échéances (vivantes et en
    //    corbeille), consultée par les soins qui les citent.
    await customStatement('DROP TABLE IF EXISTS _map_echeances');
    await customStatement(
      'CREATE TABLE _map_echeances (ancien INTEGER NOT NULL, nouveau TEXT NOT NULL)',
    );
    final vus = <String>{};
    if (await _idEstEntier('calendrier_prophylaxie')) {
      final lignes = await customSelect(
        'SELECT id, espece, jour_cycle, traitement, produit '
        'FROM calendrier_prophylaxie ORDER BY id',
      ).get();
      for (final l in lignes) {
        final ancien = l.read<int>('id');
        final uuid = _uuidEcheanceUnique(
          vus,
          l.read<String>('espece'),
          l.read<int>('jour_cycle'),
          l.read<String>('traitement'),
          l.read<String>('produit'),
          ancien,
        );
        await customStatement(
          'INSERT INTO _map_echeances (ancien, nouveau) VALUES (?, ?)',
          [ancien, uuid],
        );
      }
    }

    // 2. Corbeille : les instantanés archivés avant la v40 portent un entier. Remis
    //    en UUID déterministe, ils se restaurent avec le bon identifiant ; une
    //    échéance archivée garde le lien avec les soins qui la citent.
    final archives = await customSelect(
      "SELECT id, nom_table, donnees_json FROM corbeille WHERE nom_table IN "
      "('baremes_ration', 'taux_ration_poids', 'calendrier_prophylaxie')",
    ).get();
    for (final a in archives) {
      final donnees =
          jsonDecode(a.read<String>('donnees_json')) as Map<String, Object?>;
      final ancien = donnees['id'];
      if (ancien is! int) continue;
      final table = a.read<String>('nom_table');
      final String nouveau;
      if (table == 'baremes_ration') {
        nouveau = IdentifiantsParametresElevage.bareme(
          '${donnees['espece']}',
          '${donnees['stade']}',
        );
      } else if (table == 'taux_ration_poids') {
        nouveau = IdentifiantsParametresElevage.taux(
          '${donnees['espece']}',
          (donnees['poids_min_g'] as num).toInt(),
        );
      } else {
        nouveau = _uuidEcheanceUnique(
          vus,
          '${donnees['espece']}',
          (donnees['jour_cycle'] as num).toInt(),
          '${donnees['traitement']}',
          '${donnees['produit']}',
          ancien,
        );
        await customStatement(
          'INSERT INTO _map_echeances (ancien, nouveau) VALUES (?, ?)',
          [ancien, nouveau],
        );
      }
      donnees['id'] = nouveau;
      await customStatement(
        'UPDATE corbeille SET donnees_json = ? WHERE id = ?',
        [jsonEncode(donnees), a.read<int>('id')],
      );
    }

    // 3. Les soins : UUID aléatoires (saisis par l'utilisatrice), échéance suivie.
    //    Un soin d'hier est « à envoyer » ; son instant de saisie est celui de la
    //    migration : aucun autre poste ne le connaît encore, il ne peut battre personne.
    if (await _idEstEntier('soins_calendrier')) {
      await m.alterTable(
        TableMigration(
          soinsCalendrier,
          columnTransformer: {
            soinsCalendrier.id: const CustomExpression<String>(_uuidSql),
            soinsCalendrier.echeanceProphylaxieId:
                const CustomExpression<String>(
                  '(SELECT nouveau FROM _map_echeances '
                  'WHERE ancien = echeance_prophylaxie_id)',
                ),
            soinsCalendrier.updatedAt: const CustomExpression<String>(
              "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')",
            ),
          },
          newColumns: [
            soinsCalendrier.syncStatus,
            soinsCalendrier.syncMotif,
            soinsCalendrier.updatedAt,
          ],
        ),
      );
    }

    // 4. L'infirmerie.
    if (await _idEstEntier('infirmerie')) {
      await m.alterTable(
        TableMigration(
          infirmerie,
          columnTransformer: {
            infirmerie.id: const CustomExpression<String>(_uuidSql),
            infirmerie.updatedAt: const CustomExpression<String>(
              "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')",
            ),
          },
          newColumns: [
            infirmerie.syncStatus,
            infirmerie.syncMotif,
            infirmerie.updatedAt,
          ],
        ),
      );
    }

    // 5. Barèmes et taux : UUID déterministe depuis la clé unique.
    if (await _idEstEntier('baremes_ration')) {
      await customStatement('DROP TABLE IF EXISTS _map_baremes');
      await customStatement(
        'CREATE TABLE _map_baremes (ancien INTEGER NOT NULL, nouveau TEXT NOT NULL)',
      );
      for (final l in await customSelect(
        'SELECT id, espece, stade FROM baremes_ration ORDER BY id',
      ).get()) {
        await customStatement(
          'INSERT INTO _map_baremes (ancien, nouveau) VALUES (?, ?)',
          [
            l.read<int>('id'),
            IdentifiantsParametresElevage.bareme(
              l.read<String>('espece'),
              l.read<String>('stade'),
            ),
          ],
        );
      }
      await m.alterTable(
        TableMigration(
          baremesRation,
          columnTransformer: {
            baremesRation.id: const CustomExpression<String>(
              '(SELECT nouveau FROM _map_baremes WHERE ancien = id)',
            ),
          },
        ),
      );
      await customStatement('DROP TABLE IF EXISTS _map_baremes');
    }
    if (await _idEstEntier('taux_ration_poids')) {
      await customStatement('DROP TABLE IF EXISTS _map_taux');
      await customStatement(
        'CREATE TABLE _map_taux (ancien INTEGER NOT NULL, nouveau TEXT NOT NULL)',
      );
      for (final l in await customSelect(
        'SELECT id, espece, poids_min_g FROM taux_ration_poids ORDER BY id',
      ).get()) {
        await customStatement(
          'INSERT INTO _map_taux (ancien, nouveau) VALUES (?, ?)',
          [
            l.read<int>('id'),
            IdentifiantsParametresElevage.taux(
              l.read<String>('espece'),
              l.read<int>('poids_min_g'),
            ),
          ],
        );
      }
      await m.alterTable(
        TableMigration(
          tauxRationPoids,
          columnTransformer: {
            tauxRationPoids.id: const CustomExpression<String>(
              '(SELECT nouveau FROM _map_taux WHERE ancien = id)',
            ),
          },
        ),
      );
      await customStatement('DROP TABLE IF EXISTS _map_taux');
    }

    // 6. Le calendrier de prophylaxie : la correspondance a déjà été calculée.
    if (await _idEstEntier('calendrier_prophylaxie')) {
      await m.alterTable(
        TableMigration(
          calendrierProphylaxie,
          columnTransformer: {
            calendrierProphylaxie.id: const CustomExpression<String>(
              '(SELECT nouveau FROM _map_echeances WHERE ancien = id)',
            ),
          },
        ),
      );
    }
    await customStatement('DROP TABLE IF EXISTS _map_echeances');
  }

  /// UUID déterministe d'une échéance ; un doublon exact sur CE poste se départage
  /// par son ancien entier (la clé primaire l'exige).
  String _uuidEcheanceUnique(
    Set<String> vus,
    String espece,
    int jour,
    String traitement,
    String produit,
    int ancien,
  ) {
    var uuid = IdentifiantsParametresElevage.echeance(
      espece,
      jour,
      traitement,
      produit,
    );
    if (!vus.add(uuid)) {
      uuid = uuidDeterministe(
        'echeance_prophylaxie:$espece|$jour|$traitement|$produit#$ancien',
      );
      vus.add(uuid);
    }
    return uuid;
  }

  /// Vrai si la table existe et que sa colonne `id` n'est PAS encore du texte.
  Future<bool> _idEstEntier(String table) async {
    if (!await _tableExiste(table)) return false;
    final colonnes = await customSelect('PRAGMA table_info("$table")').get();
    final id = colonnes.where((l) => l.read<String>('name') == 'id');
    return id.isNotEmpty && id.first.read<String>('type').toUpperCase() != 'TEXT';
  }

  /// P8 — la comptabilite en UUID et prete a la synchronisation. Idempotent.
  ///
  /// - `ecriture_comptable` : `id` en UUID ; `piece_id` regroupe les lignes d'une meme
  ///   piece (exercice + numero) — une ligne sans numero forme sa propre piece ; les
  ///   ecritures d'hier sont LOCALES (`origine` vide) et a envoyer ; leur instant de
  ///   saisie est leur date. Aucune ligne n'est perdue ni renumerotee.
  /// - `notes_annexes` : `id` en UUID DETERMINISTE de (exercice, numero).
  /// - `exercice_comptable` et `clotures_periodiques` : colonnes de synchronisation ; une
  ///   cloture d'hier est « a envoyer » (le serveur la verifiera), un exercice ouvert non.
  /// - `plan_comptable` : inchange (cle naturelle = numero de compte, semis identique).
  Future<void> _comptabiliteEnUuid(Migrator m) async {
    const instantSql = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";
    const instantOuNow =
        "COALESCE(strftime('%Y-%m-%dT%H:%M:%fZ', date_cloture, 'unixepoch'), $instantSql)";

    if (!await _colonneExiste('exercice_comptable', 'sync_status')) {
      await m.alterTable(
        TableMigration(
          exerciceComptable,
          columnTransformer: {
            exerciceComptable.syncStatus: const CustomExpression<String>(
              "CASE WHEN is_cloture = 1 THEN 'pending' ELSE 'synced' END",
            ),
            exerciceComptable.updatedAt: const CustomExpression<String>(
              instantOuNow,
            ),
          },
          newColumns: [
            exerciceComptable.affectation, // v44 : absente d'une base d'avant, recopiée vide
            exerciceComptable.syncStatus,
            exerciceComptable.syncMotif,
            exerciceComptable.updatedAt,
          ],
        ),
      );
    }

    if (!await _colonneExiste('clotures_periodiques', 'sync_status')) {
      await m.alterTable(
        TableMigration(
          cloturesPeriodiques,
          columnTransformer: {
            cloturesPeriodiques.updatedAt: const CustomExpression<String>(
              instantOuNow,
            ),
          },
          newColumns: [
            cloturesPeriodiques.syncStatus,
            cloturesPeriodiques.syncMotif,
            cloturesPeriodiques.updatedAt,
          ],
        ),
      );
    }

    final notes = await customSelect(
      'PRAGMA table_info("notes_annexes")',
    ).get();
    final noteId = notes.where((l) => l.read<String>('name') == 'id');
    if (noteId.isEmpty ||
        noteId.first.read<String>('type').toUpperCase() != 'TEXT') {
      await customStatement('DROP TABLE IF EXISTS _map_notes');
      await customStatement(
        'CREATE TABLE _map_notes (ancien INTEGER NOT NULL, nouveau TEXT NOT NULL)',
      );
      for (final n in await customSelect(
        'SELECT id, exercice_annee, numero_note FROM notes_annexes',
      ).get()) {
        await customStatement(
          'INSERT INTO _map_notes (ancien, nouveau) VALUES (?, ?)',
          [
            n.read<int>('id'),
            uuidDeterministe(
              'note:${n.read<int>('exercice_annee')}-${n.read<int>('numero_note')}',
            ),
          ],
        );
      }
      await m.alterTable(
        TableMigration(
          notesAnnexes,
          columnTransformer: {
            notesAnnexes.id: const CustomExpression<String>(
              '(SELECT nouveau FROM _map_notes WHERE ancien = id)',
            ),
            notesAnnexes.updatedAt: const CustomExpression<String>(instantSql),
          },
          newColumns: [
            notesAnnexes.syncStatus,
            notesAnnexes.syncMotif,
            notesAnnexes.updatedAt,
          ],
        ),
      );
      await customStatement('DROP TABLE IF EXISTS _map_notes');
    }

    final ecritures = await customSelect(
      'PRAGMA table_info("ecriture_comptable")',
    ).get();
    final ecritureId = ecritures.where((l) => l.read<String>('name') == 'id');
    if (ecritureId.isEmpty ||
        ecritureId.first.read<String>('type').toUpperCase() != 'TEXT') {
      await customStatement('DROP TABLE IF EXISTS _map_pieces');
      await customStatement(
        'CREATE TABLE _map_pieces AS '
        'SELECT exercice_annee AS exercice, numero_piece AS numero, $_uuidSql AS nouveau '
        'FROM (SELECT DISTINCT exercice_annee, numero_piece FROM ecriture_comptable '
        'WHERE numero_piece IS NOT NULL)',
      );
      await m.alterTable(
        TableMigration(
          ecritureComptable,
          columnTransformer: {
            ecritureComptable.id: const CustomExpression<String>(_uuidSql),
            ecritureComptable.pieceId: const CustomExpression<String>(
              '(COALESCE((SELECT nouveau FROM _map_pieces '
              'WHERE exercice = exercice_annee AND numero = numero_piece), $_uuidSql))',
            ),
            // Une ecriture d'hier a ete saisie le jour de son ecriture.
            ecritureComptable.updatedAt: const CustomExpression<String>(
              "strftime('%Y-%m-%dT%H:%M:%fZ', date_ecriture, 'unixepoch')",
            ),
          },
          newColumns: [
            ecritureComptable.pieceId,
            ecritureComptable.contrepasseDe,
            ecritureComptable.origine,
            ecritureComptable.syncStatus,
            ecritureComptable.syncMotif,
            ecritureComptable.updatedAt,
          ],
        ),
      );
      await customStatement('DROP TABLE IF EXISTS _map_pieces');
    }
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
