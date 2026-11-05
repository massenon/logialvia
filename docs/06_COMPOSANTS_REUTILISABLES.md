# 06 — Bibliothèque de Composants Réutilisables

Chaque composant listé ici est utilisé sur **plusieurs** des 31 écrans. Règle absolue de qualité de code déjà posée dans Doc 02 : **un composant = un fichier dans `core/widgets/`, jamais recopié dans un écran**. Si un écran a besoin d'une variante, elle passe par un paramètre du composant existant — pas par une copie modifiée.

---

## 1. `AppButton` — boutons d'action

Le prototype utilise 3 styles de bouton visuellement distincts, observés de façon cohérente sur les 31 fichiers :

| Variante | Classes web source | Usage |
|---|---|---|
| `primary` | `bg-brand-navy text-white hover:bg-brand-navy-dark` | Action principale (Enregistrer, Encaisser, Valider) |
| `outline` | `border border-outline-variant text-outline hover:bg-surface-zebra` | Action secondaire (Annuler, Fermer) |
| `danger` | `bg-error-deep text-white hover:bg-red-800` | Confirmation de suppression/annulation |

```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

enum AppButtonVariant { primary, outline, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.fullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final style = switch (variant) {
      AppButtonVariant.primary => ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandNavy, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius)),
      AppButtonVariant.outline => OutlinedButton.styleFrom(
          foregroundColor: AppColors.outline,
          side: const BorderSide(color: AppColors.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius)),
      AppButtonVariant.danger => ElevatedButton.styleFrom(
          backgroundColor: AppColors.errorDeep, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius)),
    };
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
      Text(label),
    ]);
    final button = variant == AppButtonVariant.outline
        ? OutlinedButton(onPressed: onPressed, style: style, child: child)
        : ElevatedButton(onPressed: onPressed, style: style, child: child);
    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
```

---

## 2. `AppModal` — modale CRUD standard

Pattern observé identiquement sur les 31 écrans : conteneur blanc centré, voile sombre semi-transparent, en-tête (titre + bouton fermer ×), corps, pied avec `Annuler`/`Enregistrer`.

```dart
class AppModal extends StatelessWidget {
  const AppModal({
    super.key, required this.title, required this.child,
    this.onClose, this.actions, this.maxWidth = 480,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final List<Widget>? actions;
  final double maxWidth;

  static Future<T?> show<T>(BuildContext context, {
    required String title, required Widget child, List<Widget>? actions,
  }) {
    return showDialog<T>(
      context: context, barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
        child: AppModal(title: title, actions: actions,
          onClose: () => Navigator.of(ctx).pop(), child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: AppTypography.modalTitle)),
            IconButton(icon: const Icon(Icons.close), onPressed: onClose,
              tooltip: 'Fermer'), // aria-label equivalent — accessibilite
          ]),
          const SizedBox(height: AppSpacing.md),
          child,
          if (actions != null) ...[
            const Divider(height: AppSpacing.lg),
            Row(mainAxisAlignment: MainAxisAlignment.end,
              children: actions!.map((a) => Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm), child: a)).toList()),
          ],
        ]),
      ),
    );
  }
}
```

### Modale de Suppression avec Avertissement (pattern spécifique, répété sur `gestion-stocks`, `suivi-reproduction`, etc.)

```dart
Future<bool> showDeleteWarningModal(BuildContext context, {required String itemName}) async {
  final result = await AppModal.show<bool>(context,
    title: 'Confirmer la Suppression ?',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.warning_rounded, color: AppColors.errorDeep, size: 48),
      const SizedBox(height: AppSpacing.md),
      Text('Vous êtes sur le point de supprimer $itemName.'),
      Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(color: AppColors.errorContainer, borderRadius: AppRadius.cardRadius),
        child: const Text('Cette action est irréversible.', style: TextStyle(color: AppColors.errorDeep)),
      ),
    ]),
    actions: [
      AppButton(label: 'Annuler', variant: AppButtonVariant.outline, onPressed: () => Navigator.pop(context, false)),
      AppButton(label: 'Oui, Supprimer', variant: AppButtonVariant.danger, onPressed: () => Navigator.pop(context, true)),
    ],
  );
  return result ?? false;
}
```

---

## 3. `KpiCard` — carte indicateur, y compris état "vide"

**Exigence explicite** : même quand la valeur d'un KPI est nulle/vide, la carte doit toujours afficher son **libellé** et un texte — jamais une carte visuellement blanche/vide.

```dart
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key, required this.label, required this.value,
    this.accentColor = AppColors.infoBlue, this.icon,
  });

  final String label;
  final String value; // toujours une chaine — ex: "0", "0 FCFA", "—" si non applicable
  final Color accentColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadows.sm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: 4, width: 32, color: accentColor), // bordure gauche coloree du web
        const SizedBox(height: AppSpacing.xs),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label.toUpperCase(), style: AppTypography.label),
          if (icon != null) Icon(icon, size: 18, color: accentColor),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: AppTypography.kpiValue), // JAMAIS vide — "0" au minimum
      ]),
    );
  }
}
```

---

## 4. `StatusBadge` — badge de statut en pilule

Observé sous des dizaines de variantes de couleur/texte (`Payée`, `Avance`, `Annulée`, `OK`, `Critique`, `Mère Allaitante`, `Truie Gestante`...) mais toujours la même forme visuelle.

```dart
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.tone});
  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      StatusTone.success => (AppColors.successContainer, AppColors.successDeep),
      StatusTone.error => (AppColors.errorContainer, AppColors.errorDeep),
      StatusTone.info => (AppColors.infoBlue.withOpacity(0.1), AppColors.infoBlue),
      StatusTone.neutral => (AppColors.outlineVariant.withOpacity(0.3), AppColors.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pill),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

enum StatusTone { success, error, info, neutral }
```

---

## 5. `AppToast` — notification d'action (équivalent `showToast`)

```dart
enum ToastType { success, error, warning }

void showAppToast(BuildContext context, String message, {ToastType type = ToastType.success}) {
  final (bg, icon) = switch (type) {
    ToastType.success => (AppColors.successDeep, Icons.check_circle),
    ToastType.error => (AppColors.errorDeep, Icons.error),
    ToastType.warning => (AppColors.brandGold, Icons.warning),
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    backgroundColor: bg, behavior: SnackBarBehavior.floating,
    duration: const Duration(milliseconds: 3500),
    content: Row(children: [Icon(icon, color: Colors.white, size: 20),
      const SizedBox(width: 8), Expanded(child: Text(message, style: const TextStyle(color: Colors.white)))]),
  ));
}
```

---

## 6. `OffcanvasPanel` — volet latéral de détail (pattern Historique des Ventes)

```dart
class OffcanvasPanel extends StatelessWidget {
  const OffcanvasPanel({super.key, required this.title, required this.child, required this.onClose});
  final String title;
  final Widget child;
  final VoidCallback onClose;

  static Future<T?> show<T>(BuildContext context, {required String title, required Widget child}) {
    return showGeneralDialog<T>(
      context: context, barrierColor: Colors.black.withOpacity(0.4),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          child: SizedBox(width: 420, height: double.infinity,
            child: OffcanvasPanel(title: title, onClose: () => Navigator.pop(ctx), child: child)),
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(anim), child: child),
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.outlineVariant))),
        child: Row(children: [Expanded(child: Text(title, style: AppTypography.modalTitle)),
          IconButton(icon: const Icon(Icons.close), onPressed: onClose)])),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(AppSpacing.lg), child: child)),
    ]);
  }
}
```

---

## 7. `IconActionButton` — boutons Modifier/Supprimer des DataTables

```dart
class IconActionButton extends StatelessWidget {
  const IconActionButton({
    super.key, required this.icon, required this.onPressed,
    required this.tooltip, this.color = AppColors.infoBlue,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16, color: color),
      onPressed: onPressed, tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
    );
  }
}

// Usage type : IconActionButton(icon: Icons.edit, color: AppColors.infoBlue, tooltip: 'Modifier', onPressed: ...)
//              IconActionButton(icon: Icons.delete, color: AppColors.errorDeep, tooltip: 'Supprimer', onPressed: ...)
```

---

## 8. `AppFormField` — champ de formulaire avec validation

```dart
class AppFormField extends StatelessWidget {
  const AppFormField({
    super.key, required this.label, required this.controller,
    this.required = false, this.errorText, this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final bool required;
  final String? errorText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${label.toUpperCase()}${required ? ' *' : ''}', style: AppTypography.label),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: controller, keyboardType: keyboardType,
        decoration: InputDecoration(
          isDense: true, filled: true, fillColor: AppColors.surfaceCard,
          border: OutlineInputBorder(borderRadius: AppRadius.cardRadius,
            borderSide: const BorderSide(color: AppColors.outlineVariant)),
          errorText: errorText, // equivalent .invalid-feedback du web
        ),
      ),
    ]);
  }
}
```

---

## Récapitulatif — mapping web → widget

| Pattern HTML/Tailwind observé | Widget Flutter |
|---|---|
| `<button class="bg-brand-navy...">` | `AppButton(variant: primary)` |
| `<div id="modal-...">` | `AppModal.show()` |
| Modale de suppression avec icône warning | `showDeleteWarningModal()` |
| Carte `border-l-4 border-l-*` avec valeur | `KpiCard` |
| `<span class="rounded-full ...">Statut</span>` | `StatusBadge` |
| `showToastGeneric()` / `showToast()` | `showAppToast()` |
| `#hist-offcanvas` (volet latéral coulissant) | `OffcanvasPanel.show()` |
| Boutons crayon/poubelle dans `<td data-label="Actions">` | `IconActionButton` |
| `<label>` + `<input>` + `.invalid-feedback` | `AppFormField` |
