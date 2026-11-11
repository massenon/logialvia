import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../administration/presentation/viewmodels/auth_view_model.dart';
import '../../../administration/presentation/viewmodels/modules_actifs_view_model.dart';
import '../../router/navigation_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Recherche globale de la barre du haut.
///
/// Le prototype en a une **reelle** (`common.js` §5-BIS, `GLOBAL_SEARCH_INDEX`,
/// raccourci Ctrl+K, anti-rebond 150 ms) — ce n'est pas un champ decoratif.
/// L'index cote web est une liste de pages ; ici il est derive de
/// [NavigationModel], filtre par role et par module actif, pour qu'aucun
/// resultat ne mene a un ecran interdit ou desactive.
class RechercheGlobale extends StatefulWidget {
  const RechercheGlobale({super.key});

  @override
  State<RechercheGlobale> createState() => _RechercheGlobaleState();
}

class _RechercheGlobaleState extends State<RechercheGlobale> {
  final _controleur = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controleur.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<EntreeNavigation> _resultats(String requete) {
    if (requete.trim().isEmpty) return const [];
    final auth = context.read<AuthViewModel>();
    final modules = context.read<ModulesActifsViewModel>();
    final role = auth.session?.role.id ?? '';
    final terme = requete.trim().toLowerCase();

    return [
      for (final groupe in NavigationModel.groupes)
        if (groupe.roles.contains(role))
          for (final entree in groupe.entrees)
            if ((entree.moduleId == null || modules.estActif(entree.moduleId!)) &&
                entree.libelle.toLowerCase().contains(terme))
              entree,
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Raccourci Ctrl+K, comme cote web (common.js §5-BIS).
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _focus.requestFocus,
      },
      child: Autocomplete<EntreeNavigation>(
        optionsBuilder: (valeur) => _resultats(valeur.text),
        displayStringForOption: (entree) => entree.libelle,
        onSelected: (entree) {
          _controleur.clear();
          context.go(entree.route);
        },
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: AppRadius.cardRadius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 256, maxHeight: 280),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final entree in options)
                    ListTile(
                      dense: true,
                      leading: Icon(entree.icone, size: 18),
                      title: Text(
                        entree.libelle,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => onSelected(entree),
                    ),
                ],
              ),
            ),
          ),
        ),
        fieldViewBuilder: (context, controleur, focus, onSubmit) {
          return Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceZebra,
              border: Border.all(color: AppColors.outlineVariant),
              borderRadius: AppRadius.pill,
            ),
            child: Row(
              children: [
                const Icon(Symbols.search, size: 16, color: AppColors.outline),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: TextField(
                    controller: controleur,
                    focusNode: focus,
                    onSubmitted: (_) => onSubmit(),
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Recherche globale…',
                      hintStyle: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        color: AppColors.outline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
