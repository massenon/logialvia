import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/resultat/resultat.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/carte_section.dart';
import '../../viewmodels/compte_view_model.dart';
import 'widgets/communs_compte.dart';

/// Mon Profil — Doc F9, fidèle à `mon-profil.html`.
///
/// Grille `lg:grid-cols-[35%_65%]` : carte d'identité à gauche, mot de passe et
/// journal d'audit à droite.
class MonProfilScreen extends StatelessWidget {
  const MonProfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CompteViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    final colonnes = AppBreakpoints.estLg(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EnteteCompte(
            icone: Symbols.person,
            titre: 'Mon Profil',
            sousTitre:
                'Informations de session, sécurité et journal d\'activité '
                'personnel.',
          ),
          const SizedBox(height: AppSpacing.lg),
          if (colonnes)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 35, child: _CarteIdentite(vm: vm)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 65,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FormulaireMotDePasse(vm: vm),
                        const SizedBox(height: AppSpacing.md),
                        _JournalAudit(vm: vm),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _CarteIdentite(vm: vm),
            const SizedBox(height: AppSpacing.md),
            _FormulaireMotDePasse(vm: vm),
            const SizedBox(height: AppSpacing.md),
            _JournalAudit(vm: vm),
          ],
        ],
      ),
    );
  }
}

class _CarteIdentite extends StatelessWidget {
  const _CarteIdentite({required this.vm});

  final CompteViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandNavy,
              ),
              child: Text(
                vm.initiales,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            vm.nomAffiche,
            textAlign: TextAlign.center,
            style: grasCompte.copyWith(color: AppColors.brandNavy),
          ),
          Text(
            vm.identifiant,
            textAlign: TextAlign.center,
            style: texteCompte.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppColors.brandNavy.withValues(alpha: 0.1),
                borderRadius: AppRadius.pill,
                border: Border.all(
                  color: AppColors.brandNavy.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                vm.libelleRole,
                style: grasCompte.copyWith(color: AppColors.brandNavy),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceZebra,
              borderRadius: AppRadius.cardRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'MÉTADONNÉES DE SESSION',
                  style: AppTypography.label,
                ),
                const SizedBox(height: AppSpacing.sm),
                _LigneMeta(
                  libelle: 'Dernière connexion',
                  valeur: vm.metadonnees.derniereConnexion == null
                      ? 'Première connexion'
                      : '${Formats.date(vm.metadonnees.derniereConnexion!)} '
                            '${Formats.heure(vm.metadonnees.derniereConnexion!)}',
                ),
                _LigneMeta(
                  libelle: 'Connexions enregistrées',
                  valeur: '${vm.metadonnees.nombreConnexions}',
                ),
                const _LigneMeta(
                  libelle: 'Statut du compte',
                  valeur: 'Actif',
                  couleur: AppColors.successDeep,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const NoteCompte(
            texte:
                'Ces informations sont en lecture seule. Seule une '
                'Administratrice peut modifier les détails du profil depuis '
                'Paramètres Généraux > Gestion Utilisateurs.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const NoteCompte(
            neutre: true,
            texte:
                'L\'adresse IP affichée par la maquette n\'est pas reprise : '
                'l\'application est monoposte et hors-ligne, il n\'existe ni '
                'session distante ni adresse à journaliser. Le nombre de '
                'connexions enregistrées, lui, est réel.',
          ),
        ],
      ),
    );
  }
}

class _LigneMeta extends StatelessWidget {
  const _LigneMeta({required this.libelle, required this.valeur, this.couleur});

  final String libelle;
  final String valeur;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              libelle,
              style: texteCompte.copyWith(color: AppColors.outline),
            ),
          ),
          Text(valeur, style: grasCompte.copyWith(color: couleur)),
        ],
      ),
    );
  }
}

class _FormulaireMotDePasse extends StatefulWidget {
  const _FormulaireMotDePasse({required this.vm});

  final CompteViewModel vm;

  @override
  State<_FormulaireMotDePasse> createState() => _FormulaireMotDePasseState();
}

class _FormulaireMotDePasseState extends State<_FormulaireMotDePasse> {
  final _ancien = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _ancien.dispose();
    _nouveau.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _soumettre() async {
    setState(() {
      _erreur = null;
      _enCours = true;
    });

    final resultat = await widget.vm.changerMotDePasse(
      ancien: _ancien.text,
      nouveau: _nouveau.text,
      confirmation: _confirmation.text,
    );

    if (!mounted) return;
    setState(() => _enCours = false);

    switch (resultat) {
      case Succes():
        _ancien.clear();
        _nouveau.clear();
        _confirmation.clear();
        showAppToast(context, 'Mot de passe mis à jour avec succès.');
      case Echec(:final message):
        setState(() => _erreur = message);
        showAppToast(context, message, type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      cibleTour: 'profil-identite',
      titre: 'Modifier le Mot de Passe',
      icone: Symbols.lock,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChampCompte(
              libelle: 'Ancien mot de passe *',
              controleur: _ancien,
              masque: true,
            ),
            const SizedBox(height: AppSpacing.md),
            ChampCompte(
              libelle: 'Nouveau mot de passe *',
              controleur: _nouveau,
              masque: true,
              indication: 'Min. 8 caractères, 1 majuscule, 1 chiffre',
            ),
            const SizedBox(height: AppSpacing.md),
            ChampCompte(
              libelle: 'Confirmer le nouveau mot de passe *',
              controleur: _confirmation,
              masque: true,
            ),
            if (_erreur != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_erreur!, style: AppTypography.invalidFeedback),
            ],
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Mettre à jour le mot de passe',
                icon: Symbols.lock_reset,
                onPressed: _enCours ? null : _soumettre,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const NoteCompte(
              neutre: true,
              texte:
                  'Le mot de passe est haché en SHA-256 avec un sel aléatoire '
                  'régénéré à chaque changement, et n\'est jamais journalisé. '
                  'Les 3 règles de complexité annoncées sont réellement '
                  'appliquées — le prototype ne vérifiait que la longueur.',
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalAudit extends StatelessWidget {
  const _JournalAudit({required this.vm});

  final CompteViewModel vm;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Journal d\'Audit — Dernières Actions',
      icone: Symbols.history,
      child: vm.journal.isEmpty
          ? const EtatVide(
              message:
                  'Aucune action enregistrée pour ce compte. Le journal se '
                  'remplit au fil des connexions, ventes, achats et écritures.',
            )
          : Column(
              children: [
                const EnteteCompte2(
                  colonnes: [
                    ('DATE', 3, TextAlign.left),
                    ('ACTION', 6, TextAlign.left),
                    ('MODULE', 4, TextAlign.left),
                  ],
                ),
                for (var i = 0; i < vm.journal.length; i++)
                  LigneCompte(
                    zebre: i.isOdd,
                    cellules: [
                      (
                        Text(
                          '${Formats.date(vm.journal[i].horodatage)} '
                          '${Formats.heure(vm.journal[i].horodatage)}',
                          style: texteCompte,
                        ),
                        3,
                      ),
                      (
                        Text(
                          vm.journal[i].action,
                          style: texteCompte,
                          overflow: TextOverflow.ellipsis,
                        ),
                        6,
                      ),
                      (
                        Text(
                          vm.journal[i].module,
                          style: texteCompte.copyWith(color: AppColors.outline),
                          overflow: TextOverflow.ellipsis,
                        ),
                        4,
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}
