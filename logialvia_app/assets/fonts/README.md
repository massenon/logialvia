# Polices Roboto

Deux jeux de fichiers, pour deux usages qui n'ont pas les mêmes contraintes.

## Interface — fonte **variable**

| Fichier | Rôle |
|---|---|
| `Roboto-Variable.ttf` | Romain, axe `wght` 100–900 |
| `Roboto-Italic-Variable.ttf` | Italique, même axe |
| `LICENSE-Roboto-variable-OFL-1.1.txt` | SIL Open Font License 1.1 |

Déclarés dans `pubspec.yaml` sous `fonts:` pour la famille `Roboto`.

**Pourquoi la variable et non la série statique.** Le moteur Flutter embarque
déjà Roboto, mais en **statique** : 100 / 300 / 400 / 500 / 700 / 900. Il n'y a
ni 600 ni 800. Or l'application pose `FontWeight.w600` 22 fois et `w800`
23 fois, et le prototype web `font-semibold` 315 fois et `font-extrabold`
127 fois — que Google Fonts sert justement avec la fonte variable. Ces deux
graisses étaient donc rendues par la voisine la plus proche : c'est l'écart de
rendu que Doc K3 §4 signalait, et la raison pour laquelle le volet « pixel » de
la recette Doc K2 restait impossible.

`test/core/police_roboto_test.dart` le vérifie en mesurant de vraies largeurs de
texte : 600 doit différer **et** de 500 **et** de 700, 800 de 700 et de 900.
Déclarer une fonte variable ne prouve rien tant que personne n'a vérifié que
Flutter applique l'axe `wght` — s'il ne le faisait pas, tout le texte tomberait
sur l'instance par défaut (400), silencieusement.

## Export PDF — série **statique**

| Fichier | Rôle |
|---|---|
| `Roboto-Regular.ttf` | Corps de texte des documents |
| `Roboto-Bold.ttf` | Titres, en-têtes de tableau, totaux |
| `LICENSE-Roboto-statique-Apache-2.0.txt` | Apache License 2.0 |

Déclarés sous `assets:`, chargés par `GenerateurPdf`.

**Pourquoi pas la fonte variable ici.** Le paquet `pdf` embarque les contours
`glyf` tels quels : d'une fonte variable il ne tirerait que son **instance par
défaut** (400). Le gras des titres serait alors identique au corps de texte, et
la hiérarchie du document disparaîtrait. Deux vraies fontes statiques évitent le
pari.

Ces deux fichiers viennent du SDK Flutter
(`bin/cache/artifacts/material_fonts/`) — ce sont ceux que le moteur utilisait
déjà, sous Apache 2.0. D'où deux licences dans ce dossier : la série statique
est antérieure au passage de Roboto sous OFL.

**Ce que cela corrige.** L'export utilisait Helvetica, police de base PDF qui ne
couvre que Latin-1 : « — », « œ », « ≥ », « ’ », « € », « № », « … » et « • »
laissaient un **blanc** dans des documents officiels signés. Roboto les rend
tous. `GenerateurPdf` lit la table de caractères réellement embarquée
(`TtfParser.charToGlyphIndexMap`) et ne substitue que ce qui manque vraiment —
aujourd'hui les flèches `→` `←`, les exposants `ᵉ ʳ ᵐ`, l'espace fine
insécable et `✓`, que Roboto ne contient pas.
