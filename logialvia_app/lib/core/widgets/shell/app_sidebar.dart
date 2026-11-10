import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../administration/presentation/viewmodels/auth_view_model.dart';
import '../../../administration/presentation/viewmodels/modules_actifs_view_model.dart';
import '../../router/navigation_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../fond_degrade_marque.dart';
import '../marque_logialvia.dart';

/// Barre laterale — transcription de `assets/js/sidebar.js`.
///
/// Largeur `w-72` (288 px), degrade `.sidebar-gradient` identique a celui du
/// Splash (`linear-gradient(180deg,#1F3864,#152847)`, common.css l.54).
class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key, required this.routeActive});

  final String routeActive;

  static const double largeur = 288; // `w-72`

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthViewModel>().session;
    final modules = context.watch<ModulesActifsViewModel>();
    final role = session?.role.id ?? '';

    return SizedBox(
      width: largeur,
      child: FondDegradeMarque(
        angleDegres: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _EnTeteSidebar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                children: [
                  for (final groupe in NavigationModel.groupes)
                    if (groupe.roles.contains(role))
                      _GroupeSidebar(
                        groupe: groupe,
                        routeActive: routeActive,
                        modules: modules,
                      ),
                ],
              ),
            ),
            _PiedSidebar(
              nom: session?.utilisateur.nom ?? '—',
              role: session?.role.libelle ?? '—',
            ),
          ],
        ),
      ),
    );
  }
}

class _EnTeteSidebar extends StatelessWidget {
  const _EnTeteSidebar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Symbols.egg, size: 26, color: AppColors.brandGold),
              SizedBox(width: AppSpacing.xs),
              MarqueLogiAlvia(
                fontSize: 18, // `text-lg`
                fontWeight: FontWeight.w800,
                couleurBase: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'ALLMANY ET COMPAGNIE',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              letterSpacing: 0.6, // `tracking-wider`
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupeSidebar extends StatelessWidget {
  const _GroupeSidebar({
    required this.groupe,
    required this.routeActive,
    required this.modules,
  });

  final GroupeNavigation groupe;
  final String routeActive;
  final ModulesActifsViewModel modules;

  @override
  Widget build(BuildContext context) {
    // Doc I2 §3 : une filiere desactivee disparait de la navigation.
    final entreesVisibles = groupe.entrees
        .where((e) => e.moduleId == null || modules.estActif(e.moduleId!))
        .toList();
    if (entreesVisibles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            right: AppSpacing.xs,
            top: AppSpacing.sm,
          ),
          child: Text(
            groupe.titre,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final entree in entreesVisibles)
          _LienSidebar(entree: entree, actif: entree.route == routeActive),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _LienSidebar extends StatelessWidget {
  const _LienSidebar({required this.entree, required this.actif});

  final EntreeNavigation entree;
  final bool actif;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: actif ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: AppRadius.cardRadius,
        child: InkWell(
          borderRadius: AppRadius.cardRadius,
          hoverColor: Colors.white.withValues(alpha: 0.1),
          onTap: () => context.go(entree.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(
                  entree.icone,
                  size: 20,
                  color: actif
                      ? AppColors.brandGold
                      : Colors.white.withValues(alpha: 0.9),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    entree.libelle,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 15,
                      fontWeight: actif ? FontWeight.w700 : FontWeight.w400,
                      color: actif
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PiedSidebar extends StatelessWidget {
  const _PiedSidebar({required this.nom, required this.role});

  final String nom;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ECART_DELIBERE : `sidebar.js` affiche un bouton "Synchroniser" sans
          // aucun gestionnaire de clic (l.80) — il ne fait donc rien, meme cote
          // web. Reproduire un bouton inerte contreviendrait au Master Prompt
          // §2.3. Il est retire tant qu'aucune synchronisation reelle n'existe
          // (l'application est hors-ligne par conception, Doc B1 §7).
          // Une synchronisation reelle existe desormais (poste appaire) : son etat
          // et son declenchement manuel sont dans la barre du haut
          // (`_IndicateurSynchro`) et dans Parametres > Appairage.
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                child: const Icon(
                  Symbols.account_circle,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nom,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      role.toUpperCase(),
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 9,
                        letterSpacing: 0.45,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
