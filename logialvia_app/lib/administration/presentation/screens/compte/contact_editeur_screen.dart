import '../../../../core/widgets/auteur_courant.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/resultat/resultat.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/carte_section.dart';
import '../../../data/tables/messages_editeur_table.dart';
import '../../../domain/entities/compte_utilisateur.dart';
import '../../viewmodels/compte_view_model.dart';
import 'widgets/communs_compte.dart';

/// Contactez l'Éditeur — Doc F9, d'après `contact-editeur.html`.
///
/// ## ÉCART_DELIBERE — le formulaire du prototype n'envoie rien
///
/// `submitContactForm()` affiche `showToast('Message envoyé à l'éditeur.')`
/// **sans rien envoyer ni rien conserver** : c'est exactement l'anti-patron que
/// le Master Prompt §2.3 interdit, le même que `validateSale()`. L'application
/// est hors-ligne et aucun transport e-mail n'est configuré — le mot de passe
/// SMTP n'est d'ailleurs volontairement pas stocké (Doc I3 §3).
///
/// Deux issues honnêtes étaient possibles : retirer les formulaires, ou leur
/// donner un effet réel. La seconde a été retenue. Le message est **enregistré**
/// dans `MESSAGES_EDITEUR`, **copié dans le presse-papiers** prêt à être envoyé,
/// et l'écran affiche le numéro de l'éditeur. Rien n'est perdu, rien n'est
/// promis à tort.
class ContactEditeurScreen extends StatefulWidget {
  const ContactEditeurScreen({super.key});

  @override
  State<ContactEditeurScreen> createState() => _ContactEditeurScreenState();
}

class _ContactEditeurScreenState extends State<ContactEditeurScreen> {
  int _onglet = 0;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CompteViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EnteteCompte(
            icone: Symbols.support_agent,
            titre: 'Contactez l\'Éditeur',
            sousTitre:
                '${Editeur.societe} — Question générale ou signalement d\'un '
                'problème technique.',
          ),
          const SizedBox(height: AppSpacing.md),
          _BarreOnglets(
            actif: _onglet,
            onChange: (i) => setState(() => _onglet = i),
          ),
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Formulaire(
                  key: ValueKey(_onglet),
                  vm: vm,
                  estBug: _onglet == 1,
                ),
                const SizedBox(height: AppSpacing.md),
                _MessagesEnregistres(vm: vm),
                const SizedBox(height: AppSpacing.md),
                const _AutresMoyens(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarreOnglets extends StatelessWidget {
  const _BarreOnglets({required this.actif, required this.onChange});

  final int actif;
  final ValueChanged<int> onChange;

  static const List<String> _titres = [
    'Question Générale',
    'Signaler un Problème',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _titres.length; i++)
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
                  _titres[i],
                  style: grasCompte.copyWith(
                    color: i == actif ? AppColors.brandNavy : AppColors.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Formulaire extends StatefulWidget {
  const _Formulaire({super.key, required this.vm, required this.estBug});

  final CompteViewModel vm;
  final bool estBug;

  @override
  State<_Formulaire> createState() => _FormulaireState();
}

class _FormulaireState extends State<_Formulaire> {
  final _objet = TextEditingController();
  final _message = TextEditingController();
  final _etapes = TextEditingController();
  String? _module;
  String? _erreur;
  bool _enCours = false;

  /// Les 7 options du sélecteur « Module Concerné » de `contact-editeur.html`.
  static const List<String> _modules = [
    'Élevage & Couveuse',
    'Ventes & Clients',
    'Achats & Fournisseurs',
    'Stocks & Catalogue',
    'Santé Animale',
    'Comptabilité',
    'Autre',
  ];

  @override
  void dispose() {
    _objet.dispose();
    _message.dispose();
    _etapes.dispose();
    super.dispose();
  }

  Future<void> _soumettre() async {
    setState(() {
      _erreur = null;
      _enCours = true;
    });

    final resultat = await widget.vm.enregistrerMessage(
      type: widget.estBug ? 'bug' : 'question',
      sujet: widget.estBug ? (_module ?? '') : _objet.text,
      message: _message.text,
      etapes: widget.estBug ? _etapes.text : null,
    );

    if (!mounted) return;
    setState(() => _enCours = false);

    switch (resultat) {
      case Succes(:final valeur):
        await Clipboard.setData(
          ClipboardData(text: widget.vm.texteAEnvoyer(valeur)),
        );
        if (!mounted) return;
        _objet.clear();
        _message.clear();
        _etapes.clear();
        setState(() => _module = null);
        showAppToast(
          context,
          widget.estBug
              ? 'Rapport enregistré et copié dans le presse-papiers — '
                    'transmettez-le au ${Editeur.telephone}.'
              : 'Message enregistré et copié dans le presse-papiers — '
                    'transmettez-le au ${Editeur.telephone}.',
        );
      case Echec(:final message):
        setState(() => _erreur = message);
        showAppToast(context, message, type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      cibleTour: 'contact-formulaire',
      titre: widget.estBug
          ? 'Signaler un problème technique'
          : 'Poser une question générale',
      icone: widget.estBug ? Symbols.bug_report : Symbols.contact_support,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.estBug) ...[
            const Text('MODULE CONCERNÉ *', style: AppTypography.label),
            const SizedBox(height: AppSpacing.xs),
            DropdownButtonFormField<String>(
              initialValue: _module,
              isExpanded: true,
              style: texteCompte,
              hint: const Text('-- Sélectionner --', style: texteCompte),
              decoration: InputDecoration(
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
              ),
              items: [
                for (final m in _modules)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m, style: texteCompte),
                  ),
              ],
              onChanged: (v) => setState(() => _module = v),
            ),
            const SizedBox(height: AppSpacing.md),
            ChampCompte(
              libelle: 'Description du problème *',
              controleur: _message,
              lignes: 4,
              indication: 'Que s\'est-il passé ? Qu\'attendiez-vous ?',
            ),
            const SizedBox(height: AppSpacing.md),
            ChampCompte(
              libelle: 'Étapes pour reproduire',
              controleur: _etapes,
              lignes: 3,
              indication: '1. Aller dans... 2. Cliquer sur...',
            ),
          ] else ...[
            ChampCompte(
              libelle: 'Objet *',
              controleur: _objet,
              indication: 'ex : Question sur le module Comptabilité',
            ),
            const SizedBox(height: AppSpacing.md),
            ChampCompte(
              libelle: 'Message *',
              controleur: _message,
              lignes: 6,
              indication: 'Décrivez votre question ou suggestion...',
            ),
          ],
          if (_erreur != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_erreur!, style: AppTypography.invalidFeedback),
          ],
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: widget.estBug
                  ? 'Enregistrer et copier le rapport'
                  : 'Enregistrer et copier le message',
              icon: Symbols.content_copy,
              onPressed: _enCours ? null : _soumettre,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const NoteCompte(
            texte:
                'L\'application est hors-ligne et n\'envoie aucun e-mail. Le '
                'message est enregistré ci-dessous et copié dans le '
                'presse-papiers : collez-le dans WhatsApp ou dans votre '
                'messagerie, à destination du ${Editeur.telephone}. Le '
                'prototype web affichait « Message envoyé » sans rien envoyer.',
          ),
          if (widget.estBug) ...[
            const SizedBox(height: AppSpacing.sm),
            const NoteCompte(
              neutre: true,
              texte:
                  'La capture d\'écran prévue par la maquette n\'est pas '
                  'reprise : le modèle de données ne comporte aucun champ de '
                  'pièce jointe et l\'application ne stocke aucun fichier. '
                  'Décrivez plutôt les étapes de reproduction ci-dessus.',
            ),
          ],
        ],
      ),
    );
  }
}

class _MessagesEnregistres extends StatelessWidget {
  const _MessagesEnregistres({required this.vm});

  final CompteViewModel vm;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Messages enregistrés (${vm.messages.length})',
      icone: Symbols.outbox,
      child: vm.messages.isEmpty
          ? const EtatVide(
              message:
                  'Aucun message enregistré. Ceux que vous rédigez ci-dessus '
                  'sont conservés ici jusqu\'à ce que vous les marquiez comme '
                  'transmis.',
            )
          : Column(
              children: [
                for (var i = 0; i < vm.messages.length; i++)
                  _LigneMessage(
                    message: vm.messages[i],
                    vm: vm,
                    zebre: i.isOdd,
                  ),
              ],
            ),
    );
  }
}

class _LigneMessage extends StatelessWidget {
  const _LigneMessage({
    required this.message,
    required this.vm,
    required this.zebre,
  });

  final MessageEditeur message;
  final CompteViewModel vm;
  final bool zebre;

  @override
  Widget build(BuildContext context) {
    final transmis = message.statut == MessageEditeurStatut.transmis;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: zebre ? AppColors.surfaceZebra : null,
        border: const Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            message.estBug ? Symbols.bug_report : Symbols.contact_support,
            size: 18,
            color: message.estBug ? AppColors.errorDeep : AppColors.brandNavy,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(message.sujet, style: grasCompte)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: transmis
                            ? AppColors.successContainer
                            : AppColors.brandGold.withValues(alpha: 0.2),
                        borderRadius: AppRadius.pill,
                      ),
                      child: Text(
                        message.statut,
                        style: texteCompte.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: transmis
                              ? AppColors.successDeep
                              : AppColors.brandNavy,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${Formats.date(message.horodatage)} '
                  '${Formats.heure(message.horodatage)}',
                  style: texteCompte.copyWith(
                    fontSize: 10,
                    color: AppColors.outline,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: texteCompte.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Symbols.content_copy, size: 18),
                color: AppColors.brandNavy,
                tooltip: 'Copier à nouveau',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: vm.texteAEnvoyer(message)),
                  );
                  if (!context.mounted) return;
                  showAppToast(
                    context,
                    'Message copié dans le presse-papiers.',
                  );
                },
              ),
              if (!transmis)
                IconButton(
                  icon: const Icon(Symbols.mark_email_read, size: 18),
                  color: AppColors.successDeep,
                  tooltip: 'Marquer comme transmis',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final resultat = await vm.marquerTransmis(message);
                    if (!context.mounted) return;
                    switch (resultat) {
                      case Succes():
                        showAppToast(context, 'Message marqué comme transmis.');
                      case Echec(:final message):
                        showAppToast(context, message, type: ToastType.error);
                    }
                  },
                ),
              IconButton(
                icon: const Icon(Symbols.delete, size: 18),
                color: AppColors.outline,
                tooltip: 'Supprimer',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmerSuppression(context, vm, message),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmerSuppression(
  BuildContext context,
  CompteViewModel vm,
  MessageEditeur message,
) async {
  final confirme = await AppModal.show<bool>(
    context,
    title: 'Supprimer ce message ?',
    child: Text(
      '« ${message.sujet} » sera définitivement supprimé.\n\n'
      'Si vous ne l\'avez pas encore transmis à l\'éditeur, son contenu sera '
      'perdu.',
      style: texteCompte.copyWith(height: 1.5),
    ),
    actions: [
      Builder(
        builder: (ctx) => AppButton(
          label: 'Annuler',
          variant: AppButtonVariant.outline,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
      ),
      Builder(
        builder: (ctx) => AppButton(
          label: 'Supprimer',
          variant: AppButtonVariant.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ),
    ],
  );

  if (confirme != true || !context.mounted) return;
  final resultat = await vm.supprimerMessage(
    message,
    auteur: auteurCourant(context),
  );
  if (!context.mounted) return;
  switch (resultat) {
    case Succes():
      showAppToast(context, 'Message supprimé.', type: ToastType.warning);
    case Echec(:final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

class _AutresMoyens extends StatelessWidget {
  const _AutresMoyens();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Autres moyens de contact',
            style: grasCompte.copyWith(color: AppColors.brandNavy),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${Editeur.contact} — ${Editeur.role} — '
                  '${Editeur.telephone}',
                  style: texteCompte.copyWith(color: AppColors.outline),
                ),
              ),
              IconButton(
                icon: const Icon(Symbols.content_copy, size: 16),
                color: AppColors.outline,
                tooltip: 'Copier le numéro',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: Editeur.telephone),
                  );
                  if (!context.mounted) return;
                  showAppToast(context, 'Numéro copié.');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
