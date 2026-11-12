import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/formatage/formats.dart';
import '../../../domain/services/service_restauration.dart';
import '../../../../core/resultat/resultat.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/carte_section.dart';
import '../../../domain/services/service_sauvegarde.dart';
import '../../viewmodels/sauvegardes_view_model.dart';

const TextStyle _texte = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

/// Onglet « Sauvegardes de la Base de Données » — **ajouté**, absent du
/// prototype.
///
/// ⚠️ `parametres-generaux.html` l.75 affiche « Sauvegarde quotidienne
/// effectuée — Aujourd'hui à 05:00 » dans son panneau de notifications, alors
/// qu'aucun mécanisme de sauvegarde n'existe dans les 31 fichiers. Sur une
/// application hors-ligne dont toute la comptabilité tient dans un seul fichier
/// posé sur un ordinateur, c'est le message le plus dangereux du prototype.
class OngletSauvegardes extends StatelessWidget {
  const OngletSauvegardes({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SauvegardesViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BandeauEtat(vm: vm),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Sauvegardes de la Base de Données',
          icone: Symbols.database,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: 'Exporter une table',
                icon: Symbols.table_view,
                variant: AppButtonVariant.outline,
                height: 34,
                onPressed: () => _choisirTable(context, vm),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: vm.generationEnCours
                    ? 'Génération…'
                    : 'Générer une sauvegarde',
                icon: Symbols.backup,
                height: 34,
                onPressed: vm.generationEnCours
                    ? null
                    : () => _generer(context, vm),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CheminDossier(chemin: vm.cheminDossier),
              const SizedBox(height: AppSpacing.md),
              if (vm.sauvegardes.isEmpty)
                const EtatVide(
                  message:
                      'Aucune sauvegarde. Générez-en une avant la première '
                      'journée de saisie : toute la comptabilité, les ventes '
                      'et les fiches d\'élevage tiennent dans un seul fichier '
                      'sur cet ordinateur.',
                )
              else
                _Tableau(vm: vm),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _generer(BuildContext context, SauvegardesViewModel vm) async {
    final resultat = await vm.genererBaseComplete();
    if (!context.mounted) return;
    switch (resultat) {
      case Succes(valeur: final s):
        showAppToast(context, 'Sauvegarde ${s.nom} créée (${s.taille}).');
      case Echec(:final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }

  Future<void> _choisirTable(
    BuildContext context,
    SauvegardesViewModel vm,
  ) async {
    String? choix;
    final table = await AppModal.show<String>(
      context,
      title: 'Exporter une table en CSV',
      maxWidth: 520,
      child: StatefulBuilder(
        builder: (ctx, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Un export CSV s\'ouvre dans un tableur, contrairement au '
              'fichier de base. Il sert à vérifier ce qui est enregistré, ou '
              'à transmettre un extrait au comptable sans lui remettre toute '
              'la base — comptes utilisateurs compris.',
              style: _texte.copyWith(color: AppColors.outline, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: choix,
              isExpanded: true,
              style: _texte,
              hint: const Text('-- Choisir une table --', style: _texte),
              items: [
                for (final t in vm.tablesExportables)
                  DropdownMenuItem(
                    value: t,
                    child: Text(t, style: _texte),
                  ),
              ],
              onChanged: (v) => setState(() => choix = v),
            ),
          ],
        ),
      ),
      actions: [
        Builder(
          builder: (ctx) => AppButton(
            label: 'Annuler',
            variant: AppButtonVariant.outline,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ),
        Builder(
          builder: (ctx) => AppButton(
            label: 'Exporter',
            icon: Symbols.download,
            onPressed: () => Navigator.of(ctx).pop(choix),
          ),
        ),
      ],
    );

    if (table == null || !context.mounted) return;
    final resultat = await vm.exporterTable(table);
    if (!context.mounted) return;
    switch (resultat) {
      case Succes(valeur: final s):
        showAppToast(context, '${s.nom} exporté (${s.taille}).');
      case Echec(:final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

/// Bandeau d'ancienneté — le seul élément qui pousse à sauvegarder.
class _BandeauEtat extends StatelessWidget {
  const _BandeauEtat({required this.vm});

  final SauvegardesViewModel vm;

  @override
  Widget build(BuildContext context) {
    final jours = vm.joursDepuisDerniereSauvegarde;
    final derniere = vm.derniereSauvegardeComplete;

    final (fond, teinte, icone, message) = switch (jours) {
      null => (
        AppColors.errorContainer,
        AppColors.errorDeep,
        Symbols.warning,
        'Aucune sauvegarde complète n\'a jamais été générée. Toute la '
            'comptabilité, les ventes et les fiches d\'élevage tiennent dans '
            'un seul fichier sur cet ordinateur : une panne de disque les '
            'emporterait sans recours.',
      ),
      0 => (
        AppColors.successContainer,
        AppColors.successDeep,
        Symbols.check_circle,
        'Dernière sauvegarde complète : aujourd\'hui à '
            '${Formats.heure(derniere!)}.',
      ),
      final j when j <= 7 => (
        AppColors.successContainer,
        AppColors.successDeep,
        Symbols.check_circle,
        'Dernière sauvegarde complète le ${Formats.date(derniere!)} '
            '— il y a $j jour${j > 1 ? 's' : ''}.',
      ),
      final j => (
        AppColors.errorContainer,
        AppColors.errorDeep,
        Symbols.warning,
        'Dernière sauvegarde complète le ${Formats.date(derniere!)} '
            '— il y a $j jours. Tout ce qui a été saisi depuis serait perdu.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 22, color: teinte),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: _texte.copyWith(
                fontWeight: FontWeight.w700,
                color: teinte,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheminDossier extends StatelessWidget {
  const _CheminDossier({required this.chemin});

  final String chemin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          const Icon(Symbols.folder, size: 18, color: AppColors.outline),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              chemin,
              style: _texte.copyWith(
                fontFamily: 'monospace',
                color: AppColors.outline,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Symbols.content_copy, size: 16),
            color: AppColors.outline,
            tooltip: 'Copier le chemin',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: chemin));
              if (!context.mounted) return;
              showAppToast(context, 'Chemin copié.');
            },
          ),
          AppButton(
            label: 'Ouvrir le dossier',
            icon: Symbols.folder_open,
            variant: AppButtonVariant.outline,
            height: 30,
            onPressed: () => ouvrirDansExplorateur(context, chemin),
          ),
        ],
      ),
    );
  }
}

/// Ouvre l'Explorateur Windows sur un dossier, ou en sélectionnant un fichier.
///
/// ## Pourquoi « ouvrir » et non « télécharger »
///
/// Un téléchargement déplace un fichier d'un serveur vers la machine. Ici la
/// sauvegarde **est déjà sur la machine** : la seule action utile est de la
/// montrer là où elle se trouve, pour que la Gérante la copie sur une clé USB
/// ou l'envoie à son comptable. C'est ce que fait ce bouton.
Future<void> ouvrirDansExplorateur(
  BuildContext context,
  String chemin, {
  bool selectionner = false,
}) async {
  try {
    if (!Platform.isWindows) {
      await Clipboard.setData(ClipboardData(text: chemin));
      if (!context.mounted) return;
      showAppToast(context, 'Chemin copié : $chemin');
      return;
    }
    await Process.run('explorer', [if (selectionner) '/select,', chemin]);
  } catch (e) {
    if (!context.mounted) return;
    showAppToast(
      context,
      'Impossible d\'ouvrir le dossier. Chemin : $chemin',
      type: ToastType.error,
    );
  }
}

/// Les 4 colonnes demandées : Fichier · Date · Table · Action.
class _Tableau extends StatelessWidget {
  const _Tableau({required this.vm});

  final SauvegardesViewModel vm;

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
          child: const Row(
            children: [
              _Entete('FICHIER', flex: 5),
              _Entete('DATE', flex: 3),
              _Entete('TABLE', flex: 3),
              _Entete('ACTION', flex: 3, alignement: TextAlign.right),
            ],
          ),
        ),
        for (var i = 0; i < vm.sauvegardes.length; i++)
          _Ligne(sauvegarde: vm.sauvegardes[i], zebre: i.isOdd, vm: vm),
      ],
    );
  }
}

class _Entete extends StatelessWidget {
  const _Entete(
    this.libelle, {
    required this.flex,
    this.alignement = TextAlign.left,
  });

  final String libelle;
  final int flex;
  final TextAlign alignement;

  @override
  Widget build(BuildContext context) => Expanded(
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
    required this.sauvegarde,
    required this.zebre,
    required this.vm,
  });

  final FichierSauvegarde sauvegarde;
  final bool zebre;
  final SauvegardesViewModel vm;

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
            child: Row(
              children: [
                Icon(
                  sauvegarde.estBaseComplete
                      ? Symbols.database
                      : Symbols.table_view,
                  size: 16,
                  color: AppColors.brandNavy,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    sauvegarde.nom,
                    overflow: TextOverflow.ellipsis,
                    style: _texte.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  sauvegarde.taille,
                  style: _texte.copyWith(
                    fontSize: 11,
                    color: AppColors.outline,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${Formats.date(sauvegarde.date)} '
              '${Formats.heure(sauvegarde.date)}',
              style: _texte,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              sauvegarde.portee,
              overflow: TextOverflow.ellipsis,
              style: sauvegarde.estBaseComplete
                  ? _texte.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandNavy,
                    )
                  : _texte.copyWith(fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Une restauration ne concerne qu'une base complete :
                // remettre en place l'export d'UNE table laisserait les autres
                // dans l'etat d'aujourd'hui, et la base serait incoherente.
                if (sauvegarde.estBaseComplete)
                  IconButton(
                    icon: const Icon(Symbols.settings_backup_restore, size: 18),
                    color: AppColors.errorDeep,
                    tooltip: 'Restaurer cette sauvegarde',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _confirmerRestauration(context),
                  ),
                IconButton(
                  icon: const Icon(Symbols.download, size: 18),
                  color: AppColors.brandNavy,
                  // Le fichier est deja sur la machine : « telecharger » n'a
                  // pas de sens, le montrer la ou il est en a un.
                  tooltip: 'Ouvrir l\'emplacement du fichier',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ouvrirDansExplorateur(
                    context,
                    sauvegarde.chemin,
                    selectionner: true,
                  ),
                ),
                IconButton(
                  icon: const Icon(Symbols.delete, size: 18),
                  color: AppColors.outline,
                  tooltip: 'Supprimer ce fichier',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmerSuppression(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Met la restauration en attente, apres un avertissement sans ambiguite.
  ///
  /// La bascule ne se fait pas ici : la base est ouverte, la remplacer sous une
  /// connexion vivante produirait au mieux une erreur. Le fichier est mis en
  /// attente et applique au demarrage suivant, avant toute ouverture.
  Future<void> _confirmerRestauration(BuildContext context) async {
    final service = context.read<ServiceRestauration>();

    // Le controle a lieu AVANT d'annoncer quoi que ce soit : proposer de
    // restaurer un fichier illisible, puis echouer au redemarrage, serait le
    // pire moment pour l'apprendre.
    final controle = service.verifier(File(sauvegarde.chemin));
    if (controle case Echec<int>(:final message)) {
      if (!context.mounted) return;
      showAppToast(context, message, type: ToastType.error);
      return;
    }

    if (!context.mounted) return;
    final confirme = await AppModal.show<bool>(
      context,
      title: 'Restaurer cette sauvegarde ?',
      maxWidth: 460,
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Symbols.settings_backup_restore,
              size: 44,
              color: AppColors.errorDeep,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              sauvegarde.nom,
              textAlign: TextAlign.center,
              style: _texte.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '${Formats.date(sauvegarde.date)} à ${Formats.heure(sauvegarde.date)}'
              ' · ${sauvegarde.taille}',
              textAlign: TextAlign.center,
              style: _texte.copyWith(color: AppColors.outline),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Text(
                'Toute la base sera remplacée par cette sauvegarde. Les '
                'ventes, saisies et écritures enregistrées DEPUIS cette date '
                'seront perdues.',
                style: _texte.copyWith(color: AppColors.errorDeep),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'La base actuelle sera d\'abord conservée dans le dossier des '
              'sauvegardes : cette opération reste réversible.\n\n'
              'La restauration s\'appliquera au prochain démarrage — '
              'l\'application ne peut pas remplacer sa propre base pendant '
              'qu\'elle l\'utilise.',
              style: _texte.copyWith(color: AppColors.outline),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Annuler',
                  variant: AppButtonVariant.outline,
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppButton(
                  label: 'Restaurer',
                  variant: AppButtonVariant.danger,
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirme != true || !context.mounted) return;

    final resultat = await service.preparer(File(sauvegarde.chemin));
    if (!context.mounted) return;

    switch (resultat) {
      case Succes<void>():
        await _inviterAuRedemarrage(context);
      case Echec<void>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }

  /// Propose de fermer l'application pour que la restauration s'applique.
  Future<void> _inviterAuRedemarrage(BuildContext context) async {
    final fermer = await AppModal.show<bool>(
      context,
      title: 'Redémarrage nécessaire',
      maxWidth: 420,
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'La sauvegarde est prête à être restaurée. Elle sera appliquée '
              'à la prochaine ouverture de LogiALVIA.',
              style: _texte,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tant que vous n\'avez pas redémarré, rien n\'est modifié : '
              'vous pouvez continuer à travailler, mais les saisies faites '
              'd\'ici là seront remplacées.',
              style: _texte.copyWith(color: AppColors.outline),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Plus tard',
                  variant: AppButtonVariant.outline,
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppButton(
                  label: 'Fermer maintenant',
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (fermer == true) await windowManager.destroy();
  }

  Future<void> _confirmerSuppression(BuildContext context) async {
    final confirme = await AppModal.show<bool>(
      context,
      title: 'Supprimer ${sauvegarde.nom} ?',
      maxWidth: 480,
      child: Text(
        sauvegarde.estBaseComplete
            ? 'C\'est une copie complète de la base. Si c\'est la seule, '
                  'l\'exploitation ne pourra plus être restaurée après un '
                  'incident.'
            : 'C\'est un export de la table « ${sauvegarde.portee} ». Le '
                  'fichier est supprimé du disque, les données de '
                  'l\'application ne sont pas touchées.',
        style: _texte.copyWith(height: 1.5),
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
            label: 'Supprimer',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ),
      ],
    );

    if (confirme != true || !context.mounted) return;
    final resultat = await vm.supprimer(sauvegarde);
    if (!context.mounted) return;
    switch (resultat) {
      case Succes():
        showAppToast(context, 'Fichier supprimé.');
      case Echec(:final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}
