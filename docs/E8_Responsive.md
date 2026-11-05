# E8 — Comportement Responsive — Breakpoints Web → Flutter

## 1. Table de Correspondance des Breakpoints

| Breakpoint Tailwind | Largeur | Équivalent Flutter (largeur de fenêtre desktop) |
|---|---|---|
| (défaut, mobile) | < 640px | `AppBreakpoints` — `MediaQuery.sizeOf(context).width < 640` |
| `sm:` | ≥ 640px | `AppBreakpoints.estSm(context)` |
| `md:` | ≥ 768px | `AppBreakpoints.estMd(context)` |
| `lg:` | ≥ 1024px | `AppBreakpoints.estLg(context)` |
| `xl:` | ≥ 1280px | `AppBreakpoints.estXl(context)` |

**⚠️ Corrigé — la version précédente de ce tableau indiquait `constraints.maxWidth`, en contradiction avec le §2 du même document qui prescrivait déjà `MediaQuery`.** C'est `MediaQuery` qui est correct : un breakpoint Tailwind est une *media query*, il porte sur la largeur de la **fenêtre**, pas sur celle du conteneur qui reçoit la classe.

**Bug réellement provoqué par cette contradiction** (module F2, corrigé) : le bandeau KPI du tableau de bord mesurait les contraintes de son `LayoutBuilder`. Sur une fenêtre de 1440 px, la zone de contenu ne fait que ~1100 px une fois la barre latérale (288 px) et les marges déduites — le seuil `xl` n'était donc jamais franchi et les 8 KPI s'affichaient en **2 colonnes × 4 rangées** au lieu des **4 colonnes × 2 rangées** du web.

**Règle** : `constraints.maxWidth` sert à *dimensionner* les éléments une fois le nombre de colonnes décidé ; il ne sert **jamais** à décider ce nombre.

**Contrainte Flutter Desktop** : la fenêtre a une taille minimale fixée (Doc 11/K3, `minimumSize: Size(1024, 700)`), donc les breakpoints mobile (`< 640px`) et `sm:` ne sont jamais réellement atteints en usage normal desktop. Ils restent implémentés pour cohérence de code et pour une éventuelle réutilisation future si une version tablette est envisagée — **ne pas les supprimer du code sous prétexte qu'ils semblent inutiles en desktop pur**.

---

## 2. Widget Utilitaire Central — `AppBreakpoints`

```dart
class AppBreakpoints {
  AppBreakpoints._();
  static const double sm = 640, md = 768, lg = 1024, xl = 1280;

  static bool isMd(BuildContext context) => MediaQuery.of(context).size.width >= md;
  static bool isLg(BuildContext context) => MediaQuery.of(context).size.width >= lg;
  static bool isXl(BuildContext context) => MediaQuery.of(context).size.width >= xl;
}
```

**Règle** : ne jamais dupliquer les seuils `768`/`1024`/`1280` en dur dans un écran — toujours passer par `AppBreakpoints`, cohérent avec Strict Avoid §12 (zéro duplication) et NFRS-MAINT-02.

---

## 3. Incohérence Corrigée à Ne Pas Réintroduire

**Rappel d'un bug réel déjà rencontré et corrigé** sur `suivi-reproduction.html` : la grille KPI utilisait `xl:grid-cols-4` (bascule à 1280px) alors que `gestion-stocks.html`, pour un composant visuellement identique, utilisait `md:grid-cols-4` (768px). Résultat : incohérence visuelle entre deux écrans du même système à la même largeur de fenêtre.

**Contrôle Flutter équivalent** : puisque `KpiGrid` (Doc E7) est un **composant partagé unique**, ce type d'incohérence est structurellement impossible côté Dart — tant qu'aucun écran ne réimplémente sa propre grille KPI locale avec un seuil différent. Vérification de non-régression : `grep -r "crossAxisCount" lib/` ne doit renvoyer d'occurrence que dans `KpiGrid` lui-même.

---

## 4. Comportement par Type de Composant

| Composant | Mobile (< 768px) | Desktop (≥ 768px) |
|---|---|---|
| Sidebar de navigation | Masquée, accessible via un bouton menu (`Drawer` Flutter) | Toujours visible, rétractable en icônes seules (`NavigationRail`) |
| Grille KPI | 2 colonnes, dans un accordéon repliable (Doc E7 §3) | 4 colonnes, toujours visible |
| DataTable | Cartes empilées verticalement (une "carte" par ligne, `data-label` affiché en préfixe de chaque valeur) | Tableau classique en colonnes |
| Formulaire de saisie journalière | Champs empilés verticalement | Grille 2-3 colonnes selon la densité de champs |
| Modale | Plein écran ou quasi (`maxWidth` proche de la largeur totale) | Largeur fixe centrée (`maxWidth: 480` typique, Doc E2) |

### DataTable Mobile — transformation "carte empilée"

Le HTML source utilise déjà ce pattern via `data-label` (attribut CSS `content: attr(data-label)` en mobile). Équivalent Flutter :

```dart
Widget _buildResponsiveRow(BuildContext context, T item) {
  if (AppBreakpoints.isMd(context)) return _buildTableRow(item); // Doc E4, comportement standard

  // Mobile : carte empilee, chaque valeur precedee de son libelle de colonne
  return Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.sm),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (var c = 0; c < columns.length; c++)
        Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            SizedBox(width: 100, child: Text(columns[c], style: AppTypography.label)),
            Expanded(child: cellBuilder(context, item, c)),
          ]))])));
}
```

---

## 5. Fenêtre Desktop — dimensionnement initial (rappel de Doc K3)

`size: Size(1440, 900)` par défaut au lancement — correspond au breakpoint `xl` du design, garantissant que l'utilisateur voit la mise en page desktop complète dès l'ouverture, sans avoir à agrandir manuellement la fenêtre pour "débloquer" la grille à 4 colonnes.
