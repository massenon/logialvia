import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/formatage/formats.dart';
import '../../../../core/pdf/bouton_export_pdf.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../data/repositories/factures_mecef_repository_drift.dart';
import '../../../domain/entities/facture_mecef.dart';
import '../../../domain/entities/vente.dart';
import '../documents_commercial.dart';
import '../documents_mecef.dart';

/// La facture de la vente qui vient d'être encaissée.
///
/// ## Pourquoi une modale, et pas un simple message
///
/// Un message disparaît. Or c'est à cet instant précis — le client encore au
/// comptoir — que la facture se remet. La modale montre ce qui vient d'être
/// enregistré, et met le téléchargement à portée de clic.
///
/// Elle ne facture rien d'elle-même : émettre la pièce fiscale reste un geste
/// explicite. Un client sur deux ne demande pas de facture, et une facture
/// émise ne se supprime plus.
Future<void> ouvrirModaleFactureVente(
  BuildContext context,
  Vente vente, {
  required bool mecefActif,
}) async {
  final db = context.read<AppDatabase>();
  final depot = FacturesMecefRepositoryDrift(db);
  var facture = mecefActif ? await depot.pourVente(vente.reference) : null;

  if (!context.mounted) return;

  await AppModal.show<void>(
    context,
    title: 'Vente ${vente.reference} enregistrée',
    maxWidth: 560,
    child: StatefulBuilder(
      builder: (ctx, rafraichir) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Recapitulatif(vente: vente),
          if (mecefActif) ...[
            const SizedBox(height: AppSpacing.md),
            _BlocMecef(
              vente: vente,
              facture: facture,
              onEmise: (nouvelle) => rafraichir(() => facture = nouvelle),
            ),
          ],
        ],
      ),
    ),
    actions: [
      Builder(
        builder: (ctx) => BoutonExportPdf(
          libelle: 'Télécharger la facture',
          variante: AppButtonVariant.primary,
          // Construit au clic : si la facture MeCeF vient d'etre emise, c'est
          // elle qu'il faut imprimer, pas le recu de caisse.
          construire: () => facture != null
              ? DocumentsMecef.facture(facture!)
              : DocumentsCommercial.facture(vente),
        ),
      ),
    ],
  );
}

class _Recapitulatif extends StatelessWidget {
  const _Recapitulatif({required this.vente});

  final Vente vente;

  static const TextStyle _texte = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 12,
    color: AppColors.onSurface,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  vente.client,
                  style: _texte.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(Formats.date(vente.date), style: _texte),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final l in vente.lignes)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${Formats.nombre(l.quantite)} × ${l.nom}',
                      style: _texte,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(Formats.montant(l.total), style: _texte),
                ],
              ),
            ),
          const Divider(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total ${vente.mode}',
                  style: _texte.copyWith(color: AppColors.outline),
                ),
              ),
              Text(
                Formats.montant(vente.total),
                style: _texte.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Le bloc de conformité fiscale, quand le module MeCeF est actif.
class _BlocMecef extends StatelessWidget {
  const _BlocMecef({
    required this.vente,
    required this.facture,
    required this.onEmise,
  });

  final Vente vente;
  final FactureMecef? facture;
  final void Function(FactureMecef) onEmise;

  @override
  Widget build(BuildContext context) {
    final f = facture;

    if (f == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Aucune facture normalisée pour cette vente. Le document '
                'téléchargeable est le reçu de caisse.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  color: AppColors.outline,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'Émettre la facture',
              icon: Symbols.receipt_long,
              variant: AppButtonVariant.outline,
              onPressed: () async {
                final depot = FacturesMecefRepositoryDrift(
                  context.read<AppDatabase>(),
                );
                try {
                  final emise = await depot.emettrePourVente(
                    venteRef: vente.reference,
                  );
                  if (!context.mounted) return;
                  onEmise(emise);
                  showAppToast(context, 'Facture ${emise.reference} émise.');
                } on StateError catch (e) {
                  if (!context.mounted) return;
                  showAppToast(context, e.message, type: ToastType.error);
                }
              },
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: f.estNormalisee
            ? AppColors.successContainer
            : AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            f.estNormalisee ? Symbols.verified : Symbols.pending,
            size: 18,
            color: f.estNormalisee
                ? AppColors.successDeep
                : AppColors.brandGold,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              f.estNormalisee
                  ? 'Facture ${f.reference} — normalisée, code ${f.codeMecef}.'
                  : 'Facture ${f.reference} émise, en attente de transmission '
                        'e-MECeF. Elle ne vaut pas encore facture normalisée.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: f.estNormalisee
                    ? AppColors.successDeep
                    : AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
