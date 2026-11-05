# E4 — Spécification DataTable Complète

Pattern le plus répété visuellement sur les 31 écrans (Historique des Ventes, Gestion des Stocks, Fournisseurs, Journal Comptable, tableaux mensuels des fiches d'élevage...). Une seule implémentation générique, jamais recopiée par écran (Strict Avoid §5, §12).

---

## 1. Anatomie Complète (fidèle à la structure HTML source)

```
┌─────────────────────────────────────────────────────────┐
│ EN-TÊTE : [Recherche...] [Filtre ▾] [+ Ajouter]           │  ← DataTableHeader
├─────────────────────────────────────────────────────────┤
│ Colonne 1 │ Colonne 2 │ ... │ Actions                     │  ← En-tete colonnes (zebra)
├─────────────────────────────────────────────────────────┤
│ valeur    │ valeur    │ ... │ [✎] [🗑]                    │  ← Ligne (fond blanc)
│ valeur    │ valeur    │ ... │ [✎] [🗑]                    │  ← Ligne (fond zebra)
│           ...  (ou etat vide si 0 ligne)                   │
├─────────────────────────────────────────────────────────┤
│ Affichage de X à Y sur Z entrées      [‹] [1] [2] [3] [›]  │  ← DataTableFooter
└─────────────────────────────────────────────────────────┘
```

---

## 2. Widget Générique

```dart
class AppDataTable<T> extends StatefulWidget {
  const AppDataTable({
    super.key,
    required this.items,
    required this.columns,
    required this.cellBuilder,
    this.onSearch,
    this.filterOptions,
    this.onFilterChanged,
    this.onAdd,
    this.addLabel = 'Ajouter',
    this.rowsPerPage = 10,
    this.emptyStateMessage = 'Aucune donnée disponible.',
    this.onRowTap,
  });

  final List<T> items;
  final List<String> columns;
  final Widget Function(BuildContext, T item, int columnIndex) cellBuilder;
  final ValueChanged<String>? onSearch;
  final List<String>? filterOptions;
  final ValueChanged<String?>? onFilterChanged;
  final VoidCallback? onAdd;
  final String addLabel;
  final int rowsPerPage;
  final String emptyStateMessage;
  final void Function(T item)? onRowTap;

  @override
  State<AppDataTable<T>> createState() => _AppDataTableState<T>();
}

class _AppDataTableState<T> extends State<AppDataTable<T>> {
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final totalPages = (widget.items.length / widget.rowsPerPage).ceil().clamp(1, 999999);
    final start = (_currentPage - 1) * widget.rowsPerPage;
    final pageItems = widget.items.skip(start).take(widget.rowsPerPage).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadows.sm,
      ),
      child: Column(children: [
        _buildHeader(),
        if (widget.items.isEmpty) _buildEmptyState() else _buildTable(pageItems),
        _buildFooter(start, pageItems.length, totalPages),
      ]),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(children: [
        if (widget.onSearch != null)
          Expanded(child: TextField(
            decoration: const InputDecoration(
              isDense: true, prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Rechercher...',
              border: OutlineInputBorder(),
            ),
            onChanged: widget.onSearch,
          )),
        const SizedBox(width: AppSpacing.sm),
        if (widget.filterOptions != null)
          DropdownButton<String?>(
            hint: const Text('Filtrer'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Tous')),
              ...widget.filterOptions!.map((f) => DropdownMenuItem(value: f, child: Text(f))),
            ],
            onChanged: widget.onFilterChanged,
          ),
        const SizedBox(width: AppSpacing.sm),
        if (widget.onAdd != null)
          AppButton(label: widget.addLabel, icon: Icons.add_circle, onPressed: widget.onAdd),
      ]),
    );
  }

  Widget _buildTable(List<T> pageItems) {
    return Table(
      children: [
        TableRow(
          decoration: const BoxDecoration(color: AppColors.surfaceZebra),
          children: widget.columns.map((c) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Text(c.toUpperCase(), style: AppTypography.label),
          )).toList(),
        ),
        for (var i = 0; i < pageItems.length; i++)
          TableRow(
            decoration: BoxDecoration(color: i.isOdd ? AppColors.surfaceZebra : AppColors.surfaceCard),
            children: [
              for (var col = 0; col < widget.columns.length; col++)
                InkWell(
                  onTap: widget.onRowTap != null ? () => widget.onRowTap!(pageItems[i]) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    child: widget.cellBuilder(context, pageItems[i], col),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(children: [
        Icon(Icons.inbox_outlined, size: 48, color: AppColors.outline),
        const SizedBox(height: AppSpacing.sm),
        Text(widget.emptyStateMessage, style: const TextStyle(color: AppColors.outline)),
        if (widget.onAdd != null) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(label: widget.addLabel, icon: Icons.add_circle, onPressed: widget.onAdd),
        ],
      ]),
    );
  }

  Widget _buildFooter(int start, int count, int totalPages) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Affichage de ${count == 0 ? 0 : start + 1} à ${start + count} sur ${widget.items.length} entrées',
          style: const TextStyle(fontSize: 11, color: AppColors.outline)),
        Row(children: [
          IconButton(icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null),
          for (var p = 1; p <= totalPages; p++)
            InkWell(onTap: () => setState(() => _currentPage = p),
              child: Container(width: 28, height: 28, margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: p == _currentPage ? AppColors.brandNavy : Colors.transparent,
                  borderRadius: BorderRadius.circular(6)),
                alignment: Alignment.center,
                child: Text('$p', style: TextStyle(
                  color: p == _currentPage ? Colors.white : AppColors.outline, fontSize: 12)))),
          IconButton(icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null),
        ]),
      ]),
    );
  }
}
```

---

## 3. Colonne Actions — pattern standard

Toujours en dernière colonne, alignée à droite, avec `IconActionButton` (Doc E2) :

```dart
Row(mainAxisSize: MainAxisSize.min, children: [
  IconActionButton(icon: Icons.edit, tooltip: 'Modifier', color: AppColors.infoBlue,
    onPressed: () => _ouvrirModaleEdition(item)),
  IconActionButton(icon: Icons.delete, tooltip: 'Supprimer', color: AppColors.errorDeep,
    onPressed: () async {
      final confirme = await showDeleteWarningModal(context, itemName: item.name);
      if (confirme) viewModel.supprimer(item.id);
    }),
])
```

---

## 4. Offcanvas de Détail (pattern Historique des Ventes)

Certaines DataTables (Historique des Ventes) ouvrent un volet latéral au clic sur une ligne plutôt qu'une modale :

```dart
onRowTap: (vente) => OffcanvasPanel.show(context,
  title: 'Détail de la Vente',
  child: VenteDetailContent(vente: vente), // affiche lignes, total, bouton Imprimer (Doc E9)
),
```

---

## 5. Recherche & Filtre — comportement exact attendu

- La recherche filtre en direct (`onChanged`, pas de bouton "Rechercher" à cliquer) — fidèle au comportement JS `addEventListener('input', ...)` du prototype
- Le filtre par catégorie/statut est un menu déroulant unique combinable avec la recherche texte (les deux filtres s'appliquent simultanément, jamais l'un après réinitialisation de l'autre)
- Tout changement de filtre ou de recherche **réinitialise la pagination à la page 1** — comportement déjà implémenté côté JS (`current = 1; render();`), à répliquer strictement

---

## 6. Cas d'Usage par Écran (référence rapide)

| Écran | Colonnes | Recherche | Filtre | Actions par ligne |
|---|---|---|---|---|
| Historique des Ventes | Réf., Date, Client, Montant, Statut | Réf./Client | Statut | Clic → Offcanvas, bouton Annuler si non annulée |
| Gestion des Stocks | Désignation, Catégorie, Stock, Seuil, Valeur, Statut | — | Catégorie | Modifier, Supprimer |
| Fiches d'élevage (tableau 31 jours) | Date, Achat, Né, Vente, Morts, Dons, Effectif | — | — | Clic ligne → charge le jour dans le formulaire |
