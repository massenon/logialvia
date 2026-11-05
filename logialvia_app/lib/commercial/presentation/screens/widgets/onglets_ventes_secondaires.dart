import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/resultat/resultat.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/pdf/bouton_export_pdf.dart';
import '../../../../core/widgets/app_modal.dart';
import '../documents_commercial.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/tour/tour_guide.dart';
import '../../../../core/widgets/carte_section.dart';
import '../../../domain/entities/vente.dart';
import '../../viewmodels/ventes_view_model.dart';
import '../../../../core/saisie/formats_saisie.dart';

const TextStyle _texte = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

final InputDecoration _decoration = InputDecoration(
  isDense: true,
  filled: true,
  fillColor: AppColors.surfaceCard,
  labelStyle: _texte,
  hintStyle: _texte.copyWith(color: AppColors.outline),
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  ),
  border: OutlineInputBorder(
    borderRadius: AppRadius.cardRadius,
    borderSide: const BorderSide(color: AppColors.outlineVariant),
  ),
);

Widget _entete(
  String libelle, {
  int flex = 1,
  TextAlign alignement = TextAlign.left,
}) => Expanded(
  flex: flex,
  child: Text(
    libelle,
    textAlign: alignement,
    style: _texte.copyWith(color: AppColors.outline),
  ),
);

/// Onglet 2 — Devis Prestations (Doc H1 §Onglet 2).
class OngletDevis extends StatefulWidget {
  const OngletDevis({super.key});

  @override
  State<OngletDevis> createState() => _OngletDevisState();
}

class _OngletDevisState extends State<OngletDevis> {
  final _client = TextEditingController();
  final _objet = TextEditingController();
  final _montant = TextEditingController();
  final _validite = TextEditingController(text: '15');

  @override
  void dispose() {
    _client.dispose();
    _objet.dispose();
    _montant.dispose();
    _validite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VentesViewModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteSection(
          titre: 'Générer un Devis',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _champ('Client *', _client)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: _champ('Objet / Prestation *', _objet),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _champ(
                      'Montant Estimé (FCFA) *',
                      _montant,
                      clavier: TextInputType.number,
                      formatteurs: FormatteursSaisie.montant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _champ(
                      'Validité (jours)',
                      _validite,
                      clavier: TextInputType.number,
                      formatteurs: FormatteursSaisie.montant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Générer le Devis',
                icon: Symbols.description,
                onPressed: () async {
                  final resultat = await vm.genererDevis(
                    client: _client.text,
                    objet: _objet.text,
                    montant: double.tryParse(_montant.text),
                    validiteJours: int.tryParse(_validite.text),
                  );
                  if (!context.mounted) return;
                  switch (resultat) {
                    case Succes<DevisEmis>(valeur: final devis):
                      // Doc E6 §5 : le formulaire se reinitialise apres succes.
                      _client.clear();
                      _objet.clear();
                      _montant.clear();
                      _validite.text = '15';
                      showAppToast(context, 'Devis ${devis.reference} généré.');
                    case Echec<DevisEmis>(message: final message):
                      showAppToast(context, message, type: ToastType.error);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Devis Émis',
          child: vm.devis.isEmpty
              ? const EtatVide(message: 'Aucun devis émis pour le moment.')
              : Column(
                  children: [
                    Container(
                      color: AppColors.surfaceZebra,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          _entete('Référence'),
                          _entete('Client', flex: 2),
                          _entete('Objet', flex: 3),
                          _entete('Montant', alignement: TextAlign.right),
                          _entete('Expire le', alignement: TextAlign.right),
                        ],
                      ),
                    ),
                    for (var i = 0; i < vm.devis.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: i.isOdd ? AppColors.surfaceZebra : null,
                          border: const Border(
                            bottom: BorderSide(color: AppColors.outlineVariant),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                vm.devis[i].reference,
                                style: _texte.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brandNavy,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(vm.devis[i].client, style: _texte),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(vm.devis[i].objet, style: _texte),
                            ),
                            Expanded(
                              child: Text(
                                Formats.nombre(vm.devis[i].montant),
                                textAlign: TextAlign.right,
                                style: _texte,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                Formats.date(vm.devis[i].dateExpiration),
                                textAlign: TextAlign.right,
                                style: _texte,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _champ(
    String libelle,
    TextEditingController controleur, {
    TextInputType? clavier,
    List<TextInputFormatter>? formatteurs,
  }) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controleur,
        keyboardType: clavier,
        inputFormatters: formatteurs,
        style: _texte,
        decoration: _decoration.copyWith(labelText: libelle),
      ),
    );
  }
}

/// Onglet 3 — Historique des Ventes (Doc H1 §Onglet 3).
class OngletHistorique extends StatelessWidget {
  const OngletHistorique({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VentesViewModel>();

    return CarteSection(
      titre: 'Historique des Ventes',
      action: CibleTour(
        nom: 'filtres-historique',
        child: SizedBox(
          width: 380,
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    onChanged: vm.definirRechercheHistorique,
                    style: _texte,
                    decoration: _decoration.copyWith(
                      hintText: 'Référence ou client…',
                      prefixIcon: const Icon(Symbols.search, size: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String?>(
                  initialValue: vm.filtreStatut,
                  isExpanded: true,
                  decoration: _decoration,
                  style: _texte,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tous statuts')),
                    DropdownMenuItem(
                      value: StatutVente.payee,
                      child: Text(StatutVente.payee),
                    ),
                    DropdownMenuItem(
                      value: StatutVente.avance,
                      child: Text(StatutVente.avance),
                    ),
                    DropdownMenuItem(
                      value: StatutVente.annulee,
                      child: Text(StatutVente.annulee),
                    ),
                  ],
                  onChanged: vm.definirFiltreStatut,
                ),
              ),
            ],
          ),
        ),
      ),
      child: vm.historiqueFiltre.isEmpty
          ? const EtatVide(
              message:
                  'Aucune vente ne correspond. Les ventes encaissées depuis '
                  'l\'onglet « Enregistrer Vente » apparaissent ici.',
            )
          : CibleTour(
              nom: 'tableau-historique',
              child: Column(
                children: [
                  Container(
                    color: AppColors.surfaceZebra,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        _entete('Référence'),
                        _entete('Date'),
                        _entete('Client', flex: 2),
                        _entete('Montant', alignement: TextAlign.right),
                        _entete('Statut', alignement: TextAlign.center),
                        _entete('Actions', alignement: TextAlign.right),
                      ],
                    ),
                  ),
                  for (var i = 0; i < vm.historiqueFiltre.length; i++)
                    _LigneVente(
                      vente: vm.historiqueFiltre[i],
                      zebre: i.isOdd,
                      vm: vm,
                    ),
                ],
              ),
            ),
    );
  }
}

class _LigneVente extends StatelessWidget {
  const _LigneVente({
    required this.vente,
    required this.zebre,
    required this.vm,
  });

  final Vente vente;
  final bool zebre;
  final VentesViewModel vm;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _ouvrirDetail(context),
      child: Container(
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
              child: Text(
                vente.reference,
                style: _texte.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
            Expanded(child: Text(Formats.date(vente.date), style: _texte)),
            Expanded(flex: 2, child: Text(vente.client, style: _texte)),
            Expanded(
              child: Text(
                Formats.nombre(vente.total),
                textAlign: TextAlign.right,
                style: _texte,
              ),
            ),
            Expanded(
              child: Center(child: BadgeStatutVente(statut: vente.statut)),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: vente.estAnnulee
                    ? Text(
                        '—',
                        style: _texte.copyWith(color: AppColors.outline),
                      )
                    : TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.errorDeep,
                        ),
                        onPressed: () => _annuler(context),
                        child: const Text(
                          'Annuler',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 12,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _ouvrirDetail(BuildContext context) {
    AppModal.show<void>(
      context,
      title: 'Vente ${vente.reference}',
      maxWidth: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detail('Client', vente.client),
          _detail('Date', Formats.date(vente.date)),
          _detail('Mode de règlement', vente.mode),
          if (vente.ligneMobileMoney != null)
            _detail('Ligne créditée', vente.ligneMobileMoney!),
          // Deux lignes distinctes depuis l'arbitrage : l'instrument, puis la
          // condition. Voir `ConditionPaiement`.
          _detail(
            'Condition de paiement',
            ConditionPaiement.depuisStatut(vente.statut),
          ),
          _detail('Statut', vente.statut),
          if (vente.estEnAvance)
            _detail('Reste dû', Formats.montant(vente.resteDu)),
          if (vente.motifAnnulation != null)
            _detail('Motif d\'annulation', vente.motifAnnulation!),
          const Divider(height: AppSpacing.lg),
          const Text('LIGNES', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          for (final ligne in vente.lignes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${ligne.nom} × ${ligne.quantite.toInt()}',
                      style: _texte,
                    ),
                  ),
                  Text(Formats.nombre(ligne.total), style: _texte),
                ],
              ),
            ),
          const Divider(height: AppSpacing.lg),
          Row(
            children: [
              const Text('TOTAL', style: AppTypography.label),
              const Spacer(),
              Text(
                Formats.montant(vente.total),
                style: _texte.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Dette Doc E9 levee : le generateur unique existe desormais, le
          // bouton « Imprimer la Facture » de Doc H1 §Onglet 3 est reel.
          Align(
            alignment: Alignment.centerLeft,
            child: BoutonExportPdf(
              libelle: 'Imprimer la Facture',
              variante: AppButtonVariant.primary,
              construire: () => DocumentsCommercial.facture(vente),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(String libelle, String valeur) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(
          width: 150,
          child: Text(
            libelle,
            style: _texte.copyWith(color: AppColors.outline),
          ),
        ),
        Expanded(
          child: Text(
            valeur,
            style: _texte.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Future<void> _annuler(BuildContext context) async {
    String? motif;
    final confirme = await AppModal.show<bool>(
      context,
      title: 'Annuler la vente ${vente.reference} ?',
      maxWidth: 400,
      child: StatefulBuilder(
        builder: (ctx, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Le stock des produits vendus sera restitué et le compteur de '
              'la fiche d\'élevage corrigé. La vente reste consultable dans '
              '« Retours et Avoirs ».',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                height: 1.4,
                color: AppColors.outline,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('MOTIF D\'ANNULATION *', style: AppTypography.label),
            const SizedBox(height: AppSpacing.xs),
            DropdownButtonFormField<String>(
              initialValue: motif,
              isExpanded: true,
              decoration: _decoration,
              style: _texte,
              hint: const Text('-- Sélectionner --', style: _texte),
              items: [
                for (final m in MotifAnnulation.tous)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => setState(() => motif = v),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Retour',
                  variant: AppButtonVariant.outline,
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppButton(
                  label: 'Confirmer l\'Annulation',
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
    final resultat = await vm.annuler(reference: vente.reference, motif: motif);
    if (!context.mounted) return;
    switch (resultat) {
      case Succes<void>():
        showAppToast(
          context,
          'Vente ${vente.reference} annulée, stock restitué.',
        );
      case Echec<void>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

class BadgeStatutVente extends StatelessWidget {
  const BadgeStatutVente({super.key, required this.statut});

  final String statut;

  @override
  Widget build(BuildContext context) {
    final (fond, texte) = switch (statut) {
      StatutVente.payee => (AppColors.successContainer, AppColors.successDeep),
      StatutVente.avance => (
        AppColors.brandGold.withValues(alpha: 0.2),
        AppColors.brandNavy,
      ),
      _ => (AppColors.errorContainer, AppColors.errorDeep),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(color: fond, borderRadius: AppRadius.pill),
      child: Text(
        statut,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: texte,
        ),
      ),
    );
  }
}

/// Onglet 4 — Retours et Avoirs (Doc H1 §Onglet 4).
///
/// **Vue de consultation pure** : aucune saisie possible ici, la liste est
/// alimentée uniquement par les annulations faites depuis l'onglet Historique.
class OngletRetours extends StatelessWidget {
  const OngletRetours({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VentesViewModel>();

    return CarteSection(
      titre: 'Retours et Avoirs',
      child: vm.retours.isEmpty
          ? const EtatVide(
              message:
                  'Aucune vente annulée. Cette vue se remplit automatiquement '
                  'depuis les annulations faites dans l\'onglet Historique — '
                  'aucune saisie directe n\'est possible ici.',
            )
          : Column(
              children: [
                Container(
                  color: AppColors.surfaceZebra,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      _entete('Référence'),
                      _entete('Date'),
                      _entete('Client', flex: 2),
                      _entete('Montant', alignement: TextAlign.right),
                      _entete('Motif d\'Annulation', flex: 2),
                    ],
                  ),
                ),
                for (var i = 0; i < vm.retours.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: i.isOdd ? AppColors.surfaceZebra : null,
                      border: const Border(
                        bottom: BorderSide(color: AppColors.outlineVariant),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            vm.retours[i].reference,
                            style: _texte.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandNavy,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            Formats.date(vm.retours[i].date),
                            style: _texte,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(vm.retours[i].client, style: _texte),
                        ),
                        Expanded(
                          child: Text(
                            Formats.nombre(vm.retours[i].total),
                            textAlign: TextAlign.right,
                            style: _texte,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            vm.retours[i].motifAnnulation ?? '—',
                            style: _texte,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
