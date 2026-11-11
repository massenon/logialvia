import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/fond_degrade_marque.dart';
import '../../../../core/widgets/marque_logialvia.dart';
import '../../../domain/services/service_restauration.dart';
import '../../viewmodels/splash_view_model.dart';

/// Ecran 1 du module Authentification — Doc F1, fidele a `index.html`.
///
/// Ordre strict des sections du prototype :
/// emblème → mot-symbole → accroches → identite de l'exploitation →
/// barre de progression → message d'etat → mention de version.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// `.logo-anim{animation:logoIn 1.1s ease-out forwards;}` — index.html l.18.
  late final AnimationController _controleurLogo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// `.progress-fill{animation:fillBar 3s linear forwards;}` — index.html l.20.
  late final AnimationController _controleurProgression = AnimationController(
    vsync: this,
    duration: SplashViewModel.dureeAffichage,
  );

  @override
  void initState() {
    super.initState();
    _controleurLogo.forward();
    _controleurProgression.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _demarrer());
  }

  Future<void> _demarrer() async {
    final vm = context.read<SplashViewModel>();
    await vm.initialiser();
    if (!mounted) return;
    final route = vm.routeCible;
    if (route != null) context.go(route);
  }

  Future<void> _reessayer() async {
    final vm = context.read<SplashViewModel>();
    _controleurProgression
      ..reset()
      ..forward();
    await vm.reessayer();
    if (!mounted) return;
    final route = vm.routeCible;
    if (route != null) context.go(route);
  }

  @override
  void dispose() {
    _controleurLogo.dispose();
    _controleurProgression.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SplashViewModel>();

    return Scaffold(
      body: FondDegradeMarque(
        angleDegres: 180,
        // `.filigrane{opacity:.05}` sur des points blancs, grille de 28px.
        espacementPoints: 28,
        couleurPoints: Colors.white.withValues(alpha: 0.05),
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                // `max-w-md` = 28rem = 448px, `px-4` = 16px.
                constraints: const BoxConstraints(maxWidth: 448),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _blocLogoAnime(),
                      const SizedBox(height: 32), // `mt-8`
                      if (context.read<RapportRestauration?>() != null) ...[
                        _blocRestauration(
                          context.read<RapportRestauration?>()!,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (vm.erreurInitialisation != null)
                        _blocErreur(vm.erreurInitialisation!)
                      else
                        _blocProgression(vm.etapeCourante),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16, // `bottom-4`
              child: Text(
                'v1.0.0 — © 2026 FAGUEZ SARL',
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

  /// `@keyframes logoIn{0%{opacity:0;scale:.85}60%{opacity:1;scale:1.05}100%{scale:1}}`
  /// Confirme la restauration au moment ou elle vient d'etre appliquee.
  ///
  /// Sans ce bloc, la Gerante redemarre l'application et ne sait pas si sa
  /// sauvegarde a ete reprise : elle ne verrait qu'un ecran de connexion
  /// ordinaire, identique a celui de la veille.
  Widget _blocRestauration(RapportRestauration rapport) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.successContainer,
        border: Border.all(color: AppColors.successDeep),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Symbols.settings_backup_restore,
                size: 18,
                color: AppColors.successDeep,
              ),
              SizedBox(width: AppSpacing.xs),
              Text(
                'Sauvegarde restaurée',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.successDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            rapport.fichierRestaure,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'La base précédente a été conservée :\n'
            '${rapport.copieDeSecurite}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 10,
              color: AppColors.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _blocLogoAnime() {
    final opacite = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _controleurLogo, curve: Curves.easeOut));

    final echelle = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.05), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _controleurLogo, curve: Curves.easeOut));

    return AnimatedBuilder(
      animation: _controleurLogo,
      builder: (context, child) => Opacity(
        opacity: opacite.value,
        child: Transform.scale(scale: echelle.value, child: child),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.1),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Center(
              child: Icon(Symbols.egg, size: 44, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12), // `gap-3`
          const SizedBox(height: 8), // `mt-2` du titre
          const MarqueLogiAlvia(
            fontSize: 24, // `text-2xl`
            fontWeight: FontWeight.w800,
            couleurBase: Colors.white,
            letterSpacing: -0.6, // `tracking-tight`
          ),
          const SizedBox(height: 12),
          const Text(
            'Gestion et Suivi Avicole Intégré',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 11 * 0.15, // `tracking-[0.15em]`
              color: AppColors.brandGoldLight,
            ),
          ),
          const SizedBox(height: 4), // `mt-1`
          Text(
            'Couveuse • Élevage • Stocks • Ventes • Relances Clients',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: AppTypography.textXs,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16), // `mt-4`
          const Text(
            'ALLMANY ET COMPAGNIE',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.35, // `tracking-wide`
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Projet d\'Appui à l\'Entrepreneuriat au Bénin (PAEB)',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2, // `tracking-widest`
              color: AppColors.brandGoldLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _blocProgression(String etape) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppRadius.pill,
          child: SizedBox(
            height: 6, // `h-1.5`
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                AnimatedBuilder(
                  animation: _controleurProgression,
                  builder: (context, _) => FractionallySizedBox(
                    widthFactor: _controleurProgression.value,
                    child: const ColoredBox(color: AppColors.brandGoldLight),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8), // `space-y-2`
        SizedBox(
          height: 16, // `h-4`, evite tout saut de mise en page entre 2 messages
          // `.step-fade{animation:stepFade .4s ease-out;}` — index.html l.22.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              etape,
              key: ValueKey(etape),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: AppTypography.textXs,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Etat d'echec reel de l'initialisation. Le prototype n'a pas d'equivalent
  /// (aucune base a ouvrir cote web) : sans cet etat, une base inaccessible
  /// laisserait l'ecran de demarrage fige sans explication.
  Widget _blocErreur(String message) {
    return Column(
      children: [
        const Icon(Symbols.error, size: 32, color: AppColors.brandGoldLight),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: AppTypography.textXs,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: 'Réessayer',
          icon: Symbols.refresh,
          onPressed: _reessayer,
        ),
      ],
    );
  }
}
