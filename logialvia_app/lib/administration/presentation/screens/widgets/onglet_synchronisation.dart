import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/sync/depot_etat_synchronisation.dart';
import '../../../../core/sync/moteur_synchronisation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/carte_section.dart';
import '../../viewmodels/synchronisation_view_model.dart';

const TextStyle _texte = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

const TextStyle _petit = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 11,
  color: AppColors.outline,
);

const TextStyle _entete = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: AppColors.outline,
);

String _horodatage(DateTime? d) =>
    d == null ? 'Jamais' : '${Formats.date(d)} à ${Formats.heure(d)}';

/// Onglet « Synchronisation » : quatre blocs — l'état du poste, l'historique des
/// tentatives, les lignes refusées par le serveur, la cohérence.
class OngletSynchronisation extends StatelessWidget {
  const OngletSynchronisation({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SynchronisationViewModel>();
    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EtatDuPoste(vm: vm),
        const SizedBox(height: AppSpacing.md),
        _Historique(vm: vm),
        const SizedBox(height: AppSpacing.md),
        _Conflits(vm: vm),
        const SizedBox(height: AppSpacing.md),
        _Coherence(vm: vm),
      ],
    );
  }
}

class _EtatDuPoste extends StatelessWidget {
  const _EtatDuPoste({required this.vm});

  final SynchronisationViewModel vm;

  @override
  Widget build(BuildContext context) {
    final aJour = vm.enAttente == 0;
    final couleur = aJour ? AppColors.successDeep : AppColors.brandGold;

    return CarteSection(
      titre: 'État du poste',
      icone: Symbols.cloud_sync,
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            key: const Key('synchro-en-attente'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.12),
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: couleur),
            ),
            child: Column(
              children: [
                Text(
                  '${vm.enAttente}',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: couleur,
                  ),
                ),
                Text(
                  aJour ? 'EN ATTENTE · À JOUR' : 'EN ATTENTE',
                  style: _entete.copyWith(color: couleur),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dernière réception : ${_horodatage(vm.derniereReception)}',
                style: _texte,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Dernier envoi : ${_horodatage(vm.dernierEnvoi)}',
                style: _texte,
              ),
            ],
          ),
          AppButton(
            key: const Key('bouton-synchroniser'),
            label: vm.synchronisationEnCours
                ? 'Synchronisation…'
                : 'Synchroniser',
            icon: Symbols.sync,
            onPressed: vm.synchronisationEnCours ? null : vm.synchroniser,
          ),
        ],
      ),
    );
  }
}

class _Historique extends StatelessWidget {
  const _Historique({required this.vm});

  final SynchronisationViewModel vm;

  Future<void> _exporter(BuildContext context) async {
    try {
      final fichier = await vm.exporterJournal();
      if (!context.mounted) return;
      showAppToast(
        context,
        'Journal exporté : ${fichier.path}',
        type: ToastType.success,
      );
    } on Object {
      if (!context.mounted) return;
      showAppToast(
        context,
        'Impossible d\'exporter le journal.',
        type: ToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Historique des 10 dernières tentatives',
      icone: Symbols.history,
      action: AppButton(
        key: const Key('exporter-journal'),
        label: 'Exporter le journal',
        icon: Symbols.download,
        variant: AppButtonVariant.outline,
        onPressed: () => _exporter(context),
      ),
      child: vm.historique.isEmpty
          ? const EtatVide(
              message:
                  'Aucune tentative enregistrée : le journal se remplit à '
                  'chaque synchronisation de ce poste.',
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const Key('synchro-historique'),
                headingRowHeight: 32,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 34,
                columns: const [
                  DataColumn(label: Text('Date', style: _entete)),
                  DataColumn(label: Text('Déclencheur', style: _entete)),
                  DataColumn(
                    label: Text('Reçus', style: _entete),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text('Envoyés', style: _entete),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text('Refusés', style: _entete),
                    numeric: true,
                  ),
                  DataColumn(label: Text('Statut', style: _entete)),
                ],
                rows: [
                  for (final j in vm.historique)
                    DataRow(
                      cells: [
                        DataCell(Text(_horodatage(j.debutLe), style: _texte)),
                        DataCell(
                          Text(
                            libelleDeclencheur(j.declencheur),
                            style: _texte,
                          ),
                        ),
                        DataCell(Text('${j.recues}', style: _texte)),
                        DataCell(Text('${j.envoyees}', style: _texte)),
                        DataCell(Text('${j.refusees}', style: _texte)),
                        DataCell(_Pastille(issue: j.issue, message: j.message)),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.issue, required this.message});

  final String issue;
  final String message;

  @override
  Widget build(BuildContext context) {
    final (fond, texte) = switch (issue) {
      'terminee' => (AppColors.successContainer, AppColors.successDeep),
      'horsLigne' => (AppColors.surfaceZebra, AppColors.outline),
      _ => (AppColors.errorContainer, AppColors.errorDeep),
    };

    return Tooltip(
      message: message,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: fond, borderRadius: AppRadius.pill),
        child: Text(
          libelleIssue(issue),
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: texte,
          ),
        ),
      ),
    );
  }
}

class _Conflits extends StatelessWidget {
  const _Conflits({required this.vm});

  final SynchronisationViewModel vm;

  Future<void> _remettre(
    BuildContext context, {
    String? table,
    String? id,
  }) async {
    await vm.remettreEnFile(table: table, id: id);
    if (!context.mounted || vm.message == null) return;
    showAppToast(context, vm.message!);
  }

  @override
  Widget build(BuildContext context) {
    final lignes = vm.refusees;

    return CarteSection(
      titre: 'Refusés par le serveur',
      icone: Symbols.block,
      couleurIcone: lignes.isEmpty ? null : AppColors.errorDeep,
      action: lignes.isEmpty
          ? null
          : AppButton(
              key: const Key('remettre-tout-en-file'),
              label: vm.filtreTable == null
                  ? 'Tout remettre en file'
                  : 'Remettre la table en file',
              icon: Symbols.replay,
              variant: AppButtonVariant.outline,
              onPressed: () => _remettre(context, table: vm.filtreTable),
            ),
      child: lignes.isEmpty && vm.tablesRefusees.isEmpty
          ? const EtatVide(
              message:
                  'Aucune ligne refusée : tout ce que ce poste a envoyé a été '
                  'accepté par le serveur.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    FilterChip(
                      key: const Key('filtre-refus-toutes'),
                      label: const Text('Toutes'),
                      selected: vm.filtreTable == null,
                      onSelected: (_) => vm.filtrer(null),
                    ),
                    for (final t in vm.tablesRefusees)
                      FilterChip(
                        key: Key('filtre-refus-$t'),
                        label: Text(DepotEtatSynchronisation.libelleTable(t)),
                        selected: vm.filtreTable == t,
                        onSelected: (_) => vm.filtrer(t),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final l in lignes)
                  Container(
                    key: Key('refus-${l.table}-${l.id}'),
                    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer.withValues(alpha: 0.5),
                      borderRadius: AppRadius.cardRadius,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${l.libelleTable} · ${l.designation}',
                                style: _texte.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(l.motif, style: _petit),
                            ],
                          ),
                        ),
                        if (l.remisePossible)
                          AppButton(
                            label: 'Remettre en file',
                            icon: Symbols.replay,
                            variant: AppButtonVariant.outline,
                            onPressed: () =>
                                _remettre(context, table: l.table, id: l.id),
                          )
                        else
                          const Text(
                            'À refaire depuis Comptabilité',
                            style: _petit,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Coherence extends StatelessWidget {
  const _Coherence({required this.vm});

  final SynchronisationViewModel vm;

  @override
  Widget build(BuildContext context) {
    final verifiee = vm.coherenceVerifieeLe;
    final ecarts = vm.parTable.where((e) => !e.conforme).length;

    return CarteSection(
      titre: 'Cohérence',
      icone: Symbols.fact_check,
      action: AppButton(
        key: const Key('verifier-coherence'),
        label: 'Vérifier la cohérence',
        icon: Symbols.rule,
        variant: AppButtonVariant.outline,
        onPressed: vm.verifierCoherence,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recompte, table par table, les lignes de ce poste selon leur état '
            '(en attente, synchronisées, refusées), puis demande au serveur ce '
            'qu\'il a de plus récent que le dernier tirage de ce poste. Les '
            'saisies que ce poste vient d\'envoyer reviennent au tirage '
            'suivant : elles comptent comme « à recevoir ».',
            style: _petit,
          ),
          if (verifiee != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              key: const Key('coherence-resume'),
              ecarts == 0
                  ? 'Conforme · vérifié à ${Formats.heure(verifiee)} : aucune '
                        'ligne refusée.'
                  : '$ecarts table(s) avec des lignes refusées · vérifié à '
                        '${Formats.heure(verifiee)}.',
              style: _texte.copyWith(
                fontWeight: FontWeight.w700,
                color: ecarts == 0
                    ? AppColors.successDeep
                    : AppColors.errorDeep,
              ),
            ),
            if (vm.coherenceServeur != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _VerdictServeur(reponse: vm.coherenceServeur!),
            ],
            const SizedBox(height: AppSpacing.xs),
            if (vm.parTable.isEmpty)
              const EtatVide(
                message: 'Aucune donnée à contrôler pour le moment.',
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  key: const Key('coherence-tableau'),
                  headingRowHeight: 32,
                  dataRowMinHeight: 30,
                  dataRowMaxHeight: 30,
                  columns: const [
                    DataColumn(label: Text('Table', style: _entete)),
                    DataColumn(
                      label: Text('En attente', style: _entete),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text('Synchronisées', style: _entete),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text('Refusées', style: _entete),
                      numeric: true,
                    ),
                    DataColumn(label: Text('État', style: _entete)),
                  ],
                  rows: [
                    for (final e in vm.parTable)
                      DataRow(
                        cells: [
                          DataCell(Text(e.libelle, style: _texte)),
                          DataCell(Text('${e.enAttente}', style: _texte)),
                          DataCell(Text('${e.synchronisees}', style: _texte)),
                          DataCell(Text('${e.refusees}', style: _texte)),
                          DataCell(
                            Text(
                              e.conforme
                                  ? 'Conforme'
                                  : '${e.refusees} écart(s)',
                              style: _texte.copyWith(
                                fontWeight: FontWeight.w700,
                                color: e.conforme
                                    ? AppColors.successDeep
                                    : AppColors.errorDeep,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Ce que le serveur dit de ce poste : à jour, ou N lignes plus récentes à recevoir.
class _VerdictServeur extends StatelessWidget {
  const _VerdictServeur({required this.reponse});

  final ReponseCoherence reponse;

  @override
  Widget build(BuildContext context) {
    final (texte, couleur) = switch (reponse) {
      ReponseCoherence(repondu: false, :final issue) => (
        switch (issue) {
          IssueSynchronisation.horsLigne =>
            'Serveur injoignable : contrôle local seulement.',
          IssueSynchronisation.nonAppairee =>
            'Poste non appairé : contrôle local seulement.',
          IssueSynchronisation.revoque =>
            'Jeton refusé par le serveur : réappairez ce poste.',
          _ => 'Le serveur n\'a pas pu répondre : contrôle local seulement.',
        },
        AppColors.outline,
      ),
      ReponseCoherence(jamaisSynchronise: true) => (
        'Serveur : ce poste n\'a jamais reçu de tirage complet. Lancez '
            '« Synchroniser ».',
        AppColors.errorDeep,
      ),
      ReponseCoherence(aJour: true) => (
        'Serveur : à jour, rien de plus récent que le dernier tirage de ce poste.',
        AppColors.successDeep,
      ),
      _ => (
        'Serveur : ${reponse.total} ligne(s) plus récente(s) à recevoir '
            '(${reponse.retard.entries.map((e) => '${DepotEtatSynchronisation.libelleTable(e.key)} : ${e.value}').join(', ')}). '
            'Lancez « Synchroniser ».',
        AppColors.brandGold,
      ),
    };

    return Text(
      texte,
      key: const Key('coherence-serveur'),
      style: _texte.copyWith(fontWeight: FontWeight.w700, color: couleur),
    );
  }
}
