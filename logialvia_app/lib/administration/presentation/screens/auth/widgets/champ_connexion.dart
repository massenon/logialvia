import 'package:material_ui/material_ui.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_typography.dart';

/// Champ du formulaire de connexion — fidele au pattern `<label>` + `<input>` +
/// `.invalid-feedback` de login.html (l.83-99).
///
/// Ne reutilise pas `AppFormField` (Doc E2 §8) : celui-ci n'a ni icone
/// prefixee, ni bouton suffixe, ni l'etat `.is-invalid` (fond rouge clair) que
/// le formulaire de connexion utilise. Un parametrage de `AppFormField` couvrant
/// ces 3 besoins n'aurait de sens que si un 2e ecran les partageait — a
/// reevaluer si le cas se represente (Master Prompt §4).
class ChampConnexion extends StatelessWidget {
  const ChampConnexion({
    super.key,
    required this.label,
    required this.controller,
    required this.iconePrefixe,
    this.placeholder,
    this.erreur,
    this.masque = false,
    this.suffixe,
    this.onSubmitted,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final IconData iconePrefixe;
  final String? placeholder;
  final String? erreur;
  final bool masque;
  final Widget? suffixe;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// Permet de donner le focus depuis l'ecran — « Se souvenir de moi »
  /// pre-remplit l'identifiant et envoie le curseur au mot de passe.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final invalide = erreur != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: AppTypography.textXs,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6, // `tracking-wider`
            color: AppColors.brandNavy,
          ),
        ),
        const SizedBox(height: 6), // `mb-1.5`
        SizedBox(
          height: 52,
          child: TextField(
            focusNode: focusNode,
            controller: controller,
            obscureText: masque,
            autofocus: autofocus,
            onSubmitted: onSubmitted,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16, // `text-section-title`
              color: AppColors.onSurface,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              // `.is-invalid{border-color:#B33A3A;background-color:#FBE3E3;}`
              fillColor: invalide
                  ? AppColors.errorContainer
                  : AppColors.surfaceCard,
              hintText: placeholder,
              hintStyle: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16, // `text-section-title`
                color: AppColors.outline,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              prefixIcon: Padding(
                // `left-4` sur une icone de 18px -> zone de 44px de large
                padding: const EdgeInsets.only(left: 16, right: 10),
                child: Icon(iconePrefixe, size: 20, color: AppColors.outline),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 48),
              suffixIcon: suffixe,
              suffixIconConstraints: const BoxConstraints(minWidth: 44),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.cardRadius,
                borderSide: BorderSide(
                  color: invalide
                      ? AppColors.errorDeep
                      : AppColors.outlineVariant,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.cardRadius,
                // `focus:ring-2 focus:ring-brand-navy`
                borderSide: BorderSide(
                  color: invalide ? AppColors.errorDeep : AppColors.brandNavy,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        if (invalide)
          Padding(
            padding: const EdgeInsets.only(top: 2), // `margin-top:2px`
            child: Text(erreur!, style: AppTypography.invalidFeedback),
          ),
      ],
    );
  }
}
