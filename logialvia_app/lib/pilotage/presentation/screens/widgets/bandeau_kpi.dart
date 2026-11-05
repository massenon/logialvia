import 'package:flutter/material.dart';

import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/icone_symbole.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../domain/entities/tableau_bord_principal.dart';

/// Bandeau d'indicateurs — `#kpi-panel` de `dashboard.html` l.134.
///
/// Grille `grid-cols-2 xl:grid-cols-4` : 2 colonnes, puis 4 au-dela du
/// breakpoint `xl` (1280 px). Doc E7 §2 decrivait `md:grid-cols-4` (768 px),
/// mais le HTML reel utilise bien `xl` sur cet ecran — c'est le HTML qui fait
/// foi (Master Prompt §1).
///
/// PIEGE CORRIGE : un breakpoint Tailwind se declenche sur la largeur de la
/// **fenetre** (media query), pas sur celle du conteneur. Mesurer les
/// contraintes du `LayoutBuilder` donnait ~1100 px sur une fenetre de 1440
/// (288 px de barre laterale + marges), donc 2 colonnes et 4 rangees, la ou le
/// web en affiche 4 et 2. La largeur de fenetre est donc lue via `MediaQuery`,
/// et les contraintes ne servent plus qu'a dimensionner les cartes.
class BandeauKpi extends StatelessWidget {
  const BandeauKpi({super.key, required this.indicateurs});

  final List<IndicateurCle> indicateurs;

  static Color _couleur(AccentKpi accent) => switch (accent) {
    AccentKpi.navy => AccentCouleurs.navy,
    AccentKpi.info => AccentCouleurs.info,
    AccentKpi.or => AccentCouleurs.or,
    AccentKpi.succes => AccentCouleurs.succes,
    AccentKpi.erreur => AccentCouleurs.erreur,
  };

  @override
  Widget build(BuildContext context) {
    // `grid-cols-2 xl:grid-cols-4` — seuil lu via AppBreakpoints, jamais ecrit
    // en dur ici (Doc E8 §2).
    final colonnes = AppBreakpoints.estXl(context) ? 4 : 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeurCarte =
            (constraints.maxWidth - AppSpacing.md * (colonnes - 1)) / colonnes;

        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final indicateur in indicateurs)
              SizedBox(
                width: largeurCarte,
                child: KpiCard(
                  libelle: indicateur.libelle,
                  valeur: indicateur.valeur,
                  unite: indicateur.unite.isEmpty ? null : indicateur.unite,
                  detail: indicateur.detail,
                  icone: IconeSymbole.depuisNom(indicateur.icone),
                  // Un indicateur non calculable est affiche en gris neutre :
                  // sa bande coloree semantique suggererait une valeur reelle.
                  accent: indicateur.calculable
                      ? _couleur(indicateur.accent)
                      : AppColors.outlineVariant,
                ),
              ),
          ],
        );
      },
    );
  }
}
