import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/resultat/resultat.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/carte_section.dart';
import '../../../domain/services/service_archivage.dart';
import '../../viewmodels/auth_view_model.dart';
import '../../viewmodels/corbeille_view_model.dart';

const TextStyle _texte = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

/// Onglet « Corbeille » — restauration de ce qui a été supprimé.
///
/// Dans toute l'application, « Supprimer » **archive** : la ligne quitte sa
/// table, une copie complète entre ici, et rien n'est détruit. C'est le seul
/// écran d'où une destruction définitive est possible, et elle est réservée à
/// l'administratrice.
class OngletCorbeille extends StatelessWidget {
  const OngletCorbeille({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CorbeilleViewModel>();
    final estAdmin = context.read<AuthViewModel>().session?.role.id == 'admin';

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Explication(estAdmin: estAdmin),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Corbeille — ${vm.total} élément(s)',
          icone: Symbols.restore_from_trash,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (vm.modules.length > 1) ...[
                _FiltreModule(vm: vm),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (vm.total > 0 && estAdmin)
                AppButton(
                  label: 'Vider la corbeille',
                  icon: Symbols.delete_forever,
                  variant: AppButtonVariant.outline,
                  height: 34,
                  onPressed: () => _viderTout(context, vm),
                ),
            ],
          ),
          child: vm.elements.isEmpty
              ? EtatVide(
                  message: vm.total == 0
                      ? 'La corbeille est vide. Tout ce qui est supprimé dans '
                            'l\'application vient ici, et peut être restauré.'
                      : 'Aucun élément de ce module dans la corbeille.',
                )
              : _Tableau(vm: vm, estAdmin: estAdmin),
        ),
      ],
    );
  }

  Future<void> _viderTout(BuildContext context, CorbeilleViewModel vm) async {
    final confirme = await AppModal.show<bool>(
      context,
      title: 'Vider définitivement la corbeille ?',
      maxWidth: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Avertissement(
            texte:
                'Les ${vm.total} élément(s) archivés seront détruits. C\'est '
                'la seule opération de l\'application qui supprime vraiment '
                'quelque chose : après elle, plus aucune restauration n\'est '
                'possible.',
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Générez plutôt une sauvegarde depuis l\'onglet Sauvegardes si '
            'vous voulez alléger l\'affichage sans rien perdre.',
            style: _texte.copyWith(color: AppColors.outline, height: 1.5),
          ),
        ],
      ),
      actions: [
        Builder(
          builder: (ctx) => AppButton(
            label: 'Annuler',
            variant: AppButtonVariant.outline,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ),
        Builder(
          builder: (ctx) => AppButton(
            label: 'Vider définitivement',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ),
      ],
    );

    if (confirme != true || !context.mounted) return;
    final resultat = await vm.viderCorbeille(estAdmin: true);
    if (!context.mounted) return;
    switch (resultat) {
      case Succes():
        showAppToast(context, 'Corbeille vidée.');
      case Echec(:final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

class _Explication extends StatelessWidget {
  const _Explication({required this.estAdmin});

  final bool estAdmin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.brandGold.withValues(alpha: 0.1),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Symbols.info, size: 20, color: AppColors.brandNavy),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Dans tous les modules, « Supprimer » archive au lieu de '
              'détruire : produits, intrants, barèmes, échéances de '
              'prophylaxie, lots d\'incubation, utilisateurs, écritures et '
              'messages arrivent ici et peuvent être remis en place.'
              '${estAdmin ? '' : ' Les utilisateurs et les écritures comptables ne se restaurent que depuis un compte administrateur.'}',
              style: _texte.copyWith(height: 1.5, color: AppColors.brandNavy),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltreModule extends StatelessWidget {
  const _FiltreModule({required this.vm});

  final CorbeilleViewModel vm;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: vm.filtreModule,
        isDense: true,
        style: _texte,
        hint: const Text('Tous les modules', style: _texte),
        items: [
          const DropdownMenuItem<String?>(
            child: Text('Tous les modules', style: _texte),
          ),
          for (final module in vm.modules)
            DropdownMenuItem<String?>(
              value: module,
              child: Text(module, style: _texte),
            ),
        ],
        onChanged: vm.definirFiltreModule,
      ),
    );
  }
}

class _Tableau extends StatelessWidget {
  const _Tableau({required this.vm, required this.estAdmin});

  final CorbeilleViewModel vm;
  final bool estAdmin;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.surfaceZebra,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              _entete('ÉLÉMENT', flex: 5),
              _entete('TYPE', flex: 3),
              _entete('MODULE', flex: 2),
              _entete('ARCHIVÉ LE', flex: 3),
              _entete('PAR', flex: 2),
              _entete('ACTIONS', flex: 3, alignement: TextAlign.right),
            ],
          ),
        ),
        for (var i = 0; i < vm.elements.length; i++)
          _Ligne(
            element: vm.elements[i],
            zebre: i.isOdd,
            vm: vm,
            estAdmin: estAdmin,
          ),
      ],
    );
  }

  static Widget _entete(
    String libelle, {
    required int flex,
    TextAlign alignement = TextAlign.left,
  }) => Expanded(
    flex: flex,
    child: Text(
      libelle,
      textAlign: alignement,
      style: AppTypography.label.copyWith(color: AppColors.outline),
    ),
  );
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.element,
    required this.zebre,
    required this.vm,
    required this.estAdmin,
  });

  final ElementArchive element;
  final bool zebre;
  final CorbeilleViewModel vm;
  final bool estAdmin;

  bool get _reserve =>
      TypeArchivable.parTable(element.nomTable)?.reserveALAdmin ?? true;

  bool get _peutRestaurer => estAdmin || !_reserve;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: zebre ? AppColors.surfaceZebra : null,
        border: const Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              element.designation,
              overflow: TextOverflow.ellipsis,
              style: _texte.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(flex: 3, child: Text(element.typeElement, style: _texte)),
          Expanded(
            flex: 2,
            child: Text(
              element.module,
              style: _texte.copyWith(color: AppColors.outline),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${Formats.date(element.archiveLe)} '
              '${Formats.heure(element.archiveLe)}',
              style: _texte,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              element.archiveParNom ?? '—',
              overflow: TextOverflow.ellipsis,
              style: _texte.copyWith(
                color: element.archiveParNom == null ? AppColors.outline : null,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Tooltip(
                  message: _peutRestaurer
                      ? 'Restaurer'
                      : 'Réservé à l\'administratrice',
                  child: IconButton(
                    icon: const Icon(Symbols.restore, size: 18),
                    color: _peutRestaurer
                        ? AppColors.successDeep
                        : AppColors.outlineVariant,
                    visualDensity: VisualDensity.compact,
                    onPressed: _peutRestaurer
                        ? () => _restaurer(context)
                        : null,
                  ),
                ),
                if (estAdmin)
                  IconButton(
                    icon: const Icon(Symbols.delete_forever, size: 18),
                    color: AppColors.outline,
                    tooltip: 'Supprimer définitivement',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _purger(context),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restaurer(BuildContext context) async {
    final resultat = await vm.restaurer(element, estAdmin: estAdmin);
    if (!context.mounted) return;
    switch (resultat) {
      case Succes():
        showAppToast(context, '${element.designation} restauré.');
      case Echec(:final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }

  Future<void> _purger(BuildContext context) async {
    final confirme = await AppModal.show<bool>(
      context,
      title: 'Supprimer définitivement ?',
      maxWidth: 480,
      child: _Avertissement(
        texte:
            '« ${element.designation} » sera détruit sans recours. Il ne '
            'pourra plus être restauré.',
      ),
      actions: [
        Builder(
          builder: (ctx) => AppButton(
            label: 'Annuler',
            variant: AppButtonVariant.outline,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ),
        Builder(
          builder: (ctx) => AppButton(
            label: 'Supprimer définitivement',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ),
      ],
    );

    if (confirme != true || !context.mounted) return;
    final resultat = await vm.purger(element, estAdmin: estAdmin);
    if (!context.mounted) return;
    switch (resultat) {
      case Succes():
        showAppToast(context, 'Élément supprimé définitivement.');
      case Echec(:final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

class _Avertissement extends StatelessWidget {
  const _Avertissement({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Symbols.warning, size: 20, color: AppColors.errorDeep),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texte,
              style: _texte.copyWith(
                color: AppColors.errorDeep,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
