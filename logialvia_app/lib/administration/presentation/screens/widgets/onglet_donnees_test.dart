import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/resultat/resultat.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/carte_section.dart';
import '../../../data/seed/seed_demonstration.dart';
import '../../../domain/services/service_reinitialisation.dart';
import '../../viewmodels/auth_view_model.dart';
import '../../viewmodels/corbeille_view_model.dart';
import '../../viewmodels/parametres_generaux_view_model.dart';

const TextStyle _texte = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

/// Onglet « Données de Test » — remise à zéro de l'activité.
///
/// ## Deux verrous, pas un
///
/// 1. Le **mode « Données de Test »** doit être activé dans Modules Actifs. Il
///    est faux par défaut : sur un poste partagé entre trois rôles, laisser
///    une remise à zéro accessible en permanence, c'est attendre l'accident.
/// 2. L'utilisatrice doit être **administratrice**.
///
/// Le second sans le premier ne suffirait pas : la Gérante *est*
/// administratrice, et c'est justement son exploitation qu'il faut protéger.
class OngletDonneesTest extends StatelessWidget {
  const OngletDonneesTest({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CorbeilleViewModel>();
    final parametres = context.watch<ParametresGenerauxViewModel>();
    final estAdmin = context.read<AuthViewModel>().session?.role.id == 'admin';
    final modeActif = parametres.parametres.modeDonneesTest;

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BandeauVerrou(modeActif: modeActif, estAdmin: estAdmin),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Réinitialisation des données de test',
          icone: Symbols.restart_alt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _CeQuiEstEfface(),
              const SizedBox(height: AppSpacing.md),
              _Apercu(vm: vm),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Peupler AVANT de reinitialiser : c'est l'ordre dans lequel
                  // on s'en sert. Un ecran vide ne prouve presque rien, et
                  // c'est pour cela que ce bouton existe.
                  AppButton(
                    label: vm.enCours
                        ? 'Peuplement…'
                        : 'Peupler un mois de démonstration',
                    icon: Symbols.database,
                    variant: AppButtonVariant.outline,
                    onPressed: (!modeActif || !estAdmin || vm.enCours)
                        ? null
                        : () => _peupler(context, vm, estAdmin, modeActif),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppButton(
                    label: vm.enCours
                        ? 'Réinitialisation…'
                        : 'Réinitialiser les données',
                    icon: Symbols.restart_alt,
                    variant: AppButtonVariant.danger,
                    onPressed: (!modeActif || !estAdmin || vm.enCours)
                        ? null
                        : () => _confirmer(context, vm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Peuple un mois d'activite credible, apres avertissement.
  ///
  /// L'avertissement n'est pas de la ceremonie : ces lignes ressemblent a de
  /// vraies ventes et a de vraies saisies. Sur une base en service, elles
  /// fausseraient la comptabilite sans que rien ne le signale — d'ou le meme
  /// double verrou que la remise a zero.
  Future<void> _peupler(
    BuildContext context,
    CorbeilleViewModel vm,
    bool estAdmin,
    bool modeActif,
  ) async {
    final confirme = await AppModal.show<bool>(
      context,
      title: 'Peupler un mois de d\u00e9monstration ?',
      maxWidth: 520,
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Trente jours d\'activit\u00e9 fictive vont \u00eatre \u00e9crits : clients, '
              'ventes comptant et \u00e0 cr\u00e9dit, mouvements de stock, fiches '
              'journali\u00e8res, lots de couveuse avec mirages et remplacement, '
              'soins et entr\u00e9es d\'infirmerie.',
              style: _texte,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Ces donn\u00e9es passent par les m\u00eames chemins que la saisie r\u00e9elle : '
              'les \u00e9critures comptables et les mouvements de stock sont donc '
              'g\u00e9n\u00e9r\u00e9s comme d\'habitude.',
              style: _texte.copyWith(color: AppColors.outline),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Text(
                'Elles s\'ajoutent \u00e0 ce qui existe d\u00e9j\u00e0. Sur une base en '
                'service, elles se m\u00e9langeraient \u00e0 la vraie activit\u00e9 : '
                '\u00ab R\u00e9initialiser les donn\u00e9es \u00bb est le seul moyen de les retirer.',
                style: _texte.copyWith(color: AppColors.errorDeep),
              ),
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
                  label: 'Peupler',
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirme != true || !context.mounted) return;

    final resultat = await vm.peuplerDemonstration(
      estAdmin: estAdmin,
      modeActif: modeActif,
    );
    if (!context.mounted) return;

    switch (resultat) {
      case Succes<BilanDemonstration>(valeur: final bilan):
        showAppToast(
          context,
          '${bilan.total} ligne(s) de d\u00e9monstration \u00e9crites : '
          '${bilan.lignesParTable.entries.map((e) => '${e.value} ${e.key}').join(', ')}.',
        );
      case Echec<BilanDemonstration>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }

  Future<void> _confirmer(BuildContext context, CorbeilleViewModel vm) async {
    final confirme = await AppModal.show<bool>(
      context,
      title: 'Réinitialiser toutes les données d\'activité ?',
      maxWidth: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Symbols.warning,
                    size: 22,
                    color: AppColors.errorDeep,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      vm.lignesAEffacer == 0
                          ? 'Aucune donnée d\'activité à effacer : '
                                'l\'application est déjà vierge.'
                          : '${vm.lignesAEffacer} ligne(s) seront effacées, '
                                'et cette opération est **irréversible** — '
                                'elle ne passe pas par la corbeille.',
                      style: _texte.copyWith(
                        color: AppColors.errorDeep,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Sera effacé — toute l\'activité enregistrée :',
              style: _texte.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final entree in vm.apercuReinitialisation.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    const Icon(
                      Symbols.remove,
                      size: 14,
                      color: AppColors.errorDeep,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: Text(entree.key, style: _texte)),
                    Text(
                      '${entree.value}',
                      style: _texte.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.successContainer,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Text(
                'Sera conservé : votre compte et ceux des agents, les rôles et '
                'permissions, les paramètres de l\'entreprise, le plan '
                'comptable, les barèmes de rationnement, les calendriers de '
                'prophylaxie, le catalogue, les intrants — et les journaux '
                'd\'audit.',
                style: _texte.copyWith(
                  color: AppColors.successDeep,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Générez une sauvegarde avant, depuis l\'onglet Sauvegardes : '
              'c\'est le seul moyen de revenir en arrière.',
              style: _texte.copyWith(color: AppColors.outline, height: 1.5),
            ),
          ],
        ),
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
            label: 'Réinitialiser',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ),
      ],
    );

    if (confirme != true || !context.mounted) return;

    // Qui efface est inscrit au journal d'audit : une remise a zero sans nom
    // ne se distingue pas d'un effacement de preuves.
    final session = context.read<AuthViewModel>().session;
    final resultat = await vm.reinitialiser(
      estAdmin: true,
      modeActif: true,
      parIdentifiant: session?.utilisateur.identifiant ?? 'inconnu',
    );
    if (!context.mounted) return;
    switch (resultat) {
      case Succes<BilanReinitialisation>(valeur: final bilan):
        showAppToast(
          context,
          '${bilan.lignesEffacees} ligne(s) effacées sur '
          '${bilan.tablesEffacees.length} table(s). Paramètres et comptes '
          'conservés.',
        );
      case Echec<BilanReinitialisation>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

class _BandeauVerrou extends StatelessWidget {
  const _BandeauVerrou({required this.modeActif, required this.estAdmin});

  final bool modeActif;
  final bool estAdmin;

  @override
  Widget build(BuildContext context) {
    final (fond, teinte, icone, message) = switch ((modeActif, estAdmin)) {
      (false, _) => (
        AppColors.surfaceZebra,
        AppColors.outline,
        Symbols.lock,
        'Onglet verrouillé. Le mode « Données de Test » est désactivé — '
            'activez-le dans l\'onglet Modules Actifs. Il est fermé par défaut '
            'pour qu\'une exploitation en service ne puisse pas être remise à '
            'zéro par accident.',
      ),
      (true, false) => (
        AppColors.errorContainer,
        AppColors.errorDeep,
        Symbols.lock,
        'Le mode « Données de Test » est actif, mais seule une '
            'administratrice peut réinitialiser les données.',
      ),
      (true, true) => (
        AppColors.errorContainer,
        AppColors.errorDeep,
        Symbols.warning,
        'Mode « Données de Test » ACTIF. La réinitialisation est possible '
            'depuis cet écran : refermez le mode dans Modules Actifs dès que '
            'la période d\'essai est terminée.',
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
                color: teinte,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CeQuiEstEfface extends StatelessWidget {
  const _CeQuiEstEfface();

  @override
  Widget build(BuildContext context) {
    return Text(
      'La réinitialisation efface ce qui décrit une **activité** — ventes, '
      'achats, écritures comptables, fiches journalières, lots d\'incubation, '
      'soins, mouvements de stock — et conserve ce qui décrit '
      'l\'**exploitation** : comptes, rôles, paramètres, plan comptable, '
      'barèmes, catalogue et intrants.\n\n'
      'Après elle, l\'application est prête à travailler ; elle n\'a '
      'simplement rien fait encore. Les journaux d\'audit sont conservés : une '
      'opération qui efface l\'activité et la trace de qui l\'a effacée ne '
      'serait pas une réinitialisation.',
      style: _texte.copyWith(height: 1.6, color: AppColors.outline),
    );
  }
}

class _Apercu extends StatelessWidget {
  const _Apercu({required this.vm});

  final CorbeilleViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (vm.apercuReinitialisation.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.successContainer,
          borderRadius: AppRadius.cardRadius,
        ),
        child: Text(
          'Aucune donnée d\'activité enregistrée : il n\'y a rien à '
          'réinitialiser.',
          style: _texte.copyWith(color: AppColors.successDeep),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'État actuel — ${vm.lignesAEffacer} ligne(s) d\'activité',
            style: _texte.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 4,
            children: [
              for (final entree in vm.apercuReinitialisation.entries)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    border: Border.all(color: AppColors.outlineVariant),
                    borderRadius: AppRadius.pill,
                  ),
                  child: Text(
                    '${entree.key} · ${entree.value}',
                    style: _texte.copyWith(fontSize: 11),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
