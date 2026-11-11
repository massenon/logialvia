import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/events/domain_event.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import '../../../core/widgets/kpi_card.dart';
import 'documents_commercial.dart';
import '../../data/repositories/ventes_repository_drift.dart';
import '../viewmodels/ventes_view_model.dart';
import 'widgets/onglet_pos.dart';
import 'widgets/onglets_ventes_secondaires.dart';

class PageVentes extends StatelessWidget {
  const PageVentes({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<VentesViewModel>(
      create: (context) {
        final db = context.read<AppDatabase>();
        return VentesViewModel(
          VentesRepositoryDrift(db, context.read<EventBus>()),
          db,
        )..charger();
      },
      child: const VentesScreen(),
    );
  }
}

/// Ventes — Doc F4 Écran 1, **4 onglets internes** (Doc H1, Doc E3 §4).
///
/// Les 3 KPI restent visibles au-dessus des onglets et ne changent pas selon
/// l'onglet actif (Doc F4).
class VentesScreen extends StatefulWidget {
  const VentesScreen({super.key});

  @override
  State<VentesScreen> createState() => _VentesScreenState();
}

class _VentesScreenState extends State<VentesScreen> {
  int _onglet = 0;

  static const List<String> _onglets = [
    'Enregistrer Vente',
    'Devis Prestations',
    'Historique des Ventes',
    'Retours et Avoirs',
  ];

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VentesViewModel>();

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
                Symbols.point_of_sale,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text('Ventes', style: AppTypography.pageTitle),
              ),
              // L'historique est le seul onglet exportable en tant que tableau ;
              // le POS est un formulaire, et la facture s'imprime depuis le
              // detail d'une vente.
              if (_onglet == 2)
                BoutonExportPdf(
                  libelle: 'Exporter l\'Historique',
                  construire: () => DocumentsCommercial.historiqueVentes(vm),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _BandeauKpi(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              for (var i = 0; i < _onglets.length; i++)
                _Onglet(
                  libelle: _onglets[i],
                  actif: i == _onglet,
                  onTap: () => setState(() => _onglet = i),
                ),
            ],
          ),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          switch (_onglet) {
            0 => const OngletPos(),
            1 => const OngletDevis(),
            2 => const OngletHistorique(),
            _ => const OngletRetours(),
          },
        ],
      ),
    );
  }
}

class _BandeauKpi extends StatelessWidget {
  const _BandeauKpi({required this.vm});

  final VentesViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cartes = [
      KpiCard(
        libelle: 'CA du Jour',
        valeur: Formats.nombre(vm.chiffreAffairesDuJour),
        unite: 'FCFA',
        accent: AppColors.brandNavy,
        icone: Symbols.trending_up,
      ),
      KpiCard(
        libelle: 'Panier Moyen',
        // « — » et non « 0 » : une moyenne sur zéro vente n'existe pas.
        valeur: vm.panierMoyen == null ? '—' : Formats.nombre(vm.panierMoyen!),
        unite: vm.panierMoyen == null ? '' : 'FCFA',
        accent: AppColors.infoBlue,
        icone: Symbols.shopping_cart,
        detail: vm.panierMoyen == null ? 'Aucune vente aujourd\'hui' : null,
      ),
      KpiCard(
        libelle: 'Ventes en Attente (Avance)',
        valeur: '${vm.ventesEnAttente}',
        accent: AppColors.brandGold,
        icone: Symbols.request_quote,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeur = (constraints.maxWidth - AppSpacing.md * 2) / 3;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final carte in cartes) SizedBox(width: largeur, child: carte),
          ],
        );
      },
    );
  }
}

class _Onglet extends StatelessWidget {
  const _Onglet({
    required this.libelle,
    required this.actif,
    required this.onTap,
  });

  final String libelle;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: actif ? AppColors.brandNavy : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          libelle,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: actif ? AppColors.brandNavy : AppColors.outline,
          ),
        ),
      ),
    );
  }
}
