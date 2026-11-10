# 47h — Preuve de la synchronisation poste ↔ VRAI serveur (toutes les tables)

> **Pourquoi.** Tout ce qui a été fait de P3 à P9 avait été éprouvé contre `faux_serveur_sync.dart`, écrit de la même main que le code
> testé. Un faux serveur ne peut prouver que ce que son auteur a pensé à y mettre. Cette étape rejoue **chaque famille de tables** contre
> le **vrai** serveur Laravel (`php artisan serve`, base SQLite neuve, migrations + seeders), avec des postes Flutter complets
> (`AppDatabase` en mémoire, `SeedInitial`, les 28 `Table*Poste` de `main.dart` dans leur ordre, HTTP réel).
>
> **Résultat.** 55 essais contre le vrai serveur, tous verts, sous UTC, `Africa/Porto-Novo` et (sur un état antérieur du serveur)
> `America/Los_Angeles` / `Pacific/Kiritimati`. **Cinq vraies divergences** trouvées et corrigées (D1 à D5), plus une constatation
> d'essai (D6, sans correctif).

## 1. Relancer la preuve

```bash
bash logialvia_app/outils/essai_vrai_serveur.sh          # port 8765 ; FLUTTER=/chemin/flutter si besoin ; TZ=Africa/Porto-Novo possible
```

Le script crée la base jetable (`/tmp/lv/essai.sqlite`), les comptes `admin1…admin150`, `caissier1`, `comptable1`, `animalier1`, active la
remise à zéro (`REMISE_A_ZERO_ACTIVEE=true`), lance le serveur puis `flutter test test/integration/serveur_reel_test.dart`. L'essai est
ignoré sans `LOGIALVIA_SERVEUR` (la procédure détaillée est en tête du fichier). `LOGIALVIA_LARAVEL` + `LOGIALVIA_DB` permettent de rejouer
les écritures des **écrans web** (qui écrivent par les mêmes absorbeurs que le poste) par `artisan tinker`.

## 2. Ce qui est prouvé, famille par famille

Chaque ligne = au moins un parcours **poste A → serveur → poste B** réel, avec comparaison des valeurs (et non seulement des comptes).

| Famille | Tables | Parcours réel |
|---|---|---|
| Modules, paramètres | `modules_actifs`, `parametres_entreprise` | réglage décidé au serveur ; module proposé par A puis reçu par B ; 20 champs des paramètres saisis en A, lus en B ; refus du caissier avec le motif réel |
| Catalogue | `produits_vendables`, `groupes_taxe`, `mouvements_produit` | création (stock initial journalisé), correction de prix, correction de stock motivée, suppression par pierre tombale, poste neuf qui ne recrée pas un produit archivé ; stock jamais synchronisé |
| Intrants et journal | `intrants`, `mouvements_intrant` | création, ajustement d'inventaire, journal reçu sans toucher au stock de B, **suppression (D4)** |
| Clients | `clients` | création, correction croisée, dernier écrivain gagne, créance calculée par le serveur, créé/modifié/supprimé au web |
| Ventes | `ventes`, `lignes_vente`, `fiche_ventes_jour` | comptant, crédit, mobile money, livraison facturée, échéance, encaissement du solde, annulation ; références à code de poste ; compteurs par poste |
| Fournisseurs, achats | `fournisseurs`, `achats`, `lignes_achat` | commande, réception, règlement, 6 intrants (3 comptes de charge), fabrication de provende |
| Factures | `factures`, `lignes_facture` | facture, avoir, normalisation (code, NIM, compteur, lien) reçue par B |
| Fiches, bandes | `fiche_journee`, `bandes` | **les huit filières**, trois jours chacune (décès, dons, pesée, œufs) comparés colonne par colonne ; bande créée, clôturée, code en double |
| Couveuse | `machines_incubateur`, `cycles_couveuse` | incubateur, lot, deux mirages, éclosion avec remplacement (sous-lot), suppression, lot écrit au web (`C-WEB-…`) |
| Soins | `soins_calendrier`, `infirmerie`, `baremes_ration`, `taux_ration_poids`, `calendrier_prophylaxie` | soin confirmé, entrée clôturée, décès reporté ; barèmes/taux/échéances créés, modifiés, **supprimés** |
| Comptabilité | `plan_comptable`, `exercices_comptables`, `ecritures`, `notes_annexes`, `clotures_periodiques`, `cloture_exercice` | compte créé ; pièce manuelle (décimaux) ; **toutes** les écritures automatiques (ventes, annulations, achats, règlements, fabrication, `ANN-`) ; note annexe ; clôture de mois et écriture refusée dans un mois clos ; **clôture annuelle** et pièce refusée dans l'exercice clos |
| Transverses | — | remise à zéro (mot exact, 409 sur ancienne marque, purge, saisies perdues comptées, exercice rouvert) ; hors ligne puis reconnexion ; rejeu idempotent ; deux postes hors ligne sur la même fiche/le même client ; **quatre postes qui synchronisent en même temps** ; 450 clients en lots de 100 tirés sur plusieurs pages ; refus motivés par famille ; 409/403/table inconnue sur le fil ; droits de `caissier`, `comptable`, `animalier` |
| Contrôles croisés | — | semis du serveur = semis du poste (plan comptable, grille de taxation, modules) ; jeu de données riche (toutes colonnes facultatives) comparé **colonne par colonne** sur 17 tables ; calcul des fiches **web (`FichesElevage`) = poste (`EnregistrerJourneeUseCase`)** pour les 8 filières |

## 3. Divergences trouvées (vrais bugs)

### D1 — L'adoption initiale d'un second poste écrasait la correction du premier

- **Symptôme.** Le poste A corrige un barème de ration (110 → 140 g) ; le poste B, neuf, fait son premier cycle : le serveur repasse à 110 g et
  renvoie 110 à A. Même défaut pour un prix de produit, le seuil d'un intrant (essai réel : barème `bovins/Veau`, 1507 → 1500).
- **Cause.** `adopter*SiBesoin` propose « tout mon semis » datée de l'instant présent ; le serveur applique « dernier écrivain gagne » : le semis
  intact de B est plus récent que la décision de A. Le faux serveur ne l'avait jamais montré (aucun test ne faisait passer un second poste
  après une correction).
- **Correctif (poste).** `DepotDemandesReferentiel` : l'adoption est datée de `instantAdoption` (2000-01-01 : identique accepté, décision plus
  récente conservée et redescendue, jamais remplacée) et ne remplace pas une demande déjà en attente pour la clé (une correction faite *avant* le
  premier cycle garde son instant réel).
- **Tests.** Faux serveur : `test/core/sync/adoption_sans_ecrasement_test.dart` (barème, produit, intrant, correction d'avant le premier cycle,
  instant d'adoption) — rouge sans le correctif. PHP : `FideliteEtAdoptionTest` (produit, intrant, barème : adoption refusée avec motif sans rien
  changer ; ligne inconnue créée puis vraie décision acceptée). Réel : « référentiels et paramètres ».
- **Reste.** Deux postes qui modifient **différemment** la même ligne de semis *avant* leur premier cycle : la seconde adoption (instants égaux)
  est refusée avec le motif « modification plus récente… » et le poste prend la valeur du serveur. Voulu : le serveur fait foi.

### D2 — Le serveur altérait les textes envoyés (rognage, « vide = null »)

- **Symptôme.** Une note annexe saisie avec un retour à la ligne final, une observation de bande, le traitement de la fiche du jour : le poste B
  lisait un texte différent de celui du poste A (`"…ligne\n"` → `"…ligne"`, `""` → `null`).
- **Cause.** Les middlewares globaux `TrimStrings` et `ConvertEmptyStringsToNull` de Laravel s'appliquaient aussi à `/api/sync/*`.
- **Correctif (serveur).** `bootstrap/app.php` : les deux sont désactivés pour `api/sync/*` (le web les garde). Une désignation faite d'espaces reste
  refusée (`required` rogne lui-même).
- **Tests.** PHP : `FideliteEtAdoptionTest` (texte libre octet pour octet, chaîne vide conservée, désignation d'espaces refusée) — rouge sans le
  correctif. Faux serveur : `comptabilite_sync_poste_test` (note à retour final, accents, emoji). Réel : « fidélité » (textes limites, 6 000 caractères).
- **À savoir.** Le poste B **normalise** déjà à l'absorption les champs courts (noms, libellés, motifs : rognage, vide = absent) ; la fidélité
  octet pour octet ne vaut donc que pour les champs de texte libre (note, observation, traitement), ce que l'essai vérifie.

### D3 — Les frais de livraison facturée déséquilibraient la pièce de vente

- **Symptôme.** Contre le vrai serveur : « Pièce déséquilibrée : débit 19 500 ≠ crédit 18 000 » ; la pièce restait en conflit pour toujours.
- **Cause (poste).** Les frais entrent dans le total de la vente (donc au débit : encaissé + créance) mais `_ventilerVente` ne créditait que les lignes
  du panier. La balance du poste était elle-même déséquilibrée ; même défaut pour la contrepassation à l'annulation. Le serveur avait raison.
- **Correctif (poste).** `ventes_repository_drift.dart` : les frais sont crédités au compte de produit de la première ligne, **sans centre
  analytique** (aucune filière n'en est propriétaire), à la vente et à l'annulation. Le plan n'a pas de compte de « port facturé » : choix à valider
  avec le client (voir `46f_`).
- **Tests.** `test/comptabilite/ecritures_vente_livraison_test.dart` (équilibre, deux comptes de produit, annulation, autres modes) ; faux serveur
  (`comptabilite_sync_poste_test`, pièces acceptées) ; PHP (contrat : pièce sans le crédit des frais refusée, avec le crédit acceptée) ; réel :
  « colonne par colonne » et « écritures automatiques ».

### D4 — Supprimer un intrant ne supprimait rien ailleurs et un tirage complet le ressuscitait

- **Symptôme.** Intrant supprimé au poste A : toujours présent chez B ; « Renvoyer vers ce poste » (ou une réinstallation) le recrée chez A.
- **Cause.** Les produits ont une pierre tombale (`archive_le`, `46_` §15), les intrants non.
- **Correctif.** Serveur : colonne `intrants.archive_le` (migration), portée globale qui le cache des écrans (la synchronisation le sert quand même),
  demande `intrant` avec `archive`. Poste : la suppression propose l'archivage (après l'archivage local réussi), l'absorbeur archive localement sauf
  intrant déjà cité par un achat ou un mouvement d'ici, la restauration depuis la corbeille lève la pierre tombale. Faux serveur aligné.
- **Tests.** `test/approvisionnement/suppression_intrant_sync_poste_test.dart` (4) ; PHP : `FideliteEtAdoptionTest` (archivage, restauration, ancien refusé,
  mouvement d'un intrant archivé accepté, drapeau invalide) ; réel : « suppressions propagées ».
- **À savoir.** Un écran web qui crée un intrant de même code qu'un intrant archivé le verra comme libre (la portée le cache) : conflit de clé
  primaire à signaler aux équipes web (`GestionStocks`).

### D5 — La remise à zéro du serveur répondait 500 dès qu'un achat existait

- **Symptôme.** `POST /api/parametres/remise-a-zero` : « FOREIGN KEY constraint failed, delete from "fournisseurs" » ; rien n'était effacé.
- **Cause.** `RemiseAZeroService` effaçait les tables de faits dans l'ordre **direct** de `sync.tables` (parent avant enfant). Le poste, lui, purge déjà
  à l'envers ; le faux serveur ignore les clés étrangères, et le test PHP existant n'avait aucun achat.
- **Correctif (serveur).** Ordre inverse (`array_reverse`).
- **Tests.** PHP : `DemandesEtRemiseAZeroTest::test_la_remise_a_zero_efface_dans_l_ordre_inverse_des_dependances` — rouge sans le correctif ; réel : « remise à zéro ».

### D6 — Constatation (non corrigée) : un poste appairé à un compte sans droits propose tout son semis… et tout est refusé

Un poste appairé au compte `caissier1` propose à son premier cycle le semis complet (barèmes, taux, échéances, plan comptable, intrants) : environ 74 demandes
sont refusées (« Droit insuffisant… ») et restent en `conflict` dans `demandes_referentiel`. Sans conséquence sur les faits ni sur ce que le poste reçoit
(le serveur fait foi), mais bruyant, et le poste ne les reproposera pas si la Gérante reconnecte plus tard un compte administrateur (adoption « une seule
fois »). À décider avec le client : n'adopter qu'avec un compte qui peut écrire, ou reproposer à chaque changement de compte.

## 4. Vérifié et conforme (aucune divergence)

- Semis : plan comptable, grille de taxation, modules, UUID de produits/barèmes/incubateurs/fiches/notes/clôtures identiques poste/serveur.
- Dates : jour civil sans décalage sous UTC, UTC+1, UTC−8, UTC+14 ; pas de décalage d'une heure en traversant un changement d'heure (l'écart vu au début
  venait de l'essai : `add(Duration(days:))`).
- Décimaux (12 345,67 ; 301,25 ; 4 321,09 ; frais 1 500,5) : identiques A/B ; tolérance de 0,01 identique des deux côtés (`>` au serveur, `<` au poste, égalité exclue
  des deux côtés).
- Calcul des fiches journalières : `FichesElevage` (web) et `EnregistrerJourneeUseCase` (poste) donnent les mêmes effectifs et les mêmes stocks d'œufs pour les huit filières.
- Droits : `caissier` (ventes, clients, écritures de vente, compteurs), `comptable` (pièces, notes ; ses ventes refusées avec motif), `animalier` (élevage), `admin`.
- Concurrence : quatre postes simultanés (ventes, pièces, même fiche du jour) : aucun échec, convergence.
- Volume : 450 lignes, 3 pages de tirage, aucune ligne sautée ; rien à renvoyer au tirage suivant.

## 5. Ce qui n'a PAS pu être prouvé

- **MySQL.** Tout l'essai tourne sur SQLite. Non éprouvés : collation insensible à la casse (`UNIQUE(code)`, `B1` contre `b1`), tailles/troncatures, bornes de `datetime`,
  verrous et interblocages en vraie concurrence, `LIKE` et accents, isolation des transactions. À refaire sur le MySQL de production avant la mise en service.
- **Horloge d'un poste en avance.** « Dernier écrivain gagne » compare les instants de saisie du poste : une horloge avancée de plusieurs jours gèle la ligne contre les
  saisies des autres. Aucune garde au serveur (refus d'un instant futur) : à décider.
- **Réseau réel.** TLS, mandataire (413 sur un gros lot), coupure au milieu d'un lot : seul « hors ligne entre deux cycles » est rejoué (adresse injoignable).
- **e-MECeF réel.** La normalisation est simulée par le dépôt local (`normaliser`), jamais par la DGI.
- **Clôture annuelle : report à nouveau.** Le « doute majeur » de `46d_` (le Dart ne cumule pas l'ouverture, report à nouveau codé nulle part) n'est pas levé : l'essai prouve le
  verrouillage et la propagation, pas la justesse comptable de l'exercice suivant. La **réouverture d'un mois** (`decloturerMois`) n'a pas été rejouée contre le vrai serveur.
- **Écrans web.** Seules leurs **écritures** sont rejouées (même absorbeurs, poste web UUID nul, codes `C-WEB-…`, `DEP-WEB-…`) ; les composants Livewire eux-mêmes ne le sont pas.
- **Volumétrie.** 450 lignes, pas plusieurs dizaines de milliers ; pas de pagination du tirage forcée à 200 lignes par table sur ventes/lignes.
- **Planificateur et écrans du poste** (déclenchement toutes les 30 s, indicateur, modale) : couverts par les tests à faux serveur, pas par cet essai.
- **Reprise sur lot partiel d'une table multi-lignes** (vente + lignes) coupé en plein milieu par une panne réseau : non reproduit sur le vrai serveur.
