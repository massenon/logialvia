import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Ecran d'attente pour une route deja presente dans la navigation mais dont le
/// module n'est pas encore implemente.
///
/// Raison d'etre : `sidebar.js` expose 21 entrees. Les enregistrer sans cible
/// produirait des liens morts, formellement interdits (Doc E3 §5). Cet ecran
/// n'est **pas** une maquette : il n'affiche aucun KPI, aucun tableau, aucune
/// donnee simulee (Master Prompt §2.2/§2.3). Il indique seulement quel document
/// specifie l'ecran attendu, pour que l'etat d'avancement soit lisible.
class EcranAVenir extends StatelessWidget {
  const EcranAVenir({
    super.key,
    required this.titre,
    required this.documentSource,
  });

  final String titre;

  /// Ex. « Doc F5 — Module Stocks & Achats ».
  final String documentSource;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            border: Border.all(color: AppColors.outlineVariant),
            borderRadius: AppRadius.cardRadius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Symbols.construction,
                size: 32,
                color: AppColors.brandGold,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(titre, style: AppTypography.pageTitle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Cet écran n\'est pas encore implémenté.\nSpécification : $documentSource.',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
