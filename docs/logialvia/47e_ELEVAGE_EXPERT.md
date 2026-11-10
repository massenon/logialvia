# 47e — Élevage : lecture d'expert (zootechnie, divergence, chaîne d'effectifs), parité web ↔ poste

> **Statut au 09/11/2026.** Complète `46a_` (fiches, bandes), `46b_` (couveuse), `46c_` (soins), `46f_` (décisions).
> Schéma du poste : **v47** (réservée à ce chantier ; les versions 43 à 46 appartiennent à d'autres chantiers).
> Migration serveur : `2026_11_09_152000_add_bande_id_variantes_elevage.php`.
> Le Dart est la source ; le web s'y conforme. **Rien de ce qui est marqué « à valider » n'est validé par le client.**

## 1. Règles zootechniques appliquées

Toutes sont codées dans `reperes_zootechniques.dart` (poste) et `ReperesZootechniques.php` (web, mêmes valeurs chiffrées en test).
Les seuils sont ceux de **DV-13** (recommandés, à confirmer avec le technicien) ; comparaisons **strictes** (« supérieur à »).

| Repère | Valeur | Où |
|---|---|---|
| Mortalité **du jour** (morts ÷ effectif de la veille) | avertissement > 1 %, critique > 2 % | avertissement en direct à la saisie |
| Mortalité **cumulée** | avertissement > 10 %, critique > 20 % | KPI de la fiche, carte du dashboard |
| Taux cumulé | morts ÷ (effectif de début + **entrées**) ; sans effectif exposé : « — », jamais 0 % | fiche, dashboard, vue hebdomadaire |
| GMQ | (poids moyen final − initial) ÷ jours ; poids moyen = pesée ÷ effectif ; au moins deux pesées de jours distincts sur 28 jours | dashboard (poste et web) |
| Indice de consommation | aliment ÷ gain de poids ; sans gain strictement positif : pas d'IC | fonction (non affichée, voir §6) |
| Incubation | poule / Goliath 21 j, pintade 28 j (canard 28, barbarie 35, dinde 28, oie 30, caille 17 en référence) | constantes du Dart vérifiées exactes |
| Mirage | J+7 pas avant J+5 ; J+14 pas avant J+12 | refus à la saisie |
| Éclosion | pas plus de 4 jours avant le terme de l'espèce (poule : J+17 ; pintade : J+24) | refus à la saisie |
| Ponte | une poule pond au plus 1 œuf/jour ; taux > 96 % exceptionnel ; œufs cassés > 10 % à vérifier | refus / avertissement |
| Poids moyen vraisemblable | goliaths 30–6 000 g · pintades 25–2 800 · lapins 30–7 000 · poulets 30–6 000 · pondeuses 30–4 000 · poissons-chats 0–15 000 · escargots 0–250 · bovins 15 000–1 100 000 | avertissement |

### Contrôle de vraisemblance d'une journée (poste et web, mêmes messages)

- **Refusé** (impossible, et le plancher à 0 du calcul le masquait) : morts + dons d'une catégorie supérieurs à son effectif disponible
  (veille + entrées du jour pour la catégorie la plus jeune) ; œufs pondus supérieurs aux pondeuses de la veille.
- **Avertissement** (jamais bloquant) : ventes au-delà de la catégorie commercialisée, pesée hors repères ou sans sujet vivant,
  taux de ponte > 96 %, œufs cassés > 10 %, sorties de plateaux au-delà du stock, mortalité du jour > 1 % / > 2 %.
- **Exception** : le **décès d'infirmerie** se déclare toujours (le contrôle est suspendu) : on ne refuse pas la mort d'un sujet sanitaire
  parce que la fiche n'a pas encore ses entrées.

## 2. Erreurs d'expert trouvées et corrigées (poste ET web)

| # | Erreur | Correction | Tests chiffrés |
|---|---|---|---|
| E1 | **Taux de mortalité cumulé** : base = effectif du premier jour saisi ; une bande arrivée en cours de mois faussait le taux (jusqu'à > 100 %). | Base = effectif de début de mois + toutes les entrées du mois. | 12 morts / (100 + 140) = 5,0 % ; 200 achetés + 100 plus tard, 5 morts : 1,7 % (et non 2,5 %) |
| E2 | **Taux hebdomadaire** : effectif de début sans les entrées (« — » pour une bande qui arrive en semaine). | Effectif exposé = début + entrées de la semaine. | 200 achetés, 5 morts : 2,5 % |
| E3 | **Effectif de début de semaine périmé** : une veille non saisie ramenait à l'effectif de début de **mois**. | Dernier effectif connu avant la semaine. | veille non saisie : début 80, pas 100 ; 4 morts : 5,0 % |
| E4 | **Dashboard** : mortalité du mois rouge dès 2 % (seuil **journalier** appliqué à un **cumul**). | Seuils des cumuls (10 % / 20 %), orange puis rouge. | 10,0 % normal · 11 % orange · 21 % rouge |
| E5 | **Rations sans effet** : le barème est cherché par libellé de stade ; « Alevins » (pintade, terme interdit par DV-09) et « Sevré / Lapereaux », « Chair / Jeune » ne correspondaient à aucune catégorie, donc modifier la ration dans Paramètres Élevage ne changeait rien. | Stades équivalents déclarés par catégorie (le libellé exact prime). | « Sevré / Lapereaux » = 45 → ration 45 ; « Alevins » = 35 → 35 ; exact 40 prime sur 35 |
| E6 | **Poissons-chats : repli par tête absurde** (30 / 60 / 110 g par poisson et par jour : un alevin de 2 g en « mangeait » 30 ; les 8 / 25 / 45 du barème semé ne valent guère mieux). | 1 / 3 / 8 g (arrondi de 15 % de 2 g, 4 % de 50 g, 1,5 % de 500 g) ; sans pesée seulement, le % de biomasse prime. | 1 000 juvéniles : 3 000 g/j (et non 60 kg) |
| E7 | **Reproducteur lapin** : 110 g dans le code, 120 g dans le barème semé confirmé (Q-ELV-2). | 120 g. | 120 |
| E8 | **GMQ promis, jamais calculé** : le panneau affirmait qu'aucune colonne de poids n'existe, alors que `poids_general_g` est saisi. | GMQ calculé des pesées. | 500 g → 1 855,7 g en 27 j : 50,2 g/j |
| E9 | **Soin « Planifié » en retard non signalé** : seules les alertes au statut « En retard » (saisi à la main) comptaient. | Planifié dont la date est passée = en retard (dashboard, poste et web). | 4 soins : 2 en retard |
| E10 | Mirage et éclosion saisis à une date impossible acceptés. | Refus (voir §1). | J+4 refusé, J+5 accepté ; Goliath J+16 refusé, J+17 accepté |

À valider par le zootechnicien (non modifié, repères indicatifs) : lapins **Chair 60 g/j** (un lapin en croissance consomme plutôt 100–150 g) ; pintades et Goliaths **30 / 60 / 110 g** (barème générique non confirmé) ;
« Alevins » reste le libellé **affiché** du barème semé de la pintade (le renommer créerait un autre UUID déterministe et un doublon sur le serveur : à faire par une demande de référentiel).

## 3. Divergence : « dernier écrivain gagne » ne perd plus rien en silence (décision fragile a)

**Avant** : deux postes saisissant la même fiche sans se voir, la plus récente effaçait l'autre sans bruit.

**Maintenant**
- Le poste envoie `base_updated_at` : l'instant de la version **dont sa fiche est partie** (celle qu'il a tirée ou envoyée en dernier).
- Le serveur compare. Même contenu, même appareil, ou base = version courante (le poste *avait vu*) : suite normale, rien à signaler.
  Sinon, les deux saisies ont eu lieu sans se voir : la plus récente reste **courante**, l'autre est **conservée** dans `variantes` (JSON : appareil, instant, contenu) et redistribuée à tous.
- Une saisie locale **non envoyée** n'est plus jamais écrasée par une version différente du serveur : la version de l'autre est gardée à côté, visible.
- La fiche porte la marque « **modifiée ailleurs** » (poste : bandeau + fenêtre « Quelle version garder ? » ; web : bandeau + boutons « Garder celle-ci »).
- **Choisir** = ressaisir la version retenue (effectifs recalculés de la veille de l'appareil, cascade comprise) puis renvoyer la fiche avec `resolution: true` : seule une écriture plus récente que la courante est appliquée et elle efface les variantes partout.
- Au web, l'écriture part de la version que l'écran **avait sous les yeux** : si un poste a modifié la fiche entre-temps, la saisie du web ne l'écrase pas, elle devient une divergence visible.

Poste : colonnes `base_maj`, `variantes`, `resolution` sur `fiche_journee` (v47, additif et idempotent, ajoutées aussi à la reconstruction de la v38).
Serveur : colonne `fiche_journee.variantes` (JSON), `FichesJourneeTable::absorber`.

## 4. Chaîne d'effectifs (décision fragile b)

Effectif du jour = veille + entrées − sorties, dans l'ordre chronologique, chaque jour **saisi** partant de la dernière fiche saisie qui le précède (même règle que la saisie).
- **Vérification en lecture seule** (poste : `ChaineEffectifsUseCase.verifier` ; web : `joursIncoherents`) : un bandeau liste les jours dont l'effectif ne découle pas de la veille.
- **Bouton « Recalculer la chaîne »** : réécrit dans l'ordre **les seuls jours dont une valeur calculée change** (réécrire un jour identique le daterait de maintenant et le ferait gagner sans raison contre un autre poste) ; stock d'œufs des pondeuses compris.
- La règle d'or reste : absorber la fiche d'un autre poste n'a **aucun** effet de bord ; le recalcul est une action de l'utilisatrice.
- Différence avec la cascade automatique : celle-ci s'arrête au premier jour non saisi ; la chaîne enchaîne les jours saisis par-dessus un trou (l'effectif d'un jour non saisi est celui de la dernière fiche).

## 5. Bandes : lien soin ↔ bande, recodage (décisions c, et lien `bande_id`)

- `soins_calendrier.bande_id` **voyage** : corps du soin (poste), colonne serveur + validation (UUID, bande **connue** : « Bande inconnue du serveur. »), web (« Nouveau Soin » propose les bandes de la filière, registre affiche le code). Les bandes partent avant les soins dans le cycle.
- **Soins issus du calendrier sans doublon entre postes** : identifiant déterministe `uuidDeterministe('soin_prophylaxie:<bande>|<échéance>')` (poste, web, serveur : même calcul). Deux postes qui planifient la même échéance écrivent la **même** ligne.
- **Recodage `B2` → `B2-P2`** : le code proposé est le code actuel + le code du poste (`-2`, `-3`… si pris) ; la bande est renvoyée, l'ancien code est **tracé** dans ses observations (« Recodée de B2 en B2-P2 le AAAA-MM-JJ… ») ; le curseur de tirage est remis à zéro pour que la bande de l'autre poste, refusée tant que le code était pris, revienne. Poste : bandeau « Recoder la bande » sur une bande en conflit. Web : « Recoder la Bande » (proposition `B2-WEB`).
  Le recodage est **proposé, jamais automatique** : c'est l'utilisatrice qui valide le nouveau code.

## 6. Parité web ↔ poste : ce qui est comblé

| Écart déclaré (46a/46b/46c) | État |
|---|---|
| Décès avec report de la perte sur la fiche (cascade) | **Fait au web** (« Décès » à l'infirmerie : clôture écrite avant le report, marque après ; la mort s'ajoute aux mouvements saisis ; contrôle suspendu) |
| Réintégration | déjà présente |
| Génération des soins depuis le calendrier de prophylaxie | **Fait au web** (par échéance, id déterministe, jamais de doublon) |
| Lien soin ↔ bande | **Fait** (poste, serveur, web) |
| Provende / rationnement et prophylaxie du jour (barèmes et calendrier synchronisés) | **Fait au web** (barèmes, taux au poids vif, stades équivalents) ; provende **en stock** et autonomie : grisées « Disponible sur le poste » (décision du client) |
| Clôture / recodage de bande | clôture existante ; **recodage ajouté** (poste et web) |
| Rappels vétérinaires et alertes sanitaires du dashboard, carte couveuse | **Faits au web** (rappels = 5 prochains soins, alertes = soins en retard au sens de E9, couveuse) ; **stocks d'intrants sous seuil** : grisé « Disponible sur le poste » |
| Export PDF du poste | **Vue imprimable** web (`@media print`, bouton « Imprimer / PDF ») ; export des tableaux en **XLSX** (consigne du client, jamais de CSV) : fiche du mois, droit `export-elevage` vérifié dans la méthode |

## 7. Décisions à valider par le client

| Id | Décision prise | Alternative | Risque |
|---|---|---|---|
| X1 | Divergence : la plus récente reste **courante**, l'autre est conservée jusqu'au choix explicite. | La plus ancienne courante ; blocage tant qu'on n'a pas tranché. | La version courante est affichée avant le choix. |
| X2 | Une saisie locale non envoyée n'est **jamais** écrasée ; la version de l'autre est gardée à côté. | Écraser si plus récente (ancien comportement). | Une fiche peut rester « modifiée ailleurs » tant que personne ne tranche. |
| X3 | **Même appareil** : jamais une divergence avec soi-même (restauration de sauvegarde incluse). | Divergence aussi dans ce cas. | Une sauvegarde restaurée plus ancienne peut remplacer une version plus récente du même poste. |
| X4 | Seuils de mortalité DV-13 (1 %/2 % jour, 10 %/20 % cumul) appliqués à **toutes** les filières, pas seulement aux poussins de pintade. | Seuils par filière et par âge. | Un cumul de 10 % est normal sur un cycle de chair mais alarmant sur des pondeuses adultes : à affiner par filière. |
| X5 | Morts + dons > effectif disponible : **refus** ; ventes > effectif : **avertissement** (la caisse peut précéder la fiche). | Refuser aussi les ventes. | Un poste dont les entrées ne sont pas saisies voit ses morts refusés tant qu'il ne les saisit pas. |
| X6 | Œufs pondus > pondeuses de la veille : refus (une poule, un œuf/jour) ; sans pondeuses connues la veille, aucun contrôle. | Tolérance de 2 % (œufs à double jaune). | Une arrivée de pondeuses le jour même n'est pas jugée. |
| X7 | La chaîne enchaîne les jours saisis **par-dessus un trou**, contrairement à la cascade automatique. | Recalculer seulement jusqu'au premier trou. | Un trou long (mois non saisi) propage l'effectif tel quel. |
| X8 | Repli par tête des poissons-chats 1 / 3 / 8 g (arrondis au gramme). L'alevin à 1 g sur-nourrit ×3 sans pesée. | Pas de repli : « — » (RM-ELV-09b). | Poste existant : les barèmes **déjà semés** (8 / 25 / 45) ne sont pas réécrits (ce serait une modification hors demande de référentiel) ; à corriger dans Paramètres Élevage. |
| X9 | Recodage proposé, jamais automatique ; le tirage complet est relancé à chaque recodage. | Suffixe automatique à la détection du conflit. | Un conflit non traité laisse la bande en « conflit » comme avant. |
| X10 | Un soin Planifié en retard est signalé **sans** changer son statut stocké. | Basculer le statut en « En retard » à l'écriture. | Le registre du poste affiche toujours « Planifié » tant qu'on ne confirme pas. |

## 8. Limites et écarts restants

- **Non fait** (hors budget de ce chantier, à planifier) : modification / suppression d'un **incubateur** (le poste n'a pas non plus d'écran ; le serveur accepte déjà une modification), **corbeille d'élevage restaurable au web**, planification en bloc de tout le calendrier d'une bande, indice de consommation affiché (la fonction existe et est testée ; il manque la consommation réelle, qui dépend du stock d'intrants propre à chaque poste).
- Le web ne pose pas de pierre tombale sur une fiche, une bande ni un soin (D11 de `46a_`, D10 de `46c_` inchangés).
- Mutations : serveur 7 (divergence), web 13 (vraisemblance, seuils, base du taux, chaîne, id déterministe, drapeau de résolution, alias de stade, mirage, semaine, trace du recodage, droit d'export, report du décès) toutes tuées ; deux survivantes au premier passage renforcées (même appareil sans base ; chaîne toujours « corrigée »).
- Aucun essai contre le **vrai** serveur Laravel pour les nouvelles colonnes (`base_updated_at`, `variantes`) : le faux serveur de test (`faux_serveur_sync.dart`) rejoue les règles de `FichesJourneeTable` mais a été écrit de la même main.
- `dashboard_elevage_screen.dart` a été reformaté par `dart format` (fichier partagé) : le diff dépasse les lignes touchées.

## 9. Tests

- **Poste** : `expert_zootechnie_test.dart` (seuils, GMQ, IC, durées d'incubation, vraisemblance, couveuse, taux hebdomadaire, rations, soin déterministe) ; `fiches_sync_poste_test.dart` (divergence entre deux postes, suite normale, choix de la version, chaîne, recodage de bande) ; `elevage_sync_poste_test.dart` (`bande_id` voyage) ; `tableau_bord_repository_test.dart` (soins en retard). Suite complète : voir le rapport.
- **Serveur** : `tests/Feature/Sync/ElevageExpertTest.php` (17 cas).
- **Web** : `tests/Feature/Web/ElevageExpertWebTest.php` (48 cas), `SoinsCalendrierWebTest.php` (+10 : décès, lien de bande), `DashboardElevageWebTest.php`, `FicheEspeceWebTest.php`, `RapportsElevageWebTest.php` (valeurs de provende corrigées).
