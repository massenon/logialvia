import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/carte_kpi_lisere.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import 'documents_comptables.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import '../../data/repositories/comptabilite_repository_drift.dart';
import '../../domain/entities/comptabilite.dart';
import '../../domain/services/moteur_comptable.dart';
import '../viewmodels/comptabilite_view_model.dart';
import 'widgets/communs_compta.dart';
import '../../../core/saisie/formats_saisie.dart';

/// Journal Comptable — Doc F6 §1, fidèle à `journal-comptable.html`.
///
/// ## ÉCART_DELIBERE — disposition du tableau
///
/// Le prototype affiche **une ligne par pièce** avec deux colonnes « Débit » et
/// « Crédit » contenant chacune un *nom de compte*, plus une colonne
/// « Montant ». Cette disposition ne sait représenter qu'une pièce à exactement
/// deux lignes.
///
/// Or les écritures automatiques du système en comptent trois ou quatre : une
/// vente partiellement réglée génère 531 (débit) + 411 (débit) / 701 (crédit) +
/// 707 (crédit). La colonne « Débit » du prototype devrait alors contenir deux
/// comptes et la colonne « Montant » deux montants — c'est impossible.
///
/// Le tableau adopte donc la disposition d'un journal comptable professionnel
/// (SAGE, PERFECTO) : **une ligne par ligne d'écriture**, groupée par pièce,
/// avec les colonnes N° Pièce / Date / Compte / Libellé / Débit / Crédit. Les
/// totaux et le contrôle d'équilibre du prototype sont conservés à l'identique.
class JournalComptableScreen extends StatelessWidget {
  const JournalComptableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ComptabiliteViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.menu_book,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Journal Comptable',
                  style: AppTypography.pageTitle,
                ),
              ),
              SelecteurExercice(vm: vm),
              const SizedBox(width: AppSpacing.md),
              BoutonExportPdf(
                construire: () => DocumentsComptables.journal(vm),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Nouvelle Écriture',
                cibleTour: 'bouton-nouvelle-ecriture',
                icon: Symbols.add,
                onPressed: vm.exerciceEstCloture
                    ? null
                    : () => _ouvrirModaleEcriture(context, vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Écritures automatiques (ventes, achats) et saisie manuelle '
            'd\'opérations diverses.',
            style: texteCompta.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.lg),
          _KpisJournal(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Écritures de l\'exercice ${vm.exercice}',
            cibleTour: 'tableau-journal',
            icone: Symbols.receipt_long,
            action: _FiltresJournal(vm: vm),
            child: vm.journalFiltre.isEmpty
                ? EtatVide(
                    message: vm.ecritures.isEmpty
                        ? 'Aucune écriture sur l\'exercice ${vm.exercice}. '
                              'Chaque vente et chaque achat enregistré ailleurs '
                              'dans l\'application génère automatiquement son '
                              'écriture ici — rien à ressaisir.'
                        : 'Aucune écriture ne correspond à ces critères.',
                  )
                : _TableauJournal(vm: vm),
          ),
        ],
      ),
    );
  }
}

class _KpisJournal extends StatelessWidget {
  const _KpisJournal({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final equilibre =
        (vm.totalDebitJournal - vm.totalCreditJournal).abs() <
        EcritureValidator.tolerance;

    return Row(
      children: [
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Total Débit (Période)',
            valeur: Formats.montant(vm.totalDebitJournal),
            accent: AppColors.brandNavy,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Total Crédit (Période)',
            valeur: Formats.montant(vm.totalCreditJournal),
            accent: AppColors.brandGold,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: equilibre
                  ? AppColors.successContainer
                  : AppColors.errorContainer,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(
                color: (equilibre ? AppColors.successDeep : AppColors.errorDeep)
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ÉQUILIBRE',
                  style: AppTypography.label.copyWith(
                    color: equilibre
                        ? AppColors.successDeep
                        : AppColors.errorDeep,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(
                      equilibre ? Symbols.check_circle : Symbols.error,
                      size: 18,
                      color: equilibre
                          ? AppColors.successDeep
                          : AppColors.errorDeep,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        equilibre
                            ? 'Équilibré'
                            : 'Écart de '
                                  '${Formats.montant((vm.totalDebitJournal - vm.totalCreditJournal).abs())}',
                        style: AppTypography.kpiValue.copyWith(
                          fontSize: 18,
                          color: equilibre
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
        ),
      ],
    );
  }
}

class _FiltresJournal extends StatelessWidget {
  const _FiltresJournal({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 240,
          child: TextFormField(
            initialValue: vm.rechercheJournal,
            style: texteCompta,
            decoration: decorationCompta.copyWith(
              hintText: 'Libellé, compte, n° de pièce…',
              prefixIcon: const Icon(
                Symbols.search,
                size: 18,
                color: AppColors.outline,
              ),
            ),
            onChanged: vm.definirRechercheJournal,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: vm.filtreJournalCode,
            isDense: true,
            style: texteCompta,
            hint: const Text('Journal : Tous', style: texteCompta),
            items: [
              const DropdownMenuItem<String?>(
                child: Text('Journal : Tous', style: texteCompta),
              ),
              for (final code in CodeJournal.tous)
                DropdownMenuItem<String?>(
                  value: code,
                  child: Text(
                    '$code — ${CodeJournal.libelles[code]}',
                    style: texteCompta,
                  ),
                ),
            ],
            onChanged: vm.definirFiltreJournal,
          ),
        ),
      ],
    );
  }
}

class _TableauJournal extends StatelessWidget {
  const _TableauJournal({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final lignes = vm.journalFiltre;

    // Groupement par piece : les lignes d'une meme piece sont contigues et
    // partagent une bordure haute, comme dans un journal papier.
    String? pieceCourante;

    return Column(
      children: [
        const EnteteCompta(
          colonnes: [
            ('N° PIÈCE', 2, TextAlign.left),
            ('DATE', 2, TextAlign.left),
            ('JAL', 1, TextAlign.left),
            ('COMPTE', 3, TextAlign.left),
            ('LIBELLÉ', 5, TextAlign.left),
            ('DÉBIT', 2, TextAlign.right),
            ('CRÉDIT', 2, TextAlign.right),
            ('', 1, TextAlign.right),
          ],
        ),
        for (var i = 0; i < lignes.length; i++)
          () {
            final e = lignes[i];
            final nouvellePiece = e.numeroPiece != pieceCourante;
            pieceCourante = e.numeroPiece;
            return _LigneJournal(
              ecriture: e,
              vm: vm,
              zebre: i.isOdd,
              premiereDeLaPiece: nouvellePiece,
            );
          }(),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          color: AppColors.brandNavy,
          child: Row(
            children: [
              Expanded(
                flex: 13,
                child: Text(
                  'TOTAUX',
                  style: grasCompta.copyWith(color: Colors.white),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  Formats.nombre(vm.totalDebitJournal),
                  textAlign: TextAlign.right,
                  style: grasCompta.copyWith(
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  Formats.nombre(vm.totalCreditJournal),
                  textAlign: TextAlign.right,
                  style: grasCompta.copyWith(
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ],
    );
  }
}

class _LigneJournal extends StatelessWidget {
  const _LigneJournal({
    required this.ecriture,
    required this.vm,
    required this.zebre,
    required this.premiereDeLaPiece,
  });

  final Ecriture ecriture;
  final ComptabiliteViewModel vm;
  final bool zebre;
  final bool premiereDeLaPiece;

  @override
  Widget build(BuildContext context) {
    CompteComptable? compte;
    for (final c in vm.plan) {
      if (c.numero == ecriture.numeroCompte) compte = c;
    }

    return Container(
      decoration: premiereDeLaPiece
          ? const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.outlineVariant, width: 2),
              ),
            )
          : null,
      child: LigneCompta(
        zebre: zebre,
        cellules: [
          (
            Row(
              children: [
                Flexible(
                  child: Text(
                    premiereDeLaPiece ? (ecriture.numeroPiece ?? '—') : '',
                    style: texteCompta.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (premiereDeLaPiece && ecriture.isLocked) ...[
                  const SizedBox(width: AppSpacing.xs),
                  const Tooltip(
                    message: 'Exercice clôturé — écriture verrouillée',
                    child: Icon(
                      Symbols.lock,
                      size: 13,
                      color: AppColors.outline,
                    ),
                  ),
                ],
              ],
            ),
            2,
          ),
          (
            Text(
              premiereDeLaPiece ? Formats.date(ecriture.date) : '',
              style: texteCompta,
            ),
            2,
          ),
          (
            Text(
              ecriture.journalCode,
              style: texteCompta.copyWith(color: AppColors.outline),
            ),
            1,
          ),
          (
            Text(
              '${ecriture.numeroCompte} — ${compte?.libelle ?? 'Compte inconnu'}',
              style: texteCompta,
              overflow: TextOverflow.ellipsis,
            ),
            3,
          ),
          (
            Row(
              children: [
                Flexible(
                  child: Text(
                    ecriture.libelle,
                    style: texteCompta,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ecriture.estAutomatique) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Tooltip(
                    message:
                        'Écriture générée automatiquement par '
                        '${ecriture.venteRef ?? ecriture.achatRef}',
                    child: const Icon(
                      Symbols.bolt,
                      size: 14,
                      color: AppColors.brandGold,
                    ),
                  ),
                ],
              ],
            ),
            5,
          ),
          (
            Text(
              montantOuTiret(ecriture.debit),
              textAlign: TextAlign.right,
              style: montantCompta,
            ),
            2,
          ),
          (
            Text(
              montantOuTiret(ecriture.credit),
              textAlign: TextAlign.right,
              style: montantCompta,
            ),
            2,
          ),
          (
            premiereDeLaPiece && !ecriture.estAutomatique && !ecriture.isLocked
                ? Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(
                        Symbols.delete,
                        size: 18,
                        color: AppColors.outline,
                      ),
                      tooltip: 'Supprimer la pièce',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _confirmerSuppression(context, vm, ecriture),
                    ),
                  )
                : const SizedBox.shrink(),
            1,
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmerSuppression(
  BuildContext context,
  ComptabiliteViewModel vm,
  Ecriture ecriture,
) async {
  final piece = ecriture.numeroPiece;
  if (piece == null) return;

  final confirme = await AppModal.show<bool>(
    context,
    title: 'Supprimer la pièce $piece ?',
    child: Text(
      'Toutes les lignes de cette pièce seront supprimées, pas seulement '
      'celle-ci : une pièce ne peut pas rester à moitié saisie sans '
      'déséquilibrer la balance.\n\nCette action est irréversible.',
      style: texteCompta.copyWith(height: 1.5),
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

  final resultat = await vm.supprimerPiece(piece);
  if (!context.mounted) return;

  switch (resultat) {
    case Succes():
      showAppToast(context, 'Pièce $piece supprimée.');
    case Echec(:final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

/// Modale « Nouvelle Écriture (Opération Diverse) » — fidèle à
/// `journal-comptable.html` l.5-42 du bloc modale : **un** compte à débiter,
/// **un** compte à créditer, **un** montant. « Le même montant est appliqué au
/// Débit et au Crédit — l'équilibre est garanti par construction. »
Future<void> _ouvrirModaleEcriture(
  BuildContext context,
  ComptabiliteViewModel vm,
) async {
  final libelleCtrl = TextEditingController();
  final montantCtrl = TextEditingController();
  final comptes = vm.planActif;
  if (comptes.isEmpty) {
    showAppToast(
      context,
      'Le plan comptable est vide : aucune écriture ne peut être saisie.',
      type: ToastType.error,
    );
    return;
  }

  var compteDebit = comptes
      .firstWhere((c) => c.numero == '531', orElse: () => comptes.first)
      .numero;
  var compteCredit = comptes
      .firstWhere((c) => c.numero == '701', orElse: () => comptes.last)
      .numero;
  var date = DateTime.now();

  await AppModal.show<void>(
    context,
    title: 'Nouvelle Écriture (Opération Diverse)',
    maxWidth: 520,
    child: StatefulBuilder(
      builder: (ctx, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('DATE', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          InkWell(
            onTap: () async {
              final choix = await showDatePicker(
                context: ctx,
                initialDate: date,
                firstDate: DateTime(vm.exercice),
                lastDate: DateTime(vm.exercice, 12, 31),
                locale: const Locale('fr', 'FR'),
              );
              if (choix != null) setState(() => date = choix);
            },
            child: InputDecorator(
              decoration: decorationCompta,
              child: Row(
                children: [
                  Expanded(child: Text(Formats.date(date), style: texteCompta)),
                  const Icon(
                    Symbols.calendar_month,
                    size: 18,
                    color: AppColors.outline,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('LIBELLÉ', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: libelleCtrl,
            style: texteCompta,
            decoration: decorationCompta.copyWith(
              hintText: 'Ex. Régularisation caisse',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SelecteurCompte(
                  libelle: 'COMPTE À DÉBITER',
                  comptes: comptes,
                  valeur: compteDebit,
                  onChange: (v) => setState(() => compteDebit = v),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _SelecteurCompte(
                  libelle: 'COMPTE À CRÉDITER',
                  comptes: comptes,
                  valeur: compteCredit,
                  onChange: (v) => setState(() => compteCredit = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('MONTANT (FCFA)', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: montantCtrl,
            style: grasCompta,
            keyboardType: TextInputType.number,
            inputFormatters: FormatteursSaisie.montant,
            decoration: decorationCompta,
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceZebra,
              borderRadius: AppRadius.cardRadius,
            ),
            child: Text(
              'Le même montant est appliqué au Débit et au Crédit — '
              'l\'équilibre est garanti par construction, pas de saisie '
              'séparée possible.',
              style: texteCompta.copyWith(
                fontSize: 11,
                color: AppColors.outline,
                height: 1.5,
              ),
            ),
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
          label: 'Enregistrer l\'Écriture',
          onPressed: () async {
            final libelle = libelleCtrl.text.trim();
            final montant = double.tryParse(
              montantCtrl.text.trim().replaceAll(',', '.'),
            );

            if (libelle.isEmpty || montant == null || montant <= 0) {
              showAppToast(
                ctx,
                'Veuillez renseigner le libellé et un montant valide.',
                type: ToastType.error,
              );
              return;
            }
            if (compteDebit == compteCredit) {
              showAppToast(
                ctx,
                'Le compte Débit et le compte Crédit ne peuvent pas être '
                'identiques.',
                type: ToastType.error,
              );
              return;
            }

            final piece = vm.prochainNumeroPiece('OD');
            final resultat = await vm.enregistrerPiece(
              date: date,
              journalCode: CodeJournal.operationsDiverses,
              numeroPiece: piece,
              lignes: [
                LigneAEcrire(
                  numeroCompte: compteDebit,
                  debit: montant,
                  credit: 0,
                  libelle: libelle,
                ),
                LigneAEcrire(
                  numeroCompte: compteCredit,
                  debit: 0,
                  credit: montant,
                  libelle: libelle,
                ),
              ],
            );

            if (!ctx.mounted) return;
            switch (resultat) {
              case Succes():
                Navigator.of(ctx).pop();
                showAppToast(
                  ctx,
                  'Écriture $piece enregistrée — Débit $compteDebit / '
                  'Crédit $compteCredit.',
                );
              case Echec(:final message):
                showAppToast(ctx, message, type: ToastType.error);
            }
          },
        ),
      ),
    ],
  );

  libelleCtrl.dispose();
  montantCtrl.dispose();
}

class _SelecteurCompte extends StatelessWidget {
  const _SelecteurCompte({
    required this.libelle,
    required this.comptes,
    required this.valeur,
    required this.onChange,
  });

  final String libelle;
  final List<CompteComptable> comptes;
  final String valeur;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(libelle, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String>(
          initialValue: valeur,
          isExpanded: true,
          style: texteCompta,
          decoration: decorationCompta,
          items: [
            for (final c in comptes)
              DropdownMenuItem(
                value: c.numero,
                child: Text(
                  '${c.numero} - ${c.libelle}',
                  style: texteCompta,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChange(v);
          },
        ),
      ],
    );
  }
}
