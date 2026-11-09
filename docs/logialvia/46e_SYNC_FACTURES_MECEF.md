# 46e — Synchronisation des factures e-MECeF et de la grille de taxation (tranche P9)

> **Statut au 09/11/2026.** Poste (schéma **v42**), serveur et écran web `/factures-mecef` livrés et testés.
> Tables : `groupes_taxe`, `factures`, `lignes_facture`. Complète `46_` (§2.2, §2.5, §3) et `45_` (§6, §7, §8) ;
> ne les modifie pas : les corrections à y reporter sont listées au §8.
> Décisions de départ : DV-19 (poste en UUID), DV-20 (comptes locaux), DV-21 (préfixe de poste = numéro officiel).

## 1. Ce qui est synchronisé, et comment

| Table | Nature | Clé | Sens |
|---|---|---|---|
| `groupes_taxe` | **référentiel** : le serveur gagne | la **lettre** (`A`, `B`) ; `id` UUID v5 déterministe `groupe_taxe:<lettre>` | serveur → postes seulement |
| `factures` + `lignes_facture` | **fait** : jamais fusionné, lignes **imbriquées** (`lignes: [...]`), jamais scindées | `id` UUID (poste) ; `ref` reste la clé primaire locale | poste émetteur → serveur → autres postes |

**Grille de taxation.** Semée **à l'identique** au poste (`GroupesTaxeSeeder` Dart) et au serveur (`GroupesTaxeSeeder` PHP) :
`A` Exonéré 0 % (l'élevage, arbitrage de la Gérante), `B` Taux normal 18 %. Les autres lettres de la grille DGI ne sont pas
inventées. L'UUID déterministe est calculé de la même façon des deux côtés (valeurs figées dans `GroupesTaxeTest` et
`factures_sync_poste_test.dart` : un des deux qui change fait échouer l'autre).
Règle d'absorption au poste (même principe que `parametres_entreprise`, `45_` §6e) : une ligne dont `updated_at == created_at`
est une **valeur de semis**, jamais une décision ; elle crée un groupe absent mais n'écrase **jamais** une grille corrigée à
la main. Une ligne décidée par le serveur l'emporte. Un groupe absent du serveur n'est jamais supprimé (des lignes de facture
le citent). Une ligne incohérente (lettre, libellé vide, taux hors 0-100, UUID qui n'est pas celui de la lettre) est refusée.

**Schéma poste v42** (`_facturesEnUuid`, idempotent, **une garde par table**) : `factures` reçoit `id` (UUID, unique),
`origine`, `sync_status`, `sync_motif`, `updated_at` ; `lignes_facture.id` passe en UUID texte. Rien ne bouge d'autre :
références `FV-2026-001` conservées, aucune ligne perdue (les lignes ne tiennent à leur facture que par le texte `facture_ref`,
sans clé étrangère : la reconstruction n'emporte rien), grille de taxation intacte. Une facture d'hier est **à envoyer** ; son instant
de saisie est celui de sa dernière modification connue (sa normalisation, sinon son émission), **jamais** l'instant de la
migration (il la ferait gagner contre une correction faite ailleurs). Migration interrompue entre les deux tables : elle reprend
là où elle s'est arrêtée, sans changer un UUID de facture. Testée sur une vraie base v41 (`migration_v42_factures_test.dart`, 9 tests).

**Serveur** : migration `2026_11_09_144000_create_groupes_taxe_factures_tables.php`, modèles `GroupeTaxe`, `Facture`,
`LigneFacture`, tables de synchronisation `GroupesTaxeTable` et `FacturesTable` déclarées dans `sync.tables` **juste après
`VentesTable`**, `GroupesTaxeSeeder`. Droits : lecture `view-facturation` (admin, comptable, caissier), écriture
`manage-facturation` (admin, comptable).

## 2. Qui l'emporte quand deux postes divergent sur le statut d'une facture

**Le rang, pas l'horloge.** Machine à états à sens unique :

```
à transmettre (0)  <  rejetée (1)  <  normalisée (2)
```

Un statut **ne régresse jamais**, même venant d'une saisie plus récente : une horloge de poste en avance ne peut donc pas
« dé-normaliser » une facture. Une rejetée peut être retransmise (donc devenir normalisée), jamais redevenir « à transmettre ».
Mêmes règles au serveur (`FacturesTable`) et au poste (`TableFacturesPoste`), éprouvées des deux côtés :

| Cas | Serveur | Poste (à l'absorption) |
|---|---|---|
| reçu plus avancé que le détenu | applique | applique, **même sur une saisie locale non envoyée** (comptée « supplantée ») |
| reçu moins avancé que le détenu | **refuse** (« un statut ne régresse jamais ») | conserve sa saisie, qui partira |
| deux **rejets** | le plus récent gagne, un rejet plus ancien est sans effet | idem (dernier écrivain gagne) |
| deux **normalisations identiques** (rejeu) | accepte sans rien changer (ne relance pas le tirage) | marque `synced` |
| deux normalisations **différentes** (double transmission à la DGI) | **refuse** avec son motif ; garde la première reçue | **conserve la sienne, marque `conflict`** avec le motif, ne l'écrase pas |

Une double normalisation est un **incident fiscal** (la même facture a deux codes à la DGI) : elle n'est jamais départagée en
silence. Elle reste visible comme conflit au poste qui l'a causée ; la comptable doit la signaler à la DGI et, au besoin, émettre
un avoir. Un conflit n'est jamais renvoyé en boucle.

**Contenu immuable.** Après création, ni l'entête ni les lignes ne changent : un envoi qui modifie le client, un total, la
référence ou les lignes d'une facture connue est **refusé** (« Une facture émise ne se modifie pas : émettez un avoir »). Seuls le
statut et ce que la DGI a rendu (code, NIM, compteur, lien, date, erreur) évoluent, selon la machine à états ci-dessus. Au poste,
`normaliser` refuse de renormaliser et `marquerRejetee` ne fait jamais régresser une facture normalisée.

**Validation stricte** (poste et serveur, mêmes règles) : UUID, référence `(FV|FA)-(P<n>-)?AAAA-NNN+` cohérente avec le type,
au moins une ligne, quantité > 0, groupe = une lettre majuscule, taux entre 0 et 100, `total_ttc = total_ht + total_taxe` et
totaux **égaux à la somme des lignes** (tolérance d'arrondi 0,01 FCFA par ligne). Un avoir porte **la facture qu'il corrige et un
motif** ; une facture de vente ne désigne aucune origine. « Normalisée » = un code **et** un NIM **et** une date ; sinon ni code
ni NIM (une facture « normalisée » sans code serait un mensonge sur le document imprimé).

**Une seule facture de vente par vente.** Le serveur refuse une seconde `FV` qui vise la même `vente_ref` (« Cette vente porte
déjà la facture FV-… »), globale pour une référence à code de poste, propre au poste sinon. Deux postes qui facturent la même
vente hors ligne : le premier arrivé gagne, l'autre voit un conflit explicite. Un avoir, lui, vise une facture de **vente**
connue du serveur (« La facture d'origine est inconnue du serveur » sinon) ; le poste envoie **les factures avant les avoirs**
(une facture normalisée tard a un `updated_at` plus récent que son avoir).

## 3. Numérotation (DV-21)

`FV-P2-2026-001`, `FA-P2-2026-001` pour un poste appairé ; `FV-2026-001` pour un poste jamais appairé (le code attribué survit à la
déconnexion). Séquence continue **par poste, par type et par année**, calculée sur le **maximum numérique** (le tri du texte
placerait `…-1000` avant `…-999` et produirait un doublon ; testé). `P1` et `P12` ne se mélangent pas. Une facture n'est **jamais
renumérotée**, ni au poste ni au serveur. Unicité : `UNIQUE(portee_reference, reference)`, globale avec code de poste,
par poste sans code (comme les ventes et les achats).

## 4. Secrets et transmission : ce qui reste au poste

- **La transmission à la DGI reste au poste.** Le serveur et le web n'appellent jamais e-MECeF : ils n'ont ni client HTTP, ni jeton,
  ni URL pour cela (testé : `Http::fake()` + `assertNothingSent`, et le composant web est scanné : aucune référence à `Http`,
  `mecef_url`, `jeton`).
- **Le jeton e-MECeF ne quitte jamais le coffre du système** (`flutter_secure_storage`). Il n'est ni dans le corps d'envoi
  (testé, y compris avec un jeton secret réel dans le coffre de test), ni en base serveur. La liste des colonnes servies par le
  serveur est **fermée** (testée à l'égalité) : un champ en trop échoue.
- Le serveur reçoit : la facture, ses lignes, son statut et ce que la DGI a rendu **pour cette facture** (code de normalisation,
  NIM **imprimé sur la facture**, compteur, lien de vérification, date, message d'erreur). Voir « Décisions à valider » D1 à propos du NIM.
- **Un seul poste normalise une facture : celui qui l'a émise.** Une facture absorbée d'un autre poste porte `origine` (le poste
  émetteur) ; elle est lisible et imprimable, mais ni « Transmettre » ni « Saisir le code de normalisation » ne lui sont offerts, et
  le dépôt refuse (`StateError`, message en français). Cela empêche la cause la plus probable d'une double normalisation (deux
  postes qui transmettent la même facture). Elle ne repart jamais du poste qui l'a absorbée.
- **Règle actée** : absorber le fait d'un autre poste n'a **aucun effet de bord local** : ni écriture comptable, ni lien forcé avec
  la vente, ni stock, ni compteur de numérotation, ni événement, ni transmission (testé : écritures et stock de B inchangés).

## 5. Écran web `/factures-mecef` (module `mecef`)

Lecture seule, conforme au Dart (`factures_mecef_screen.dart`, mêmes libellés) : KPI **Facturé net** (ventes **moins** avoirs),
**À transmettre**, **Normalisées** (statut **et** code réellement reçu), **Rejetées**, calculés sur **toutes** les factures
(pas sur la liste filtrée) ; filtres de statut (Toutes / À transmettre / Normalisée / Rejetée) ; recherche référence ou client
(jokers `%` et `_` littéraux) ; tableau ≥ 640 px, cartes en dessous ; un avoir est en négatif et nomme sa facture (« sur FV-… ») ;
détail (lignes, totaux par groupe de taxe, champs de la DGI **seulement si normalisée**, erreur si rejetée, poste d'émission).
Dates dans le fuseau de l'entreprise. Le module suit `parametres_entreprise.mecef_actif` : 404 quand il est désactivé, entrée de
la barre latérale masquée. **Aucune méthode d'écriture** : le composant n'expose que `filtrer`, `ouvrir`, `fermer`, `render`
(testé par réflexion), donc aucun droit `manage-facturation` à vérifier.

**Écarts déclarés (dans l'écran, bandeau `data-ecart="factures-mecef"`)** :

| Dart | Web |
|---|---|
| Émettre une facture (à partir d'une vente encaissée) | **absent** : l'émission suppose la vente, ses lignes, le groupe de taxe du produit et le poste émetteur |
| Transmettre à e-MECeF, saisie manuelle du code | **absent, par principe** : jeton et URL au poste |
| Émettre un avoir | **absent** |
| Export / impression PDF | **absent** |
| Bandeau « Transmission non configurée » | sans objet (le web ne transmet pas) ; remplacé par le bandeau d'écart |
| Icônes Material Symbols | absentes (police non embarquée, `45_` §7) |

## 6. Limites connues

- **Contrat e-MECeF non éprouvé** contre le service réel (déjà déclaré dans `transmission_mecef.dart`) ; cette tranche n'y touche pas.
- **Pas d'essai contre le vrai serveur Laravel** pour ces tables (`test/integration/serveur_reel_test.dart` non étendu). Le faux
  serveur Dart rejoue les règles du vrai (`FacturesTable`), mais les deux ont été écrits par la même main : à croiser à la recette.
- **Un conflit n'a pas d'écran dédié** au poste : la facture passe `conflict` avec son motif (visible par l'indicateur de
  synchronisation « à vérifier ») ; la comptable doit l'instruire.
- **Les écritures comptables ne sont pas synchronisées** (`ecriture_comptable` hors périmètre) : une facture reçue d'un autre poste
  n'en crée aucune, par construction.
- `vente_ref` est un **texte** (la référence de la vente), pas une clé étrangère : la facture est acceptée même si sa vente est
  refusée ou pas encore connue du serveur (une pièce fiscale ne doit pas rester coincée).
- Une facture n'est **jamais supprimée** ni archivée (pièce fiscale) : pas de pierre tombale, pas d'écran de suppression.
- **Poste restauré sur une autre machine / réinstallé** : une facture déjà connue du serveur reviendrait avec `origine` = son propre
  ancien poste (donc non transmissible d'ici). Une réinstallation est un **nouveau** poste (`46_` §3) ; à traiter avec la
  régénération de l'identifiant du poste (`TODO(dette)` de `45_` §6c).
- Le groupe de taxe d'une ligne n'est pas contrôlé contre la grille du serveur (format seulement) : la grille du poste peut avoir
  une lettre que le serveur n'a pas. Une facture n'est pas refusée pour cela.
- **Serveur déjà installé** : la migration crée la table vide ; semer la grille par `php artisan db:seed --class=GroupesTaxeSeeder`
  (idempotent). Sans cela le poste garde sa propre grille, qui est la bonne.
- Modifier la grille au poste n'est possible que dans la base (aucun écran) et n'est **pas proposé** au serveur (aucune demande
  `groupe_taxe` n'existe) ; le web n'a pas non plus d'écran pour la modifier.

## 7. Décisions à valider par le client

Chaque choix douteux a reçu l'option la plus prudente ; aucun n'a bloqué.

| Id | Question | Option retenue (prudente) | Alternative |
|---|---|---|---|
| **D1** | Le **NIM** de chaque facture voyage-t-il vers le serveur ? La consigne dit « URL/NIM restent au poste ». | Le NIM **imprimé sur la facture** (rendu par la DGI) est envoyé avec le code : une facture normalisée sans lui serait incomplète au web et sur un autre poste (réimpression). **Doute** : la configuration `mecef_url` et `mecef_nim` des *Paramètres* est déjà synchronisée par la tranche `parametres_entreprise` (`DemandesReferentiel::CHAMPS_PARAMETRES`) ; non touchée ici. | Retirer le NIM des factures ; décider aussi si `mecef_url`/`mecef_nim` doivent quitter le poste |
| **D2** | Qui peut transmettre une facture ? | **Seul le poste émetteur.** Si ce poste est détruit, ses factures non transmises ne peuvent plus l'être d'un autre poste. | Autoriser tout poste, au risque d'une double normalisation (traitée, mais après coup) |
| **D3** | Double normalisation (deux codes DGI pour une facture) | Jamais départagée en silence : le serveur garde la **première** reçue, le poste fautif garde la sienne en conflit. Avoir à émettre. | Le serveur garde la dernière / une règle métier DGI |
| **D4** | Remise à zéro du serveur | Le serveur efface ses factures (comme toute table de faits). Le **poste conserve ses factures normalisées** (pièces fiscales, conservation légale) et les renvoie ; il purge les autres. | Tout effacer partout, ou ne jamais effacer les factures normalisées au serveur |
| **D5** | Compte `caissier` | Il **lit** les factures (DV-06) mais le serveur lui **refuse** l'écriture (`manage-facturation` : admin et comptable). Le poste du caissier crée aujourd'hui des factures (écart `45_` §4b non corrigé) : tant que l'appairage se fait avec un compte sans `manage-facturation`, ses factures seraient refusées. Appairer avec le compte de l'administrateur (`45_` §5) évite le problème. | Donner `manage-facturation` au caissier, ou corriger le poste (DV-06) |
| **D6** | Une facture de vente par vente | Imposée au serveur (le premier arrivé gagne, l'autre est en conflit). | Autoriser plusieurs factures par vente et laisser la comptable trancher |
| **D7** | Numérotation `FV-`/`FA-` | Préfixe de **poste** (DV-21), jamais renumérotée par le serveur. `46_` §3 laissait « la numérotation fiscale à la machine e-MECeF/au serveur » : la **numérotation fiscale** que renvoie la DGI (compteur) est conservée telle quelle, à côté du numéro de la pièce. | Numéro unique attribué par le serveur |
| **D8** | Grille de taxation | Deux groupes semés ; le serveur gagne seulement quand il a **décidé** ; aucune modification n'est proposée par un poste ni par le web. | Ajouter l'écran et la demande `groupe_taxe` quand la grille officielle de la DGI sera vérifiée |
| **D9** | Web | Lecture seule, sans émission, avoir ni PDF (écarts du §5). | Émission d'un avoir au web, par un fait rejoué (nécessite la règle de transmission au poste) |
| **D10** | Facture sans vente connue | Acceptée (la vente est un texte). | Refuser tant que la vente n'est pas synchronisée |

## 8. À reporter dans les documents partagés (le coordinateur)

- `46_` §2.5 : sur les 5 tables « comptabilité », `factures` et `lignes_facture` sont désormais des **faits synchronisés** (ce document) ;
  `ecriture_comptable`, `notes_annexes`, `clotures_periodiques` restent hors synchronisation. `groupes_taxe` reste un référentiel (§2.2),
  désormais branché.
- `46_` §3 « Hors du champ de B » : les factures `FV-`/`FA-` portent le préfixe de poste (D7).
- `45_` §6 (ordre de travail) et §7.1 (écrans convertis) : ligne « Facturation MeCeF », écarts du §5 ci-dessus ; §7.2 : « factures MeCeF » n'est plus bloqué.
- `config/logialvia.php` : `GroupesTaxeTable` et `FacturesTable` après `VentesTable` ; `DatabaseSeeder` : `GroupesTaxeSeeder`.

## 9. Tests et mutations

| Couche | Fichier | Tests |
|---|---|---|
| Poste, migration | `test/core/migration_v42_factures_test.dart` | 9 |
| Poste, synchronisation | `test/commercial/factures_sync_poste_test.dart` (faux serveur étendu : `test/core/sync/faux_serveur_sync.dart`) | 53 |
| Serveur | `tests/Feature/Sync/FacturesTest.php`, `GroupesTaxeTest.php` | 59 |
| Web | `tests/Feature/Web/FacturesMecefWebTest.php` | 29 |

Suites complètes vertes : Flutter 1452 tests (`flutter analyze` : « No issues found! »), PHP 544 tests, `npm run build` OK.

**Mutations** (chacune : casser une garde, voir un test rougir) : poste 21, serveur 32, web 23 — toutes tuées. Les survivantes
du premier passage ont été **renforcées** : poste (renormaliser une facture normalisée ; maximum de séquence lexicographique ;
totaux de l'entête non vérifiés), serveur (somme des lignes vérifiée sur le seul HT), web (filtre de statut inconnu, date en UTC,
code du poste d'émission, indicateurs calculés sur la liste filtrée). Gardes éprouvées : rang du statut (les deux sens), double
normalisation, contenu immuable, aucun envoi d'une facture d'un autre poste, jeton absent du fil, pièces normalisées conservées à la
remise à zéro, ordre facture avant avoir, une facture par vente, portée des références, droits de lecture et d'écriture, module
`mecef`, aucune méthode d'écriture au web.
