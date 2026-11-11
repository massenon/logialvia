import 'package:material_ui/material_ui.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/tour/tour_guide.dart';

const TextStyle texteRapport = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

final TextStyle grasRapport = texteRapport.copyWith(
  fontWeight: FontWeight.w700,
);

/// Chiffres de largeur fixe : une colonne de montants doit se lire en diagonale.
final TextStyle monoRapport = texteRapport.copyWith(
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// Barre d'onglets — même rendu que les États Financiers et Paramètres Élevage.
class BarreOnglets extends StatelessWidget {
  const BarreOnglets({
    super.key,
    required this.titres,
    required this.actif,
    required this.onChange,
    this.cibleTour,
  });

  final List<String> titres;
  final int actif;
  final ValueChanged<int> onChange;

  /// Nom de la cible de visite guidee, si cette barre en est une.
  final String? cibleTour;

  @override
  Widget build(BuildContext context) {
    final barre = _barre();
    return cibleTour == null ? barre : CibleTour(nom: cibleTour!, child: barre);
  }

  Widget _barre() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < titres.length; i++)
              InkWell(
                onTap: () => onChange(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: i == actif
                            ? AppColors.brandNavy
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    titres[i],
                    style: grasRapport.copyWith(
                      color: i == actif
                          ? AppColors.brandNavy
                          : AppColors.outline,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Carte KPI à bande latérale colorée — `border-l-4` du prototype.
///
/// La bande est un `Container` superposé, jamais un côté de `Border` à couleur
/// non uniforme : Flutter le refuse avec un `borderRadius` (Doc K4 §6).
class CarteKpiRapport extends StatelessWidget {
  const CarteKpiRapport({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.accent,
    required this.icone,
    this.detail,
    this.fond,
    this.couleurValeur,
  });

  final String libelle;
  final String valeur;
  final Color accent;
  final IconData icone;
  final String? detail;
  final Color? fond;
  final Color? couleurValeur;

  @override
  Widget build(BuildContext context) {
    // ⚠️ Le liseré d'accent est peint dans un `Stack`, jamais étiré.
    //
    // Un `Container(width: 4)` dans un `Row(crossAxisAlignment: stretch)`
    // réclame une hauteur infinie dès que la carte se trouve dans une colonne
    // défilante — « BoxConstraints forces an infinite height » à chaque rendu.
    // `border-l-4` serait la traduction littérale, mais Flutter refuse un
    // `borderRadius` sur une bordure de couleurs non uniformes. Le `Positioned`
    // s'étire sur la hauteur que le contenu impose au `Stack`, donc bornée.
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
            // La place du liseré est reprise à gauche.
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
                        libelle.toUpperCase(),
                        style: AppTypography.label,
                      ),
                    ),
                    Icon(icone, size: 18, color: accent),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  valeur,
                  style: AppTypography.kpiValue.copyWith(
                    fontSize: 20,
                    color: couleurValeur,
                  ),
                ),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      detail!,
                      style: texteRapport.copyWith(
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

/// Barre horizontale proportionnelle — visualisation Recettes vs Dépenses.
class BarreComparative extends StatelessWidget {
  const BarreComparative({
    super.key,
    required this.libelle,
    required this.montant,
    required this.maximum,
    required this.couleur,
  });

  final String libelle;
  final double montant;
  final double maximum;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final ratio = maximum.abs() < 0.01
        ? 0.0
        : (montant / maximum).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            libelle,
            style: texteRapport.copyWith(
              fontSize: 11,
              color: AppColors.outline,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: AppRadius.pill,
            child: Container(
              height: 16,
              color: AppColors.surfaceZebra,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: ratio,
                child: Container(color: couleur),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 80,
          child: Text(
            Formats.nombre(montant),
            textAlign: TextAlign.right,
            style: grasRapport.copyWith(fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// Filtre déroulant + bouton « Réinitialiser », motif commun aux 5 onglets
/// filtrables du prototype.
class FiltreRapport extends StatelessWidget {
  const FiltreRapport({
    super.key,
    required this.valeur,
    required this.libelleTous,
    required this.options,
    required this.onChange,
  });

  final String? valeur;
  final String libelleTous;

  /// (valeur technique, libellé affiché).
  final List<(String, String)> options;
  final ValueChanged<String?> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: valeur,
            isDense: true,
            style: texteRapport,
            hint: Text(libelleTous, style: texteRapport),
            items: [
              DropdownMenuItem<String?>(
                child: Text(libelleTous, style: texteRapport),
              ),
              for (final (cle, libelle) in options)
                DropdownMenuItem<String?>(
                  value: cle,
                  child: Text(libelle, style: texteRapport),
                ),
            ],
            onChanged: onChange,
          ),
        ),
        if (valeur != null) ...[
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            icon: const Icon(Icons.filter_alt_off, size: 16),
            color: AppColors.outline,
            tooltip: 'Réinitialiser',
            visualDensity: VisualDensity.compact,
            onPressed: () => onChange(null),
          ),
        ],
      ],
    );
  }
}

class EnteteRapport extends StatelessWidget {
  const EnteteRapport({super.key, required this.colonnes});

  final List<(String, int, TextAlign)> colonnes;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceZebra,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          for (final (libelle, flex, alignement) in colonnes)
            Expanded(
              flex: flex,
              child: Text(
                libelle,
                textAlign: alignement,
                style: texteRapport.copyWith(color: AppColors.outline),
              ),
            ),
        ],
      ),
    );
  }
}

class LigneRapport extends StatelessWidget {
  const LigneRapport({
    super.key,
    required this.cellules,
    required this.zebre,
    this.couleurFond,
  });

  final List<(Widget, int)> cellules;
  final bool zebre;
  final Color? couleurFond;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: couleurFond ?? (zebre ? AppColors.surfaceZebra : null),
        border: const Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          for (final (widget, flex) in cellules)
            Expanded(flex: flex, child: widget),
        ],
      ),
    );
  }
}

/// Montant aligné à droite ; un zéro s'affiche « — » comme dans le prototype.
class MontantRapport extends StatelessWidget {
  const MontantRapport(
    this.valeur, {
    super.key,
    this.couleur,
    this.gras = false,
  });

  final double valeur;
  final Color? couleur;
  final bool gras;

  @override
  Widget build(BuildContext context) {
    final nul = valeur.abs() < 0.01;
    return Text(
      nul ? '—' : Formats.nombre(valeur),
      textAlign: TextAlign.right,
      style: monoRapport.copyWith(
        fontWeight: gras && !nul ? FontWeight.w700 : FontWeight.w400,
        color: nul ? AppColors.outline : couleur,
      ),
    );
  }
}

class BadgeRapport extends StatelessWidget {
  const BadgeRapport({
    super.key,
    required this.libelle,
    required this.alerte,
    this.succes = false,
  });

  final String libelle;
  final bool alerte;
  final bool succes;

  @override
  Widget build(BuildContext context) {
    final (fond, texte) = alerte
        ? (AppColors.errorContainer, AppColors.errorDeep)
        : succes
        ? (AppColors.successContainer, AppColors.successDeep)
        : (AppColors.brandGold.withValues(alpha: 0.2), AppColors.brandNavy);

    return Align(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(color: fond, borderRadius: AppRadius.pill),
        child: Text(
          libelle,
          style: texteRapport.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: texte,
          ),
        ),
      ),
    );
  }
}

/// Note de bas de tableau — sert à énoncer une limite plutôt qu'à la masquer.
class NoteEcheance extends StatelessWidget {
  const NoteEcheance({super.key, required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 14, color: AppColors.outline),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              texte,
              style: texteRapport.copyWith(
                fontSize: 11,
                color: AppColors.outline,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
