import 'package:flutter/material.dart';

import '../../../../core/resultat/resultat.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../domain/entities/utilisateur.dart';
import '../../viewmodels/parametres_generaux_view_model.dart';

/// Modale « Ajouter un Utilisateur » — Doc F8 Onglet 3.
///
/// ⚠️ AJOUT NECESSAIRE, signalé : la modale du prototype ne comporte que **2
/// champs** (Nom Complet, Rôle). Un compte créé ainsi n'a ni identifiant de
/// connexion ni mot de passe — il serait donc **impossible de s'y connecter**,
/// et l'écran ne serait qu'une liste décorative (Master Prompt §2.3).
/// Deux champs sont ajoutés : identifiant et mot de passe (avec confirmation).
Future<Resultat<Utilisateur>?> afficherModaleUtilisateur(
  BuildContext context,
  ParametresGenerauxViewModel vm,
) {
  return AppModal.show<Resultat<Utilisateur>>(
    context,
    title: 'Ajouter un Utilisateur',
    child: _Formulaire(vm: vm),
  );
}

class _Formulaire extends StatefulWidget {
  const _Formulaire({required this.vm});

  final ParametresGenerauxViewModel vm;

  @override
  State<_Formulaire> createState() => _FormulaireState();
}

class _FormulaireState extends State<_Formulaire> {
  final _nom = TextEditingController();
  final _identifiant = TextEditingController();
  final _motDePasse = TextEditingController();
  final _confirmation = TextEditingController();
  String? _roleId;
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _nom.dispose();
    _identifiant.dispose();
    _motDePasse.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.creerUtilisateur(
      nom: _nom.text,
      identifiant: _identifiant.text,
      roleId: _roleId,
      motDePasse: _motDePasse.text,
      confirmation: _confirmation.text,
    );
    if (!mounted) return;

    if (resultat is Echec<Utilisateur>) {
      setState(() {
        _enCours = false;
        _erreur = resultat.message;
      });
      return;
    }
    Navigator.of(context).pop(resultat);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _champ('Nom Complet *', _nom),
        const SizedBox(height: AppSpacing.md),
        _champ(
          'Identifiant de Connexion *',
          _identifiant,
          note: 'Utilisé pour se connecter — pseudo ou adresse e-mail.',
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('RÔLE *', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String>(
          initialValue: _roleId,
          isExpanded: true,
          decoration: _decoration,
          hint: const Text('-- Sélectionner --', style: _style),
          items: [
            for (final role in ParametresGenerauxViewModel.rolesAttribuables)
              DropdownMenuItem(
                value: role.id,
                child: Text(role.libelle, style: _style),
              ),
          ],
          onChanged: (v) => setState(() => _roleId = v),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Le rôle Administratrice n\'est pas attribuable ici : il n\'existe '
          'que pour le compte initial.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _champ(
          'Mot de Passe *',
          _motDePasse,
          masque: true,
          note: '8 caractères minimum.',
        ),
        const SizedBox(height: AppSpacing.md),
        _champ('Confirmer le Mot de Passe *', _confirmation, masque: true),
        if (_erreur != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_erreur!, style: AppTypography.invalidFeedback),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: _enCours ? 'Création…' : 'Créer le Compte',
              onPressed: _enCours ? null : _valider,
            ),
          ],
        ),
      ],
    );
  }

  Widget _champ(
    String libelle,
    TextEditingController controleur, {
    bool masque = false,
    String? note,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(libelle.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controleur,
          obscureText: masque,
          style: _style,
          decoration: _decoration,
        ),
        if (note != null)
          Text(
            note,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              color: AppColors.outline,
            ),
          ),
      ],
    );
  }
}

const TextStyle _style = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 13,
  color: AppColors.onSurface,
);

final InputDecoration _decoration = InputDecoration(
  isDense: true,
  filled: true,
  fillColor: AppColors.surfaceCard,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  ),
  border: OutlineInputBorder(
    borderRadius: AppRadius.cardRadius,
    borderSide: const BorderSide(color: AppColors.outlineVariant),
  ),
);
