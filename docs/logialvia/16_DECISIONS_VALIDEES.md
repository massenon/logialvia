# 16 — REGISTRE DES DÉCISIONS VALIDÉES PAR LE CLIENT (DV-01 à DV-15)

## USAGE

- **Quand l'utiliser** : avant de toucher à une ration, une vente de poisson, l'incubation des pintades, une alerte d'autonomie, la corbeille, les droits ou les rôles. Ce registre est la SOURCE de ce qui est TRANCHÉ ; les autres fichiers de `docs/logialvia/` portent le texte normatif et renvoient ici par « TRANCHÉ (DV-xx) ».
- **Ordre** : `10_BRS` → … → `15_REGLES_METIER` → **`16_DECISIONS_VALIDEES`** → modules `20_` à `29_`. En cas de conflit entre ce registre et un autre fichier, ce registre prévaut et l'autre fichier est corrigé.
- **Date de validation** : 08/11/2026. DV-01 à DV-11 : décisions **validées par le client** (DV-16 à DV-18 : ajout des filières escargots et bovins et règle du prototype, validés par le client le 08/11/2026 ; leurs valeurs zootechniques sont recommandées par l'assistant) (DV-08 à DV-11 : réponses du client du 08/11/2026). DV-12 à DV-14 : **recommandations de l'assistant, adoptées comme valeurs par défaut paramétrables**, statut « **recommandé, à confirmer avec le technicien** ». DV-15 : **décision par défaut** faute de réponse du client (Q-DV-5 et Q-DV-7 restent ouvertes).
- **Chemins** : `logialvia/…` = `/home/user/massenon/logialvia/…` (lecture seule) ; sans préfixe = monorepo `/home/user/agrierp`.

> **Avertissement général.** Les repères zootechniques de ce registre (taux de ration, températures, humidités, durées, poids, rations par âge, indices de conversion, âges d'abattage) sont des **ORDRES DE GRANDEUR donnés par l'assistant, à confirmer par le technicien/vétérinaire et les fiches techniques des aliments ; seule la décision d'adopter la règle est validée.** Aucune valeur de ce registre ne s'écrit en dur dans le code comme « vérité ferme » : barèmes, seuils et durées sont des PARAMÈTRES éditables, marqués « repère terrain, à valider » tant que le technicien ne les a pas confirmés.

Statut de chaque ligne ci-dessous : **validé par le client** (la règle) ; les valeurs numériques sont des **repères à valider** sauf mention contraire (durée d'incubation 28 j, seuils d'autonomie 7 j et 3 j : valeurs par défaut validées, paramétrables). Les valeurs de DV-12 à DV-14 (arrondi, 20 %, 500 g, 1 %/2 %, 10 %/20 %, marge de 4 j, repères de poussinière) sont **recommandées, à confirmer avec le technicien**, et restent des paramètres.

---

## 1. Tableau récapitulatif

| Id | Date | Décision (résumé) | Statut | Questions fermées | Reste À DÉFINIR |
|---|---|---|---|---|---|
| DV-01 | 08/11/2026 | Ration des poissons-chats = % de la biomasse par jour | validé par le client | Q-PIS-5, C-3 ; Q-PIS-3 (en partie) | taux retenus par classe, validation technicien |
| DV-02 | 08/11/2026 | Vente/récolte de poisson : poids (kg) ET nombre de sujets ; estimation marquée « estimé » | validé par le client | Q-PIS-6 | arrondi, seuil de tolérance, poids minimum de vente |
| DV-03 | 08/11/2026 | Pintades : libellé du stade voir DV-09 ; incubation 28 j paramétrable (26–28), deux modes, rappels | validé par le client | Q-PIN-4, C-4, C-6 ; Q-PIN-2 (en partie) | repères d'incubateur, seuil de mortalité, poussinière, rations |
| DV-04 | 08/11/2026 | Autonomie de provende : alerte 7 j, critique 3 j, paramétrables par ferme | validé par le client | Q-ALR-1, C-7 | marge de sécurité par fournisseur |
| DV-05 | 08/11/2026 | Corbeille : jamais d'écriture comptable ; contre-passation | validé par le client | Q-CPT-3, C-10 | — |
| DV-06 | 08/11/2026 | Droits du caissier : `/inventaire` interdit ; `/factures-mecef` consultation + réimpression | validé par le client | écarts documentation↔code (1) et (2) de `20_` §3 ; onglet « Retours et Avoirs » (DV-08) | rôle « responsable stock » (DV-15, Q-DV-5) |
| DV-07 | 08/11/2026 | 4 rôles : administrateur, comptable, caissier, animalier | validé par le client | Q-ROL-1, C-9, E-ROL | périmètre exact du comptable |
| DV-08 | 08/11/2026 | Caissier : voit l'onglet « Retours et Avoirs » de `/ventes` et y enregistre un retour client | validé par le client | Q-DV-6 | limite : aucun avoir MeCeF/FA (DV-06) |
| DV-09 | 08/11/2026 | Premier stade des pintades : libellé du glossaire « Poussin(s) » (remplace « pintadeaux » de DV-03 pour le libellé) | validé par le client | Q-DV-8 | catégorie 2 « Pintadau » : inchangée (glossaire) |
| DV-10 | 08/11/2026 | Départ par stade : demandé à l'ouverture de la fiche (comportement AgriERP conservé), pas à la création de la bande | validé par le client | — | — |
| DV-11 | 08/11/2026 | Règles d'incubation modifiables : formulaire « Incubation et règles » dans Paramètres Élevage | validé par le client | — | valeurs numériques = repères à valider |
| DV-12 | 08/11/2026 | Estimation du nombre de sujets d'une vente de poisson : arrondi, écarts, poids minimum, poids moyen initial | recommandé, à confirmer avec le technicien | Q-DV-2 (en « recommandé ») | validation technicien |
| DV-13 | 08/11/2026 | Pintadeaux : alertes de mortalité 1 %/2 % du jour, 10 %/20 % cumulés ; repères de poussinière | recommandé, à confirmer avec le technicien | Q-DV-3 (en « recommandé ») | validation technicien |
| DV-14 | 08/11/2026 | Autonomie de provende : critique = délai fournisseur ; alerte = délai + marge de 4 j | recommandé, à confirmer avec le technicien | Q-DV-4 (en « recommandé ») | délai réel du fournisseur |
| DV-15 | 08/11/2026 | `/inventaire` réservé à l'administrateur ; comptable calqué sur AgriERP | décision par défaut (aucune réponse du client) | — | Q-DV-5 et Q-DV-7 OUVERTES |
| DV-16 | 08/11/2026 | Nouvelle filière **escargots** (achatines) : fiche générique du poste, 3 stades, vente à la pièce | ajout validé par le client ; paramètres recommandés, à confirmer avec le technicien | Q-ESC-1 à Q-ESC-7 (en « recommandé ») | repères zootechniques (poids, cycle, ration, mortalité) |
| DV-17 | 08/11/2026 | Nouvelle filière **bovins** : fiche générique, 3 stades, ration en % du poids vif (mécanisme de DV-01), vente à la tête | ajout validé par le client ; paramètres recommandés, à confirmer avec le technicien et le vétérinaire | Q-BOV-1 à Q-BOV-7 (en « recommandé ») | race, poids de maturité, calendrier vétérinaire, doses |
| DV-18 | 08/11/2026 | Prototype HTML : si absent, le web est converti depuis le code Dart du poste ; s'il est fourni, il prime | validé par le client | Q-PROTO-1 | fourniture de `prototype_html` |

---

## 2. Fiches de décision

### DV-01 — Ration des poissons-chats (Clarias gariepinus) en pourcentage de la biomasse
- **Décision (texte normatif).** La ration journalière d'une catégorie de poissons = **effectif × poids moyen (g) × taux (% de biomasse par jour)**, jamais des grammes par poisson. Le barème est exprimé en **pourcentage de la biomasse par classe de poids**, éditable (CRUD, archivage) dans `/parametres/elevage` > « Rationnement ». Le poids moyen se recalcule par une **pesée d'échantillon tous les 15 jours** sur 5 à 10 % des sujets (minimum 30 poissons). La biomasse (effectif × poids moyen) est une grandeur de suivi.
- **Repères (ordres de grandeur, à valider par le technicien)** :

| Classe de poids | Taux de ration (% de la biomasse par jour) |
|---|---|
| alevin < 5 g | 10–20 % |
| fingerling 5–20 g | 6–8 % |
| juvénile 20–100 g | 3–5 % |
| grossissement 100–500 g | 2–3 % |
| > 500 g | 1–2 % |

  Indice de conversion visé 1,0–1,8 avec un granulé de qualité ; température optimale 26–30 °C, réduire la ration sous 22 °C.
- **Justification zootechnique.** Un poisson-chat grossit vite et son appétit relatif décroît avec la taille : la ration rapportée à la biomasse reste stable, alors qu'une ration « g/tête » oblige à ressaisir un barème à chaque pesée. La biomasse suit la croissance ; la ration en grammes par tête ne la suit pas.
- **Écart de LogiALVIA, vérifié dans le code (08/11/2026, lecture seule).** `logialvia_app/lib/elevage/domain/entities/configuration_espece.dart` porte `rationGrammesParJour` (« Ration normative en g/j ») : l'unité est le **gramme par jour et par sujet**, et la série **30 / 60 / 110 croît avec la taille** (Alevin 30, Juvénile 60, Mature 110). L'hypothèse « 30/60/110 = 3 %/6 %/11 % de la biomasse » **n'est donc PAS confirmée** : elle supposait l'unité « g par kg de biomasse et par jour » et un ordre inverse de la taille, ce qui n'est pas le cas. La série **30/60/110 ET la série 8/25/45** du barème semé (`data/seed/parametres_elevage_seeder.dart`, tous « non confirmé ») sont **à écarter** pour la pisciculture : le barème en % de biomasse les remplace, aucune des deux n'est convertie.
- **Impact par fichier** : `15_` RM-ELV-09b (nouvelle règle), §7.1, §9 (C-3) ; `23_` §3 (rationnement), §4.5, §8 ; `30_` (colonnes `poids_moyen_g`, `biomasse_g`, barème en %) ; `31_` cas T-DV01-* ; `13_` FR-ELV-31 et FR-ELV-33 ; `12_` SR-054 ; `10_` BR-043 ; `11_` PR-021.
- **Reste À DÉFINIR.** Taux unique retenu dans chaque fourchette (valeur par ferme, saisie par le technicien) ; bornes exactes des classes (5, 20, 100, 500 g : à confirmer) ; poids moyen initial d'un lot avant la première pesée (poids déclaré à l'achat ?) ; produit d'aliment (granulé flottant, taille du granulé) ; suivi de l'indice de conversion (Q-PIS-5 en partie).
- **Statut** : validé par le client le 08/11/2026.

### DV-02 — Vente et récolte de poisson : on vend au poids, on compte en sujets
- **Décision (texte normatif).** À **chaque vente ou récolte de poisson**, saisir **DEUX valeurs : le poids en kg ET le nombre de sujets**. L'effectif de la bande baisse du **nombre de sujets**. Si le nombre est inconnu, il est **estimé** = poids vendu (kg) × 1 000 ÷ poids moyen de la dernière pesée (g), et la ligne est marquée **« estimé »** (indicateur persisté, affiché, jamais présenté comme mesuré). La biomasse reste une grandeur de suivi (calculée, jamais saisie). Le produit « **Poisson-chat vif (kg)** » reste vendu **au kilo** ; le prix se calcule sur le poids.
- **Justification.** Le client facture au poids mais l'effectif d'un bassin se compte en têtes : sans les deux valeurs, l'effectif dérive. Une estimation honnête, marquée, vaut mieux qu'un nombre inventé ou qu'un effectif qui ne baisse pas.
- **Impact par fichier** : `15_` RM-ELV-12 (nouvelle règle), RM-ELV-05, §7.1 ; `24_` §3 (grille produits, panier : champ « Nombre de sujets », case « estimé ») ; `23_` §4.5 ; `30_` (`sale_lines.sold_weight_kg`, `sold_count`, `count_is_estimated`) ; `31_` cas T-DV02-* ; `12_` SR-054 ; `13_` FR-VTE-19 ; `10_` BR-044.
- **Refus** : poids ≤ 0 ; nombre ≤ 0 saisi ; nombre > effectif disponible de la catégorie ; nombre inconnu ET aucune pesée antérieure (estimation impossible : la saisie du nombre devient obligatoire).
- **Reste À DÉFINIR.** Arrondi de l'estimation (proposé : à l'entier le plus proche, moitié vers le haut, au moins 1, plafonné à l'effectif) ; écart toléré entre nombre saisi et nombre estimé avant avertissement ; poids minimum de vente ; délai d'attente après traitement (3 j du bleu de méthylène confirmé en prophylaxie).
- **Statut** : validé par le client le 08/11/2026.

### DV-03 — Pintades : libellé du stade voir DV-09, incubation 28 jours paramétrable
- **Décision (texte normatif).**
  1. **Libellé du premier stade : voir DV-09** (« Poussin(s) », glossaire ; ce point remplace « pintadeaux » de la première rédaction). Le terme « Alevins » (poisson) reste interdit pour une pintade. Le barème semé de LogiALVIA est à corriger (`parametres_elevage_seeder.dart` : ligne `pintades / Alevins` → libellé exact du glossaire).
  2. **Incubation : 28 jours** (code `cycle_incubation.dart` et F3) ; `INDEX_MAITRE` qui dit 27 est à corriger. Mais la durée est un **PARAMÈTRE** (défaut 28 j) avec une **fenêtre d'éclosion 26–28 j** : 26–27 j ont été observés en climat chaud ou en couvaison naturelle.
  3. **Deux modes** : couveuse artificielle ; couvaison naturelle (sous poule ou pintade).
  4. **Date d'éclosion prévue = mise en incubation + 28 j**, avec plage affichée 26–28 j ; **mirages vers J7 et J14** ; **transfert à l'éclosoir vers J25** ; rappels automatiques pour ces trois échéances (mirages et transfert : en mode artificiel ; en couvaison naturelle, mirages possibles, pas de transfert).
  5. Suivi du **taux de fertilité** et du **taux d'éclosion** : à MESURER sur la ferme, aucune valeur imposée (RM-COU-03 existant).
  6. **Mortalité forte des premières semaines** du poussin de pintade (froid, humidité) : alerte prévue ; seuils : voir DV-13 (recommandé).
  7. Élevage des poussins de pintade en **poussinière chauffée**.
- **Repères terrain, à valider (ordres de grandeur)** : incubateur 37,5–37,8 °C ; humidité 55–60 %, puis 65–75 % les trois derniers jours ; retournements plusieurs fois par jour jusqu'à J25 ; œufs conservés ≤ 7–10 jours avant la mise en incubation ; poussinière ≈ 35 °C la première semaine puis réduction progressive ; ration **10–60 g/jour par pintadeau selon l'âge**, **90–120 g/jour adulte** (à confirmer avec la fiche de l'aliment) ; abattage : élevage amélioré vers 14–16 semaines, élevage traditionnel bien plus tard.
- **Justification.** 28 j est la durée de référence (code et F3, corrigée par la Gérante) ; la fenêtre reconnaît les écarts de terrain sans les masquer ; les rappels évitent l'oubli des mirages (RM-COU-05).
- **Impact par fichier** : `15_` RM-COU-01 (mise à jour), RM-COU-06 (nouvelle), §7.2, §9 (C-4, C-6) ; `23_` §4.4, §6 ; `30_` (`cycle_couveuse.duree_incubation_jours`, `fenetre_min_jours`, `fenetre_max_jours`, `mode_incubation`) ; `31_` cas T-DV03-* ; `12_` SR-055 ; `13_` FR-ELV-19, FR-ELV-32, FR-ELV-34 ; `10_` BR-045, E-INC.
- **Reste À DÉFINIR.** (Libellé de la catégorie 1 : TRANCHÉ par DV-09.) Les repères d'incubateur et de poussinière sont éditables (DV-11) et à confirmer par le technicien ; seuils de mortalité : DV-13 (recommandé) ; durée exacte du stade pintadeau et seuil de maturité (Q-PIN-1) ; ration définitive par âge (Q-PIN-2 : l'ordre de grandeur est donné, le barème reste à valider) ; reproducteurs et œufs de pintade (Q-PIN-3).
- **Statut** : validé par le client le 08/11/2026.

### DV-04 — Autonomie de provende : deux seuils paramétrables par ferme
- **Décision (texte normatif).** Deux seuils, **paramétrables par ferme** : **alerte à 7 jours** (avertissement) et **critique à 3 jours**. Règle de calcul du **premier** seuil : **délai d'approvisionnement du fournisseur + marge de sécurité** ; la valeur **7** est le défaut. Autonomie (jours) = provende disponible (g) ÷ provende journalière calculée (g) (RM-ELV-10). Ne bloque JAMAIS l'enregistrement ; une alerte par objet et par jour. Contrainte : seuil critique < seuil d'alerte.
- **Justification.** Le délai d'achat de provende à Natitingou n'est pas celui d'une autre ferme : le seuil d'alerte doit couvrir au moins le délai de réapprovisionnement ; le seuil critique signale la rupture imminente.
- **Impact par fichier** : `15_` RM-ELV-10, §8, §9 (C-7) ; `25_` (seuils) ; `29_` (paramètres) ; `23_` §3 (KPI Pondeuses) ; `30_` (`farm_settings.autonomy_alert_days`, `autonomy_critical_days`) ; `31_` cas T-DV04-* ; `13_` FR-ELV-30, FR-ADM-14 ; `12_` SR-056 ; `10_` BR-046.
- **Reste À DÉFINIR.** (Marge de sécurité par défaut : recommandée à 4 jours, DV-14.) Le délai d'approvisionnement est-il saisi par fournisseur ou une seule fois par ferme ? (à demander au client.)
- **Statut** : validé par le client le 08/11/2026.

### DV-05 — Corbeille : les écritures comptables n'y entrent jamais
- **Décision (texte normatif).** Les **écritures comptables n'entrent JAMAIS dans la corbeille** (intangibilité OHADA) : une écriture **ne se supprime pas et ne se restaure pas** ; elle se **CONTRE-PASSE**, puis on en saisit une nouvelle. LogiALVIA retire les écritures de sa corbeille (AgriERP avait raison) : `supprimerPiece` est supprimée, le type `Ecriture` sort de la liste blanche `TypeArchivable`.
- **Justification réglementaire.** Les principes comptables SYSCOHADA/OHADA exigent l'intangibilité et la traçabilité des écritures : toute correction laisse la trace de l'écriture d'origine et de son extourne. Restaurer une écriture supprimée ferait diverger le Bilan.
- **Impact par fichier** : `15_` RM-CPT-09 (nouvelle), §9 (C-10), §8 ; `26_` §4 ; `29_` onglet 6 « Corbeille » (7 types au lieu de 8) ; `12_` SR-007 (déjà conforme) ; `13_` FR-ADM-08, FR-CPT-08, FR-CPT-17 ; `30_` ; `31_` cas T-DV05-* ; `10_` BR-019, BR-047.
- **Reste À DÉFINIR.** Rien sur le principe. Reprise : les écritures déjà présentes dans une corbeille existante du poste doivent être restituées au journal par migration (hors périmètre de ce registre).
- **Statut** : validé par le client le 08/11/2026.

### DV-06 — Droits du caissier : la matrice fait foi, le code la suit
- **Décision (texte normatif).**
  - **`/inventaire`** : réservé à l'**administrateur** (et à un **responsable stock** s'il existe). Le caissier n'y accède pas (ni menu, ni URL directe).
  - **`/factures-mecef`** : le caissier **CONSULTE** et **RÉIMPRIME** ses factures ; il ne peut ni **annuler**, ni **retransmettre**, ni **créer d'avoir**.
  - **Le code suit la matrice des droits.** Si le client veut d'autres accès, on corrige la matrice (puis le code), jamais l'inverse. Les « arbitrages de la Gérante » consignés dans `permission_service.dart` (inventaire ouvert au caissier, facturation complète au caissier) sont **annulés** par cette décision.
- **Traduction en permissions** : `/inventaire` exige `view-stocks` (donc plus `view-ventes`) ; le caissier reçoit `view-facturation` SANS `manage-facturation` ; la réimpression est une lecture.
- **Justification.** Séparation des tâches : celui qui encaisse ne corrige pas la facture normalisée et ne voit pas le coût de revient ni la valorisation.
- **Impact par fichier** : `20_` §3 (matrice), §4 (routes 17 et 18) ; `21_` §8 ; `24_` §3, §5, §6 ; `25_` §8 ; `29_` (matrice en lecture) ; `12_` SR-057 ; `13_` FR-VTE-20, FR-STK-12 ; `14_` NFR-SEC-15 ; `10_` BR-048 ; `31_` T-DV06-*.
- **Reste À DÉFINIR.** Existence du rôle « responsable stock » : valeur par défaut DV-15 (pas de cinquième rôle ; Q-DV-5 ouverte). L'onglet « Retours et Avoirs » du caissier est TRANCHÉ par DV-08 (limite : aucun avoir MeCeF/FA pour le caissier).
- **Statut** : validé par le client le 08/11/2026.

### DV-07 — Quatre rôles
- **Décision (texte normatif).** Quatre rôles : **administrateur (`admin`), comptable (`comptable`), caissier (`caissier`), animalier (`animalier`)**. Celui qui encaisse n'est pas celui qui comptabilise. LogiALVIA n'en avait que trois (le comptable était rattaché à `admin`).
- **Justification.** Séparation des fonctions ; alignement sur le web d'AgriERP (`RolesAndPermissionsSeeder.php` : `admin`, `comptable`, `caissier`, `animalier`).
- **Périmètre du comptable (PROPOSÉ, calqué sur AgriERP, à confirmer)** : `view/manage-comptabilite`, `export` et `view-rapports`/`export-rapports` ; consultation des ventes, de la facturation et des achats ; **gestes de facturation que le caissier n'a pas** (annuler, retransmettre, avoir) ; `close-fiscal-year` : à confirmer entre comptable et admin ; aucune saisie d'encaissement, aucun accès élevage ni paramètres.
- **Impact par fichier** : `20_` §3 ; `21_` §2, §8 ; `26_` §2 ; `29_` onglet 3 (libellés de rôle : « Comptable » à ajouter) et §4 ; `10_` BR-017, BR-049, E-ROL ; `11_` §2 (persona comptable) ; `12_` SR-057 ; `13_` FR-ADM-13 ; `31_` `RbacParRouteTest` ; `15_` §9 (C-9, C-12).
- **Reste À DÉFINIR.** Périmètre exact du comptable : valeur par défaut DV-15 (Q-DV-7 ouverte) (RH et paie si le module existe : Q-RH-1/Q-PAI-1) ; libellé affiché du rôle (« Comptable »).
- **Statut** : validé par le client le 08/11/2026.

### DV-08 — Caissier : l'onglet « Retours et Avoirs » est visible
- **Décision (texte normatif).** Le caissier **voit l'onglet « Retours et Avoirs »** de `/ventes` et **enregistre un retour client** (vente d'origine, produit, quantité, motif, décision « réintégré » ou « réformé »). La **validation reste au serveur** : les 3 refus de RM-VTE-07 s'appliquent, le stock et l'écriture inverse sont gérés par le service unique, jamais par le client.
- **Limite (d'après DV-06).** Le droit du caissier est `manage-ventes` ; il n'a **pas** `manage-facturation`. Il ne crée donc **aucun avoir MeCeF / facture d'avoir `FA-AAAA-NNN`** sur une facture normalisée : s'il enregistre un retour sur une vente déjà normalisée, le retour est enregistré, la ligne reste « avoir MeCeF à émettre » et l'avoir `FA` est émis par l'administrateur ou le comptable (`manage-facturation`). Le bouton « Émettre un avoir » de `/factures-mecef` reste absent ET refusé pour lui.
- **Justification.** Le retour de marchandise est un geste de comptoir ; l'émission de l'avoir fiscal ne l'est pas (séparation des tâches, DV-06).
- **Impact par fichier** : `24_` §3 (onglet 4) et §6 ; `20_` §3 ; `21_` §8 ; `13_` FR-VTE-20 ; `31_` T-DV08-*.
- **Statut** : validé par le client le 08/11/2026.

### DV-09 — Premier stade des pintades : on garde le glossaire (« Poussin(s) »)
- **Décision (texte normatif).** Le premier stade des pintades s'appelle **« Poussin(s) »**, comme dans le code de LogiALVIA et le glossaire / dictionnaire Élevage (volailles) partagé avec AgriERP. Cela **remplace « pintadeaux » de DV-03 pour le LIBELLÉ** ; le terme « Alevins » reste interdit pour une pintade.
- **Conséquence.** L'erreur à corriger dans le barème semé est « Alevins » → **« Poussins »** : le rapprochement du barème avec la catégorie se fait par **libellé exact**, donc le libellé du barème doit être celui du glossaire. Catégories des pintades : **Poussins · Pintadau (immatures) · Mature** (inchangées). « Pintadeau » peut rester un mot d'usage courant dans le texte, jamais un libellé d'écran ni de barème.
- **Impact par fichier** : `15_` §7.2 et C-4 ; `23_` §4.4 ; `13_` FR-ELV-32 ; `31_` UAT-ELV-11.
- **Statut** : validé par le client le 08/11/2026. **Q-DV-8 fermée.**

### DV-10 — Départ par stade : demandé à l'ouverture de la fiche (comportement actuel conservé)
- **Décision (texte normatif).** On **laisse** le comportement d'AgriERP : la **répartition de départ** par catégorie/stade est demandée **à l'ouverture de la fiche** de la bande, **pas à la création** de la bande. Explication et exemple chiffré : `23_` §5.
- **Statut** : validé par le client le 08/11/2026.

### DV-11 — Réglages d'incubation et règles modifiables dans « Paramètres Élevage »
- **Décision (texte normatif).** Un **formulaire** (section « Incubation et règles » de `/parametres/elevage`) permet d'**éditer** les règles d'incubation par espèce (pintade, poule, autre volaille si présente) : durée, fenêtre d'éclosion, mode, jours de mirage, jour de transfert, rappels, délai de conservation des œufs, repères d'incubateur (avertissement). Droit `manage-elevage`, validations françaises, audit, synchronisation vers le poste. Spécification champ par champ : `29_` §4b et `23_` §6b ; construction et prompt : `23_` §6b et §13.
- **Constat AgriERP.** AgriERP **n'a pas de module d'incubation de pintades**. Ses durées de cycle de reproduction (lapins, porcs : palpation, sevrage) sont des dates attendues portées par chaque événement `livestock_reproduction_events`, calculées dans `SuiviReproduction.php` (valeurs fixes dans le code : palpation à +14 j, sevrage à +42 j), **non éditables dans un formulaire de réglage** ; seuls sont éditables dans `ParametresElevage` les barèmes, la prophylaxie, les provendes, les formats de numérotation (`elevage_numbering_settings`) et le délai de rappel des soins (`company_settings.rappel_soins_jours`, entier 0–30). Ces deux derniers servent de **modèle de construction**.
- **Impact par fichier** : `23_` §6 et §8 ; `29_` ; `30_` ; `13_` FR-ELV-34, FR-ADM-14 ; `31_` T-DV11-*.
- **Statut** : validé par le client le 08/11/2026 (valeurs numériques : repères à valider).

### DV-12 — Estimation du nombre de sujets d'une vente de poisson [recommandé, à confirmer avec le technicien]
- **Règle.** `n_estimé = arrondi à l'entier le plus proche (poids vendu en kg ÷ poids moyen du lot en kg de la dernière pesée)`, **borné entre 1 et l'effectif vivant**. Valeurs par défaut paramétrables.
- **Exemples calculés.** 12,4 kg ÷ 0,62 kg = 20,0 → **20** ; 12,4 ÷ 0,58 = 21,38 → **21** ; 3,0 ÷ 0,62 = 4,84 → **5** ; 900 kg ÷ 0,62 = 1 451,6 mais effectif 1 200 → **1 200 (plafonné)**.
- **Si l'opérateur saisit AUSSI le nombre réel** : avertissement NON bloquant si l'écart avec l'estimation dépasse **20 %** ; avertissement si le poids moyen des sujets vendus (kg ÷ nombre) sort de **50–150 %** du poids moyen du lot.
- **Poids minimum de vente** (paramètre, défaut **500 g** par sujet, calculé sur le poids moyen vendu) : avertissement sous ce seuil, **jamais de blocage** (poisson-chat de table courant : 500–1 000 g).
- **Poids moyen initial d'un lot** : saisie **obligatoire** à la création d'un lot de poissons (poids d'empoissonnement, ex. 2 g), puis mis à jour par chaque pesée d'échantillon (tous les 15 jours, ≥ 30 poissons ou 5–10 %). Sans pesée de plus de **30 jours** : avertissement « poids moyen périmé » et l'estimation reste marquée « estimée ».
- **Précise DV-02** (arrondi : « moitié vers le haut » de DV-02 est remplacé par « entier le plus proche » ; les deux concordent hors cas de moitié exacte). **Impact** : `15_` RM-ELV-12 ; `24_` §3 ; `25_`/`29_` (paramètres) ; `30_` ; `31_` T-DV12-*. **Ferme Q-DV-2 en « recommandé ».**

### DV-13 — Poussins de pintade : repères et alertes [recommandé, à confirmer avec le technicien]
- **Mortalité** (paramétrable) : du jour **> 1 %** de l'effectif : avertissement ; **> 2 %** : critique. Cumulée depuis la mise en place **> 10 % à 4 semaines** : avertissement ; **> 20 %** : critique.
- **Exemple chiffré** (lot de 200) : avertissement dès **3 morts le même jour** (1,5 %), critique dès **5** (2,5 %) ; cumul : avertissement à **21 morts** (> 20), critique à **41** (> 40).
- **Poussinière** : température sous éleveuse ≈ **35 °C** la première semaine puis baisse d'environ **3 °C par semaine** jusqu'à **25–27 °C** vers la 4ᵉ–5ᵉ semaine (repère à confirmer). Aliment démarrage riche en protéines (≈ **24 %**, à confirmer avec la fiche de l'aliment). Incubateur : voir DV-11.
- **Impact** : `15_` RM-COU-06 ; `23_` §4.4 ; `29_` ; `31_` T-DV13-*. **Ferme Q-DV-3 en « recommandé ».**

### DV-14 — Autonomie de provende : seuils calculés [recommandé, à confirmer avec le technicien]
- **Règle.** **Critique = délai d'approvisionnement du fournisseur (jours)** ; **alerte = délai + marge de sécurité** ; marge recommandée **4 jours** (week-end de 2 jours + 1 jour de retard + 1 jour de livraison partielle).
- **Exemples.** Délai 3 j → critique 3 j, alerte **7 j** (= les défauts 7/3 de DV-04) ; délai 5 j → critique 5, alerte **9** ; provende fabriquée sur place : délai = fabrication + achat des matières premières.
- Les deux seuils restent **éditables** (Paramètres Élevage, `autonomy_alert_days`, `autonomy_critical_days`) ; le délai réel du fournisseur est **à demander au client**. **Ferme Q-DV-4 en « recommandé ».** (Q « par fournisseur ou par ferme » : voir DV-04, reste à demander.)

### DV-15 — Responsable stock et comptable : valeurs par défaut (aucune réponse du client)
- **Responsable stock.** `/inventaire` **réservé à l'administrateur**. Si un « responsable stock » existe, on lui donnera **un droit dédié plus tard** ; **pas de 5ᵉ rôle**. **Q-DV-5 reste OUVERTE** avec cette valeur par défaut.
- **Comptable.** Périmètre par défaut **calqué sur AgriERP** (les gestes de facturation de DV-07 sont conservés) : comptabilité et exercices en gestion, rapports, TVA, **lecture** des ventes, achats et stocks ; **ni caisse ni élevage**. **Q-DV-7 reste OUVERTE** avec cette valeur par défaut. (Précision : « lecture des stocks » ne donne PAS l'accès à `/inventaire`, qui reste administrateur seul ; voir « Contradictions » ci-dessous.)
- **Statut** : décision par défaut, non validée par le client.

---

## 3. Filières ajoutées le 08/11/2026 : escargots et bovins

> Le client demande d'ajouter **l'espèce escargot et l'espèce bovins**. Règle donnée : (a) pour les sept questions, **suivre ce que fait le poste Flutter actuel** (`configuration_espece.dart` : fiche générique, 3 catégories dont une jeune qui reçoit achats et naissances et une commercialisée, ration par catégorie, glossaire propre à la filière, calendrier de prophylaxie, numérotation) ; (b) là où le poste ne répond pas, **suivre la recommandation d'un expert en élevage**. Tout chiffre ci-dessous est donc un **repère zootechnique recommandé, à valider par le technicien (escargots) et le vétérinaire (bovins)** : il se saisit comme valeur modifiable par ferme, jamais comme règle figée. Les deux filières sont **désactivées par défaut** (comme pisciculture, aviculture classique et cuniculture) ; Goliaths et Pintades restent toujours actifs.

### DV-16 — Escargots (héliciculture) [ajout validé ; paramètres recommandés, à confirmer avec le technicien]

- **Identité (proposée).** `identifiant` `escargots` · libellé « Escargots » · route `/elevage/escargots` · module activable `heliciculture` · icône Material Symbols à choisir (proposé : `eco`).
- **Q-ESC-1 Espèce.** Achatines géantes d'Afrique de l'Ouest : *Archachatina marginata* et *Achatina achatina* (à confirmer ; la fiche ne distingue pas l'espèce dans cette version).
- **Q-ESC-2 Stades (modèle : Lapins).** 3 catégories : **Naissain** (jeune ; reçoit achats et naissances) · **Marchand** (commercialisée ; seule déduite des ventes) · **Reproducteur**. Pastilles « Rappel du Cycle » : *Ponte et éclosion · Naissain · Marchand · Reproducteur*. Glossaire : colonne 1 « Achats », colonne 2 « **Nés (Éclosions)** ».
- **Q-ESC-3 Unité de vente (modèle : toutes les fiches sauf poisson).** À la **pièce** (nombre de sujets) ; le stock du produit vendable est en sujets. Vente au kilo : NON ADOPTÉ (pas de DV-02 pour les escargots).
- **Q-ESC-4 Cycle et maturité (repères).** Éclosion 3 à 5 semaines après la ponte ; taille marchande vers 6 à 8 mois pour environ 100 g. Seuils de l'alerte de maturité proposés : `poidsMaturiteGrammes` 100 · `ageMaturiteJours` 180. Alertes de mortalité : même mécanisme que DV-13, **seuils cumulés 10 % (alerte) / 20 % (critique)**.
- **Q-ESC-5 Alimentation (repères, g/tête/jour).** Naissain **1** · Marchand **5** · Reproducteur **8** (aliment composé et complément de calcium ; les végétaux frais ne passent pas en provende). `noteRationnement` : « Barème indicatif d'héliciculture, à valider par le technicien ». Intrant à semer au module Stocks : « Complément calcium (coquilles broyées) » (code à créer, seuil d'alerte à fixer).
- **Q-ESC-6 Prophylaxie (modèle : calendrier du poste).** Pas de vaccination. Calendrier d'**hygiène** proposé, SANS produit ni dose inventés : nettoyage des bacs/parcs (hebdomadaire), désinfection (mensuelle), quarantaine des sujets achetés (14 jours), contrôle de l'humidité (quotidien). Aucune échéance n'est semée par défaut : l'écran « Calendriers Prophylaxie » offre la pastille « Escargots » vide, avec « Ajouter une Échéance » ; produits et rémanences à saisir par le technicien.
- **Q-ESC-7 Écran.** **Fiche générique du poste**, aucun champ propre dans cette version. Température et humidité des parcs : note libre de la saisie journalière. Champs d'ambiance dédiés : NON ADOPTÉ, évolution possible. Numérotation (Paramètres Élevage) : groupe « HÉLICICULTURE (ESCARGOTS) », préfixe **BAC** (proposé), préfixe vide refusé comme les autres.
- **Reste À DÉFINIR.** Poids et âge de maturité réels de l'élevage ; densité par bac ; seuils de mortalité ; calendrier d'hygiène définitif ; vente au kilo si le marché l'exige.

### DV-17 — Bovins [ajout validé ; paramètres recommandés, à confirmer avec le technicien et le vétérinaire]

- **Identité (proposée).** `identifiant` `bovins` · libellé « Bovins » · route `/elevage/bovins` · module activable `bovins` · icône à choisir (proposé : `agriculture`).
- **Q-BOV-1 Race.** Taurins locaux (Borgou, Somba) et zébus (Peulh) du nord du Bénin ; non distinguées dans la fiche (à confirmer).
- **Q-BOV-2 Stades (modèle : Lapins).** 3 catégories : **Veau** (jeune, 0 à 6 mois ; reçoit achats et naissances) · **Embouche** (commercialisée, environ 6 à 24 mois) · **Reproducteur**. Pastilles : *Naissance · Veau · Embouche · Reproducteur*. Glossaire : « Achats », « **Nés (Vêlage)** ».
- **Q-BOV-3 Unité de vente.** À la **tête**. Le poids vif est relevé à la pesée (champ de pesée de la fiche) et sert à la classe de ration et au prix indicatif ; vente au kilo de poids vif : NON ADOPTÉ.
- **Q-BOV-4 Cycle et maturité (repères).** Gestation environ 283 jours (9 mois) ; sevrage vers 6 mois ; embouche de 3 à 6 mois ; maturité commerciale proposée : `poidsMaturiteGrammes` **250 000** (250 kg) ou `ageMaturiteJours` **730** (24 mois). Mortalité cumulée : **5 % (alerte) / 10 % (critique)**.
- **Q-BOV-5 Alimentation.** Un ruminant se rationne en **matière sèche (MS) = 2,5 à 3,5 % du poids vif par jour, sur le poids moyen du groupe**, pas en g par tête fixes. On **réutilise le mécanisme de DV-01** : second tableau « Taux de ration par classe de poids » (CLASSE DE POIDS (kg) · TAUX (% DU POIDS VIF PAR JOUR, EN MS) · CONFIRMÉ ? · ACTIONS), avec CRUD complet et archivage. Valeurs d'ouverture, repères à valider : < 150 kg **3,5 %** ; 150 à 300 kg **3,0 %** ; > 300 kg **2,5 %**. Le fourrage (pâturage, foin) n'entre pas en stock dans cette version : le calcul porte sur l'aliment complémentaire ; « Les 30/60/110 g du poste ne s'appliquent pas aux bovins ».
- **Q-BOV-6 Prophylaxie (modèle : calendrier du poste, 11 échéances semées pour les autres filières).** Échéances proposées, **produits, doses et rémanences laissés au vétérinaire** : vaccination contre la péripneumonie contagieuse bovine (annuelle), contre le charbon bactéridien et symptomatique (annuelle), contre la pasteurellose (selon avis vétérinaire) ; déparasitage interne (2 fois par an) ; lutte contre les tiques par bain ou pulvérisation (périodique, plus fréquente en saison des pluies). Échéances semées SANS produit : à compléter.
- **Q-BOV-7 Écran.** Fiche générique du poste, plus le champ de poids vif (Q-BOV-3). Numérotation : groupe « ÉLEVAGE BOVIN », préfixe **PARC** (proposé).
- **Reste À DÉFINIR.** Race, poids de maturité, taux de ration définitifs, calendrier et produits vétérinaires, gestion du fourrage et du pâturage, traçabilité par tête (boucle d'identification) si le client la veut.

### DV-18 — Prototype HTML : convertir depuis le Dart tant qu'il n'est pas fourni

- **Décision.** Le prototype HTML/Tailwind (31 pages, version HTML du poste Flutter) est sur le poste du client, `C:\Projects\logialvia-monrepo\prototype_html`, hors dépôt. Il **sera fourni plus tard**. D'ici là, **le web Laravel + Tailwind est converti depuis le code Dart du poste**, en suivant la documentation de ce dossier (`04_UI_UX_DESIGN_SYSTEM.md`, `02_ARCHITECTURE_WEB_ET_STACK.md`, `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md`).
- **Hiérarchie des sources visuelles (en cas de conflit, la plus haute gagne).** 1. `prototype_html`, dès qu'il est fourni ; 2. le code du poste : `logialvia_app/lib/core/theme` (couleurs, espacements, rayons, ombres, typographie, breakpoints), `core/widgets`, et chaque écran de `lib/*/presentation` ; 3. les captures de référence `docs/manuel/captures/*.png` (68 écrans, générées par les tests) ; 4. les documents `docs/01_DESIGN_SYSTEM.md`, `E4` à `E9`, `G2`, `K2`.
- **Règle de conversion.** Par RÔLE : `AppColors` → `tailwind.config.js` (mêmes valeurs hexadécimales), `AppSpacing`/`AppRadius`/`AppShadows`/`AppTypography` → échelle Tailwind du design system, widgets partagés → composants Blade/Livewire, `AppBreakpoints` → les 4 classes Desktop/Laptop/Tablet/Mobile. Aucune valeur n'est reconstruite de mémoire ni reprise d'AgriERP.
- **Quand le prototype arrive.** Comparer, écran par écran, la conversion et le prototype ; tout écart est relevé dans un rapport (valeur, fichier, écran) avant correction ; le prototype l'emporte, sauf `ÉCART_DELIBERE` déjà documenté dans le code du poste (arbitrages de la Gérante).
- **Reste À DÉFINIR.** Mode de fourniture du prototype (copie, dépôt GitHub) : Q-PROTO-1.

## 4. Nouvelles questions ouvertes nées de ces décisions

| Id | Question | Décision liée |
|---|---|---|
| Q-DV-1 | Quel technicien/vétérinaire valide le barème en % de biomasse (taux par classe) et le poids moyen initial d'un lot avant la première pesée ? | DV-01 |
| Q-DV-2 | ~~Arrondi, écart toléré, poids minimum de vente~~ **FERMÉE « recommandé, à confirmer avec le technicien » (DV-12)** : entier le plus proche, 1 à l'effectif, écart 20 %, 500 g. | DV-02, DV-12 |
| Q-DV-3 | ~~Seuil et fenêtre de l'alerte de mortalité~~ **FERMÉE « recommandé » (DV-13)** : 1 %/2 % du jour, 10 %/20 % cumulés à 4 semaines. Reste : repères validés par le technicien. | DV-03, DV-13 |
| Q-DV-4 | ~~Marge de sécurité par défaut~~ **FERMÉE « recommandé » (DV-14)** : 4 jours. Reste à demander au client : le délai réel du fournisseur (par fournisseur ou par ferme). | DV-04, DV-14 |
| Q-DV-5 | **OUVERTE** (valeur par défaut DV-15 : `/inventaire` administrateur seul, pas de 5ᵉ rôle ; droit dédié plus tard) : un « responsable stock » existe-t-il ? | DV-06, DV-15 |
| Q-DV-6 | ~~Le caissier garde-t-il l'onglet « Retours et Avoirs » ?~~ **FERMÉE (DV-08)** : oui, retour client ; aucun avoir MeCeF/FA. | DV-06, DV-08 |
| Q-DV-7 | **OUVERTE** (valeur par défaut DV-15 : calqué sur AgriERP) : périmètre exact du comptable (RH, achats, `close-fiscal-year`) ? | DV-07, DV-15 |
| Q-DV-9 | Quel technicien valide les repères escargots (poids, cycle, ration, mortalité, hygiène) et quel vétérinaire valide le calendrier, les produits et les doses des bovins ? | DV-16, DV-17 |
| Q-PROTO-1 | Comment le client fournit-il `prototype_html` (copie, dépôt GitHub) ? | DV-18 |
| Q-DV-8 | ~~Libellé exact du premier stade des pintades~~ **FERMÉE (DV-09)** : « Poussin(s) » (glossaire) ; catégorie 2 « Pintadau » inchangée. | DV-03, DV-09 |

**Questions restées ouvertes** : Q-DV-1 (technicien du barème en % de biomasse), Q-DV-5 et Q-DV-7 (valeurs par défaut DV-15) ; reste à demander au client le délai réel du fournisseur de provende (DV-14).

## 4b. Contradictions apparentes entre décisions (relevées le 08/11/2026)

- **DV-03 ↔ DV-09** : « pintadeaux » (DV-03) contre « Poussin(s) » (DV-09). Résolue : DV-09 prévaut pour le LIBELLÉ ; DV-13 et le reste du dossier parlent de « poussins de pintade » (« pintadeaux » n'est plus qu'un mot d'usage).
- **DV-02 ↔ DV-12** : arrondi « moitié vers le haut » contre « entier le plus proche » : même résultat, sauf conventions de langage ; DV-12 précise DV-02 sans le contredire. Le poids moyen est en grammes dans DV-02 (× 1 000 ÷ g) et en kg dans DV-12 : formules équivalentes.
- **DV-04 ↔ DV-14** : DV-04 fixe 7 j / 3 j par défaut ; DV-14 les dérive (délai + 4 j / délai). Compatibles seulement pour un délai de 3 j ; avec un autre délai les seuils recommandés changent, donc DV-04 reste la valeur initiale et DV-14 la méthode de réglage.
- **DV-06/DV-08 ↔ DV-15** : le caissier voit « Retours et Avoirs » mais n'émet pas d'avoir FA ; et « lecture des stocks » du comptable (DV-15) ne contredit pas DV-06 car `/inventaire` exige `view-stocks` réservé à l'administrateur. À arbitrer si le client veut que le comptable lise l'inventaire.
- **DV-07 ↔ DV-15** : DV-07 propose pour le comptable les gestes de facturation (annuler, retransmettre, avoir) ; DV-15 ne les cite pas (lecture des ventes). Par défaut on garde DV-07 (proposé) ; à confirmer avec Q-DV-7.
- **DV-11 ↔ AgriERP** : la consigne présupposait des durées de cycle lapins/porcs déjà éditables ; vérification faite dans le code, elles ne le sont pas (voir DV-11).

## 5. Critères d'acceptation du registre

- [ ] Chaque DV porte date, décision, justification, impact par fichier, reste À DÉFINIR, statut.
- [ ] En tête : l'avertissement « ordres de grandeur… » (présent).
- [ ] Chaque question fermée est remplacée dans son fichier par « TRANCHÉ (DV-xx) ».
- [ ] Aucun repère zootechnique n'est codé en dur : barèmes, seuils, durées et fenêtres sont des paramètres.
