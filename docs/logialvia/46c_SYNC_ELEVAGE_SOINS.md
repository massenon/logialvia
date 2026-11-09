# 46c — Élevage : soins, infirmerie et paramètres d'élevage (tranche P7c)

> **Statut : implémenté (09/11/2026)**, poste v40, serveur, deux écrans web. Complète `46_` (contrat) et `45_` (plan).
> Le Dart est la source ; le Laravel s'y conforme. Les choix métier douteux sont listés en
> **« Décisions à valider par le client »** (§7) : chacun est l'option la plus prudente.

## 1. Périmètre

| Table du poste | Nature | Clé | Serveur | Droits |
|---|---|---|---|---|
| `soins_calendrier` | **FAIT**, dernier écrivain gagne | UUID aléatoire | `SoinsCalendrierTable` | lecture `view-elevage`, écriture `manage-elevage` |
| `infirmerie` | **FAIT**, dernier écrivain gagne | UUID aléatoire | `InfirmerieTable` | idem |
| `baremes_ration` | **RÉFÉRENTIEL** (le serveur gagne) | UUID **déterministe** de (espèce, stade) | `BaremesRationTable` + demande `bareme_ration` | lecture `view-elevage`, demande `manage-elevage` |
| `taux_ration_poids` | **RÉFÉRENTIEL** | UUID déterministe de (espèce, poids min) | `TauxRationPoidsTable` + demande `taux_ration_poids` | idem |
| `calendrier_prophylaxie` | **RÉFÉRENTIEL** | UUID déterministe au semis, aléatoire à la saisie | `CalendrierProphylaxieTable` + demande `echeance_prophylaxie` | idem |

La **suppression** d'un référentiel (pierre tombale `archive_le`) exige `archive-elevage`. La matrice est celle de
`config/logialvia.php` : seuls l'administrateur et l'agent d'élevage lisent et écrivent l'élevage ; le comptable et le
caissier n'ont aucun droit sur ces tables (elles ne leur sont même pas servies au tirage).

La **numérotation** (préfixes enclos, cage, bande, bassin, bac, parc) n'est pas une nouvelle table : elle vit dans
`parametres_entreprise` et voyage déjà par la demande `parametres_entreprise` (`46_` §10).

## 2. Poste : schéma v40

Migration `_soinsEtParametresElevageEnUuid` (`app_database.dart`, bloc `if (from < 40)`), **idempotente et rejouable** :

- chaque table est testée séparément (`_idEstEntier`) ; l'ordre (correspondance des échéances → soins → infirmerie → barèmes
  → taux → échéances) garantit qu'une reprise après interruption retrouve les **mêmes** identifiants ;
- **aucune ligne perdue** (reconstruction `TableMigration`, pas de clé étrangère à cascader : `soins_calendrier` ne référence
  rien par clé étrangère) ; l'ordre d'insertion est conservé (`rowid`) ;
- **barèmes, taux, échéances** reçoivent `uuidDeterministe(clé naturelle)` (`IdentifiantsParametresElevage`) : deux postes
  migrés — ou semés — donnent le **même** identifiant à la même ration. Un doublon exact d'échéance sur un poste se départage
  par son ancien entier ;
- `soins_calendrier.echeance_prophylaxie_id` passe en texte et **suit** l'échéance (table de correspondance, supprimée en
  fin) ; la **corbeille** est remise en UUID (instantanés d'avant la v40), y compris pour une échéance archivée citée par un
  soin ;
- soins et infirmerie d'hier : `sync_status = pending`, `updated_at` = instant de la migration (aucun autre poste ne les connaît,
  ils ne peuvent battre personne) ;
- nouvelles colonnes de synchronisation (`sync_status`, `sync_motif`, `updated_at`) sur les **faits** uniquement ; les
  référentiels n'en portent pas (comme les produits : la file de demandes et `saisi_le` du serveur suffisent) ;
- les seeders des anciennes migrations (v27, v28, v30) insèrent en SQL brut sans identifiant tant que la table est encore en
  entiers ; le semis courant (`executer`) utilise les UUID déterministes.

> **À la fusion** : la v40 est écrite sans les blocs 38 et 39 des autres tranches. Les trois blocs sont indépendants
> (`from < 38`, `from < 39`, `from < 40`) ; `versionSchema = 40`. Les tests de migration estampillent la base de départ à **39**.
> Si la tranche « bandes » convertit `bandes.id` en UUID, voir §8 (`bande_id`).

### Moteur du poste

- `TableSoinsPoste`, `TableInfirmeriePoste` (faits) et `TableBaremesRationPoste`, `TableTauxRationPoidsPoste`,
  `TableCalendrierProphylaxiePoste` (référentiels), branchées dans `main.dart` (référentiels après les intrants, faits après
  les mouvements de produits).
- `DepotDemandesReferentiel` : trois types, `proposer*` / `proposerArchivage*`, et **adoption unique** des paramètres locaux
  (`adopterParametresElevageSiBesoin`, drapeau `sync.parametres_elevage_adoptes`), appelée par le moteur avec celles du
  catalogue et des intrants. Les écrans du poste proposent chaque création, modification et suppression ; la **restauration
  depuis la corbeille** lève la pierre tombale.
- **Absorbeur strict** (faits) : UUID, instant, espèce, date, statut, rémanence ≥ 0, coût ≥ 0, cohérence entrée/sortie de
  l'infirmerie… Une ligne incohérente est refusée et **comptée**, jamais lissée.
- **Règle d'or** : absorber le fait d'un autre poste n'a **aucun effet de bord** (ni stock, ni fiche d'élevage, ni compteur,
  ni écriture comptable, ni événement) — testé en comptant les lignes de 9 tables avant/après.
- Dernier écrivain gagne : une saisie locale non envoyée n'est remplacée que si le serveur est **strictement** plus récent
  (comptée « supplantée ») ; à instant égal, elle est conservée.
- Référentiels : une demande locale en attente n'est supplantée que par une décision du serveur **postérieure** à sa saisie.
  Une ligne dont la clé naturelle est déjà portée ici par un autre identifiant cède la place au serveur, sauf si elle attend
  d'être proposée.
- Remise à zéro du serveur : soins et infirmerie sont purgés (les non envoyés sont comptés et annoncés) ; les référentiels
  sont préservés.
- `FauxServeurSync` rejoue les règles du vrai serveur (validation, clé naturelle, instants, pierre tombale, droits non rejoués :
  le faux serveur est administrateur).

## 3. Serveur

Migration `2026_11_09_142000_create_soins_infirmerie_parametres_elevage_tables.php` ; modèles `BaremeRation`,
`TauxRationPoids`, `EcheanceProphylaxie`, `SoinCalendrier`, `EntreeInfirmerie` ; classes `App\Sync\Tables\*` déclarées dans
`sync.tables` (référentiels après `intrants`, faits après `mouvements_produit`).

- **Faits** : `TableSync::absorber` (UUID, `updated_at`, validation, dernier écrivain gagne strict, rejeu sans effet sur
  l'instant de réception). Nouveau crochet `TableSync::controler()` pour les contrôles croisés : échéance **connue** du
  serveur (soins) ; sortie ≥ entrée, statut cohérent avec la sortie, marque de mortalité réservée au « Décédé » (infirmerie).
- **Référentiels** : `DemandesReferentiel` (3 types). Identique à l'état actuel → accepté sans rien changer ; plus ancien
  **ou égal** → refusé (« Une modification plus récente existe… ») ; clé naturelle déjà portée par un autre UUID → refusé
  (« Un barème existe déjà pour ce stade. ») ; `archive: true` → `archive_le` (jamais d'effacement), redistribué.
- Plages : ration 1–20 000 g/j ; taux 0–25 % (le web borne à 10 % pour les bovins, comme le Dart) ; jour du cycle 1–365 ;
  rémanence 0–3 650 j.
- `type_soin` est un **texte libre** : « Planifier une Intervention » le saisit tel quel (« Vaccin Newcastle (Rappel) »), hors
  des 4 types du registre (point trouvé en lisant le Dart ; une liste fermée aurait refusé toute intervention planifiée).
- Dates civiles (`date_prevue`, `date_entree`, `date_sortie`) envoyées en `AAAA-MM-JJ`, sans fuseau.
- Remise à zéro serveur : les tables de **faits** sont vidées (soins, infirmerie), les référentiels restent.

## 4. Web

| Écran | Route | Droit | Ce que fait le web |
|---|---|---|---|
| Soins & Calendrier | `/elevage/soins` | `view-elevage` ; écriture `manage-elevage` | 4 KPI et bannière de rémanence (formules du poste), Registre (filtres, « Confirmer »), Calendrier des Doses (mois courant, « Planifier une Intervention »), Suivi Infirmerie (« Nouvelle Entrée », « Réintégrer »), « Nouveau Soin ». Écrit par `TableSync::absorber`, device `Catalogue::POSTE_WEB`. |
| Paramètres Élevage | `/parametres/elevage` | `view-elevage` ; écriture `manage-elevage`, suppression `archive-elevage`, numérotation `manage-parametres` | Rationnement (barèmes + taux par classe de poids), Calendriers Prophylaxie, Intrants de Provende (lecture), Numérotation. Écrit par `DemandesReferentiel::traiter`. |

Les écritures du web posent un `updated_at`/`saisi_le` **postérieur** à la version qu'elles remplacent (un poste à l'horloge en
avance ne fait pas perdre le web). Un identifiant de barème ou de taux créé au web est le **même** que celui du poste
(`FilieresElevage::uuidDeterministe` reproduit `uuidDeterministe` du Dart ; valeurs de référence vérifiées en test).

Le **module d'élevage actif** conditionne les écrans : la route ne dépend d'aucun module (comme au poste), mais les filières
**proposées pour une création** sont Goliaths, Pintades et celles dont le module est actif (`FilieresElevage::actives`) ; les
lignes d'une filière inactive restent visibles.

## 5. Écarts déclarés avec le Dart

| Écart | Raison |
|---|---|
| Pas d'export PDF (registre des soins) | hors périmètre web |
| Pas de lien de bande sur un soin ; pas de génération de soins depuis le calendrier de prophylaxie au web | les bandes ne sont pas synchronisées |
| « Décès » absent de l'infirmerie web (seulement « Réintégrer ») | il porte la perte sur la fiche d'élevage, que le web ne peut pas modifier (fiches non synchronisées) |
| Intrants de Provende en **lecture seule**, sans stock ni prix indicatif ; ajout/modification dans Gestion Stocks | stock et PMP propres à chaque poste (`46_` §14) |
| Suppression : pierre tombale, **non restaurable depuis le web** | pas de corbeille web ; le poste la restaure depuis sa corbeille |
| Numérotation : droit `manage-parametres` (administrateur) | c'est celui du serveur ; voir §7 D5 |
| Filières proposées à la création = filières actives | matrice des modules ; le Dart propose les 6 (paramètres) ou les 8 (soins) |
| Pas de « Réinitialiser » du brouillon de numérotation, d'avertissement « modifications non enregistrées », ni de visite guidée | confort du poste |
| « Calendrier des Doses » : une pastille par jour et par espèce (comme le Dart) ; sur téléphone, liste au lieu de la grille | pas de défilement horizontal caché |

## 6. Règles de convergence retenues

- **Pas de doublon de soins issus du calendrier entre postes** : tant que les bandes ne sont pas synchronisées, une bande
  n'existe que sur le poste qui l'a ouverte ; l'injection du calendrier y est idempotente (couple bande/échéance) et deux postes
  ne peuvent pas injecter la même bande. Quand les bandes passeront en UUID, l'identifiant du soin injecté devra être
  `uuidDeterministe('soin_prophylaxie:<uuid de la bande>|<uuid de l'échéance>')` : à faire avec les bandes (§8).
- **Même barème saisi sur deux postes** : même UUID (déterministe) ; contenu identique accepté, contenu différent → le plus
  récent gagne, le plus ancien est refusé avec son motif et redescend au tirage.
- **Même échéance saisie sur deux postes** : deux UUID aléatoires, donc **deux lignes** (pas de clé naturelle unique : un
  traitement peut légitimement se répéter à un même jour). À valider (D3).

## 7. Décisions à valider par le client

| # | Décision (option la plus prudente) | Alternative |
|---|---|---|
| D1 | Un **décès** se déclare **au poste** (il porte la perte sur la fiche). Le web ne propose que « Réintégrer ». | Autoriser « Décès » au web : la perte ne serait portée nulle part tant qu'un poste ne le fait pas, et ce poste ne pourrait plus le faire (« entrée déjà clôturée »). |
| D2 | La marque de mortalité (`categorie_mortalite`) d'un décès venu d'un autre poste est **absorbée telle quelle** : le poste récepteur n'y reporte pas la perte une seconde fois. | Ne pas l'absorber : risque de double comptage si l'animalier la saisit aussi. |
| D3 | Deux échéances au **même contenu** mais créées séparément restent **deux lignes**. | Imposer (espèce, jour, traitement, produit) unique et fusionner (perd une répétition légitime). |
| D4 | Barèmes et taux : clé naturelle **unique**, UUID déterministe ; deux contenus différents pour la même clé → le plus récent gagne. | UUID aléatoires et doublons tolérés (tableau ambigu). |
| D5 | **Numérotation** modifiable au web seulement avec le droit `manage-parametres` (administrateur). Au poste, l'agent d'élevage peut la modifier localement mais **le serveur refuserait sa demande** (`manage-parametres`) : incohérence existante. | Donner `manage-elevage` à la numérotation (changer la règle du serveur) ou la réserver à l'administrateur au poste aussi. |
| D6 | **Suppression** d'un paramètre : tous les postes l'archivent dans leur corbeille ; `archive-elevage` requis ; non restaurable depuis le web. | Suppression locale seulement (le calendrier divergerait entre postes). |
| D7 | Les **filières proposées à la création** au web sont les filières actives. | Proposer toutes les filières comme le poste. |
| D8 | Les plages du serveur : ration 1–20 000 g/j, taux 0–25 %, jour 1–365, rémanence ≤ 3 650 j. Les plafonds par espèce du poste (5 kg ; 20 kg bovins ; taux 10 % ; 25 % poissons) sont appliqués **par le web** ; le serveur ne retient que le plus large. | Reporter les plafonds par espèce côté serveur. |
| D9 | Un soin dont l'échéance est inconnue du serveur est **refusé** (visible en « conflit » au poste) plutôt qu'accepté sans lien. | Accepter en perdant le lien. |
| D10 | Les soins et l'infirmerie ne sont **jamais supprimés** (le poste n'a pas de suppression). | — |
| D11 | Les référentiels d'élevage sont **lus** par ceux qui ont `view-elevage` (administrateur, agent d'élevage), pas par le comptable ni le caissier. | Les servir à tous (le poste du caissier n'en a pas l'usage). |

## 8. Limites

- **`soins_calendrier.bande_id` reste un entier LOCAL** et ne voyage pas : les bandes ne sont pas encore synchronisées. Le soin
  reçu arrive sans bande (`vientDuCalendrier` faux) ; le lien local d'une ligne déjà connue n'est jamais effacé. **À la fusion
  avec la tranche « bandes »** : si `bandes.id` passe en UUID, `bande_id` doit suivre (migration à compléter), voyager
  (`bande_id` nullable au serveur, vérifié contre `bandes`) et entrer dans l'identifiant déterministe des soins injectés.
- `Soin.id`, `EntreeInfirmerie.id`, `BaremeRation.id`, `TauxRationPoids.id`, `EcheanceProphylaxie.id` sont désormais des
  `String` dans les entités du poste ; `echeanceProphylaxieId` aussi. Tout code de la tranche « bandes » qui passe un identifiant
  de barème ou d'échéance en entier devra suivre.
- Un soin lié à une échéance **jamais proposée** au serveur (échéance supprimée avant l'adoption) est refusé (D9).
- Le web n'a pas de corbeille : une suppression au web ne se défait qu'au poste.
- `fiche_journee`, `bandes`, `cycle_couveuse` (fiches, couveuse) ne sont pas synchronisés : « Décès » (D1) et le report de
  mortalité restent au poste.
- Essai contre le **vrai serveur Laravel** non fait pour ces cinq tables (le faux serveur rejoue les mêmes règles ; test
  d'équivalence par lecture croisée des deux jeux de cas).

## 9. Vérification

- **Poste** : 75 tests (62 de synchronisation dont l'absorption stricte, les refus comptés, l'absence d'effet de bord, l'instant
  égal, la remise à zéro et le hors ligne ; 13 de migration sur une vraie base v39) ; **36 mutations** (barèmes déterministes,
  accusé conditionnel, `>` strict, lien de bande, purge, droits des demandes, restauration, corbeille, lien soin → échéance…),
  dont 1 survivante au premier passage (la bande dans le corps envoyé) renforcée. Suite complète : 1 465 tests, `flutter analyze`
  « No issues found! ».
- **Serveur** : 60 tests (`tests/Feature/Sync/ElevageTest.php`) ; 28 mutations dont 1 survivante renforcée (pierre tombale à la
  création). Suite complète : 572 tests.
- **Web** : 56 tests (22 + 34) ; 34 mutations dont 3 survivantes renforcées et 1 équivalente (le jour de cycle est aussi borné
  par le serveur, que le web interroge). `npm run build` : OK.
