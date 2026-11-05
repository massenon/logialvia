import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/formatage/formats.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import 'documents_comptables.dart';
import '../../domain/entities/comptabilite.dart';
import '../viewmodels/comptabilite_view_model.dart';
import 'widgets/communs_compta.dart';

/// États Financiers — Doc F6 §4, fidèle à `etats-financiers.html`.
///
/// 4 onglets : Bilan · Compte de Résultat · Flux de Trésorerie (TAFIRE) ·
/// Notes Annexes.
///
/// **BR-CPT-005** : les trois premiers onglets lisent le *même*
/// `ComptabiliteViewModel`, dont le Résultat Net vient d'une source unique
/// (`CalculerResultatNet`). Le Résultat affiché au Bilan, celui du Compte de
/// Résultat et celui du TAFIRE sont donc le même nombre par construction — pas
/// par coïncidence de trois calculs parallèles.
class EtatsFinanciersScreen extends StatefulWidget {
  const EtatsFinanciersScreen({super.key});

  @override
  State<EtatsFinanciersScreen> createState() => _EtatsFinanciersScreenState();
}

class _EtatsFinanciersScreenState extends State<EtatsFinanciersScreen> {
  int _onglet = 0;

  static const List<String> _titres = [
    'Bilan',
    'Compte de Résultat',
    'Flux de Trésorerie',
    'Notes Annexes',
  ];

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ComptabiliteViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.description,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'États Financiers',
                  style: AppTypography.pageTitle,
                ),
              ),
              SelecteurExercice(vm: vm),
              const SizedBox(width: AppSpacing.md),
              // « Exporter PDF (Onglet Actif) » — le prototype clone le panneau
              // de l'onglet affiche, pas les quatre.
              BoutonExportPdf(
                libelle: 'Exporter PDF (Onglet Actif)',
                construire: () => switch (_onglet) {
                  0 => DocumentsComptables.bilan(vm),
                  1 => DocumentsComptables.compteDeResultat(vm),
                  2 => DocumentsComptables.tafire(vm),
                  _ => DocumentsComptables.notesAnnexes(vm),
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Bilan, Compte de Résultat, Tableau des Flux de Trésorerie et '
            'Notes Annexes — conformité SYSCOHADA.',
            style: texteCompta.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.md),
          _BarreOnglets(
            titres: _titres,
            actif: _onglet,
            onChange: (i) => setState(() => _onglet = i),
          ),
          const SizedBox(height: AppSpacing.md),
          switch (_onglet) {
            0 => _OngletBilan(vm: vm),
            1 => _OngletCompteResultat(vm: vm),
            2 => _OngletTafire(vm: vm),
            _ => _OngletNotes(vm: vm),
          },
        ],
      ),
    );
  }
}

class _BarreOnglets extends StatelessWidget {
  const _BarreOnglets({
    required this.titres,
    required this.actif,
    required this.onChange,
  });

  final List<String> titres;
  final int actif;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
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
                  style: grasCompta.copyWith(
                    color: i == actif
                        ? AppColors.brandNavy
                        : AppColors.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Onglet 1

class _OngletBilan extends StatelessWidget {
  const _OngletBilan({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final bilan = vm.bilan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            border: Border.all(color: AppColors.outlineVariant),
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: texteCompta.copyWith(color: AppColors.outline),
                    children: [
                      const TextSpan(text: 'Situation au '),
                      TextSpan(
                        text: Formats.date(DateTime.now()),
                        style: grasCompta.copyWith(color: AppColors.brandNavy),
                      ),
                      TextSpan(
                        text:
                            ' — Exercice ${vm.exercice} '
                            '(${vm.exerciceEstCloture ? 'clôturé' : 'non clôturé'})',
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: bilan.estEquilibre
                      ? AppColors.successContainer
                      : AppColors.errorContainer,
                  borderRadius: AppRadius.pill,
                ),
                child: Text(
                  bilan.estEquilibre
                      ? 'Actif = Passif'
                      : 'Déséquilibre de '
                            '${Formats.montant((bilan.totalActif - bilan.totalPassif).abs())}',
                  style: texteCompta.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: bilan.estEquilibre
                        ? AppColors.successDeep
                        : AppColors.errorDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ColonneBilan(
                  titre: 'ACTIF',
                  sousTitre: '(Emplois)',
                  postes: bilan.actif,
                  total: bilan.totalActif,
                  libelleTotal: 'TOTAL GÉNÉRAL ACTIF',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _ColonneBilan(
                  titre: 'PASSIF',
                  sousTitre: '(Ressources)',
                  postes: bilan.passif,
                  total: bilan.totalPassif,
                  libelleTotal: 'TOTAL GÉNÉRAL PASSIF',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColonneBilan extends StatelessWidget {
  const _ColonneBilan({
    required this.titre,
    required this.sousTitre,
    required this.postes,
    required this.total,
    required this.libelleTotal,
  });

  final String titre;
  final String sousTitre;
  final List<PosteEtat> postes;
  final double total;
  final String libelleTotal;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.cardRadius,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          border: Border.all(color: AppColors.outlineVariant),
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: AppColors.brandNavy,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Text(
                    titre,
                    style: AppTypography.sectionTitle.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    sousTitre,
                    style: texteCompta.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            if (postes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: EtatVide(
                  message:
                      'Aucun compte de cette colonne n\'est mouvementé sur '
                      'l\'exercice.',
                ),
              )
            else
              for (final poste in postes)
                if (!poste.estTotal) LignePosteEtat(poste: poste),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.brandGold.withValues(alpha: 0.1),
                border: const Border(
                  top: BorderSide(color: AppColors.brandNavy, width: 2),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      libelleTotal,
                      style: grasCompta.copyWith(
                        fontSize: 13,
                        color: AppColors.brandNavy,
                      ),
                    ),
                  ),
                  Text(
                    Formats.nombre(total),
                    style: grasCompta.copyWith(
                      fontSize: 13,
                      color: AppColors.brandNavy,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Onglet 2

class _OngletCompteResultat extends StatelessWidget {
  const _OngletCompteResultat({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cr = vm.compteResultat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _CadreEtat(
            titre: 'COMPTE DE RÉSULTAT — Structure en Cascade SYSCOHADA',
            postes: cr.postes,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Text(
            'Le Résultat Net de l\'Exercice ci-dessus est calculé depuis la '
            'même source que celui affiché au Bilan (BR-CPT-005) — les deux '
            'valeurs sont toujours strictement identiques.',
            style: texteCompta.copyWith(
              fontSize: 11,
              color: AppColors.outline,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- Onglet 3

class _OngletTafire extends StatelessWidget {
  const _OngletTafire({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final tafire = vm.tafire;

    // Le prototype annonce cette verification sans jamais la faire : la
    // Tresorerie de cloture du TAFIRE doit egaler la Tresorerie-Actif du Bilan.
    final tresorerieBilan = vm.tresorerie;
    final ecart = tafire.tresorerieCloture - tresorerieBilan;
    final coherent = ecart.abs() < 0.01;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _CadreEtat(
            titre: 'TABLEAU DES FLUX DE TRÉSORERIE (TAFIRE simplifié)',
            postes: tafire.postes,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Text(
            'La Trésorerie à la Clôture doit être égale à la Trésorerie-Actif '
            'du Bilan (onglet Bilan) — vérification automatique ci-dessous.',
            style: texteCompta.copyWith(
              fontSize: 11,
              color: AppColors.outline,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: coherent
                  ? AppColors.successContainer
                  : AppColors.errorContainer,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(
                color: coherent ? AppColors.successDeep : AppColors.errorDeep,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  coherent ? Symbols.check_circle : Symbols.error,
                  size: 18,
                  color: coherent
                      ? AppColors.successDeep
                      : AppColors.errorDeep,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    coherent
                        ? 'Trésorerie de clôture (TAFIRE) = Trésorerie-Actif '
                              '(Bilan) = ${Formats.montant(tresorerieBilan)}.'
                        : 'Incohérence de ${Formats.montant(ecart.abs())} entre '
                              'la Trésorerie de clôture du TAFIRE '
                              '(${Formats.montant(tafire.tresorerieCloture)}) '
                              'et la Trésorerie-Actif du Bilan '
                              '(${Formats.montant(tresorerieBilan)}).',
                    style: texteCompta.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                      color: coherent
                          ? AppColors.successDeep
                          : AppColors.errorDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CadreEtat extends StatelessWidget {
  const _CadreEtat({required this.titre, required this.postes});

  final String titre;
  final List<PosteEtat> postes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.cardRadius,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          border: Border.all(color: AppColors.outlineVariant),
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: AppColors.brandNavy,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                titre,
                style: AppTypography.sectionTitle.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
            for (final poste in postes) LignePosteEtat(poste: poste),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Onglet 4

/// Notes Annexes — les 5 notes obligatoires de Doc F6 §4.
///
/// Notes **2, 3 et 4** sont calculées depuis la balance : les valoriser à la
/// main permettrait de publier une annexe qui contredit le bilan qu'elle
/// commente. Notes **1 et 5** sont rédactionnelles et donc saisies, avec le
/// texte du prototype comme point de départ ; elles sont persistées dans
/// `NOTES_ANNEXES` par exercice.
class _OngletNotes extends StatelessWidget {
  const _OngletNotes({required this.vm});

  final ComptabiliteViewModel vm;

  static const String _texteNote1ParDefaut =
      'Les immobilisations sont amorties selon la méthode linéaire. Les stocks '
      '(intrants provende et produits finis) sont valorisés au Prix Moyen '
      'Pondéré (PMP). La monnaie de présentation est le Franc CFA (FCFA), sans '
      'décimale.';

  static const String _texteNote5ParDefaut =
      'Néant à la date de clôture de la période présentée.';

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NoteRedactionnelle(
            vm: vm,
            numero: 1,
            titre: NoteAnnexe.titresObligatoires[1]!,
            texteParDefaut: _texteNote1ParDefaut,
          ),
          const SizedBox(height: AppSpacing.md),
          _NoteImmobilisations(vm: vm),
          const SizedBox(height: AppSpacing.md),
          _NoteStocks(vm: vm),
          const SizedBox(height: AppSpacing.md),
          _NoteCreancesDettes(vm: vm),
          const SizedBox(height: AppSpacing.md),
          _NoteRedactionnelle(
            vm: vm,
            numero: 5,
            titre: NoteAnnexe.titresObligatoires[5]!,
            texteParDefaut: _texteNote5ParDefaut,
          ),
        ],
      ),
    );
  }
}

class _NoteRedactionnelle extends StatefulWidget {
  const _NoteRedactionnelle({
    required this.vm,
    required this.numero,
    required this.titre,
    required this.texteParDefaut,
  });

  final ComptabiliteViewModel vm;
  final int numero;
  final String titre;
  final String texteParDefaut;

  @override
  State<_NoteRedactionnelle> createState() => _NoteRedactionnelleState();
}

class _NoteRedactionnelleState extends State<_NoteRedactionnelle> {
  late final TextEditingController _controleur;
  bool _modifie = false;

  @override
  void initState() {
    super.initState();
    final enregistre = widget.vm.contenuNote(widget.numero);
    _controleur = TextEditingController(
      text: enregistre.isEmpty ? widget.texteParDefaut : enregistre,
    );
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      cibleTour: 'etats-financiers-corps',
      titre: 'Note ${widget.numero} — ${widget.titre}',
      action: _modifie
          ? AppButton(
              label: 'Enregistrer',
              icon: Symbols.save,
              height: 32,
              onPressed: () async {
                final resultat = await widget.vm.enregistrerNote(
                  NoteAnnexe(
                    numero: widget.numero,
                    titre: widget.titre,
                    contenu: _controleur.text.trim(),
                  ),
                );
                if (!context.mounted) return;
                switch (resultat) {
                  case Succes():
                    setState(() => _modifie = false);
                    showAppToast(
                      context,
                      'Note ${widget.numero} enregistrée.',
                    );
                  case Echec(:final message):
                    showAppToast(context, message, type: ToastType.error);
                }
              },
            )
          : null,
      child: TextField(
        controller: _controleur,
        maxLines: null,
        minLines: 3,
        style: texteCompta.copyWith(height: 1.6),
        decoration: decorationCompta,
        onChanged: (_) {
          if (!_modifie) setState(() => _modifie = true);
        },
      ),
    );
  }
}

class _NoteImmobilisations extends StatelessWidget {
  const _NoteImmobilisations({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    // Classe 2 : les comptes 28x portent les amortissements (crediteurs), tous
    // les autres la valeur brute (debiteurs).
    final lignes = vm.balance.where((l) => l.numeroCompte.startsWith('2'));
    final brutes = lignes.where((l) => !l.numeroCompte.startsWith('28'));
    final amortissements = lignes.where(
      (l) => l.numeroCompte.startsWith('28'),
    );

    final totalBrut = brutes.fold<double>(
      0,
      (s, l) => s + l.finalDebit - l.finalCredit,
    );
    final totalAmort = amortissements.fold<double>(
      0,
      (s, l) => s + l.finalCredit - l.finalDebit,
    );

    return CarteSection(
      titre: 'Note 2 — ${NoteAnnexe.titresObligatoires[2]}',
      child: brutes.isEmpty && amortissements.isEmpty
          ? const EtatVide(
              message:
                  'Aucune immobilisation enregistrée. Le plan comptable ne '
                  'comporte aujourd\'hui aucun compte de classe 2 mouvementé — '
                  'les bâtiments d\'élevage et le matériel doivent y être '
                  'saisis pour apparaître ici.',
            )
          : Column(
              children: [
                const EnteteCompta(
                  colonnes: [
                    ('NATURE', 4, TextAlign.left),
                    ('VALEUR BRUTE', 2, TextAlign.right),
                    ('AMORT. CUMULÉS', 2, TextAlign.right),
                    ('VALEUR NETTE', 2, TextAlign.right),
                  ],
                ),
                for (var i = 0; i < brutes.length; i++)
                  () {
                    final ligne = brutes.elementAt(i);
                    final brut = ligne.finalDebit - ligne.finalCredit;
                    // Amortissement associe : 28 + les 2 chiffres du compte.
                    final suffixe = ligne.numeroCompte.substring(1);
                    final amort = amortissements
                        .where((a) => a.numeroCompte.startsWith('28$suffixe'))
                        .fold<double>(
                          0,
                          (s, a) => s + a.finalCredit - a.finalDebit,
                        );
                    return LigneCompta(
                      zebre: i.isOdd,
                      cellules: [
                        (Text(ligne.libelle, style: texteCompta), 4),
                        (
                          Text(
                            montantOuTiret(brut),
                            textAlign: TextAlign.right,
                            style: montantCompta,
                          ),
                          2,
                        ),
                        (
                          Text(
                            montantOuTiret(amort),
                            textAlign: TextAlign.right,
                            style: montantCompta.copyWith(
                              color: amort.abs() < 0.01
                                  ? null
                                  : AppColors.errorDeep,
                            ),
                          ),
                          2,
                        ),
                        (
                          Text(
                            montantOuTiret(brut - amort),
                            textAlign: TextAlign.right,
                            style: montantCompta.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          2,
                        ),
                      ],
                    );
                  }(),
                _LigneTotalNote(
                  libelle: 'Total Immobilisations',
                  montants: [totalBrut, totalAmort, totalBrut - totalAmort],
                  flexLibelle: 4,
                ),
              ],
            ),
    );
  }
}

class _NoteStocks extends StatelessWidget {
  const _NoteStocks({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final lignes = vm.balance
        .where((l) => l.numeroCompte.startsWith('3'))
        .toList();
    final total = lignes.fold<double>(
      0,
      (s, l) => s + l.finalDebit - l.finalCredit,
    );

    return CarteSection(
      titre: 'Note 3 — ${NoteAnnexe.titresObligatoires[3]}',
      child: lignes.isEmpty
          ? const EtatVide(
              message:
                  'Aucun compte de stock (classe 3) n\'est mouvementé. La '
                  'valorisation des intrants est tenue par le module Stocks & '
                  'Achats ; sa reprise en comptabilité suppose une écriture '
                  'd\'inventaire, non encore automatisée.',
            )
          : Column(
              children: [
                const EnteteCompta(
                  colonnes: [
                    ('CATÉGORIE', 6, TextAlign.left),
                    ('VALEUR (FCFA)', 3, TextAlign.right),
                  ],
                ),
                for (var i = 0; i < lignes.length; i++)
                  LigneCompta(
                    zebre: i.isOdd,
                    cellules: [
                      (Text(lignes[i].libelle, style: texteCompta), 6),
                      (
                        Text(
                          montantOuTiret(
                            lignes[i].finalDebit - lignes[i].finalCredit,
                          ),
                          textAlign: TextAlign.right,
                          style: montantCompta,
                        ),
                        3,
                      ),
                    ],
                  ),
                _LigneTotalNote(
                  libelle: 'Total Stocks',
                  montants: [total],
                  flexLibelle: 6,
                  flexMontant: 3,
                ),
              ],
            ),
    );
  }
}

class _NoteCreancesDettes extends StatelessWidget {
  const _NoteCreancesDettes({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final tiers = vm.balance
        .where((l) => l.numeroCompte.startsWith('4'))
        .where(
          (l) => l.finalDebit.abs() >= 0.01 || l.finalCredit.abs() >= 0.01,
        )
        .toList();

    return CarteSection(
      titre: 'Note 4 — ${NoteAnnexe.titresObligatoires[4]}',
      child: tiers.isEmpty
          ? const EtatVide(
              message:
                  'Aucune créance client ni dette fournisseur à la date de '
                  'clôture : tout a été réglé comptant.',
            )
          : Column(
              children: [
                const EnteteCompta(
                  colonnes: [
                    ('COMPTE', 2, TextAlign.left),
                    ('INTITULÉ', 5, TextAlign.left),
                    ('NATURE', 2, TextAlign.left),
                    ('MONTANT', 2, TextAlign.right),
                  ],
                ),
                for (var i = 0; i < tiers.length; i++)
                  () {
                    final ligne = tiers[i];
                    final creance = ligne.finalDebit.abs() >= 0.01;
                    return LigneCompta(
                      zebre: i.isOdd,
                      cellules: [
                        (
                          Text(
                            ligne.numeroCompte,
                            style: texteCompta.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          2,
                        ),
                        (
                          Text(
                            ligne.libelle,
                            style: texteCompta,
                            overflow: TextOverflow.ellipsis,
                          ),
                          5,
                        ),
                        (
                          Text(
                            creance ? 'Créance' : 'Dette',
                            style: texteCompta.copyWith(
                              color: AppColors.outline,
                            ),
                          ),
                          2,
                        ),
                        (
                          Text(
                            Formats.nombre(
                              creance ? ligne.finalDebit : ligne.finalCredit,
                            ),
                            textAlign: TextAlign.right,
                            style: montantCompta.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.errorDeep,
                            ),
                          ),
                          2,
                        ),
                      ],
                    );
                  }(),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'L\'ancienneté des créances affichée par le prototype '
                  '(« 12 jours », « Urgent ») n\'est pas reprise ici : elle se '
                  'calcule sur les échéances client du module Ventes, pas sur '
                  'les soldes comptables agrégés. Le suivi client par client '
                  'est disponible sur l\'écran Clients & Créances.',
                  style: texteCompta.copyWith(
                    fontSize: 11,
                    color: AppColors.outline,
                    height: 1.5,
                  ),
                ),
              ],
            ),
    );
  }
}

class _LigneTotalNote extends StatelessWidget {
  const _LigneTotalNote({
    required this.libelle,
    required this.montants,
    required this.flexLibelle,
    this.flexMontant = 2,
  });

  final String libelle;
  final List<double> montants;
  final int flexLibelle;
  final int flexMontant;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceZebra,
        border: Border(
          top: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: flexLibelle, child: Text(libelle, style: grasCompta)),
          for (final montant in montants)
            Expanded(
              flex: flexMontant,
              child: Text(
                montantOuTiret(montant),
                textAlign: TextAlign.right,
                style: grasCompta.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
