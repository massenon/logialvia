import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../administration/presentation/viewmodels/auth_view_model.dart';
import '../../../pilotage/domain/entities/tableau_bord_principal.dart';
import '../../../pilotage/presentation/viewmodels/alertes_view_model.dart';
import '../../formatage/formats.dart';
import '../../router/navigation_model.dart';
import '../../sync/moteur_synchronisation.dart';
import '../../sync/planificateur_synchronisation.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../app_button.dart';
import '../app_modal.dart';
import 'recherche_globale.dart';

/// Barre du haut — `<header class="h-16 ...">` commun aux 28 ecrans internes.
///
/// ELEMENTS VOLONTAIREMENT NON REPRODUITS, et pourquoi :
/// - Badge « 3 en attente » du prototype : le nombre est ecrit en dur dans le
///   HTML. Le reproduire serait un indicateur mensonger (Master Prompt §2.3).
///   Il est REMPLACE par un indicateur reel ([IndicateurSynchro]) : toujours
///   visible, il dit l'etat de la derniere synchronisation (en cours, a jour,
///   hors ligne, a verifier) ou que le poste n'est pas encore appaire.
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
          const IndicateurSynchro(),
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

/// L'état réel de la synchronisation — jamais un compteur écrit en dur.
///
/// Toujours présent (avec son modal) tant qu'un planificateur existe : un poste
/// pas encore appairé le dit (« Poste non appairé : il travaille hors ligne »)
/// au lieu de laisser croire que la synchronisation n'existe pas. `watch<…?>` :
/// sans planificateur dans l'arbre, rien ne s'affiche au lieu de lever une erreur.
class IndicateurSynchro extends StatelessWidget {
  const IndicateurSynchro({super.key});

  @override
  Widget build(BuildContext context) {
    final planificateur = context.watch<PlanificateurSynchronisation?>();
    if (planificateur == null) return const SizedBox.shrink();

    final rapport = planificateur.dernierRapport;
    final revoque = rapport?.issue == IssueSynchronisation.revoque;
    // Suspendu sans révocation = poste jamais appairé : on le dit, sans alarme.
    final nonAppaire = planificateur.suspendu && !revoque;

    final IconData icone;
    final Color couleur;
    final String texte;
    if (nonAppaire) {
      icone = Symbols.link_off;
      couleur = AppColors.outline;
      texte =
          'Poste non appairé : il travaille hors ligne. Appairez-le dans '
          'Paramètres > Appairage pour synchroniser avec le serveur.';
    } else if (planificateur.enCours) {
      icone = Symbols.sync;
      couleur = AppColors.brandNavy;
      texte = 'Synchronisation en cours…';
    } else if (rapport == null) {
      icone = Symbols.cloud_sync;
      couleur = AppColors.outline;
      texte = 'Synchronisation en attente.';
    } else if (rapport.issue == IssueSynchronisation.revoque) {
      icone = Symbols.link_off;
      couleur = AppColors.errorDeep;
      texte = 'Poste non appairé : reconnectez-le dans Paramètres > Appairage.';
    } else if (rapport.issue == IssueSynchronisation.horsLigne) {
      icone = Symbols.cloud_off;
      couleur = AppColors.outline;
      texte =
          'Hors ligne : vos saisies sont conservées et partiront à la '
          'reconnexion.';
    } else if (!rapport.reussie ||
        rapport.refusees > 0 ||
        rapport.envoiSuspendu ||
        rapport.horlogeAAvertir) {
      // `47g_` : une horloge à corriger se dit aussi ici (et dans la modale au clic).
      icone = rapport.envoiSuspendu || rapport.horlogeAAvertir
          ? Symbols.schedule
          : Symbols.sync_problem;
      couleur = AppColors.errorDeep;
      texte = rapport.message;
    } else {
      icone = Symbols.cloud_done;
      couleur = AppColors.successDeep;
      final quand = planificateur.derniereTentative;
      texte = quand == null
          ? 'Synchronisé.'
          : 'Synchronisé à ${Formats.heure(quand)}.';
    }

    return IconButton(
      key: const Key('indicateur-synchro'),
      tooltip: '$texte\nCliquer pour le détail de la synchronisation.',
      onPressed: () => _ouvrirModaleEtat(
        context,
        planificateur: planificateur,
        texte: texte,
        couleur: couleur,
      ),
      icon: Icon(icone, color: couleur, size: 22),
    );
  }

  /// Modale de l'icône de synchronisation : l'état en clair, ce que le dernier cycle a fait, l'horloge, et le geste
  /// « Synchroniser maintenant » (l'ancien clic direct). Maquette : pastille « en attente » de la barre du haut.
  static Future<void> _ouvrirModaleEtat(
    BuildContext context, {
    required PlanificateurSynchronisation planificateur,
    required String texte,
    required Color couleur,
  }) {
    final rapport = planificateur.dernierRapport;
    final quand = planificateur.derniereTentative;
    final lignes = <(String, int)>[
      if (rapport != null) ...[
        ('Envoyées au serveur', rapport.envoyees),
        ('Acceptées', rapport.acceptees),
        ('Refusées', rapport.refusees),
        ('En attente de droit', rapport.enAttenteDeDroit),
        ('Reçues des autres postes', rapport.recues),
        ('Référentiels mis à jour', rapport.referentielsMisAJour),
        ('Conservées localement', rapport.conserveesLocalement),
      ],
    ];
    const style = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: AppTypography.textXs,
      color: AppColors.outline,
      height: 1.5,
    );

    return AppModal.show<void>(
      context,
      title: 'Synchronisation',
      maxWidth: 480,
      child: Column(
        key: const Key('synchro-modale-etat'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceZebra,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Text(
              texte,
              key: const Key('synchro-modale-resume'),
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: AppTypography.textXs,
                fontWeight: FontWeight.w700,
                color: couleur,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            quand == null
                ? 'Aucune synchronisation depuis le démarrage.'
                : 'Dernière tentative à ${Formats.heure(quand)}.',
            style: style,
          ),
          if (lignes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final (libelle, valeur) in lignes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(libelle, style: style),
                    Text(
                      '$valeur',
                      style: style.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (rapport?.horloge?.message case final alerte?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              alerte,
              key: const Key('synchro-modale-horloge'),
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: AppTypography.textXs,
                color: AppColors.errorDeep,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
      actions: [
        Builder(
          builder: (ctx) => AppButton(
            label: 'Fermer',
            variant: AppButtonVariant.outline,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ),
        Builder(
          builder: (ctx) => AppButton(
            key: const Key('synchro-maintenant'),
            label: 'Synchroniser maintenant',
            icon: Symbols.sync,
            onPressed: planificateur.enCours || planificateur.suspendu
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    unawaited(planificateur.synchroniserMaintenant());
                  },
          ),
        ),
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
  static const List<({String libelle, IconData icone, String route})> _entrees =
      [
        (libelle: 'Mon Profil', icone: Symbols.person, route: '/profil'),
        (libelle: 'Aide & À Propos', icone: Symbols.help, route: '/aide'),
        (
          libelle: 'Contactez l\'Éditeur',
          icone: Symbols.support_agent,
          route: '/contact',
        ),
        (
          libelle: 'Paramètres',
          icone: Symbols.settings,
          route: '/parametres/generaux',
        ),
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
