import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Modale CRUD standard — Doc E2 §2.
/// Conteneur blanc centre, voile sombre, en-tete (titre + bouton fermer),
/// corps, pied optionnel.
class AppModal extends StatelessWidget {
  const AppModal({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.actions,
    this.maxWidth = 480,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final List<Widget>? actions;
  final double maxWidth;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget child,
    List<Widget>? actions,
    double maxWidth = 480,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
        child: AppModal(
          title: title,
          actions: actions,
          maxWidth: maxWidth,
          onClose: () => Navigator.of(ctx).pop(),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: AppTypography.modalTitle)),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.outline),
                  onPressed: onClose,
                  tooltip: 'Fermer',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Le corps defile quand il depasse la hauteur disponible.
            //
            // Sans cela, une modale un peu longue -- le rappel de prophylaxie
            // avec ses echeances, la liste des stocks critiques -- debordait
            // par le bas : le contenu existait mais devenait inatteignable, et
            // les boutons d'action disparaissaient avec lui.
            Flexible(child: SingleChildScrollView(child: child)),
            if (actions != null) ...[
              const Divider(height: AppSpacing.lg),
              // `Wrap` et non `Row` : la modale est large de 560 px au plus,
              // et deux boutons a libelle explicite -- « Plus tard » et
              // « Ouvrir la Gestion des Stocks » -- n'y tiennent pas cote a
              // cote. Une `Row` debordait de 68 px, en silence a l'ecran et en
              // rouge dans les tests. Le passage a la ligne ne change rien
              // quand la place suffit.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: actions!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
