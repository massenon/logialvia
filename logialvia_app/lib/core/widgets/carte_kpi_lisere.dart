import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Carte KPI à liseré d'accent — `border-l-4 border-l-*` du prototype.
///
/// ## Pourquoi ce widget existe
///
/// Le motif avait été réécrit **six fois** : Journal Comptable, Balance
/// Générale, Grand Livre, Clôture d'Exercice, Saisie des Dépenses et Rapports.
/// Toutes ces copies dessinaient le liseré de la même façon fautive :
///
/// ```dart
/// Row(
///   crossAxisAlignment: CrossAxisAlignment.stretch,
///   children: [Container(width: 4, color: accent), ...],
/// )
/// ```
///
/// Dans une colonne défilante, la hauteur disponible est **infinie** :
/// `stretch` en réclame donc une infinie, et Flutter lève
/// `BoxConstraints forces an infinite height` **à chaque rendu**. C'est ce qui
/// cassait ces écrans — pas un défaut d'affichage, une exception.
///
/// `border-l-4` serait la traduction littérale, mais Flutter refuse un
/// `borderRadius` sur une bordure de couleurs non uniformes
/// (« A borderRadius can only be given on borders with uniform colors »). Le
/// liseré est donc peint dans un `Stack` : le `Positioned` s'étire sur la
/// hauteur que le **contenu** impose au `Stack`, bornée par construction.
///
/// Un widget partagé plutôt qu'un septième copier-coller : c'est la seule
/// façon d'être sûr que la correction ne se perde pas au prochain écran.
class CarteKpiLisere extends StatelessWidget {
  const CarteKpiLisere({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.accent,
    this.icone,
    this.detail,
    this.couleurValeur,
    this.fond,
    this.tailleValeur = 20,
  });

  final String libelle;
  final String valeur;

  /// Couleur du liseré gauche.
  final Color accent;

  /// Affichée à droite du libellé, quand l'écran en pose une.
  final IconData? icone;

  /// Précision sous la valeur — sur quoi elle porte, ce qu'elle exclut.
  final String? detail;

  final Color? couleurValeur;
  final Color? fond;
  final double tailleValeur;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: fond ?? AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4, // `border-l-4`
            child: ColoredBox(color: accent),
          ),
          Padding(
            // La place du lisere est reprise a gauche.
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md + 4,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        // Intitule de KPI : `text-outline`, et non le
                        // `brand-navy` d'un libelle de champ.
                        libelle.toUpperCase(),
                        style: AppTypography.caption,
                      ),
                    ),
                    if (icone != null) Icon(icone, size: 18, color: accent),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  valeur,
                  style: AppTypography.kpiValue.copyWith(
                    fontSize: tailleValeur,
                    color: couleurValeur,
                  ),
                ),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail!,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 10,
                        color: AppColors.outline,
                      ),
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
