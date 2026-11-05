# E7 — Dashboards & KPI — Spécification Complète

## 1. Règle Non-Négociable — Affichage même à Vide

**Exigence explicitement posée** : un KPI dont la valeur est nulle, zéro, ou non encore calculable DOIT toujours afficher son libellé et un texte de valeur (`"0"`, `"0 FCFA"`, `"—"` si réellement non applicable) — **jamais une carte visuellement blanche ou tronquée**. Voir `KpiCard` (Doc E2 section 3), déjà conçu pour respecter cette règle structurellement (le paramètre `value` est de type `String`, non-nullable).

```dart
// ✅ CORRECT — meme si aucune vente aujourd'hui
KpiCard(label: 'Ventes du Jour', value: '0 FCFA', accentColor: AppColors.infoBlue)

// ❌ INTERDIT — ne jamais conditionner l'affichage de la carte elle-meme
if (ventesDuJour > 0) KpiCard(...)  // la carte doit TOUJOURS etre presente
```

---

## 2. Grille KPI — comportement responsive (référence croisée Doc E8)

**⚠️ Corrigé après lecture du HTML réel** : `dashboard.html` l.134 utilise `grid-cols-2 xl:grid-cols-4` — le basculement à 4 colonnes se fait au breakpoint **`xl` (1280 px)**, pas `md` (768 px). Le code ci-dessous conserve la structure mais le seuil réel est 1280.

Pattern : `grid-cols-2` en dessous de 1280 px, 4 colonnes au-delà.

```dart
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.cards});
  final List<KpiCard> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 768 ? 4 : 2;
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: AppSpacing.md, mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 1.6,
        children: cards,
      );
    });
  }
}
```

---

## 3. Panneau KPI Rétractable (mobile) — accordéon

Sur mobile (< 768px), le panneau KPI est présenté comme un accordéon repliable par défaut, pour libérer l'espace vertical — pattern déjà observé et corrigé (ajout `aria-expanded`) lors de l'audit `suivi-reproduction.html`.

```dart
class KpiAccordionPanel extends StatefulWidget {
  const KpiAccordionPanel({super.key, required this.cards});
  final List<KpiCard> cards;

  @override
  State<KpiAccordionPanel> createState() => _KpiAccordionPanelState();
}

class _KpiAccordionPanelState extends State<KpiAccordionPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 768) return KpiGrid(cards: widget.cards); // desktop: toujours visible

      return Column(children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Semantics(
            button: true, expanded: _expanded, // equivalent aria-expanded
            child: Container(padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(color: AppColors.surfaceCard, border: Border.all(color: AppColors.outlineVariant)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Indicateurs (Replier / Déplier)', style: AppTypography.label),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ])),
          ),
        ),
        if (_expanded) KpiGrid(cards: widget.cards),
      ]);
    });
  }
}
```

---

## 4. Bordure Colorée Sémantique (gauche, 4px)

Chaque KPI a une couleur d'accent sémantique, fidèle au prototype (`border-l-4 border-l-*`) :

| Type d'indicateur | Couleur | Constante |
|---|---|---|
| Information neutre (effectifs, comptages) | Bleu | `AppColors.infoBlue` |
| Alerte / à traiter (échéances dues, seuils) | Or | `AppColors.brandGold` |
| Positif / confirmé (ventes validées, éclosions réussies) | Vert | `AppColors.successDeep` |
| Négatif / critique (mortalité, pertes) | Rouge | `AppColors.errorDeep` |

---

## 5. Graphique d'Activité (Dashboard Principal — CA vs Dépenses)

Le prototype trace un graphique en aire/ligne sur 6 mois. Package recommandé : `fl_chart` (à ajouter à `pubspec.yaml`, Doc K3).

```dart
LineChart(LineChartData(
  gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 50000),
  titlesData: FlTitlesData(/* mois en abscisse, FCFA en ordonnee */),
  lineBarsData: [
    LineChartBarData(spots: caSpots, color: AppColors.brandNavy, barWidth: 2),
    LineChartBarData(spots: depensesSpots, color: AppColors.errorDeep, barWidth: 2),
  ],
))
```

---

## 6. Fil d'Activité Chronologique (Timeline)

Section "Activités du Jour" des dashboards — liste chronologique des dernières saisies système, tous modules confondus.

### ✅ TRANCHÉ — `AUDIT_LOGS` plutôt qu'une table `JournalActivite` dédiée

La version précédente signalait qu'une table transversale `JournalActivite` manquait au modèle D1 et laissait le point ouvert. **Décision prise à l'implémentation de Doc F2** : le fil d'activité lit `AUDIT_LOGS` (Doc D1, Doc I3 §6), qui porte déjà exactement l'information nécessaire — `horodatage`, `utilisateurId`, `action`, `entiteConcernee`, `entiteId`.

Créer une seconde table dédiée à l'affichage imposerait une écriture double à chaque action métier et deux sources de vérité à maintenir cohérentes (Strict Avoid §12). La liste des valeurs autorisées de `AUDIT_LOGS.action` devra en revanche s'élargir au fil des modules (aujourd'hui : suppression, modification, clôture, déclôture, connexion).

**Règle d'affichage** : une journée sans activité affiche un texte explicite (« Aucune activité enregistrée aujourd'hui. »), jamais un panneau blanc muet.

---

## 7. Structure Générale d'un Écran Dashboard

Fidèle à l'ordre de sections déjà observé et devant être répliqué à l'identique (Master Prompt) :

```
1. KpiAccordionPanel / KpiGrid (indicateurs strategiques)
2. Centre de Pilotage : graphique (8/12) + panneau d'alertes (4/12)
3. Cartes de recensement par filiere (Elevage uniquement)
4. Fil d'activite chronologique
5. Tableau Top Produits / Top Ventes
```
