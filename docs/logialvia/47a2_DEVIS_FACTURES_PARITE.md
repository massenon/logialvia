# 47a2 — Parité poste / web : devis de prestations et facturation MeCeF

> **Statut au 09/11/2026.** Poste (schéma **v43**), serveur et web livrés et testés. Complète `46e_` (factures) et `45_` ; ne les
> modifie pas : les corrections à y reporter sont au §9. Le Dart est la source ; quand le Dart n'avait rien (cycle de vie du devis),
> le choix est écrit au §2 et soumis à validation (§7).

## 1. Ce que le web sait faire désormais

| Écran | Possible au web | Reste au poste |
|---|---|---|
| **Devis** `/ventes/devis` | créer, modifier (devis « émis »), dupliquer, changer le statut, supprimer (pierre tombale), imprimer (`@media print` / PDF), exporter la liste (XLSX) | rien : parité complète |
| **Factures** `/factures-mecef` | émettre une facture de vente depuis une vente, émettre un avoir (total ou partiel), imprimer (`@media print` / PDF), exporter la liste (XLSX) | **la transmission à la DGI, la saisie du code de normalisation, le jeton et l'URL e-MECeF** (par principe : secrets) |

Droits : devis = `view-ventes` (lecture, impression) / `manage-ventes` (écriture) / `export-ventes` (XLSX). Factures = `view-facturation`
(lecture, impression, XLSX) / `manage-facturation` (émission, avoir). Le droit est vérifié **dans chaque méthode d'écriture** du composant
(403 sinon, testé avec un composant neuf par appel interdit). Toute écriture passe par `TableSync::absorber` (poste web `00000000-…`),
jamais par un update direct : mêmes validations et mêmes règles que pour un poste.

## 2. Devis de prestations

### 2.1 Ce que le Dart faisait (et ne faisait pas)

Avant cette tranche, le Dart ne savait que **créer** un devis (`client`, `objet`, `montant_estime`, `validite_jours`, `date_emission`) et
les lister. Ni statut, ni modification, ni suppression, ni transformation en vente. La table avait un entier auto-incrémenté et n'était
pas synchronisée. Un devis « expire » à `date_emission + validite_jours`.

### 2.2 Cycle de vie retenu (poste **et** web, donc ajouté au Dart)

```
émis ──► accepté      (figé : ni modification, ni suppression)
  │  ╲
  │   ► refusé
  └─ (expiré : DÉDUIT de la date pour un devis « émis », jamais stocké)
```

- **Modifier** : seulement un devis « émis » ; la référence et la date d'émission ne changent jamais.
- **Changer le statut** : libre entre émis / accepté / refusé (le client change d'avis, ou on a fait une erreur). Le contenu n'est pas touché.
- **Supprimer** : pierre tombale (`supprime_le`) ; la ligne reste, cachée, pour que la suppression se propage et que **le numéro ne soit jamais réutilisé**. Interdit pour un devis accepté.
- **Dupliquer** : un nouveau devis (nouveau numéro, « émis », émis aujourd'hui) au contenu de l'original.
- **Transformer en vente** : **non**, le Dart ne le fait pas (un devis n'est ni une vente, ni un stock, ni une écriture comptable) ; le web non plus.
- « Expiré » ne se « passe » nulle part : aucun poste n'a de tâche à faire tourner, aucun conflit d'horloge possible.

### 2.3 Numérotation

`DV-P2-2026-001` (poste appairé), `DV-2026-001` (poste jamais appairé, ancien format), `DV-WEB-2026-001` (web). Séquence continue **par émetteur et
par année**, calculée sur le **maximum numérique** (suppressions comprises : un tri textuel mettrait `…-1000` avant `…-999`, et un devis
supprimé ne libère pas son numéro). `P1` et `P12`, et le web, ne se mélangent pas. Jamais renumérotée, ni au poste, ni au serveur, ni au web.
Unicité : `UNIQUE(portee_reference, reference)` — globale pour une référence à code (`P<n>` ou `WEB`), propre au poste sinon. Deux écrans web qui
créent en même temps : l'unicité tranche, le composant reprend le numéro (3 essais).

### 2.4 Synchronisation

- Poste : migration **v43** (`_devisEnUuid`, idempotente, une garde par colonne) : `id` UUID, `statut` (« emis »), `supprime_le`, `sync_status`,
  `sync_motif`, `updated_at`. Un devis d'hier est **à envoyer**, « émis », son instant de saisie est **sa date d'émission** (jamais l'instant de la
  migration : il ferait gagner un vieux devis contre une correction faite ailleurs). Testée sur une vraie base v42 (`migration_v43_devis_test.dart`, 7 tests :
  UUID distincts, numéros intacts, rejouée, colonnes manquantes ajoutées, table absente créée, unicités).
- `TableDevisPoste` (câblée dans `main.dart`) : fait, **dernier écrivain gagne** par UUID ; absorbeur strict (référence `DV-((P\d+|WEB)-)?AAAA-NNN+`, montant > 0,
  validité entière ≥ 1, statut connu, dates valides) ; la référence d'un même UUID ne change jamais ; une référence déjà prise par un **autre** devis n'est jamais
  écrasée ; un devis **accepté ici** refuse un contenu différent ou une pierre tombale reçus ; aucun effet de bord (ni vente, ni écriture comptable).
- Serveur : migration `2026_11_09_150000_create_devis_table.php`, modèle `Devis`, `DevisTable` (déclarée dans `sync.tables`, après `FacturesTable`),
  droits `view-ventes` / `manage-ventes`. Mêmes règles que le poste ; liste de colonnes servies fermée (pas de `portee_reference`) ; pierre tombale servie.
- Faux serveur Dart (`FauxServeurSync`) étendu (`devis`, `ajouterDevis`, `_devis`) : rejoue les règles de `DevisTable`.

### 2.5 Intégration à l'écran Ventes **sans modifier `Ventes.php`**

Route `/ventes/devis` (composant `App\Livewire\Devis`), déclarée dans `routes/ecrans/ventes-devis.php` **hors** de `Ecrans::declarer` et de la matrice
`config/logialvia.php` (cette matrice doit rester égale aux routes du poste : `ConformiteDroitsDartTest`). Droit de route `can:view-ventes`.

**Ligne à ajouter par l'agent Commerce** dans `resources/views/livewire/ventes.blade.php`, à l'endroit des onglets/actions :

```blade
@include('partiels.lien-devis')
```

(`resources/views/partiels/lien-devis.blade.php` rend le lien « Devis Prestations » seulement avec `view-ventes`.) Le bandeau d'écart de `ventes.blade.php`
(« les devis de prestations … restent sur le poste ») est à retirer par le même agent : il est devenu faux.

## 3. Facturation MeCeF au web

### 3.1 Émission d'une facture de vente

Depuis une **vente existante** non annulée, **une seule facture de vente par vente** (le serveur la refuse aussi : « Cette vente porte déjà la facture … »). Pour une vente
sans code de poste (`V-2026-001`, ancien format), seule compte la facture de **ce** poste ou celle émise au web (deux postes peuvent porter la même référence de vente).
Champs repris de la vente : client, date (`date_facture` = date de la vente, **comme le poste**), lignes ; saisis : IFU et adresse du client (facultatifs).

### 3.2 Calcul HT / TVA / TTC — identique au Dart, « arrondis » compris

Les prix du panier sont des montants **toutes taxes comprises** ; ils sont ramenés hors taxe selon le groupe de taxe du produit (`CalculFacture`, même
ordre d'opérations que `factures_mecef_repository_drift.dart` / `facture_mecef.dart`) :

```
ttc = qte × pu           ht = ttc / (1 + taux/100)       prix_unitaire_ht = ht / qte
montant_ht = qte × prix_unitaire_ht        montant_taxe = montant_ht × taux / 100
total_ht = Σ montant_ht   total_taxe = Σ montant_taxe   total_ttc = total_ht + total_taxe
```

- **Aucun arrondi n'est stocké** (comme le poste) : l'arrondi se fait à l'affichage (FCFA entiers). Le serveur tolère 0,01 FCFA par ligne entre un total et la somme de ses lignes.
- Groupe du produit absent de la grille : **A (exonéré)** — facturer une taxe non due engage l'entreprise, un oubli se corrige par un avoir.
- Valeurs de contrôle **produites par le Dart** (`dart run`) et figées dans `FacturesMecefEmissionWebTest` : 3 × 3 333 TTC à 18 % → `prix_unitaire_ht` 2824,576271186441, `montant_ht` 8473,728813559323, taxe 1525,271186440678 ; 2,5 × 777 → HT 1646,1864406779662 ; total TTC de 3 × 3 333 + 7 × 1 234,5 = 18 640,5.
- Écart de précision **assumé** : PHP/PDO écrit un `double` sur 14 chiffres significatifs (`precision`), la base relit donc 2824,5762711864 au lieu de 2824,576271186441 (écart < 1e-9 FCFA, sans conséquence fiscale ; les tests comparent à 1e-8). Aucun total affiché ne change.

### 3.3 Avoir

Sur une **facture de vente connue** (jamais sur un avoir), total (reprend toutes les lignes) ou **partiel ligne à ligne** (quantité créditée ≤ quantité facturée). Motif obligatoire
(255 c.). **Un avoir ne dépasse jamais la facture** : le cumul des avoirs déjà émis sur elle + le nouveau reste ≤ total TTC (tolérance 0,01), message chiffré sinon. Nouveaux UUID de lignes ;
la facture d'origine n'est jamais modifiée. **Écart corrigé au poste** : le Dart n'avait pas ce plafond (deux avoirs totaux sur la même facture passaient) ; il est ajouté à
`emettreAvoir` (poste, testé). Le serveur ne plafonne **pas** les avoirs poussés par un poste (une pièce fiscale déjà émise ne doit pas rester coincée) — voir §8.
Un avoir sur une facture **sans code de poste** (`FV-2026-001`, émise avant l'appairage) est refusé au web (le serveur ne saurait pas retrouver son origine) : il s'émet depuis son poste.

### 3.4 Numérotation, statut, immutabilité

`FV-WEB-AAAA-NNN` / `FA-WEB-AAAA-NNN` (maximum numérique de l'année, séquences FV et FA séparées, jamais renumérotées). L'année est celle de la **date de la facture** : la date de la
vente pour une facture de vente (comme le poste), le jour pour un avoir. Statut initial **« À transmettre »** ; un statut ne régresse jamais (rang `à transmettre < rejetée < normalisée`,
inchangé). Une facture émise est **immuable** (aucune méthode de modification, de suppression ni de transmission au web : testé par réflexion). **Aucune écriture comptable** n'est générée
(la vente l'a déjà fait ; testé).

### 3.5 Vue imprimable

`/factures-mecef/{facture}/imprimer` (`FactureImprimableController`, droit `view-facturation`, module `mecef`), page autonome, CSS `@media print` (barre masquée, marges, coupures de ligne) et
bouton « Imprimer / PDF » (`window.print()`). Reprend `documents_mecef.dart` : en-tête de l'entreprise, indicateurs, client / IFU / adresse, mention d'avoir (« Avoir sur la facture … — motif »),
vente d'origine, tableau des lignes, **récapitulatif par groupe de taxe**, TOTAL, NET À PAYER TTC (négatifs pour un avoir). La mention est **franche** : facture normalisée = code, NIM, compteur, date, lien ;
sinon « FACTURE NON NORMALISÉE — en attente de transmission e-MECeF. Ce document ne vaut pas facture normalisée … » (une facture « normalisée » sans code s'imprime comme non normalisée).
**Aucun QR** (celui d'une facture normalisée encode le lien de la DGI : en fabriquer un ici ne vérifierait rien). Ni jeton ni URL e-MECeF dans la page (testé). Écarts de forme avec le PDF du poste :
les quantités gardent leurs décimales (le Dart arrondit à l'entier), le P.U. HT est arrondi au FCFA à l'affichage.

## 4. Règle de transmission d'une facture émise au web

Une facture web n'a **pas de poste émetteur** (son émetteur est le poste web `00000000-0000-0000-0000-000000000000`). Règle retenue :

1. **N'importe quel poste appairé** dont le compte a `manage-facturation` peut la transmettre (le poste affiche « Transmettre » et « Saisir le code » pour une facture « web » ; la facture d'un **autre poste** reste intransmissible).
2. **Avant** de transmettre (ou de saisir un code), le poste **réserve** la transmission : `POST /api/sync/factures/reserver {device_id, facture_id}` (jeton Sanctum du poste, `poste.jeton`).
   - le serveur n'accorde la réservation qu'à **un poste à la fois** (mise à jour atomique conditionnelle), pour **15 minutes** ; le détenteur peut redemander ; une réservation **expirée** peut être reprise ;
   - refusée : compte sans `manage-facturation` (403), facture inconnue (404), facture émise par un poste (422), déjà normalisée (409), détenue par un autre poste (409, « en cours de transmission depuis le poste P3 ») ;
   - **hors ligne, non appairé, ou serveur injoignable = pas de réservation = pas de transmission** (e-MECeF exige de toute façon le réseau).
3. **Seul le détenteur** peut envoyer le statut : une normalisation ou un rejet poussé par un autre poste, ou sans réservation, est **refusé** (« … sa transmission doit être réservée au serveur avant d'être envoyée »).
   Un **rejet libère** la réservation (un autre poste, ou le même, peut retransmettre). Une normalisation reste au poste web comme émetteur (`device_id` ne change pas).
4. Filets inchangés (`46e_` §2) : une seconde normalisation différente est refusée (la première reçue gagne), jamais départagée en silence.
5. **Aucun secret ne voyage** : le jeton DGI et l'URL restent au coffre du poste (testé : le fil ne contient ni l'un ni l'autre) ; le serveur n'appelle jamais e-MECeF (`Http::assertNothingSent`).
6. Les colonnes du verrou (`transmission_poste`, `transmission_reservee_jusqua`, migration `2026_11_09_150100_*`) ne sont **jamais servies** aux postes (liste des colonnes toujours fermée, testée).
7. Au poste, une facture web normalisée ici repart au serveur (`aEnvoyer` inclut l'origine « web »), et survit à une remise à zéro du serveur comme toute pièce normalisée (repart `pending`).

## 5. Tests

| Couche | Fichier | Tests |
|---|---|---|
| Poste, migration v43 | `test/core/migration_v43_devis_test.dart` | 7 |
| Poste, devis (dépôt + synchro) | `test/commercial/devis_sync_poste_test.dart` | 28 |
| Poste, facture web (réservation, transmission, avoir plafonné) | `test/commercial/factures_web_poste_test.dart` | 20 |
| Serveur, devis | `tests/Feature/Sync/DevisTest.php` | 11 |
| Serveur, verrou de transmission | `tests/Feature/Sync/FacturesWebTransmissionTest.php` | 20 |
| Web, devis | `tests/Feature/Web/DevisWebTest.php` | 25 |
| Web, émission / avoir / impression / XLSX | `tests/Feature/Web/FacturesMecefEmissionWebTest.php` | 33 |
| Web, lecture (mis à jour : plus « lecture seule ») | `tests/Feature/Web/FacturesMecefWebTest.php` | 30 |

**Mutations** (une garde cassée, un test doit rougir) : poste devis 17 + 1 renforcée, poste facture web 12, serveur devis 14, serveur verrou 15, web devis 21, web factures 38 — toutes tuées (les survivantes du premier passage ont été renforcées :
maximum de séquence « dernier lu », plafond d'avoir « toutes factures confondues », purge qui oubliait les factures web, message d'une facture déjà normalisée, garde `refuse` du formulaire de devis, fuseau et entier de l'export XLSX).
Équivalentes assumées : `montant <= 0` / `validité < 1` du formulaire web (le serveur refuse avec le même message : défense en profondeur).

## 6. Écarts restants avec le Dart

| Sujet | Écart |
|---|---|
| Devis | Le Dart n'avait ni statut, ni modification, ni suppression : **ajoutés au poste** (boutons Modifier / Dupliquer / statut / Supprimer de l'onglet « Devis Prestations ») pour la parité. |
| Avoir | Plafond au total de la facture ajouté au poste (le Dart laissait doubler un avoir total). |
| PDF | Le web imprime par le navigateur (`@media print`), pas de PDF généré côté serveur. Quantités avec décimales (le Dart les arrondit). |
| Icônes | Pas de Material Symbols au web (`45_` §7). |
| Transmission | Au web : jamais. Au poste : par réservation pour une facture web. |

## 7. Décisions à valider par le client

| Id | Question | Option retenue (prudente) | Alternative |
|---|---|---|---|
| **A1** | Cycle de vie du devis (le Dart n'en avait pas) | émis → accepté / refusé, « expiré » déduit de la date ; accepté = figé, non supprimable ; statut librement corrigeable | statuts supplémentaires (« envoyé », « facturé »), transformation en vente |
| **A2** | Devis → vente | **non** (le Dart ne le fait pas) | bouton « Transformer en vente » (et lien devis↔vente) |
| **A3** | Qui transmet une facture web ? | tout poste appairé avec `manage-facturation`, après réservation serveur de 15 min | un poste désigné ; ou aucune transmission possible tant que le poste émetteur n'est pas connu |
| **A4** | Durée de la réservation | 15 minutes, reprise possible ensuite | plus courte / renouvelable ; réservation jusqu'à acquittement |
| **A5** | Année du numéro d'une facture | celle de la **date de la facture** (date de la vente), comme le poste. Une vente de décembre facturée en janvier garde l'année de la vente : la **chronologie annuelle** n'est alors pas garantie | année de l'émission (avertir si la date de la vente est d'une autre année) |
| **A6** | Plafond des avoirs | au web et au poste : cumul ≤ total TTC de la facture ; **pas** refusé par le serveur pour un avoir déjà émis par un poste | refuser aussi au serveur (une pièce déjà émise resterait en conflit) |
| **A7** | Précision des montants | aucun arrondi stocké (comme le poste) ; arrondi au FCFA à l'affichage. **Non vérifié** : la règle d'arrondi exigée par la DGI sur la facture normalisée | arrondir chaque ligne (et totaux) au FCFA à l'émission, au poste comme au web |
| **A8** | IFU / adresse du client au web | saisis à l'émission, facultatifs | repris de la fiche client (la table `clients` n'a pas ces champs) |
| **A9** | Avoir sur une facture sans code de poste | refusé au web (« depuis son poste ») | lever la limite côté serveur |

## 8. Limites connues

- **Contrat e-MECeF toujours non éprouvé** contre le service réel (`transmission_mecef.dart`) ; cette tranche n'y touche pas.
- **Pas d'essai contre le vrai serveur Laravel** pour la réservation (`test/integration/serveur_reel_test.dart` non étendu) : le faux serveur Dart rejoue les règles du vrai, écrit par la même main ; à croiser à la recette.
- La réservation expire sans signal : si le poste détenteur transmet à la DGI **après** l'expiration et qu'un autre poste a repris la réservation, le serveur refuse son envoi (la double normalisation est évitée **côté serveur**, mais la DGI aurait reçu deux transmissions). Le poste transmet aussitôt après avoir réservé (secondes, pour 15 minutes de marge).
- Un poste ne reçoit pas l'échéance de sa réservation (le serveur la renvoie, le poste ne l'utilise pas) : il ne refuse pas de transmettre « trop tard ».
- Une vente **sans code de poste** dont la facture web et la facture d'un **autre** poste portent la même référence de vente texte : la facture du poste est refusée à tort (« Cette vente porte déjà la facture FV-WEB-… »). Cas réservé aux postes appairés après coup avec des références anciennes identiques ; documenté, non traité.
- Une facture ou un devis **supprimé n'efface rien** : pierre tombale pour le devis, jamais de suppression pour une facture (pièce fiscale).
- Un devis web ou une facture web est écrit par le **poste web** : un compte web n'a pas d'identité de poste, l'audit applicatif reste celui de `AuditLog` (non étendu ici).
- Le poste n'a pas d'écran de résolution des conflits (`46e_` §6) : une réservation refusée est affichée en toast, un envoi refusé passe la facture en `conflict` avec son motif.

## 9. À reporter dans les documents partagés (le coordinateur)

- `CLAUDE.md` : `versionSchema = 43` ; `45_`/`46_` : table `devis` = **fait synchronisé** (UUID, pierre tombale), numérotation `DV-…` ; `factures` : poste émetteur « web », règle de transmission du §4, `POST /api/sync/factures/reserver`.
- `46e_` §5 et §9 : l'écran `/factures-mecef` n'est plus en lecture seule ; ses écarts (« émission absente », « avoir absent », « export / impression PDF absent ») sont levés ; reste « transmission : au poste ».
- `config/logialvia.php` : `DevisTable` après `FacturesTable` dans `sync.tables` (fait) ; **aucune** ligne ajoutée à `routes` (conformité Dart).
- `ventes.blade.php` (agent Commerce) : `@include('partiels.lien-devis')` et retrait du bandeau d'écart « devis » (§2.5).
- `46f_` : décisions A1 à A9 ci-dessus.
