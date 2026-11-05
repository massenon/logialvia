# 01 — Design System LogiALVIA → Flutter

Source unique de vérité : `/home/claude/logialvia_prototype/assets/js/tailwind-config.js` (lu intégralement, aucune valeur devinée ou approximée).

---

## 1. Palette de Couleurs

| Token web (Tailwind) | Hex | Usage réel dans le prototype | Constante Dart proposée |
|---|---|---|---|
| `brand-navy` | `#1F3864` | Couleur primaire — boutons d'action, en-têtes, texte de marque | `AppColors.brandNavy` |
| `brand-navy-dark` | `#152847` | États hover/active des éléments navy | `AppColors.brandNavyDark` |
| `brand-gold` | `#B58B2A` | Accent secondaire — avicole, volaille, terre | `AppColors.brandGold` |
| `brand-gold-light` | `#D4A94D` | États hover/surbrillance des éléments gold | `AppColors.brandGoldLight` |
| `surface-bg` | `#F2F2F2` | Fond général de l'application | `AppColors.surfaceBg` |
| `surface-card` | `#FFFFFF` | Fond des cartes, modales, tableaux | `AppColors.surfaceCard` |
| `surface-zebra` | `#F7F7F8` | Lignes alternées des tableaux (zebra striping) | `AppColors.surfaceZebra` |
| `outline-variant` | `#D8DCE3` | Bordures fines (1px), séparateurs | `AppColors.outlineVariant` |
| `outline` | `#6B7280` | Texte secondaire, icônes inactives | `AppColors.outline` |
| `on-surface` | `#1A1D23` | Texte principal par défaut | `AppColors.onSurface` |
| `error-deep` | `#B33A3A` | Alertes stock critique, statuts sanitaires, suppression | `AppColors.errorDeep` |
| `error-container` | `#FBE3E3` | Fond des badges/bannières d'erreur | `AppColors.errorContainer` |
| `success-deep` | `#3A7D44` | Confirmations, statuts "OK"/"Payée" | `AppColors.successDeep` |
| `success-container` | `#E1F0E3` | Fond des badges/bannières de succès | `AppColors.successContainer` |
| `info-blue` | `#2563EB` | Informations neutres (ex. mode de paiement Mobile Money) | `AppColors.infoBlue` |

### Implémentation Dart (`lib/core/theme/app_colors.dart`)

```dart
import 'package:flutter/material.dart';

/// Couleurs officielles LogiALVIA — CDCT §10.4.
/// Ne jamais approximer ces valeurs : elles proviennent de
/// assets/js/tailwind-config.js du prototype de reference.
class AppColors {
  AppColors._();

  static const Color brandNavy = Color(0xFF1F3864);
  static const Color brandNavyDark = Color(0xFF152847);
  static const Color brandGold = Color(0xFFB58B2A);
  static const Color brandGoldLight = Color(0xFFD4A94D);

  static const Color surfaceBg = Color(0xFFF2F2F2);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceZebra = Color(0xFFF7F7F8);

  static const Color outlineVariant = Color(0xFFD8DCE3);
  static const Color outline = Color(0xFF6B7280);
  static const Color onSurface = Color(0xFF1A1D23);

  static const Color errorDeep = Color(0xFFB33A3A);
  static const Color errorContainer = Color(0xFFFBE3E3);
  static const Color successDeep = Color(0xFF3A7D44);
  static const Color successContainer = Color(0xFFE1F0E3);
  static const Color infoBlue = Color(0xFF2563EB);
}
```

---

## 2. Typographie

Le prototype utilise **Roboto** (`fontFamily.sans: ['Roboto', 'Calibri', 'ui-sans-serif', 'system-ui']`).

### Poids réellement observés dans le HTML
En grep systématique sur les 31 fichiers, les classes Tailwind de poids utilisées sont : `font-semibold` (600), `font-bold` (700), `font-extrabold` (800), et le poids normal (400) par défaut. Aucun `font-medium` (500) ni `font-light` (300) n'est utilisé — **ne pas en ajouter arbitrairement**.

### Échelle de taille observée (classes Tailwind → px)
| Classe Tailwind | Taille | Usage principal |
|---|---|---|
| `text-[9px]` à `text-[11px]` | 9–11px | Badges, labels de champ, notes |
| `text-xs` | 12px | Corps de texte des tableaux, boutons |
| `text-sm` | 14px | Champs de formulaire, texte de modale |
| `text-base` | 16px | Titres de section |
| `text-lg` | 18px | Titres de modale |
| `text-xl` / `text-2xl` | 20–24px | Titres de page, valeurs KPI |

### Implémentation Dart (`lib/core/theme/app_typography.dart`)

```dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Roboto';

  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontFamily, fontSize: 22, fontWeight: FontWeight.w800,
    color: AppColors.onSurface,
  );
  static const TextStyle modalTitle = TextStyle(
    fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w700,
    color: AppColors.brandNavy,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
  );
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily, fontSize: 14, color: AppColors.onSurface,
  );
  static const TextStyle tableCell = TextStyle(
    fontFamily: fontFamily, fontSize: 12, color: AppColors.onSurface,
  );
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily, fontSize: 10, fontWeight: FontWeight.w700,
    color: AppColors.brandNavy, letterSpacing: 0.4,
  );
  static const TextStyle kpiValue = TextStyle(
    fontFamily: fontFamily, fontSize: 24, fontWeight: FontWeight.w800,
    color: AppColors.onSurface,
  );
}
```

### ⚠️ `text-xs` vaut 13,6 px, et non 12

`assets/css/common.css` l.44 pose :

```css
.text-xs { font-size: 0.85rem !important; }
```

La racine valant 16 px, **`text-xs` = 13,6 px**, et le `!important` bat la
règle utilitaire de Tailwind. C'est la classe la plus employée du prototype :
**1381 emplois**.

**Ce fichier est chargé par 35 des 41 pages** — toutes les pages applicatives ;
les six exceptions sont les maquettes `m10-*`, remplacées depuis par les écrans
comptables réels. La surcharge est donc **globale**. Le portage l'avait lue
comme une particularité des trois écrans d'authentification, qui se contentent
de la redéclarer en ligne : 13,6 px au Splash, à l'Accueil et à la Connexion,
**12 px partout ailleurs**. Tout le reste de l'application était rendu 12 %
trop petit.

### Tableaux : les cellules sont plus grandes que les en-têtes

Mesure faite sur les 41 pages par `outils/audit_typographie.py`, qui ne compte
que les tailles posées **explicitement** sur l'élément et refuse de résoudre
l'héritage — beaucoup de lignes sont assemblées dans des chaînes JavaScript où
l'arbre n'est pas balancé, et une mesure fausse serait pire que pas de mesure.

| Élément | Classe dominante | Taille | Relevé |
|---|---|---|---|
| `<th>` | `text-[12px]` | 12 px | 202 / 205 |
| `<td>` | `text-xs` | **13,6 px** | 327 / 338 |

Le portage avait égalisé les deux à 12 px, ce qui aplatit la hiérarchie de
**toutes** les tables — et cet ERP est fait de tables. `AppTypography.tableCell`
et `AppTypography.tableHeader` portent désormais les deux valeurs, et les styles
de base des sept modules (`texteCompta`, `texteAppro`, `texteCompte`,
`texteRapport`, et les `_texte` locaux) sont alignés sur `AppTypography.textXs`.
`test/core/echelle_typographique_test.dart` verrouille l'échelle, l'espacement
et les 15 couleurs contre `tailwind-config.js`.

### L'héritage résolu d'un niveau, et l'écart qu'il a révélé

27 tables du prototype posent `text-xs` sur la balise **`<table>`** plutôt que
sur chaque cellule — les cinq fiches d'élevage, `dashboard`,
`etats-financiers` et `bilan-entreprise` en font partie. En résolvant ce seul
niveau, **433 des 444 cellules mesurables sont à 13,6 px** (97,5 %). Les
tableaux mensuel et hebdomadaire des fiches, ainsi que le suivi d'infirmerie,
sont donc alignés sur cette valeur, mesure à l'appui.

**ÉCART_DÉLIBÉRÉ — `cycle-couveuse.html`.** Cette page ne pose **aucune** taille
sur ses cellules : ni sur les `<td>`, ni sur son `<table class="w-full rtable">`,
ni sur aucun ancêtre. Elles héritent donc des **16 px** de la racine, alors que
ses propres en-têtes sont en `text-[12px]`. Reproduire ces 16 px donnerait, sur
ce seul écran, des cellules plus grandes que le corps de texte courant et que
toutes les autres tables de l'application. C'est un oubli du prototype, pas une
intention : la table est alignée sur les autres, et l'écart est commenté dans le
code. `cloture-exercice` et `comptabilite-analytique` sont dans le même cas.

### La famille des 12 px capitales — deux styles, pas un

Le prototype pose trois formes très répandues à 12 px en capitales grasses :

| Forme | Couleur | Relevé | Jeton |
|---|---|---|---|
| `<label class="block text-[12px] text-brand-navy font-bold uppercase mb-xs">` | `brand-navy` | **147** | `AppTypography.label` |
| `<th class="… text-[12px] text-outline font-bold uppercase">` | `outline` | **196** | `AppTypography.tableHeader` |
| Intitulé de KPI, mêmes classes | `outline` | **86** | `AppTypography.caption` |

Les deux dernières sont **le même style** : `tableHeader` est un alias de
`caption`, deux définitions jumelles finissant toujours par diverger. Seule la
**couleur** sépare le libellé de champ de l'intitulé.

⚠️ **Deux corrections sur `AppTypography.label`.** Le portage posait **10 px**
— les libellés étaient 17 % trop petits — et ajoutait un `letterSpacing: 0.4`
que le prototype **ne demande nulle part** : `uppercase` n'ajoute aucun crénage,
et les classes `tracking-*` n'apparaissent que sur une poignée d'éléments
décoratifs des écrans d'accueil, jamais sur un libellé de champ. Un jeton
touché, 82 emplois corrigés.

**376 cellules restent à lire à la main**, ainsi que les éléments hors tableau
— formulaires, pastilles, panneaux — dont 103 emplois de 12 px subsistent côté
Dart. La correspondance élément Dart ↔ élément HTML n'y est pas mécanique :
elle se vérifie écran par écran, l'outil à côté.

**Police locale — fournie.** Roboto est embarquée en asset (`assets/fonts/`), jamais chargée depuis Google Fonts : l'exploitation n'a pas de connexion garantie. ⚠️ **En fonte variable, et non en série statique** : la série statique de Roboto — celle qu'embarque le moteur Flutter — va 100/300/400/500/700/900 et n'a **ni 600 ni 800**, alors que l'interface pose `FontWeight.w600` 22 fois et `w800` 23 fois, et le prototype `font-semibold` 315 fois et `font-extrabold` 127 fois. Ces deux graisses étaient donc rendues par la voisine la plus proche. La fonte variable (axe `wght` 100–900, celle-là même que Google Fonts sert au prototype) les rend exactement, ce qu'un test vérifie en mesurant de vraies largeurs de texte. L'export PDF utilise en revanche la série **statique** Regular/Bold : le paquet `pdf` ne tirerait d'une variable que son instance par défaut, et le gras des titres disparaîtrait. Voir `assets/fonts/README.md`.

---

## 3. Échelle d'Espacement

Directement issue de `tailwind-config.js` :

| Token | Valeur | Constante Dart |
|---|---|---|
| `xs` | 4px | `AppSpacing.xs` |
| `sm` | 8px | `AppSpacing.sm` |
| `md` | 16px | `AppSpacing.md` |
| `lg` | 24px | `AppSpacing.lg` |
| `xl` | 32px | `AppSpacing.xl` |

```dart
class AppSpacing {
  AppSpacing._();
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
}
```

---

## 4. Rayons de Bordure et Ombres

Observés dans le HTML (classes `rounded-lg`, `rounded-full`, `shadow-sm`, `shadow-xl`) :

| Classe Tailwind | Valeur | Usage |
|---|---|---|
| `rounded-lg` | 8px | Cartes, modales, champs de formulaire, boutons rectangulaires |
| `rounded-full` | 9999px (pilule) | Badges de statut, boutons d'action principale |
| `shadow-sm` | Ombre légère | Cartes au repos, en-tête |
| `shadow-md` | Ombre moyenne | Cartes au survol |
| `shadow-xl` | Ombre prononcée | Modales |

```dart
class AppRadius {
  AppRadius._();
  static const double card = 8.0;
  static BorderRadius get cardRadius => BorderRadius.circular(card);
  static BorderRadius get pill => BorderRadius.circular(9999);
}

class AppShadows {
  AppShadows._();
  static List<BoxShadow> get sm => [
    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1)),
  ];
  static List<BoxShadow> get xl => [
    BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8)),
  ];
}
```

---

## 5. Stratégie d'Icônes — décision requise

Le prototype utilise **Material Symbols Outlined** (police web Google), avec des dizaines d'icônes différentes (`edit`, `delete`, `close`, `search`, `add_circle`, `point_of_sale`, `inventory_2`, `pets`, `egg`, `cruelty_free`, `set_meal`, etc.).

**Deux options** :

| Option | Avantage | Inconvénient |
|---|---|---|
| A. Package `material_symbols_icons` | Correspondance quasi 1:1 avec le web, noms d'icônes identiques | Dépendance externe supplémentaire, package à télécharger depuis pub.dev |
| B. `Icons` natif Flutter + table de correspondance manuelle | Zéro dépendance externe | Certaines icônes n'ont pas d'équivalent Material Icons classique exact, risque d'écarts visuels mineurs |

### ✅ DÉCISION ACTÉE — Option A

**`material_symbols_icons` est retenu** (confirmé explicitement avant l'implémentation du module F1). Ajouté au `pubspec.yaml`, version résolue : `4.2960.0`.

Usage :
```dart
import 'package:material_symbols_icons/symbols.dart';

// `Symbols.<nom>` = style Outlined, exactement celui du prototype.
// Les styles Rounded/Sharp portent un suffixe (`Symbols.egg_rounded`) —
// ne jamais les utiliser ici : le prototype charge MaterialSymbolsOutlined.
Icon(Symbols.egg, size: 44, color: Colors.white)
```

Le nom de l'icône Dart est **identique** au nom web : `<span class="material-symbols-outlined">point_of_sale</span>` → `Symbols.point_of_sale`. Aucune table de correspondance manuelle n'est donc nécessaire — la conversion est mécanique et vérifiable icône par icône.

Les réglages par défaut du package (`FILL 0`, `wght 400`, `GRAD 0`, `opsz 24`) correspondent exactement à `font-variation-settings:'FILL' 0,'wght' 400,'GRAD' 0,'opsz' 24` déclaré sur les 31 pages du prototype — aucun paramétrage supplémentaire n'est requis sur les `Icon()`.

**15 icônes déjà vérifiées comme existantes** dans le package (module F1) : `egg`, `inventory_2`, `point_of_sale`, `campaign`, `translate`, `person`, `lock`, `visibility`, `visibility_off`, `lock_open`, `lock_clock`, `receipt`, `vaccines`, `account_balance`, `close`.

---

## 6. Densité & Dimensions de Composants

Observées dans le HTML :

| Composant | Hauteur | Classe Tailwind source |
|---|---|---|
| Champ de formulaire (`input`, `select`) | 40px | `h-10` |
| Bouton standard | 40px | `h-10` |
| En-tête de page (topbar) | 64px | `h-16` |
| Ligne de tableau | ~36–40px (padding `py-sm` = 8px + contenu) | `px-md py-sm` |
