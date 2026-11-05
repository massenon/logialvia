import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../administration/presentation/viewmodels/auth_view_model.dart';
import '../../../pilotage/domain/entities/tableau_bord_principal.dart';
import '../../../pilotage/presentation/viewmodels/alertes_view_model.dart';
import '../../router/navigation_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'recherche_globale.dart';

/// Barre du haut — `<header class="h-16 ...">` commun aux 28 ecrans internes.
///
/// ELEMENTS VOLONTAIREMENT NON REPRODUITS, et pourquoi :
/// - Badge « 3 en attente » avec icone `sync` animee : aucune synchronisation
///   n'existe (application hors-ligne par conception, Doc B1 §7) et le nombre
///   est ecrit en dur dans le HTML. Le reproduire serait un indicateur
///   mensonger (Master Prompt §2.3).
/// - Les 2 boutons dont le `title` commence par « Démonstration — forcer
///   l'affichage… » : ce sont des outils de test du prototype, pas des
///   fonctionnalites de production — meme statut que le selecteur de role RBAC
///   (Doc I1 §1, Doc F1).
/// - Selecteur de role RBAC : idem, outil d'audit. En production le role vient
///   du compte connecte.
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.routeActive,
    required this.onBasculerSidebar,
  });

  final String routeActive;
  final VoidCallback onBasculerSidebar;

  static const double hauteur = 64; // `h-16`

  @override
  Widget build(BuildContext context) {
    return Container(
      height: hauteur,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBasculerSidebar,
            icon: const Icon(Symbols.menu_open, size: 22),
            color: AppColors.outline,
            tooltip: 'Afficher/Masquer la barre latérale',
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _FilDAriane(routeActive: routeActive)),
          const SizedBox(width: AppSpacing.md),
          const SizedBox(width: 256, child: RechercheGlobale()), // `w-64`
          const SizedBox(width: AppSpacing.md),
          const _CloctheNotifications(),
          const SizedBox(width: AppSpacing.sm),
          const _MenuProfil(),
        ],
      ),
    );
  }
}

class _FilDAriane extends StatelessWidget {
  const _FilDAriane({required this.routeActive});

  final String routeActive;

  @override
  Widget build(BuildContext context) {
    final segments = NavigationModel.filDAriane(routeActive);
    if (segments.isEmpty) return const SizedBox.shrink();

    const styleParent = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: AppTypography.textXs,
      color: AppColors.outline,
    );
    const styleCourant = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: AppTypography.textXs,
      fontWeight: FontWeight.w700,
      color: AppColors.brandNavy,
    );

    return Row(
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0)
            const Icon(
              Symbols.chevron_right,
              size: 15,
              color: AppColors.outline,
            ),
          Flexible(
            child: Text(
              segments[i],
              overflow: TextOverflow.ellipsis,
              style: i == segments.length - 1 ? styleCourant : styleParent,
            ),
          ),
        ],
      ],
    );
  }
}

class _CloctheNotifications extends StatelessWidget {
  const _CloctheNotifications();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AlertesViewModel>();

    return MenuAnchor(
      alignmentOffset: const Offset(-260, 8),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceCard),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: AppRadius.cardRadius,
            side: const BorderSide(color: AppColors.outlineVariant),
          ),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: 320, // `w-80`
          child: vm.alertes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    'Aucune alerte en cours.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: AppTypography.textXs,
                      color: AppColors.outline,
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final alerte in vm.alertes)
                      InkWell(
                        onTap: () => context.go(alerte.route),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          child: Text(
                            alerte.message,
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: AppTypography.textXs,
                              fontWeight: FontWeight.w600,
                              color: alerte.severite == SeveriteAlerte.critique
                                  ? AppColors.errorDeep
                                  : AppColors.brandNavy,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
      builder: (context, controller, child) => IconButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        tooltip: 'Notifications',
        icon: Badge(
          isLabelVisible: vm.nombre > 0,
          backgroundColor: AppColors.errorDeep,
          label: Text('${vm.nombre}'),
          child: const Icon(Symbols.notifications, color: AppColors.outline),
        ),
      ),
    );
  }
}

class _MenuProfil extends StatelessWidget {
  const _MenuProfil();

  /// Entrees du menu profil — `dashboard.html` l.79-85, ordre exact.
  static const List<({String libelle, IconData icone, String route})> _entrees = [
    (libelle: 'Mon Profil', icone: Symbols.person, route: '/profil'),
    (libelle: 'Aide & À Propos', icone: Symbols.help, route: '/aide'),
    (
      libelle: 'Contactez l\'Éditeur',
      icone: Symbols.support_agent,
      route: '/contact',
    ),
    (libelle: 'Paramètres', icone: Symbols.settings, route: '/parametres/generaux'),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();

    return MenuAnchor(
      alignmentOffset: const Offset(-140, 8),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceCard),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: AppRadius.cardRadius,
            side: const BorderSide(color: AppColors.outlineVariant),
          ),
        ),
      ),
      menuChildren: [
        for (final entree in _entrees)
          MenuItemButton(
            leadingIcon: Icon(entree.icone, size: 16),
            onPressed: () => context.go(entree.route),
            child: Text(entree.libelle, style: _styleEntree),
          ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(
            Symbols.logout,
            size: 16,
            color: AppColors.errorDeep,
          ),
          onPressed: () async {
            await context.read<AuthViewModel>().seDeconnecter();
            if (context.mounted) context.go('/login');
          },
          child: const Text(
            'Déconnexion',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: AppTypography.textXs,
              color: AppColors.errorDeep,
            ),
          ),
        ),
      ],
      builder: (context, controller, child) => InkWell(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Symbols.account_circle, color: AppColors.brandNavy),
              const SizedBox(width: AppSpacing.xs),
              Text(
                auth.session?.role.libelle ?? '',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: AppTypography.textXs,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandNavy,
                ),
              ),
              const Icon(
                Symbols.expand_more,
                size: 16,
                color: AppColors.brandNavy,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const TextStyle _styleEntree = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.textXs,
    color: AppColors.onSurface,
  );
}
