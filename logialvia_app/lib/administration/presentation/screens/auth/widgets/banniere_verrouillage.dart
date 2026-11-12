import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_typography.dart';

/// Banniere `#lock-banner` — login.html l.77-80.
/// Affichee apres 5 echecs consecutifs, avec le compte a rebours du deblocage.
class BanniereVerrouillage extends StatelessWidget {
  const BanniereVerrouillage({super.key, required this.libelleCompteARebours});

  final String libelleCompteARebours;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: AppTypography.textXs,
      color: AppColors.errorDeep,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16, // `px-4`
        vertical: 8, // `py-2`
      ),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        border: Border.all(color: AppColors.errorDeep.withValues(alpha: 0.3)),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          const Icon(Symbols.lock_clock, size: 18, color: AppColors.errorDeep),
          const SizedBox(width: 8), // `gap-2`
          Expanded(
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  const TextSpan(
                    text:
                        'Trop de tentatives de connexion. Accès bloqué '
                        'pendant ',
                  ),
                  TextSpan(
                    text: libelleCompteARebours,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
