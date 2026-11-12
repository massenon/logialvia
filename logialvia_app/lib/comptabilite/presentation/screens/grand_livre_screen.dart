import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/carte_kpi_lisere.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/carte_section.dart';
import 'documents_comptables.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import '../../domain/entities/comptabilite.dart';
import '../viewmodels/comptabilite_view_model.dart';
import 'widgets/communs_compta.dart';

/// Grand Livre — Doc F6 §2, fidèle à `grand-livre.html`.
///
/// Le solde progressif suit le **sens naturel du compte** (BR-CPT-007) : sur un
/// compte débiteur par nature, le débit augmente le solde ; sur un compte
/// créditeur, c'est le crédit. Le prototype code ce sens dans deux tableaux en
/// dur (`COMPTES_DEBITEURS_PAR_NATURE`) qui ne couvrent que 6 comptes ; ici il
/// est dérivé du numéro et de la classe pour **tous** les comptes du plan.
class GrandLivreScreen extends StatelessWidget {
  const GrandLivreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ComptabiliteViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    final compte = vm.compteCourant;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.import_contacts,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text('Grand Livre', style: AppTypography.pageTitle),
              ),
              SelecteurExercice(vm: vm),
              const SizedBox(width: AppSpacing.md),
              BoutonExportPdf(
                construire: () => DocumentsComptables.grandLivre(vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Liste chronologique des écritures d\'un compte, avec solde '
            'progressif.',
            style: texteCompta.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.lg),
          _BarreSelection(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          if (compte == null)
            const CarteSection(
              titre: 'Grand Livre',
              icone: Symbols.import_contacts,
              child: EtatVide(
                message:
                    'Sélectionnez un compte ci-dessus pour afficher ses '
                    'écritures et son solde progressif.',
              ),
            )
          else ...[
            _KpisCompte(vm: vm, compte: compte),
            const SizedBox(height: AppSpacing.lg),
            CarteSection(
              cibleTour: 'grand-livre-tableau',
              titre: '${compte.numero} — ${compte.libelle}',
              icone: Symbols.receipt_long,
              action: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceZebra,
                  borderRadius: AppRadius.pill,
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Text(
                  compte.estDebiteurParNature
                      ? 'Débiteur par nature'
                      : 'Créditeur par nature',
                  style: texteCompta.copyWith(
                    fontSize: 11,
                    color: AppColors.outline,
                  ),
                ),
              ),
              child: vm.grandLivre.isEmpty
                  ? const EtatVide(
                      message:
                          'Aucune écriture ne correspond à ces critères.',
                    )
                  : _TableauGrandLivre(vm: vm),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarreSelection extends StatelessWidget {
  const _BarreSelection({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('COMPTE :', style: AppTypography.label),
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              initialValue: vm.compteSelectionne,
              isExpanded: true,
              style: grasCompta,
              decoration: decorationCompta,
              hint: const Text('Sélectionner un compte', style: texteCompta),
              items: [
                for (final c in vm.planActif)
                  DropdownMenuItem(
                    value: c.numero,
                    child: Text(
                      '${c.numero} — ${c.libelle}',
                      style: grasCompta,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: vm.selectionnerCompte,
            ),
          ),
          _ChampDate(
            libelle: 'DU',
            valeur: vm.debutGrandLivre,
            annee: vm.exercice,
            onChange: (d) => vm.definirPeriodeGrandLivre(
              debut: d,
              fin: vm.finGrandLivre,
            ),
          ),
          _ChampDate(
            libelle: 'AU',
            valeur: vm.finGrandLivre,
            annee: vm.exercice,
            onChange: (d) => vm.definirPeriodeGrandLivre(
              debut: vm.debutGrandLivre,
              fin: d,
            ),
          ),
          SizedBox(
            width: 260,
            child: TextFormField(
              initialValue: vm.rechercheGrandLivre,
              style: texteCompta,
              decoration: decorationCompta.copyWith(
                hintText: 'Rechercher un libellé, une référence…',
                prefixIcon: const Icon(
                  Symbols.search,
                  size: 18,
                  color: AppColors.outline,
                ),
              ),
              onChanged: vm.definirRechercheGrandLivre,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChampDate extends StatelessWidget {
  const _ChampDate({
    required this.libelle,
    required this.valeur,
    required this.annee,
    required this.onChange,
  });

  final String libelle;
  final DateTime? valeur;
  final int annee;
  final ValueChanged<DateTime?> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(libelle, style: AppTypography.label),
        const SizedBox(width: AppSpacing.xs),
        InkWell(
          onTap: () async {
            final choix = await showDatePicker(
              context: context,
              initialDate: valeur ?? DateTime(annee, 1, 1),
              firstDate: DateTime(annee, 1, 1),
              lastDate: DateTime(annee, 12, 31),
              locale: const Locale('fr', 'FR'),
            );
            if (choix != null) onChange(choix);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceZebra,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Text(
              valeur == null ? '—' : Formats.date(valeur!),
              style: grasCompta,
            ),
          ),
        ),
        if (valeur != null)
          IconButton(
            icon: const Icon(Symbols.close, size: 16),
            color: AppColors.outline,
            tooltip: 'Retirer cette borne',
            visualDensity: VisualDensity.compact,
            onPressed: () => onChange(null),
          ),
      ],
    );
  }
}

class _KpisCompte extends StatelessWidget {
  const _KpisCompte({required this.vm, required this.compte});

  final ComptabiliteViewModel vm;
  final CompteComptable compte;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Solde d\'Ouverture',
            valeur: Formats.montant(vm.soldeOuvertureCompte),
            accent: AppColors.brandNavy,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Total Débit Période',
            valeur: Formats.montant(vm.totalDebitCompte),
            accent: AppColors.successDeep,
            couleurValeur: AppColors.successDeep,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Total Crédit Période',
            valeur: Formats.montant(vm.totalCreditCompte),
            accent: AppColors.errorDeep,
            couleurValeur: AppColors.errorDeep,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Solde Final',
            valeur: Formats.montant(vm.soldeFinalCompte),
            accent: AppColors.brandGold,
            couleurValeur: AppColors.brandNavy,
            fond: AppColors.brandGold.withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }
}

class _TableauGrandLivre extends StatelessWidget {
  const _TableauGrandLivre({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final lignes = vm.grandLivre;

    return Column(
      children: [
        const EnteteCompta(
          colonnes: [
            ('DATE', 2, TextAlign.left),
            ('ORIGINE', 2, TextAlign.left),
            ('LIBELLÉ', 5, TextAlign.left),
            ('DÉBIT', 2, TextAlign.right),
            ('CRÉDIT', 2, TextAlign.right),
            ('SOLDE PROGRESSIF', 3, TextAlign.right),
          ],
        ),
        // Ligne de report : sans elle, la premiere valeur de la colonne
        // « Solde Progressif » sort de nulle part.
        LigneCompta(
          zebre: false,
          couleurFond: AppColors.surfaceZebra,
          cellules: [
            (const SizedBox.shrink(), 2),
            (const SizedBox.shrink(), 2),
            (
              Text(
                'Report — solde d\'ouverture',
                style: texteCompta.copyWith(
                  fontStyle: FontStyle.italic,
                  color: AppColors.outline,
                ),
              ),
              5,
            ),
            (const SizedBox.shrink(), 2),
            (const SizedBox.shrink(), 2),
            (
              Text(
                Formats.nombre(vm.soldeOuvertureCompte),
                textAlign: TextAlign.right,
                style: montantCompta.copyWith(color: AppColors.outline),
              ),
              3,
            ),
          ],
        ),
        for (var i = 0; i < lignes.length; i++)
          LigneCompta(
            zebre: i.isOdd,
            cellules: [
              (Text(Formats.date(lignes[i].ecriture.date), style: texteCompta), 2),
              (
                Text(
                  lignes[i].ecriture.venteRef ??
                      lignes[i].ecriture.achatRef ??
                      lignes[i].ecriture.numeroPiece ??
                      '—',
                  style: texteCompta.copyWith(fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
                2,
              ),
              (
                Text(
                  lignes[i].ecriture.libelle,
                  style: texteCompta,
                  overflow: TextOverflow.ellipsis,
                ),
                5,
              ),
              (
                Text(
                  montantOuTiret(lignes[i].ecriture.debit),
                  textAlign: TextAlign.right,
                  style: montantCompta.copyWith(
                    color: lignes[i].ecriture.debit > 0
                        ? AppColors.successDeep
                        : null,
                  ),
                ),
                2,
              ),
              (
                Text(
                  montantOuTiret(lignes[i].ecriture.credit),
                  textAlign: TextAlign.right,
                  style: montantCompta.copyWith(
                    color: lignes[i].ecriture.credit > 0
                        ? AppColors.errorDeep
                        : null,
                  ),
                ),
                2,
              ),
              (
                Text(
                  Formats.nombre(lignes[i].soldeProgressif),
                  textAlign: TextAlign.right,
                  style: montantCompta.copyWith(fontWeight: FontWeight.w700),
                ),
                3,
              ),
            ],
          ),
      ],
    );
  }
}
