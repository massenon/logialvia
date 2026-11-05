import 'package:flutter/material.dart';

import '../saisie/formats_saisie.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Champ numérique de la saisie journalière — **un seul** pour tous les usages.
///
/// ## Pourquoi ce widget existe
///
/// Le prototype décrit ces champs par une classe unique, répétée à l'identique
/// sur les trois colonnes de `#form-saisie-journaliere` :
///
/// ```html
/// <input class="w-full h-10 px-md border border-outline-variant rounded-lg
///               text-sm bg-white">
/// ```
///
/// Côté Flutter, ce champ avait été réécrit **trois fois** — deux fois dans la
/// fiche d'espèce, une fois dans le suivi du stock d'œufs — et les copies
/// avaient divergé : la version des colonnes « Achats » et « Nés » ne
/// renseignait que `border`, sans `enabledBorder`, et n'avait donc pas la même
/// bordure au repos que la troisième. Il n'existe plus qu'une définition.
///
/// ## Pas à pas `− valeur +`
///
/// Sur demande de la Gérante, les colonnes de la saisie journalière se pilotent
/// aux boutons. C'est le patron que le prototype emploie déjà pour les morts et
/// les dons par catégorie (`dayCounterStep()`, fiche-goliaths.html l.170-174) :
/// les deux blocs de la même page se saisissent enfin de la même façon.
///
/// ⚠️ **Le champ central reste saisissable**, à la différence du compteur des
/// catégories. Charger 300 sujets au clic serait absurde ; mais la frappe est
/// filtrée aux chiffres seuls ([FormatteursSaisie.entierPositif]) et bornée à
/// zéro. Aucune valeur négative ne peut entrer, ni au clavier ni au bouton
/// (BR-ELV-001).
class ChampSaisieNombre extends StatelessWidget {
  const ChampSaisieNombre({
    super.key,
    required this.libelle,
    required this.valeur,
    this.onChange,
    this.suffixeLibelle,
    this.note,
    this.erreur,
    this.hauteur = hauteurStandard,
    this.pasAPas = true,
    this.pas = 1,
  });

  /// `h-11` (44 px) — la hauteur des champs de formulaire du prototype.
  ///
  /// La saisie journalière utilisait `h-10` (40 px), la taille des barres de
  /// filtres. Sur un écran où l'animalier saisit tous les jours, c'était trop
  /// serré : la Gérante a demandé de les agrandir. 44 px n'est pas un nombre
  /// inventé — c'est la hauteur que le prototype donne à ses champs de saisie.
  static const double hauteurStandard = 44;

  final String libelle;
  final int valeur;

  /// `null` rend le champ en lecture seule — c'est le cas de « Ventes (POS) »,
  /// alimentée par le point de vente et jamais saisie ici. Les deux boutons
  /// disparaissent alors : un pas à pas inerte serait un bouton décoratif.
  final ValueChanged<int>? onChange;

  /// Complément affiché dans le libellé, plus petit et sans gras :
  /// `<span class="text-outline font-normal text-[9px]">(POS)</span>`.
  final String? suffixeLibelle;

  /// Précision sous le champ. À n'utiliser que si toutes les colonnes de la
  /// même ligne en ont une, sans quoi la ligne se désaligne.
  final String? note;

  /// Message d'erreur : le champ passe en rouge et l'explication s'affiche
  /// dessous (suivi du stock d'œufs).
  final String? erreur;

  /// Hauteur du champ. Voir [hauteurStandard].
  final double hauteur;

  /// Affiche les boutons `−` et `+` de part et d'autre du champ.
  final bool pasAPas;

  /// Incrément d'un appui. Toujours strictement positif.
  final int pas;

  bool get _lectureSeule => onChange == null;

  @override
  Widget build(BuildContext context) {
    final couleurBordure = erreur != null
        ? AppColors.errorDeep
        : AppColors.outlineVariant;
    final couleurFond = switch ((erreur, _lectureSeule)) {
      (final String _, _) => AppColors.errorContainer,
      (_, true) => AppColors.surfaceZebra,
      _ => AppColors.surfaceCard,
    };

    final avecBoutons = pasAPas && !_lectureSeule;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: libelle.toUpperCase(),
            children: [
              if (suffixeLibelle != null)
                TextSpan(
                  text: ' $suffixeLibelle',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w400,
                    color: AppColors.outline,
                    letterSpacing: 0,
                  ),
                ),
            ],
          ),
          style: AppTypography.label,
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: hauteur,
          child: Container(
            decoration: BoxDecoration(
              color: couleurFond,
              border: Border.all(color: couleurBordure),
              borderRadius: AppRadius.cardRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                if (avecBoutons)
                  _Bouton(
                    symbole: '−',
                    // Jamais en dessous de zero (BR-ELV-001) : le bouton
                    // s'eteint plutot que de produire un negatif.
                    onTap: valeur > 0
                        ? () => onChange!((valeur - pas).clamp(0, 999999))
                        : null,
                  ),
                Expanded(child: _champ(couleurFond)),
                if (avecBoutons)
                  _Bouton(
                    symbole: '+',
                    onTap: () => onChange!(valeur + pas),
                  ),
              ],
            ),
          ),
        ),
        if (erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(erreur!, style: AppTypography.invalidFeedback),
          )
        else if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              note!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                color: AppColors.outline,
              ),
            ),
          ),
      ],
    );
  }

  Widget _champ(Color fond) => TextFormField(
    // La cle porte la valeur : quand un autre jour est selectionne, ou quand
    // un bouton l'a fait varier, le champ doit repartir de cette valeur-la.
    // Sans elle, `initialValue` serait ignore et l'ancienne saisie resterait
    // affichee.
    key: ValueKey('$libelle-$valeur-$_lectureSeule'),
    initialValue: '$valeur',
    readOnly: _lectureSeule,
    keyboardType: TextInputType.number,
    inputFormatters: FormatteursSaisie.entierPositif,
    textAlign: pasAPas ? TextAlign.center : TextAlign.start,
    onChanged: _lectureSeule ? null : (v) => onChange!(int.tryParse(v) ?? 0),
    style: TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 14, // `text-sm`
      fontWeight: pasAPas ? FontWeight.w700 : FontWeight.w400,
      color: _lectureSeule ? AppColors.outline : AppColors.onSurface,
    ),
    decoration: InputDecoration(
      isDense: true,
      filled: true,
      fillColor: fond,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
      ),
      // La bordure est portee par le conteneur : le champ n'en dessine pas une
      // seconde a l'interieur.
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
    ),
  );
}

/// Bouton `−` ou `+` du pas à pas.
class _Bouton extends StatelessWidget {
  const _Bouton({required this.symbole, required this.onTap});

  final String symbole;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final actif = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 40,
        alignment: Alignment.center,
        color: AppColors.surfaceZebra,
        child: Text(
          symbole,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: actif ? AppColors.brandNavy : AppColors.outlineVariant,
          ),
        ),
      ),
    );
  }
}
