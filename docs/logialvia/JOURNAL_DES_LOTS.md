# JOURNAL_DES_LOTS — Journal des lots de livraison

**Statut : reconstitué le 2026-11-11 depuis l'historique git** (`origin/main` = `894d98e` ; branche de travail `claude/trusting-carson-s1msqv` = `a007d5c`, 5 commits d'avance, non fusionnée). Aucune date n'est inventée : elles viennent de `git log --format=%ad` (heure d'**auteur**, telle que stockée par git). Les commits écrits pendant les sessions Claude portent le décalage `+0000` ; les fusions faites sur GitHub et le premier commit portent `+0100`. Un même instant peut donc s'afficher à une heure d'écart (par exemple le commit `86509a7` à 16:01 `+0000` est postérieur à la fusion `54e4986` de 16:44 `+0100`).

Les tests cités sont ceux **annoncés dans les messages de commit ou dans les documents du dépôt** ; ils n'ont pas été rejoués pour écrire ce journal (aucun serveur PHP/Flutter n'a été lancé ici).

## 1. Méthode (reproductible)

```bash
git log --first-parent origin/main --format='%h|%ad|%s' --date=iso
git log --format='%h|%ad|%s' --date=iso origin/main..origin/claude/trusting-carson-s1msqv
git log --merges --format='%h %p %s' origin/main
git diff --shortstat <premier parent> <fusion>
```

Chiffres de l'historique relevés : 198 commits sur `origin/main` (191 signés « Claude », 6 « Rhodes Adderly Massenon », 1 « massenon » ; premier commit `142b73c`, 2026-11-05 13:10 `+0100`) ; la fusion #1 amène 170 commits.

## 2. Pull requests

`git log --first-parent origin/main` donne, du plus récent au plus ancien : #4, #3, #2, `601aa42`, `67705e2`, #1, `142b73c`.

| PR | Hash | Date | Périmètre | Volume (premier parent → fusion) |
|---|---|---|---|---|
| (base) | `142b73c` | 2026-11-05 13:10 `+0100` | « first commit » : poste Flutter existant | — |
| **#1** | `54e4986` (fusion de `142b73c` et `6b5487b`, 170 commits) | 2026-11-10 16:44:27 `+0100` | « LogiALVIA : web Laravel, synchronisation poste ↔ web, installateur Windows, README » : W0 à W4, P0 à P9, parité web/poste (`47a_` à `47u_`), droits et horloge (`47g_`), MySQL et réseau réel (`47r_`), stock ciblé (`47s_`), plan SYSCOHADA (`47p_`), tests navigateur (`47n_`), installateur (`47w_`) | 958 fichiers, +175 497 / −14 667 |
| (suite) | `67705e2`, `601aa42` | 2026-11-10 16:58 et 16:59 `+0100` | retrait du logo du README, correction de la liste des fonctionnalités (directement sur `main`) | — |
| **#2** | `18b212a` | 2026-11-11 12:55:09 `+0100` | conformité visuelle du web aux maquettes : connexion, coque, tableau de bord, fiches d'élevage, Ventes, Dashboard Élevage, Stocks, Soins, Rapports, Dépenses, Profil, Comptabilité ; filière **Ovins** remplace Bovins (DV-22) ; modal de synchronisation au poste et au web ; aperçu social et README (sous-titre « Gestion et Suivi Avicole Intégré ») | 168 fichiers, +6 168 / −1 475 |
| **#3** | `7f2cda5` | 2026-11-11 13:58:24 `+0100` | maquettes : Catalogue, Clients et Créances, Achats, Fournisseurs, Paramètres Élevage, Cycle Couveuse, Mirages, Inventaire, Facturation e-MECeF ; essais navigateur adaptés | 15 fichiers, +164 / −96 |
| **#4** | `894d98e` | 2026-11-11 14:47:54 `+0100` | Catalogue (filière, colonne Stock, onglet Seuils d'Alerte), Achats (onglets, filtres mode et dates), Fournisseurs (colonnes), Inventaire (quatre onglets) | 9 fichiers, +201 / −11 |
| **#5 (en cours)** | `a007d5c` (tête de la branche `claude/trusting-carson-s1msqv`) | 2026-11-11 14:16 à 16:12 `+0000` (5 commits) | « PWA + PWA-PERF » : web installable, performance du premier chargement, gardes automatiques (voir §5) | 40 fichiers, +3 831 / −17 (`origin/main` → branche) |

Le numéro #5 vient de la demande ; **aucun outil de ce dépôt ne l'a confirmé** (`gh pr list` est refusé dans cet environnement : GraphQL indisponible) : seul l'état git (5 commits en avance sur `origin/main`) est vérifié.

## 3. Lots fusionnés dans la PR #1 (étapes W0–W4 et P0–P9)

Les étapes sont définies dans `45_PLAN_APPAIRAGE_SYNCHRO_POSTE_WEB.md` §6. Dates = date d'auteur du commit principal (`+0000`, 2026-11-09 sauf mention). Les tests sont ceux **annoncés** par le commit.

| Lot | Commit(s) | Date | Périmètre | Tests annoncés | Limites connues |
|---|---|---|---|---|---|
| Préparation | `790813b`, `32ba573`, `02cc31a` | 2026-11-07 09:22 ; 11-08 06:08 ; 11-08 09:57 | `CLAUDE.md` ; filières escargots et bovins au poste (schéma v27 à v30) ; état d'implémentation du poste | — | la filière Bovins sera remplacée par Ovins le 11-11 (DV-22) |
| Plan et blocage | `0f956af`, `66f8080` | 11-08 12:57 ; 11-09 02:50 | plan d'appairage et de synchronisation (`45_`), décisions DV-19 (poste en UUID), DV-20 (comptes locaux), diagnostic du blocage Composer (archives GitHub refusées) | — | Composer : installer avec `--prefer-source` (`CLAUDE.md`) |
| **P0** contrat | `d614b8a` | 11-09 02:52 | `46_CONTRAT_SYNCHRONISATION.md`, 38 tables classées (brouillon) | — | le tableau d'avancement de `45_` §6 marque encore P0 « à faire » ; `46_` §5 : critère « chaque table dans exactement une catégorie » sans test retrouvé |
| **W0** | `c1bbfc5` | 11-09 03:02 | squelette Laravel 12.71, Livewire 3.8, Sanctum 4.3, Spatie Permission 7.4, DomPDF 3.1, Tailwind 3.4 ; jetons de design repris du Dart | `ConformiteDartTest` (vérifié par mutation) | job CI Laravel « non exécuté ici » (message du commit) |
| **W1** | `18dd5e9` | 11-09 03:18 | utilisateurs UUID, 4 rôles, 22 droits, 5 modules, paramètres, premier administrateur par variable d'environnement | 31 tests | — |
| **W2** | `8216ab3`, `132e5d1` | 11-09 04:10 ; 04:15 | API d'appairage (jeton par poste, 90 jours, révocation), écran « Postes & Appairage », mot de passe obligatoire | 30 puis 89 tests Laravel, gardes vérifiés par mutation | coque web alors provisoire (`45_` §6b) |
| **W3** | `93b5125` | 11-09 04:46 | moteur `pull`/`push` serveur (curseur de réception, idempotence par UUID, dernier écrivain gagne), essai à deux postes | 129 tests (`45_` §6) ; 6 simulations à graine fixe | 3 tables seulement à ce stade |
| **W3b** | `75286c3` | 11-09 04:56 | demandes de synchronisation, renvoi complet, remise à zéro à trois verrous | 144 tests (`45_` §6) | — |
| **P1b** | `e9c9476` | 11-09 05:35 | appairage du poste : identifiant UUID, adresse normalisée, jeton au coffre système, onglet Appairage | 33 tests contre un faux serveur, 8 mutations | restaurer une sauvegarde sur une autre machine copie l'identifiant du poste (`TODO(dette)`, `45_` §6c) |
| **P1a/P2** palier 1 | `4a945af` | 11-09 06:20 | clients en UUID (schéma v31), premier moteur de synchronisation du poste | 52 tests (faux serveur), 13 mutations, 5 essais contre le vrai serveur | — |
| P2 palier 2 | `a20137f`, `5a41e7e` | 11-09 06:55 ; 07:32 | référentiels, planificateur (ouverture, 30 s, gestes, routine, suspension sur 401), demandes de référentiel, synchronisation à la fermeture | 88 tests de synchronisation, 7 essais réels | — |
| **P3a/b/c** | `936c656`, `49bec33`, `a1ddceb`, `fddb68a` | 11-09 07:43 ; 08:01 ; 09:06 ; 09:32 | produits, lignes de vente et ventes en UUID (v33, v34), références à préfixe de poste (DV-21), serveur et poste, sélecteur de client au POS | serveur : 196 tests, 14 mutations ; poste : 142 tests de synchro, 16 du sélecteur, 11 essais réels | références `V-Pn-AAAA-NNN` jamais renumérotées (DV-21) |
| **P4** | `421939c`, `733ebf7` | 11-09 10:01 ; 10:20 | fournisseurs et achats (serveur, poste v35), références `ACH-Pn-…` | serveur : 216 tests, 8 mutations ; poste : 26 tests, 13 essais réels | aucun effet de stock à la réception d'un achat d'un autre poste |
| **P5** | `62aae92`, `263d5c1` | 11-09 11:00 ; 11:11 | intrants (référentiel) et journal des mouvements partagé ; **stock propre à chaque poste** (schéma v36) | serveur : 238 tests, 11 mutations | pas de stock global (décision du client) |
| **P6** | `ea239ab`, `9ec9719`, `3587be0` | 11-09 11:36 ; 11:46 ; 12:03 | journal des corrections de stock des produits (v37) ; motif exigé ; suppression propagée par pierre tombale | essais et docs (compteurs non donnés dans les messages) | — |
| **W4a–W4d** | `3c87600`, `628584c`, `c8bde5c`, `6ca7c03`, `b368868`…`33bab56`, `f01b109` | 11-09 12:07 à 12:59 | coque (barre latérale transcrite du Dart), Catalogue, Clients, Stocks, Tableau de bord, Fournisseurs, Achats, Paramètres, Profil, Aide, Contact ; doc W4 | `ConformiteNavigationDartTest` ; recette §8 de `45_` | écrans dépendant de données non synchronisées déclarés « bloqués » (`45_` §7) |
| **P7a** | `1a61ba1`, `f5f0f6f`, `3657cb4`, `a191c5a` | 11-09 13:55 à 14:07 | fiches journalières, compteurs de ventes du jour, bandes (poste v38, serveur, 8 écrans web) ; doc `46a_` | poste 43 tests (26 mutations) ; serveur 25 tests (17 mutations) ; web 62+11+16+5 tests (31 mutations) | décisions D1 à D10 à valider par le client (`46f_`) |
| **P7b** | `7a2e030`, `831b452`, `ebafd0d`, `7aaae65` | 11-09 13:49 à 14:14 | couveuse et mirages (poste v39, serveur, écrans) ; doc `46b_` | poste 8+59 ; serveur 53 ; web 51+12+14 ; mutations vérifiées | 11 décisions à valider (`46b_`) |
| **P7c** | `2f0e670`, `1236498`, `5d4cf78`, `2ecc5b7` | 11-09 13:56 à 14:16 | soins, infirmerie, barèmes, taux, prophylaxie (poste v40, serveur, écrans) ; doc `46c_` | poste 75 ; serveur 60 ; web 56 ; 34/27/38 mutations | 11 décisions à valider (`46c_`) |
| **P8** | `a49a2f5`, `a915f61`, `1ac55c4`, `659fe8c` | 11-09 14:03 à 14:31 | comptabilité en UUID (v41), écritures, clôtures, notes ; neuf écrans web ; doc `46d_` | non détaillés dans les messages de commit (voir `46d_` §5 (chiffres) et §6 (tests et mutations)) | 14 décisions à valider ; « doute majeur » sur l'ouverture cumulée (levé ensuite par `47c_`) |
| **P9** | `23014a8`, `bad9a15`, `9187eed`, `da4dd44` | 11-09 13:44 à 14:06 | factures e-MECeF et grille de taxation (v42) ; écran Facturation e-MECeF ; doc `46e_` | poste 62 (23 mutations) ; serveur 59 (33) ; web 29 (23) | transmission e-MECeF jamais essayée contre la DGI ni un vrai boîtier (`47v_`) |
| Synthèse P7–P9 | `13229f7` | 11-09 15:02 | `45_` §7.2, `46f_` | — | — |

## 4. Parité web/poste et fiabilisation (même PR #1)

| Lot | Commit(s) | Date (2026-11-09 sauf mention) | Périmètre | Tests annoncés | Limites connues |
|---|---|---|---|---|---|
| W5 écrans | `981dc27`, `f9cb053`, `0de111b` | 16:38 ; 16:41 ; 18:39 | Inventaire, Rapports & États (l'export CSV devient XLSX) | Inventaire 50 tests / 68 mutations ; Rapports 64 tests | pas de PDF généré au web |
| Parité commerce, achats | `e2e0cb2`…`29539d5`, `080daa3`, `ffcea37`, `7ebf8f6`, `8a7b600`, `4554019` | 18:38 à 19:13 | caisse web, recouvrement, impressions, achats complets, fournisseurs, dépenses, docs `47a_`, `47b_` | non détaillés | décisions à valider dans chaque doc |
| Administration | `55e3d6b`, `4736868`, `ae42753`, `401bb83`, `5e6d922`, `aa0b7d3`, `bd7bf16` | 18:36 à 19:08 | utilisateurs, journal d'audit, corbeille, messages à l'éditeur, sauvegarde logique JSON ; doc `47u_` | non détaillés | la sauvegarde logique du web n'est pas restaurable par le web |
| Devis et factures web | `fe1aadd`, `c96d896`, `0640db6`, `f89ccc9`, `0eb066c`, `dc7af1a`, `47c33b8`, `978d4ac` | 18:40 à 19:26 | devis synchronisés (poste v43), émission de factures et d'avoirs au web, verrou de transmission (15 min) ; doc `47a2_` | non détaillés | seul un poste appairé transmet une facture web |
| **`47c_` SYSCOHADA RAN** | `4c0e22b`, `b961acd`, `a6a78ff`, `e6d072e` | 19:13 à 19:15 | report à nouveau, clôture en 4 étapes, réouverture, états cumulés, TAFIRE exact | jeu 2024 calculé à la main (résultat 300 000, à-nouveaux 1 550 000) ; 16 tests web `ReportANouveauTest` | décisions V1 à V6 à valider ; voir `CLOTURE_EXERCICE_SYSCOHADA.md` |
| `47e_` élevage expert | `e66e0a7`, `f042989`, `163e9d4`, `8f9fa83`, `49135a8`, `92d556f` | 19:01 à 19:35 | contrôles zootechniques, divergence de fiche, chaîne d'effectifs ; schéma poste 47 | non détaillés | décisions à valider (`47e_`) |
| **`47h_` vrai serveur** | `e0095ff`…`6648756`, `bb848cf` | 19:18 à 20:16 | essai de toutes les familles de tables poste A → serveur → poste B ; 5 divergences corrigées (D1–D5) + D6 | 55 essais réels | un faux serveur écrit de la même main ne prouvait pas tout (`47h_` en-tête) |
| **`47g_`** droits et horloge | `0caad8d`, `c0d3b42`, `f3f4f08`, `e1ac9b2`, `47243f9`, `198c4ab` | 21:05 à 21:43 | droits annoncés au poste, « en attente de droit », garde d'horloge 5 min ; schéma poste 50 | `DroitsEtHorlogeTest` (19), `droits_et_horloge_poste_test` (30) ; essai réel 68/68 | tolérance de 5 min et seuil d'avertissement de 2 min à valider |
| **`47r_`** MySQL et réseau | `85b559a`, `3eb7ceb`, `3ca20ac`, `5d43ffd` | 21:26 à 21:52 | MariaDB 10.11 et MySQL 8.0.46 : 96 échecs initiaux corrigés ; couche HTTP unique du poste (TLS strict, 413 par dichotomie, rejeu) | suite PHP 1635/1635 puis 1647/1647 ; essai réel 55/55 ; 20 essais derrière un mandataire | hébergeur mutualisé réel **non prouvé** ; environnements déclarés Laragon (test) et cPanel (production) |
| **`47s_`** stock ciblé | `964f50a`, `7001688`, `03cf778`, `017f928`, `b3f4601` | 21:17 à 22:01 | un poste désigné applique l'effet de stock et de PMP d'une opération web une seule fois (schéma 49) | essai réel 61/61 (message du commit `017f928`) ; 23 tests web | décisions à valider (`47s_` §9) |
| **`47n_`** navigateur | `9fd2c15`, `240294f`, `d0ff2e9`, `f2b22d1` | 21:13 à 22:42 | suite Playwright : 52 scénarios (routes, parcours, exports XLSX, impression, accessibilité) | 52/52 (`b7a8016`, 2026-11-11 08:17 `+0000`) | Safari/Firefox non essayés (`45_` §10) |
| **`47p_`** plan SYSCOHADA | `817c864`, `5931373`, `242e7b7`, `55e714b`, `8ca1d5e`, `5e00b13` | 21:17 à 23:52 ; 2026-11-10 00:42 | plan révisé de 60 comptes, TVA ventilée, garde `plan_version`, migration v48 ; vérifié contre le PDF client : 59 comptes sur 60 | tests de conformité Dart ↔ PHP | 611 non confirmé ; relecture par l'expert-comptable recommandée |
| `47v_` e-MECeF | `f5ac4cb`, `c5f3058` | 2026-11-10 00:28 ; 00:35 | état documentaire, prix envoyé en TTC entier | tests de parité du constructeur de facture | rien essayé contre la DGI ni un vrai boîtier ; adresses d'API non confirmées |
| `47w_` installateur | `da1bc6d`, `a353fe2` | 2026-11-10 00:56 ; 09:37 | `build_windows.bat` et `installer/logialvia.iss` ; option `--rapide` interdite en production | **aucun** (écrit, non exécuté) | voir `PROMPT_INSTALLATEUR_WINDOWS_FLUTTER.md` |
| Finitions de la PR #1 | `71065da`, `9845cf7`, `7042e2e`, `77f276a`, `0a3d898`, `6b5487b` | 2026-11-10 10:05 à 15:15 | plus de verrouillage de connexion au poste ; README ; CI MySQL | — | — |

## 5. Lot PR #5 (en cours) : PWA et PWA-PERF

Branche `claude/trusting-carson-s1msqv`, 5 commits au-dessus de `origin/main` (`git log origin/main..origin/claude/trusting-carson-s1msqv`) :

| Commit | Date `+0000` | Contenu |
|---|---|---|
| `94818b1` | 2026-11-11 14:16:01 | « PWA installable + PWA-PERF » : manifeste, icônes, service worker généré (précache suivant le build Vite, cache-first sur `/build`, `/fonts`, `/icons`, page `/hors-ligne`), Livewire/Alpine empaquetés par Vite, CSS critique préchargé, polices WOFF2, axios retiré, middlewares `PrechargerPolices` et `CompresserReponse`, `.htaccess`, `PerformanceAssetsTest` (JS ≤ 300 Ko, CSS ≤ 100 Ko), garde LCP Lighthouse + Playwright, `outils/mesure_performance.sh`, doc `47x_` |
| `f293959` | 2026-11-11 15:27:50 | garde LCP étendue à 37 écrans (connexion + 36), corrections du CLS (Roboto préchargée) et du LCP mobile (bandeau d'installation à la première interaction) |
| `d9402a9` | 2026-11-11 15:49:59 | CI performance : Chrome du runner (plus d'`apt` ni de Playwright `--with-deps`) |
| `cf58cf5` | 2026-11-11 16:02:41 | suppression de la police italique (son échange repoussait le LCP mobile au-dessus de 2 s en CI) |
| `a007d5c` | 2026-11-11 16:12:41 | garde LCP : un dépassement Lighthouse est confirmé par la médiane de 3 passes |

Tests et limites (`47x_PWA_ET_PERFORMANCE.md`) : `PerformanceAssetsTest`, `PwaTest`, `CompresserReponseTest`, garde LCP < 2 s (`e2e/performance.mjs`, workflow `.github/workflows/performance.yml`) ; marge faible sur mobile simulé (≈ 30 à 40 ms sous 2 s) ; mesures en HTTP local (le coût TLS réel n'est pas simulé) ; Lighthouse mobile est un modèle simulé ; **le cache ne sert jamais de page HTML** : la PWA n'apporte **pas** de saisie hors ligne côté web (voir `BLUEPRINT_SYNCHRONISATION_POSTES.md` §12).

```bash
LV_SCRIPT=e2e/performance.mjs bash logialvia_laravel/e2e/lancer.sh
bash logialvia_laravel/outils/mesure_performance.sh https://domaine
```

## 6. Lots de conformité visuelle (PR #2 à #4), 2026-11-11

| PR | Commits | Contenu | Tests / limites |
|---|---|---|---|
| #2 | `7be6855`, `b245289`, `8eb81f0`, `5b964ac`, `fd1533d`, `6a136cf`, `30d5415`, `4932353`, `7b76086`, `f9fc430`, `b7a8016`, `b84f25c`, `7cb328e`, `2a8215a`, `082d8b7`, `86509a7` (06:47 à 11:47 `+0000`, hors `86509a7` du 2026-11-10 16:01) | connexion, coque, tableau de bord, fiches d'élevage, notifications, modal de synchronisation (web et poste), **Bovins → Ovins** (poste v51, migration serveur, alias hérité `bovins` → `ovins`, DV-22), Ventes, Dashboard Élevage, Stocks, Soins, Rapports, Dépenses, Profil, Comptabilité ; échelle de tailles de texte unique et test de garde ; `POST /api/auth/login` sans limite d'essais (décision du client) | 52/52 parcours navigateur (`b7a8016`) ; repères zootechniques ovins « à valider » (message de `f9fc430`) ; le commit `8eb81f0` note « les tests du tableau de bord seront alignés » (corrigé par la suite) |
| #3 | `e53861b`, `8e45c7e`, `5713d27`, `6e5eb72` (12:07 à 12:44) | Catalogue, Clients (onglets Liste / Suivi des Soldes / Relances CRM), Achats, Fournisseurs, Paramètres Élevage, Couveuse, Mirages, Inventaire, Facturation e-MECeF ; essais navigateur adaptés | — |
| #4 | `d861889` (13:28) | champ « Filière » du produit (alimente le compteur de ventes du jour), seuils d'alerte modifiables, colonne « Sur le poste » (le stock reste propre à chaque poste) | — |

## 7. Ce qui n'est pas fait ou pas prouvé (état au 2026-11-11)

- **Installateur Windows** : écrit, **jamais exécuté** sur Windows d'après `47w_` (voir `PROMPT_INSTALLATEUR_WINDOWS_FLUTTER.md` pour la nuance sur les durées « constatées »).
- **e-MECeF** : aucune transmission réelle (DGI ni boîtier) ; adresses d'API non confirmées (`47v_`).
- **Hébergeur mutualisé réel**, MySQL 5.7, charge au-delà de 4 postes, Safari/Firefox : non prouvés (`45_` §10, `47r_`).
- **Décisions métier à valider par le client** : `46f_` et les sections « Décisions à valider » de `47a_` à `47u_`.
- **Plan comptable** : relecture par l'expert-comptable avant la première déclaration fiscale (`47p_` V1).
- **Import en masse** : n'existe pas (`GUIDE_MODELES_IMPORT.md`).
- Il n'existe pas de fichier `RESTE_A_FAIRE` dans le dépôt (recherche `find . -name 'RESTE_A_FAIRE*'` : aucun résultat).

## 8. Reconstituer ce journal

```bash
git log --format='%h|%ad|%s' --date=iso --reverse origin/main | head -60
git log --format='%h|%ad|%s' --date=iso --reverse origin/main..origin/claude/trusting-carson-s1msqv
git show --stat --format='%h %ad %s' --date=iso 54e4986 | head
```
