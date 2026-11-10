import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/resultat/resultat.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../domain/entities/journee_elevage.dart';
import '../../viewmodels/fiche_espece_view_model.dart';

/// Bandeaux d'expert de la fiche d'élevage (`47e_`) : fiche « modifiée ailleurs »,
/// chaîne d'effectifs incohérente, bande à recoder. Chacun disparaît quand il n'a rien
/// à dire.
class BandeauxExpert extends StatelessWidget {
  const BandeauxExpert({super.key, required this.vm});

  final FicheEspeceViewModel vm;

  @override
  Widget build(BuildContext context) {
    final bande = vm.bande;
    final blocs = <Widget>[
      if (vm.journeeActive.modifieeAilleurs)
        _Encart(
          cle: const Key('bandeau-divergence'),
          icone: Symbols.call_split,
          texte:
              'Fiche du ${Formats.date(vm.jourActif)} modifiée ailleurs : un autre '
              'poste (ou le web) a saisi ce jour sans voir votre version. Aucune '
              'saisie n\'est perdue ; choisissez la version à garder.',
          bouton: 'Choisir la version',
          onPressed: () => _choisir(context, vm),
        ),
      if (vm.joursIncoherents.isNotEmpty)
        _Encart(
          cle: const Key('bandeau-chaine'),
          icone: Symbols.link_off,
          texte:
              '${vm.joursIncoherents.length} jour'
              '${vm.joursIncoherents.length > 1 ? 's' : ''} dont l\'effectif ne '
              'découle pas de la veille (fiche d\'un autre poste arrivée sans '
              'recalcul), à partir du ${Formats.date(vm.joursIncoherents.first.date)}.',
          bouton: 'Recalculer la chaîne',
          onPressed: () async {
            final r = await vm.recalculerChaine();
            if (!context.mounted) return;
            switch (r) {
              case Succes<RapportChaine>(valeur: final rapport):
                showAppToast(
                  context,
                  rapport.etaitCoherente
                      ? 'La chaîne était déjà cohérente.'
                      : '${rapport.joursCorriges.length} jour'
                            '${rapport.joursCorriges.length > 1 ? 's' : ''} recalculé'
                            '${rapport.joursCorriges.length > 1 ? 's' : ''}.',
                );
              case Echec<RapportChaine>(message: final message):
                showAppToast(context, message, type: ToastType.error);
            }
          },
        ),
      if (bande != null && bande.enConflit)
        _Encart(
          cle: const Key('bandeau-recodage'),
          icone: Symbols.edit_note,
          texte:
              '${bande.motifConflit} Recodez la bande ${bande.code} (le code reste '
              'tracé dans ses observations).',
          bouton: 'Recoder la bande',
          onPressed: () => _recoder(context, vm),
        ),
    ];
    if (blocs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocs.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            blocs[i],
          ],
        ],
      ),
    );
  }
}

class _Encart extends StatelessWidget {
  const _Encart({
    required this.cle,
    required this.icone,
    required this.texte,
    required this.bouton,
    required this.onPressed,
  });

  final Key cle;
  final IconData icone;
  final String texte;
  final String bouton;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: cle,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.brandGold.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.brandGold),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Icon(icone, size: 22, color: AppColors.brandGold),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texte,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            label: bouton,
            variant: AppButtonVariant.outline,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

String _resume(JourneeElevage j) =>
    'Entrées ${j.achat + j.ne} · morts ${j.totalMorts} · effectif ${j.effectif}'
    '${j.poidsGeneralG != null ? ' · pesée ${Formats.nombre(j.poidsGeneralG!)} g' : ''}'
    '${(j.traitementObs ?? '').isNotEmpty ? ' · « ${j.traitementObs} »' : ''}';

Future<void> _choisir(BuildContext context, FicheEspeceViewModel vm) async {
  final versions = vm.versionsEnDivergence;
  final choix = await AppModal.show<VersionJournee>(
    context,
    title: 'Quelle version garder ?',
    maxWidth: 560,
    child: Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Le choix est le vôtre : la machine ne tranche pas. La version gardée '
            'sera envoyée partout et les jours suivants recalculés.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final v in versions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.outlineVariant),
                  borderRadius: AppRadius.cardRadius,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${v.estCourante ? 'Version courante' : v.origine} — '
                            'saisie le ${Formats.date(v.instant.toLocal())}',
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandNavy,
                            ),
                          ),
                          Text(
                            _resume(v.journee),
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 11,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppButton(
                      label: 'Garder celle-ci',
                      variant: AppButtonVariant.outline,
                      onPressed: () => Navigator.of(ctx).pop(v),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
  if (choix == null || !context.mounted) return;
  final r = await vm.resoudreDivergence(choix);
  if (!context.mounted) return;
  switch (r) {
    case Succes<void>():
      showAppToast(
        context,
        'Version gardée : la fiche n\'est plus en divergence.',
      );
    case Echec<void>(message: final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

Future<void> _recoder(BuildContext context, FicheEspeceViewModel vm) async {
  final propose = await vm.codeRecodageBandePropose() ?? '';
  if (!context.mounted) return;
  final controleur = TextEditingController(text: propose);
  final code = await AppModal.show<String>(
    context,
    title: 'Recoder la bande',
    maxWidth: 420,
    child: Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Nouveau code (proposé : code actuel + code du poste) :',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: controleur, autofocus: true),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Annuler',
                variant: AppButtonVariant.outline,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Recoder',
                onPressed: () => Navigator.of(ctx).pop(controleur.text),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  controleur.dispose();
  if (code == null || !context.mounted) return;
  final r = await vm.recoderBande(code);
  if (!context.mounted) return;
  switch (r) {
    case Succes<void>():
      showAppToast(context, 'Bande recodée en ${code.trim()}.');
    case Echec<void>(message: final message):
      showAppToast(context, message, type: ToastType.error);
  }
}
