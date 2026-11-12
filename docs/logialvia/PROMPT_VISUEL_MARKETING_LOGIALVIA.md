# PROMPT_VISUEL_MARKETING_LOGIALVIA — Prompt d'image pour l'affiche « Gestion et Suivi Avicole Intégré »

**Statut : prompts rédigés le 2026-11-11, non essayés** (aucun générateur d'image n'a été appelé ; les rendus de DALL·E 3 / ChatGPT image varient d'une génération à l'autre). Ce document fournit un prompt carré 1:1 à coller, une version courte, une variante paysage 16:9, un « prompt négatif », une liste de contrôles après génération et des conseils d'itération.

Principe retenu : **l'image sert d'ambiance et de décor ; le texte exact doit être vérifié, et au besoin ajouté en post-production** (§7), car les générateurs d'images déforment souvent les accents et les petits caractères (observation d'usage courante, à confirmer à l'essai).

## 1. Ce qui vient du dépôt (à ne pas inventer)

| Élément | Valeur | Source |
|---|---|---|
| Nom du produit | LogiALVIA, écrit « Logi » en blanc et « ALVIA » en or sur fond marine | `docs/readme/social-preview.png` |
| Baseline produit | « Gestion et Suivi Avicole Intégré » | `README.md`, commit `86509a7` |
| Phrase de marque existante | « Chaque œuf, chaque sac, chaque franc comptés. » | `README.md` (ligne 12), `social-preview.png` |
| Bleu marine (primaire) | `#1F3864` ; variante sombre `#152847` | `docs/01_DESIGN_SYSTEM.md` (`brand-navy`, `brand-navy-dark`), `lib/core/theme/app_colors.dart` |
| Or (accent secondaire « avicole, volaille, terre ») | `#B58B2A` ; clair `#D4A94D` | idem (`brand-gold`, `brand-gold-light`) |
| Vert | `#3A7D44` (`success-deep`) et fond `#E1F0E3` (`success-container`) | idem. **Le design system n'a pas de jeton « vert foncé » de marque** : `success-deep` est le plus proche |
| Fond neutre / texte | `#F2F2F2` fond général, `#1A1D23` texte principal | idem |
| Police de l'interface | Roboto | `docs/01_DESIGN_SYSTEM.md` (ligne 63 : `fontFamily.sans: ['Roboto', …]`) |
| Logo officiel | `logo/logo_logialvia.png` (médaillon + mot-symbole + baseline + raison sociale) ; icône (embleme ALLMANY) `logo/app_icon_apercu.png`, logo ALLMANY `logo/logo_allmany.png` | `logo/`, `logialvia_app/outils/generer_icone.py` |
| Raison sociale | ALLMANY ET COMPAGNIE | `Runner.rc`, `README.md` |
| Fuseau et pays de l'exploitation | Benin (fuseau `Africa/Porto-Novo`, exploitation à Natitingou) | `logialvia_laravel/config/logialvia.php`, `app/Services/Comptabilite/Verrous.php` |

### Filières réelles du projet (`CLAUDE.md`)

`goliaths`, `pintades`, `lapins`, `poissons-chats`, `poulets`, `pondeuses`, `escargots`, `ovins` (clés de `FilieresElevage::LIBELLES` ; libellés : Goliaths, Pintades, Lapins, Poissons-Chats, Poulets, Pondeuses, Escargots, Ovins). La filière Bovins a été **remplacée** par Ovins le 2026-11-11 (DV-22).

Correspondance avec le sous-titre demandé :

| Mot du sous-titre | Filière ou objet du projet |
|---|---|
| Pintades | `pintades` |
| Couveuses | écran Cycle Couveuse (`/elevage/couveuse`), pas une filière |
| Poules | `poulets` et `pondeuses` (aucune filière ne s'appelle « poules ») |
| Œufs de pintade | produit et suivi d'œufs de la filière `pintades` |
| Poisson-chat | `poissons-chats` |
| Lapins | `lapins` |

Non représentés par défaut sur l'affiche : `goliaths`, `escargots`, `ovins`. Pour une version qui nomme **toutes** les filières, remplacer le sous-titre par : « Goliaths • Pintades • Lapins • Poissons-chats • Poulets • Pondeuses • Escargots • Ovins » (texte plus long : prévoir deux lignes).

## 2. Textes exacts à écrire dans l'image

À recopier **à la lettre** (accents et majuscules compris) :

| Zone | Texte |
|---|---|
| Titre | `Votre logiciel de Gestion et Suivi Avicole Intégré` |
| Sous-titre | `Pintades • Couveuses • Poules • Œufs de pintade • Poisson-chat • Lapins` |
| Phrase d'accroche | `Chaque œuf, chaque sac, chaque franc comptés.` (phrase existante du README ; remplaçable) |
| Picto 1 | `Tableaux de bord intelligents` |
| Picto 2 | `Suivi élevage en temps réel` |
| Picto 3 | `Gestion des stocks et ventes` |
| Picto 4 | `Comptabilité & Finance intégrée` |
| Picto 5 | `Administration simplifiée` |

Remarque d'exactitude : « Suivi élevage en temps réel » est un libellé commercial fourni. Le poste fonctionne **hors ligne** et se synchronise par cycles (toutes les 5 minutes en routine, voir `BLUEPRINT_SYNCHRONISATION_POSTES.md` §9) : « temps réel » est à employer avec cette nuance si l'affiche engage le produit.

## 3. Prompt principal, carré 1:1 (à coller dans DALL·E 3 / ChatGPT image)

```text
Crée une affiche publicitaire CARRÉE (format 1:1, 1024 x 1024) pour un logiciel de gestion d'élevage.

SCÈNE : un clos d'élevage tropical au Bénin, en fin de journée, lumière dorée rasante (heure dorée). Au premier plan à gauche, des cages grillagées métalliques avec des pintades au plumage gris perlé moucheté de blanc. À droite, un silo de provende vert. Au centre, un plateau d'œufs de pintade bien rangés (œufs beiges tachetés) et, derrière, une couveuse électrique compacte à la porte vitrée. Sur les côtés : un bassin d'élevage de poissons-chats avec une eau calme, un lapin au poil clair dans une cage propre, une poule rousse qui picore. Sol de terre ocre, végétation tropicale douce (manguiers, palmes) en arrière-plan flou. Ambiance propre, ordonnée, professionnelle, sans personnages au premier plan.

PALETTE (à respecter) : bleu marine #1F3864 (bandeaux, texte du titre), or #B58B2A et #D4A94D (accents, reflets de la lumière), vert foncé #3A7D44 (silo, feuillage), fond doux #F2F2F2 pour les zones de texte. Pas d'autres couleurs dominantes.

TEXTE À ÉCRIRE DANS L'IMAGE (exactement, en français, avec les accents, typographie sans empattement type Roboto, très lisible, aucun autre texte) :
- Titre en haut, en bleu marine gras, sur fond clair : « Votre logiciel de Gestion et Suivi Avicole Intégré »
- Juste dessous, en or : « Pintades • Couveuses • Poules • Œufs de pintade • Poisson-chat • Lapins »
- Phrase d'accroche en bas du décor : « Chaque œuf, chaque sac, chaque franc comptés. »
- Une rangée de 5 pictogrammes simples, ronds, trait blanc sur fond bleu marine, en bas de l'affiche, chacun avec sa légende exacte sous lui :
  1. un graphique en barres : « Tableaux de bord intelligents »
  2. une icône d'œuf avec un pouls : « Suivi élevage en temps réel »
  3. un sac et un chariot : « Gestion des stocks et ventes »
  4. une calculatrice avec une pièce : « Comptabilité & Finance intégrée »
  5. un bouclier avec un engrenage : « Administration simplifiée »

CONTRAINTES :
- Aucun logo de marque tierce, aucune marque, aucun filigrane, aucun QR code, aucune URL.
- Pas de logo LogiALVIA inventé : laisse un espace libre en haut à gauche pour le placer ensuite.
- Texte net, non déformé, non coupé, orthographe exacte (É, œ, &). Si un mot ne peut pas être écrit correctement, laisse la zone de texte vide plutôt que d'écrire des lettres fausses.
- Composition aérée : texte lisible sur zones unies, décor en arrière-plan, marges de sécurité de 5 % sur les bords.
- Style photo réaliste retouchée, lumière chaude, netteté élevée, esthétique d'affiche professionnelle.

À ÉVITER : texte flou ou illisible, lettres inventées, mains ou visages déformés, animaux difformes (pattes en trop), logos, marques, filigranes, saturation excessive, fond encombré, couleurs néon, style dessin animé, effets 3D exagérés.
```

## 4. Version courte (1:1)

```text
Affiche carrée 1:1 : clos d'élevage tropical au Bénin à l'heure dorée, cages grillagées avec pintades, silo vert, couveuse, plateau d'œufs de pintade, bassin de poissons-chats, lapin, poule. Palette : bleu marine #1F3864, or #B58B2A, vert #3A7D44. Texte exact, en français, police sans empattement : titre « Votre logiciel de Gestion et Suivi Avicole Intégré » ; sous-titre « Pintades • Couveuses • Poules • Œufs de pintade • Poisson-chat • Lapins » ; accroche « Chaque œuf, chaque sac, chaque franc comptés. » ; 5 pictos ronds légendés : « Tableaux de bord intelligents », « Suivi élevage en temps réel », « Gestion des stocks et ventes », « Comptabilité & Finance intégrée », « Administration simplifiée ». Aucun logo tiers, aucun texte déformé, pas d'autre texte.
```

## 5. Variante paysage 16:9

```text
Crée une affiche publicitaire PAYSAGE (format 16:9, 1792 x 1024) pour un logiciel de gestion d'élevage.

SCÈNE : même univers que la version carrée, étalé en largeur : clos d'élevage tropical au Bénin à l'heure dorée ; de gauche à droite : cages grillagées avec pintades, plateau d'œufs de pintade et couveuse électrique, bassin de poissons-chats, lapin en cage, poule rousse, silo de provende vert à l'extrémité droite. Végétation tropicale douce et floue en arrière-plan, sol de terre ocre, lumière dorée rasante. Aucune personne au premier plan.

DISPOSITION : tiers gauche = zone de texte sur fond bleu marine #1F3864 (légèrement dégradé vers #152847) avec le titre ; deux tiers droits = scène photographique ; bande horizontale en bas = 5 pictogrammes ronds alignés avec légendes.

PALETTE : bleu marine #1F3864, or #B58B2A / #D4A94D, vert #3A7D44, fond clair #F2F2F2.

TEXTE (exact, en français, sans empattement type Roboto, aucun autre texte) :
- Titre, blanc gras sur le bleu marine : « Votre logiciel de Gestion et Suivi Avicole Intégré »
- Sous-titre, or : « Pintades • Couveuses • Poules • Œufs de pintade • Poisson-chat • Lapins »
- Accroche, blanc : « Chaque œuf, chaque sac, chaque franc comptés. »
- Pictos (trait blanc sur rond bleu marine) : « Tableaux de bord intelligents » · « Suivi élevage en temps réel » · « Gestion des stocks et ventes » · « Comptabilité & Finance intégrée » · « Administration simplifiée »

CONTRAINTES : aucun logo tiers ; espace libre en haut à gauche pour le logo LogiALVIA (à ajouter ensuite) ; texte net et non déformé, orthographe exacte (É, œ, &) ; marges de sécurité de 5 %.

À ÉVITER : texte illisible, lettres inventées, animaux difformes, logos, marques, filigranes, couleurs néon, style dessin animé.
```

## 6. « Prompt négatif »

DALL·E 3 / ChatGPT image n'ont pas de champ « negative prompt » dédié (à ma connaissance, à confirmer dans votre interface) : on l'écrit dans le prompt, après « À ÉVITER ». Si vous utilisez un générateur qui offre ce champ (Stable Diffusion, Midjourney `--no`), coller :

```text
texte flou, texte illisible, lettres inventées, fautes d'orthographe, accents manquants, texte déformé, texte coupé, logo, marque, filigrane, QR code, URL, mains difformes, visages déformés, animaux difformes, pattes en trop, surexposition, saturation excessive, couleurs néon, style dessin animé, style 3D exagéré, fond encombré, personnages au premier plan, drapeau, symbole politique ou religieux
```

## 7. Contrôles après génération (à cocher)

Texte (à vérifier mot à mot) :
- [ ] Titre : « Votre logiciel de Gestion et Suivi Avicole Intégré » (« Intégré » avec accent)
- [ ] Sous-titre : « Pintades • Couveuses • Poules • Œufs de pintade • Poisson-chat • Lapins » (« Œufs » avec le œ ligaturé, séparateurs « • » présents, singulier « Poisson-chat »)
- [ ] Accroche : « Chaque œuf, chaque sac, chaque franc comptés. » (accord de « comptés »)
- [ ] 5 légendes exactes (« Comptabilité & Finance intégrée » : accent sur « Comptabilité », esperluette conservée)
- [ ] Aucun texte parasite, aucune lettre inventée, aucun chiffre

Image :
- [ ] Les éléments demandés sont reconnaissables : cages grillagées, silo vert, pintades (plumage gris moucheté), couveuse, plateaux d'œufs, poisson-chat/bassin, lapin, poule
- [ ] Animaux anatomiquement corrects (nombre de pattes, têtes)
- [ ] Palette cohérente avec le design system (marine, or, vert)
- [ ] Aucun logo ou marque tiers, aucun filigrane
- [ ] Marges de sécurité respectées, texte hors des bords

Contenu :
- [ ] Si l'affiche promet « temps réel », la nuance « poste hors ligne, synchronisation » est assumée (§2)
- [ ] Les filières montrées correspondent à la liste du projet (§1)

Logo : **ne pas demander au générateur de dessiner le logo LogiALVIA** ; ajouter ensuite le fichier officiel `logo/logo_logialvia.png` dans l'espace laissé libre (ou, pour un petit format, le médaillon seul : `logo/app_icon_apercu.png`).

## 8. Conseils d'itération

1. **Une idée par essai** : d'abord valider la scène (sans texte), puis ajouter le texte. Pour l'étape 1, retirer du prompt toute la section « TEXTE ».
2. **Texte déformé** : raccourcir (titre seul), puis ajouter sous-titre et pictos en post-production (Canva, Figma, Photoshop) avec la police Roboto et les couleurs du §1. C'est la méthode la plus fiable pour des accents exacts.
3. **Pictos** : demander des pictos **sans légende** et poser les légendes soi-même ; ou n'en garder que trois.
4. **Animaux** : si un animal est difforme, le nommer en tête de la scène (« une pintade au plumage gris perlé moucheté de blanc, tête bleutée ») et réduire le nombre d'animaux par image.
5. **Lumière** : « heure dorée, soleil bas, ombres longues, reflets chauds sur le grillage » pour renforcer l'ambiance ; éviter « coucher de soleil rouge » (dérive de palette).
6. **Cohérence de série** : réutiliser la même phrase de palette et la même description de scène pour la version 16:9 et d'éventuels formats stories (9:16 : demander un format vertical et regrouper les pictos en colonne).
7. **Droits** : ne pas importer d'image de marque tierce comme référence ; les logos de la marque viennent uniquement de `logo/`.
8. **Archiver** le prompt retenu et la version finale (nom de fichier, date, outil) pour pouvoir régénérer.

## 9. Ce qui n'existe pas (encore)

| Attendu | Réalité dans le dépôt |
|---|---|
| Charte graphique marketing (affiche, réseaux sociaux) | Seul existe le design system de l'**interface** (`docs/01_DESIGN_SYSTEM.md`) et l'aperçu social `docs/readme/social-preview.png` (1280×640) ; aucun gabarit d'affiche |
| Jeton « vert foncé » de marque | Absent : `success-deep` `#3A7D44` est un vert d'état (confirmations) |
| Visuel validé par le client | Aucun : les textes des pictos sont fournis par la demande, non relus par le propriétaire du produit dans le dépôt |
| Banque d'images des filières | Absente (`docs/manuel/captures/` ne contient que des captures d'écran de l'application) |
| Prompt testé | Aucun essai de génération n'a été fait pour écrire ce document |
