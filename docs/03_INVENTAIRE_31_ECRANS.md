# 03 — Inventaire des 31 Écrans & Correspondance Fichier → Dart

Liste extraite directement de `/home/claude/logialvia_prototype/` — 31 fichiers réels, aucun ajouté ni omis. Correspondance **1:1 stricte**, conformément à votre décision.

---

## Table de correspondance complète

| # | Fichier HTML source | Écran Dart (`presentation/screens/`) | Route | Catégorie fonctionnelle |
|---|---|---|---|---|
| 1 | `login.html` | `login/login_screen.dart` | `/login` | Authentification |
| 2 | `welcome.html` | `welcome/welcome_screen.dart` | `/welcome` | Authentification |
| 3 | `index.html` | `splash/splash_screen.dart` | `/` | Démarrage |
| 4 | `dashboard.html` | `dashboard/dashboard_screen.dart` | `/dashboard` | Pilotage |
| 5 | `elevage-dashboard.html` | `elevage_dashboard/elevage_dashboard_screen.dart` | `/elevage/dashboard` | Pilotage Élevage |
| 6 | `fiche-goliaths.html` | `fiches/fiche_goliaths_screen.dart` | `/elevage/goliaths` | Fiche Journalière |
| 7 | `fiche-pintades.html` | `fiches/fiche_pintades_screen.dart` | `/elevage/pintades` | Fiche Journalière |
| 8 | `fiche-lapins.html` | `fiches/fiche_lapins_screen.dart` | `/elevage/lapins` | Fiche Journalière |
| 9 | `fiche-poulets-pondeuses.html` | `fiches/fiche_poulets_pondeuses_screen.dart` | `/elevage/poulets-pondeuses` | Fiche Journalière (2 onglets) |
| 10 | `fiche-poissons-chats.html` | `fiches/fiche_poissons_chats_screen.dart` | `/elevage/poissons-chats` | Fiche Journalière |
| 11 | `cycle-couveuse.html` | `couveuse/cycle_couveuse_screen.dart` | `/elevage/couveuse` | Élevage |
| 12 | `soins-calendrier.html` | `soins/soins_calendrier_screen.dart` | `/elevage/soins` | Élevage |
| 13 | `parametres-elevage.html` | `parametres/parametres_elevage_screen.dart` | `/parametres/elevage` | Paramètres |
| 14 | `ventes.html` | `ventes/ventes_screen.dart` | `/ventes` | Commercial (4 onglets) |
| 15 | `catalogue-produits.html` | `catalogue/catalogue_produits_screen.dart` | `/catalogue` | Commercial |
| 16 | `relances-clients.html` | `clients/relances_clients_screen.dart` | `/clients` | Commercial |
| 17 | `gestion-stocks.html` | `stocks/gestion_stocks_screen.dart` | `/stocks` | Stocks |
| 18 | `achats-commandes.html` | `achats/achats_commandes_screen.dart` | `/achats` | Achats |
| 19 | `fournisseurs.html` | `fournisseurs/fournisseurs_screen.dart` | `/fournisseurs` | Achats |
| 20 | `saisie-depenses.html` | `depenses/saisie_depenses_screen.dart` | `/depenses` | Comptabilité |
| 21 | `comptabilite-hub.html` | `comptabilite/comptabilite_hub_screen.dart` | `/comptabilite` | Comptabilité |
| 22 | `journal-comptable.html` | `comptabilite/journal_comptable_screen.dart` | `/comptabilite/journal` | Comptabilité |
| 23 | `plan-comptable.html` | `comptabilite/plan_comptable_screen.dart` | `/comptabilite/plan` | Comptabilité |
| 24 | `comptabilite-analytique.html` | `comptabilite/comptabilite_analytique_screen.dart` | `/comptabilite/analytique` | Comptabilité |
| 25 | `cloture-exercice.html` | `comptabilite/cloture_exercice_screen.dart` | `/comptabilite/cloture` | Comptabilité |
| 26 | `bilan-entreprise.html` | `comptabilite/bilan_entreprise_screen.dart` | `/comptabilite/bilan` | Comptabilité |
| 27 | `rapports-exports.html` | `rapports/rapports_exports_screen.dart` | `/rapports` | Rapports |
| 28 | `parametres-generaux.html` | `parametres/parametres_generaux_screen.dart` | `/parametres/generaux` | Paramètres |
| 29 | `mon-profil.html` | `profil/mon_profil_screen.dart` | `/profil` | Compte |
| 30 | `aide-a-propos.html` | `aide/aide_a_propos_screen.dart` | `/aide` | Compte |
| 31 | `contact-editeur.html` | `aide/contact_editeur_screen.dart` | `/contact` | Compte |

---

## Écrans à onglets internes — attention particulière

Deux fichiers de la liste ci-dessus contiennent **plusieurs vues logiques dans un seul fichier**, via un système d'onglets JS (`switchTab`/`switchHubTab`). Pour respecter la contrainte "1:1 strict" (1 fichier = 1 écran Dart), ces sous-vues doivent être des **widgets internes à l'écran**, pilotés par un `TabController` ou un état local — **pas** des écrans/routes séparés :

- **`ventes.html`** → 4 sous-vues : Enregistrer Vente (POS), Devis Prestations, Historique des Ventes, Retours et Avoirs
- **`fiche-poulets-pondeuses.html`** → 2 sous-vues : Poulets (chair), Pondeuses (ponte, avec suivi SRH/TS/Stock Final)

## Fiches d'élevage — points d'attention pour la fidélité fonctionnelle

Les 5 écrans `fiche-*` (lignes 6 à 10) partagent une structure commune (formulaire journalier + tableau 31 jours + calendrier mobile) mais chacun a des catégories d'espèce propres, déjà normalisées ce trimestre :

| Écran | Catégories réelles (Morts/Dons/Rationnement, uniformisées) |
|---|---|
| Goliaths | Poussin / Goliathau / Mature |
| Pintades | Poussin / Pintadau / Mature |
| Lapins | Lapereau / Chair / Reproducteur |
| Poulets (onglet) | Poussin / Poulette / Adulte |
| Poissons-Chats | Alevin / Juvenile / Mature |
| Pondeuses (onglet) | Poussin Ponte / Croissance / Poulette / Pondeuse (4 catégories) |

→ Détail complet des formules de calcul : **Doc 05**.

---

## Écrans nécessitant la couche de synchronisation partagée

Ces écrans lisent/écrivent tous la **même source de données** (équivalent Dart du `logialvia-store.js`/`LogiALVIASync`, voir Doc 04) — une action dans l'un doit se répercuter visuellement dans les autres sans redémarrage :

- `ventes.html` (écrit : décrémente stock, incrémente vente du jour par espèce)
- `gestion-stocks.html` (lit/écrit le stock)
- Les 5 `fiche-*.html` (lisent le compteur de vente du jour de leur espèce)
