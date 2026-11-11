import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/fond_degrade_marque.dart';
import '../../../../core/widgets/marque_logialvia.dart';

/// Ecran 2 du module Authentification — Doc F1, fidele a `welcome.html`.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  /// Les 4 tuiles de bas de page, dans l'ordre exact du prototype.
  static const List<(IconData, String)> _tuiles = [
    (Symbols.egg, 'Couveuse'),
    (Symbols.inventory_2, 'Stocks'),
    (Symbols.point_of_sale, 'Ventes'),
    (Symbols.campaign, 'Relances Clients'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FondDegradeMarque(
        angleDegres: 160,
        // welcome.html n'a ni `.filigrane` ni texture de grain — contrairement
        // au Splash et au Login. Non ajoute pour rester fidele.
        child: Column(
          children: [
            const _EnTete(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 40, // `py-10`
                ),
                child: Center(child: _corps(context)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24), // `pb-6`
              child: Text(
                'Version 1.0.0  •  Projet PAEB  •  FAGUEZ SARL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  letterSpacing: 0.6, // `tracking-wider`
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _corps(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FadeUp(
          delai: const Duration(milliseconds: 100), // `.d1`
          child: Container(
            width: 112, // `md:w-28`
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Center(
              child: Icon(
                Symbols.egg,
                size: 56,
                color: AppColors.brandGoldLight,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24), // `mb-6`
        _FadeUp(
          delai: const Duration(milliseconds: 250), // `.d2`
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 768), // `max-w-3xl`
            child: const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Bienvenue sur '),
                  // Le prototype dore "Logi" ici, et "ALVIA" ailleurs.
                  TextSpan(
                    text: 'Logi',
                    style: TextStyle(color: AppColors.brandGold),
                  ),
                  TextSpan(text: 'ALVIA'),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 48, // `md:text-5xl`
                fontWeight: FontWeight.w800,
                height: 1.25, // `leading-tight`
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16), // `mt-4`
        _FadeUp(
          delai: const Duration(milliseconds: 400), // `.d3`
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 576), // `max-w-xl`
            child: Text(
              'Gérez votre élevage, vos stocks et vos clients en toute simplicité.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16, // `md:text-base`
                height: 1.625, // `leading-relaxed`
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32), // `mt-8`
        _FadeUp(
          delai: const Duration(milliseconds: 550), // `.d4`
          child: _BoutonOr(onPressed: () => context.go('/login')),
        ),
        const SizedBox(height: 48), // `mt-12`
        _FadeUp(
          delai: const Duration(milliseconds: 550),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672), // `max-w-2xl`
            child: Row(
              children: [
                for (var i = 0; i < _tuiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12), // `gap-3`
                  Expanded(
                    child: _TuileFonctionnalite(
                      icone: _tuiles[i].$1,
                      libelle: _tuiles[i].$2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete();

  @override
  Widget build(BuildContext context) {
    final styleSecondaire = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: AppTypography.textXs,
      color: Colors.white.withValues(alpha: 0.7),
    );

    return Padding(
      // `px-4 md:px-10 py-4`
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Symbols.egg, size: 22, color: AppColors.brandGoldLight),
              SizedBox(width: 8), // `gap-2`
              MarqueLogiAlvia(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                couleurBase: Colors.white,
              ),
            ],
          ),
          Row(
            children: [
              Icon(
                Symbols.translate,
                size: 16,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4), // `gap-1`
              Text('Français', style: styleSecondaire),
              const SizedBox(width: 12), // `gap-3`
              Text(
                'v1.0.0',
                style: styleSecondaire.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6, // `tracking-wider`
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bouton pilule or a texte navy. Volontairement local a cet ecran et non
/// ajoute comme 4e variante de `AppButton` (Doc E2 §1) : un `grep` sur
/// `bg-brand-gold` dans les 31 fichiers du prototype montre que ce style plein
/// n'existe QUE sur welcome.html — partout ailleurs l'or n'apparait qu'en fond
/// translucide (`bg-brand-gold/20`) ou en bordure.
class _BoutonOr extends StatelessWidget {
  const _BoutonOr({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style:
          ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandGold,
            foregroundColor: AppColors.brandNavy,
            elevation: 6, // `shadow-lg`
            padding: const EdgeInsets.symmetric(
              horizontal: 32, // `px-8`
              vertical: 10, // `py-2.5`
            ),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
          ).copyWith(
            overlayColor: WidgetStatePropertyAll(
              AppColors.brandGoldLight.withValues(alpha: 0.4),
            ),
          ),
      child: const Text(
        'Se connecter',
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TuileFonctionnalite extends StatelessWidget {
  const _TuileFonctionnalite({required this.icone, required this.libelle});

  final IconData icone;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16), // `py-4`
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        children: [
          Icon(icone, size: 22, color: AppColors.brandGoldLight),
          const SizedBox(height: 4), // `gap-1`
          Text(
            libelle.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.35, // `tracking-wide`
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.fade-up{animation:fadeUp .8s ease-out forwards;opacity:0;}` avec les
/// retards `.d1`/`.d2`/`.d3`/`.d4` — welcome.html l.18-21.
class _FadeUp extends StatefulWidget {
  const _FadeUp({required this.child, required this.delai});

  final Widget child;
  final Duration delai;

  @override
  State<_FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<_FadeUp> with SingleTickerProviderStateMixin {
  late final AnimationController _controleur = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delai, () {
      if (mounted) _controleur.forward();
    });
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final courbe = CurvedAnimation(parent: _controleur, curve: Curves.easeOut);
    return FadeTransition(
      opacity: courbe,
      child: AnimatedBuilder(
        animation: courbe,
        builder: (context, child) => Transform.translate(
          // `translateY(14px)` -> 0
          offset: Offset(0, 14 * (1 - courbe.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
