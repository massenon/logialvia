import 'package:material_ui/material_ui.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../domain/entities/journee_elevage.dart';
import '../../../domain/services/agregation_hebdomadaire.dart';

/// Vue Hebdomadaire — `#density-view-weekly` de `fiche-goliaths.html` l.407.
///
/// Le prototype la décrit dans sa propre visite guidée : « Basculez vers une
/// vue agrégée par semaine si la saisie quotidienne détaillée n'est pas
/// nécessaire ce mois-ci. » Elle ne se saisit pas : c'est une lecture cumulée
/// du même tableau mensuel.
///
/// Voir [AgregationHebdomadaire] pour les deux corrections apportées au calcul.
class TableauHebdomadaire extends StatelessWidget {
  const TableauHebdomadaire({
    super.key,
    required this.nombreJours,
    required this.journees,
    required this.moisAffiche,
    required this.effectifInitial,
    required this.libelleNaissances,
  });

  final int nombreJours;
  final Map<int, JourneeElevage> journees;
  final DateTime moisAffiche;

  /// Effectif de report du mois précédent — départ de la première semaine.
  final int effectifInitial;

  /// « Cumul Nés », « Cumul Nés / Transferts »… — le glossaire de la filière
  /// vaut ici aussi. Voir `ConfigurationEspece.libelleNaissances`.
  final String libelleNaissances;

  static const List<(String, int, TextAlign)> _colonnes = [
    ('SEMAINE', 4, TextAlign.left),
    ('CUMUL ACHATS', 2, TextAlign.right),
    ('CUMUL', 2, TextAlign.right), // complété par le glossaire
    ('CUMUL MORTS', 2, TextAlign.right),
    ('CUMUL VENTES', 2, TextAlign.right),
    ('EFFECTIF FIN DE SEMAINE', 3, TextAlign.right),
    ('TAUX MORTALITÉ SEMAINE', 3, TextAlign.right),
    ('TRAITEMENTS & PROPHYLAXIE', 4, TextAlign.left),
  ];

  @override
  Widget build(BuildContext context) {
    final semaines = const AgregationHebdomadaire().calculer(
      nombreJoursDuMois: nombreJours,
      journees: journees,
      effectifInitial: effectifInitial,
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      clipBehavior: Clip.antiAlias,
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
                for (final (titre, flex, alignement) in _colonnes)
                  Expanded(
                    flex: flex,
                    child: Text(
                      titre == 'CUMUL'
                          ? 'CUMUL ${libelleNaissances.toUpperCase()}'
                          : titre,
                      textAlign: alignement,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < semaines.length; i++)
            _LigneSemaine(
              semaine: semaines[i],
              moisAffiche: moisAffiche,
              journees: journees,
              zebre: i.isOdd,
            ),
        ],
      ),
    );
  }
}

class _LigneSemaine extends StatelessWidget {
  const _LigneSemaine({
    required this.semaine,
    required this.moisAffiche,
    required this.journees,
    required this.zebre,
  });

  final SemaineElevage semaine;
  final DateTime moisAffiche;
  final Map<int, JourneeElevage> journees;
  final bool zebre;

  /// Les observations de traitement réellement saisies sur la semaine.
  ///
  /// Le prototype remplit cette colonne depuis `PROPHYLAXIE_MULTI_CALENDAR`,
  /// indexé sur le **jour du cycle** et interrogé ici avec un jour du mois
  /// (voir `ProphylaxieDuJour`). On affiche donc ce qui a été noté sur les
  /// journées, pas une projection fausse.
  String get _traitements {
    final notes = <String>[];
    for (var jour = semaine.premierJour; jour <= semaine.dernierJour; jour++) {
      final observation = journees[jour]?.traitementObs?.trim();
      if (observation != null && observation.isNotEmpty) notes.add(observation);
    }
    return notes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final vide = !semaine.aDesJourneesSaisies;
    final traitements = _traitements;

    Widget nombre(int valeur, {Color? couleur, bool gras = false}) => Text(
      vide ? '—' : '$valeur',
      textAlign: TextAlign.right,
      style: TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: AppTypography.textXs,
        fontWeight: gras ? FontWeight.w700 : FontWeight.w400,
        color: vide ? AppColors.outline : couleur,
      ),
    );

    return Container(
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
            flex: 4,
            child: Text(
              'Semaine ${semaine.numero} '
              '(${semaine.premierJour}-${semaine.dernierJour} '
              '${_mois[moisAffiche.month - 1]})',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: AppTypography.textXs,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
          ),
          Expanded(flex: 2, child: nombre(semaine.cumulAchats)),
          Expanded(flex: 2, child: nombre(semaine.cumulNaissances)),
          Expanded(
            flex: 2,
            child: nombre(
              semaine.cumulMorts,
              couleur: semaine.cumulMorts > 0 ? AppColors.errorDeep : null,
              gras: semaine.cumulMorts > 0,
            ),
          ),
          Expanded(flex: 2, child: nombre(semaine.cumulVentes)),
          Expanded(flex: 3, child: nombre(semaine.effectifFin, gras: true)),
          Expanded(
            flex: 3,
            child: Text(
              // Sans effectif de depart il n'y a pas de taux : « 0,0 % »
              // laisserait croire a une semaine sans perte.
              vide || semaine.tauxMortalite == null
                  ? '—'
                  : Formats.pourcentage(semaine.tauxMortalite!),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: AppTypography.textXs,
                fontWeight: FontWeight.w600,
                color: vide
                    ? AppColors.outline
                    : ((semaine.tauxMortalite ?? 0) > 0
                          ? AppColors.errorDeep
                          : AppColors.onSurface),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              traitements.isEmpty ? '—' : traitements,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: AppTypography.textXs,
                color: traitements.isEmpty
                    ? AppColors.outline
                    : AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _mois = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
}

/// Pilule « Grille Quotidienne / Vue Hebdomadaire » — `switchDensityView()`.
class BasculeDensite extends StatelessWidget {
  const BasculeDensite({
    super.key,
    required this.hebdomadaire,
    required this.onChange,
  });

  final bool hebdomadaire;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Onglet(
            libelle: 'Grille Quotidienne',
            actif: !hebdomadaire,
            onTap: () => onChange(false),
          ),
          _Onglet(
            libelle: 'Vue Hebdomadaire',
            actif: hebdomadaire,
            onTap: () => onChange(true),
          ),
        ],
      ),
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
      borderRadius: AppRadius.pill,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: actif ? AppColors.brandNavy : null,
          borderRadius: AppRadius.pill,
        ),
        child: Text(
          libelle,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: actif ? Colors.white : AppColors.outline,
          ),
        ),
      ),
    );
  }
}
