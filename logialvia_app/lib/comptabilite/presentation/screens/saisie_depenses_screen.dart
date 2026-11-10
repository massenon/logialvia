import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/formatage/formats.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import 'documents_comptables.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import '../../data/repositories/comptabilite_repository_drift.dart';
import '../../domain/entities/comptabilite.dart';
import '../viewmodels/comptabilite_view_model.dart';
import 'widgets/communs_compta.dart';
import '../../../core/saisie/formats_saisie.dart';
import '../../domain/plan_syscohada.dart';

/// Saisie des Dépenses — Doc F6, fidèle à `saisie-depenses.html`.
///
/// Une dépense n'est **pas** une entité à part : c'est une pièce comptable
/// équilibrée, charge au débit et trésorerie (ou fournisseur) au crédit. Le
/// prototype la stocke dans un tableau `DEPENSES` séparé, d'où sa
/// désynchronisation permanente avec le Journal. Ici, enregistrer une dépense
/// écrit dans `ECRITURE_COMPTABLE` : elle apparaît immédiatement au Journal, au
/// Grand Livre, dans la Balance et au Compte de Résultat.
///
/// ## Deux erreurs du prototype corrigées, signalées
///
/// 1. Le champ est libellé « Compte de Trésorerie **Débité** ». C'est l'inverse :
///    lors d'une dépense la trésorerie est **créditée** (elle diminue) et le
///    compte de charge est débité. Le libellé est corrigé ; la mécanique du
///    prototype, elle, était juste (`compteToCredit()` crédite bien 571/552).
/// 2. Le filtre de statut propose « En attente » alors que le formulaire
///    n'offre que Caisse et Mobile Money : aucune dépense saisie ne peut jamais
///    être « en attente », le filtre est décoratif. Le choix « À crédit —
///    Fournisseur (401) » est donc ajouté (ÉCART_DELIBERE), ce qui rend le
///    statut réel : une charge soldée par 401 reste due.
class SaisieDepensesScreen extends StatefulWidget {
  const SaisieDepensesScreen({super.key});

  @override
  State<SaisieDepensesScreen> createState() => _SaisieDepensesScreenState();
}

class _SaisieDepensesScreenState extends State<SaisieDepensesScreen> {
  /// Relie le bouton « Modifier » d'une ligne au formulaire pose plus haut sur
  /// la meme page — `editExpense()` remplit les champs, il n'ouvre rien.
  final _controleur = ControleurFormulaireDepense();
  final _defilement = ScrollController();

  @override
  void dispose() {
    _controleur.dispose();
    _defilement.dispose();
    super.dispose();
  }

  /// `document.querySelector('form').scrollIntoView({behavior:'smooth'})` —
  /// le formulaire est en haut, la ligne cliquee peut etre loin en dessous.
  void _modifier(Depense depense) {
    _controleur.modifier(depense);
    _defilement.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ComptabiliteViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      controller: _defilement,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.request_page,
                size: 26,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Saisie des Dépenses',
                  style: AppTypography.pageTitle,
                ),
              ),
              SelecteurExercice(vm: vm),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Charges d\'exploitation courantes de la ferme (SYSCOHADA '
            'Classe 6) — hors achats d\'intrants, déjà couverts par Achats & '
            'Commandes.',
            style: texteCompta.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Ordre de `saisie-depenses.html` : KPI, formulaire de saisie, barre
          // de filtres, tableau. Le formulaire est POSE SUR LA PAGE, pas dans
          // une modale — voir `_FormulaireDepense`.
          _KpisDepenses(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          _FormulaireDepense(vm: vm, controleur: _controleur),
          const SizedBox(height: AppSpacing.lg),
          _BarreFiltres(vm: vm),
          const SizedBox(height: AppSpacing.md),
          CarteSection(
            cibleTour: 'depenses-formulaire',
            titre: 'Dépenses enregistrées',
            icone: Symbols.receipt_long,
            child: vm.depensesFiltrees.isEmpty
                ? EtatVide(
                    message: vm.depenses.isEmpty
                        ? 'Aucune dépense enregistrée sur l\'exercice '
                              '${vm.exercice}. Utilisez « Nouvelle Dépense » '
                              'pour saisir une charge d\'exploitation ; '
                              'l\'écriture correspondante partira '
                              'automatiquement au Journal.'
                        : 'Aucune dépense ne correspond à ces filtres.',
                  )
                : _TableauDepenses(vm: vm, onModifier: _modifier),
          ),
        ],
      ),
    );
  }
}

class _KpisDepenses extends StatelessWidget {
  const _KpisDepenses({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CarteKpiDepense(
            libelle: 'Dépenses du Mois',
            valeur: Formats.montant(vm.depensesDuMois),
            accent: AppColors.brandNavy,
            icone: Symbols.payments,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _CarteKpiDepense(
            libelle: 'Charges Fixes',
            valeur: Formats.montant(vm.chargesFixes),
            accent: AppColors.brandGold,
            icone: Symbols.event_repeat,
            detail: 'Comptes ${PlanSyscohada.locations} et ${PlanSyscohada.assurances}',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _CarteKpiDepense(
            libelle: 'Charges Variables',
            valeur: Formats.montant(vm.chargesVariables),
            accent: AppColors.successDeep,
            icone: Symbols.trending_down,
            detail: 'Autres comptes de charge',
          ),
        ),
      ],
    );
  }
}

class _CarteKpiDepense extends StatelessWidget {
  const _CarteKpiDepense({
    required this.libelle,
    required this.valeur,
    required this.accent,
    required this.icone,
    this.detail,
  });

  final String libelle;
  final String valeur;
  final Color accent;
  final IconData icone;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    // ⚠️ Le liseré d'accent est peint dans un `Stack`, jamais étiré.
    //
    // La version précédente le dessinait avec un `Container(width: 4)` dans un
    // `Row(crossAxisAlignment: stretch)`. Dans une colonne défilante la hauteur
    // disponible est infinie : `stretch` réclamait alors une hauteur infinie et
    // la carte levait « BoxConstraints forces an infinite height » à chaque
    // rendu. **C'est ce qui cassait l'écran.**
    //
    // `border-l-4` serait la traduction littérale, mais Flutter refuse un
    // `borderRadius` sur une bordure de couleurs non uniformes. Le `Positioned`
    // s'étire donc sur la hauteur que le contenu impose au `Stack` — bornée par
    // construction.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
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
                  style: AppTypography.kpiValue.copyWith(fontSize: 20),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: texteCompta.copyWith(
                      fontSize: 10,
                      color: AppColors.outline,
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

/// Barre de filtres — `saisie-depenses.html` l.78-91.
///
/// C'est une **carte a part entiere**, posee entre le formulaire et le
/// tableau, pas l'en-tete du tableau. Elle porte la recherche, le filtre de
/// statut, la reinitialisation, et l'export PDF pousse a droite (`ml-auto`).
class _BarreFiltres extends StatelessWidget {
  const _BarreFiltres({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('recherche-dep-${vm.rechercheDepenses.isEmpty}'),
              initialValue: vm.rechercheDepenses,
              style: texteCompta,
              decoration: decorationCompta.copyWith(
                hintText: 'Rechercher…',
                prefixIcon: const Icon(
                  Symbols.search,
                  size: 18,
                  color: AppColors.outline,
                ),
              ),
              onChanged: vm.definirRechercheDepenses,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          DropdownButtonHideUnderline(
            child: DropdownButton<bool?>(
              value: vm.filtrePayee,
              isDense: true,
              style: texteCompta,
              hint: const Text('Tous les statuts', style: texteCompta),
              items: [
                const DropdownMenuItem<bool?>(
                  child: Text('Tous les statuts', style: texteCompta),
                ),
                const DropdownMenuItem<bool?>(
                  value: true,
                  child: Text('Payée', style: texteCompta),
                ),
                const DropdownMenuItem<bool?>(
                  value: false,
                  child: Text('En attente', style: texteCompta),
                ),
              ],
              onChanged: vm.definirFiltrePayee,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            label: 'Réinitialiser',
            icon: Symbols.filter_alt_off,
            variant: AppButtonVariant.outline,
            height: 34,
            onPressed: vm.reinitialiserFiltresDepenses,
          ),
          // `ml-auto` : l'export est pousse a droite de la barre.
          const Spacer(),
          BoutonExportPdf(construire: () => DocumentsComptables.depenses(vm)),
        ],
      ),
    );
  }
}

class _TableauDepenses extends StatelessWidget {
  const _TableauDepenses({required this.vm, required this.onModifier});

  final ComptabiliteViewModel vm;

  /// Charge la dépense dans le formulaire du haut de page — `editExpense()`.
  final ValueChanged<Depense> onModifier;

  @override
  Widget build(BuildContext context) {
    final depenses = vm.depensesFiltrees;
    final total = depenses.fold<double>(0, (s, d) => s + d.montant);

    return Column(
      children: [
        const EnteteCompta(
          colonnes: [
            ('N° PIÈCE', 2, TextAlign.left),
            ('DATE', 2, TextAlign.left),
            ('LIBELLÉ', 4, TextAlign.left),
            ('CATÉGORIE', 4, TextAlign.left),
            ('MONTANT', 2, TextAlign.right),
            ('STATUT', 2, TextAlign.center),
            ('ACTIONS', 2, TextAlign.right),
          ],
        ),
        for (var i = 0; i < depenses.length; i++)
          LigneCompta(
            zebre: i.isOdd,
            cellules: [
              (
                Text(
                  depenses[i].numeroPiece,
                  style: texteCompta.copyWith(fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
                2,
              ),
              (Text(Formats.date(depenses[i].date), style: texteCompta), 2),
              (
                Text(
                  depenses[i].libelle,
                  style: grasCompta,
                  overflow: TextOverflow.ellipsis,
                ),
                4,
              ),
              (
                Text(
                  depenses[i].categorie,
                  style: texteCompta,
                  overflow: TextOverflow.ellipsis,
                ),
                4,
              ),
              (
                Text(
                  Formats.montant(depenses[i].montant),
                  textAlign: TextAlign.right,
                  style: montantCompta.copyWith(fontWeight: FontWeight.w700),
                ),
                2,
              ),
              (_BadgeStatut(payee: depenses[i].payee), 2),
              (
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // `editExpense()` de `saisie-depenses.html` l.344 — le
                    // prototype le propose sur chaque ligne ; il manquait.
                    IconButton(
                      icon: const Icon(Symbols.edit, size: 18),
                      color: AppColors.brandNavy,
                      tooltip: 'Modifier la dépense',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onModifier(depenses[i]),
                    ),
                    IconButton(
                      icon: const Icon(Symbols.delete, size: 18),
                      color: AppColors.outline,
                      tooltip: 'Supprimer la dépense',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _confirmerSuppression(context, vm, depenses[i]),
                    ),
                  ],
                ),
                2,
              ),
            ],
          ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          color: AppColors.surfaceZebra,
          child: Row(
            children: [
              Expanded(
                flex: 12,
                child: Text(
                  'TOTAL AFFICHÉ (${depenses.length} dépense'
                  '${depenses.length > 1 ? 's' : ''})',
                  style: grasCompta,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  Formats.montant(total),
                  textAlign: TextAlign.right,
                  style: grasCompta.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Expanded(flex: 3, child: SizedBox()),
            ],
          ),
        ),
      ],
    );
  }
}

class _BadgeStatut extends StatelessWidget {
  const _BadgeStatut({required this.payee});

  final bool payee;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: payee
              ? AppColors.successContainer
              : AppColors.brandGold.withValues(alpha: 0.2),
          borderRadius: AppRadius.pill,
          border: Border.all(
            color: payee
                ? AppColors.successDeep.withValues(alpha: 0.3)
                : AppColors.brandGold,
          ),
        ),
        child: Text(
          payee ? 'Payée' : 'En attente',
          style: texteCompta.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: payee ? AppColors.successDeep : AppColors.brandNavy,
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmerSuppression(
  BuildContext context,
  ComptabiliteViewModel vm,
  Depense depense,
) async {
  // Une dépense déjà transmise au serveur est un fait partagé : elle ne s'efface
  // pas, elle est annulée par l'écriture inverse (le Journal garde les deux traces).
  final transmise = vm.pieceEstTransmise(depense.numeroPiece);
  final confirme = await AppModal.show<bool>(
    context,
    title: transmise
        ? 'Annuler la dépense ${depense.numeroPiece} ?'
        : 'Supprimer la dépense ${depense.numeroPiece} ?',
    child: Text(
      transmise
          ? '« ${depense.libelle} » — ${Formats.montant(depense.montant)}.\n\n'
                'Cette dépense a déjà été transmise au serveur : elle ne peut '
                'plus être effacée. Une écriture inverse (ANN-…) sera passée '
                'au Journal : la charge disparaîtra du Compte de Résultat et '
                'la trésorerie sera reconstituée d\'autant.'
          : '« ${depense.libelle} » — ${Formats.montant(depense.montant)}.\n\n'
                'Les deux lignes d\'écriture de cette pièce seront supprimées : la '
                'charge disparaîtra du Compte de Résultat et la trésorerie sera '
                'reconstituée d\'autant.',
      style: texteCompta.copyWith(height: 1.5),
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
          label: transmise ? 'Annuler la dépense' : 'Supprimer',
          variant: AppButtonVariant.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ),
    ],
  );

  if (confirme != true || !context.mounted) return;

  final resultat = await vm.supprimerPiece(depense.numeroPiece);
  if (!context.mounted) return;

  switch (resultat) {
    case Succes():
      showAppToast(
        context,
        transmise
            ? 'Dépense ${depense.numeroPiece} annulée (écriture inverse passée).'
            : 'Dépense ${depense.numeroPiece} supprimée.',
      );
    case Echec(:final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

/// Carte « Nouvelle Dépense » — `saisie-depenses.html` l.24-76.
///
/// ## Ce formulaire n'est pas une modale
///
/// C'était le défaut structurel de la version précédente. Le prototype pose ce
/// bloc **en clair sur la page**, entre les KPI et la barre de filtres :
///
/// ```html
/// <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-lg mb-lg">
///   <h3 …>Nouvelle Dépense</h3>
///   <p class="text-xs text-outline mb-md">Enregistrez une charge…</p>
///   <form class="grid grid-cols-1 md:grid-cols-2 gap-md">…</form>
/// </div>
/// ```
///
/// Ce choix n'est pas décoratif : la saisie des dépenses est un écran de
/// **saisie répétitive**. La Gérante enregistre plusieurs charges à la suite et
/// voit la liste se remplir sous ses yeux. Un formulaire modal impose un clic
/// d'ouverture par dépense et masque le tableau pendant la saisie.
///
/// C'est aussi ce qui rend `editExpense()` cohérent : le prototype ne rouvre
/// rien, il **remplit ce formulaire-ci** et y fait défiler la page. D'où le
/// bouton qui devient « Mettre à Jour la Dépense » plutôt qu'un titre de
/// modale qui changerait.
class _FormulaireDepense extends StatefulWidget {
  const _FormulaireDepense({required this.vm, required this.controleur});

  final ComptabiliteViewModel vm;

  /// Permet à la ligne du tableau de charger une dépense dans ce formulaire —
  /// l'équivalent de `editExpense(id)`, qui écrit dans les mêmes champs.
  final ControleurFormulaireDepense controleur;

  @override
  State<_FormulaireDepense> createState() => _FormulaireDepenseState();
}

/// Passerelle entre le tableau et le formulaire, tous deux sur la même page.
class ControleurFormulaireDepense extends ChangeNotifier {
  Depense? _enEdition;
  Depense? get enEdition => _enEdition;

  void modifier(Depense depense) {
    _enEdition = depense;
    notifyListeners();
  }

  void reinitialiser() {
    _enEdition = null;
    notifyListeners();
  }
}

class _FormulaireDepenseState extends State<_FormulaireDepense> {
  final _libelleCtrl = TextEditingController();
  final _montantCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  String? _compteCharge;
  String? _compteReglement;
  String? _centreAnalytique;
  Map<String, String> _erreurs = const {};
  bool _enCours = false;

  Depense? _enEdition;
  bool get _enModification => _enEdition != null;

  @override
  void initState() {
    super.initState();
    widget.controleur.addListener(_reprendreDepense);
  }

  @override
  void dispose() {
    widget.controleur.removeListener(_reprendreDepense);
    _libelleCtrl.dispose();
    _montantCtrl.dispose();
    super.dispose();
  }

  /// `editExpense()` : les champs sont remplis, le bouton change de libellé.
  void _reprendreDepense() {
    final depense = widget.controleur.enEdition;
    setState(() {
      _enEdition = depense;
      _erreurs = const {};
      if (depense == null) {
        _libelleCtrl.clear();
        _montantCtrl.clear();
        _date = DateTime.now();
        _compteCharge = null;
        _compteReglement = null;
        _centreAnalytique = null;
      } else {
        _libelleCtrl.text = depense.libelle;
        _montantCtrl.text = depense.montant.toStringAsFixed(0);
        _date = depense.date;
        _compteCharge = depense.numeroCompteCharge;
        _compteReglement = depense.compteRegle;
        _centreAnalytique = depense.centreAnalytique;
      }
    });
  }

  Future<void> _valider() async {
    final libelle = _libelleCtrl.text.trim();
    final montant = double.tryParse(
      _montantCtrl.text.trim().replaceAll(',', '.'),
    );

    final erreurs = <String, String>{
      if (libelle.isEmpty) 'libelle': 'Ce champ est obligatoire.',
      if (montant == null || montant <= 0)
        'montant': 'Montant obligatoire, supérieur à zéro.',
      if (_compteCharge == null) 'categorie': 'Ce champ est obligatoire.',
      if (_compteReglement == null) 'reglement': 'Ce champ est obligatoire.',
    };

    if (erreurs.isNotEmpty) {
      setState(() => _erreurs = erreurs);
      showAppToast(
        context,
        'Veuillez compléter les champs obligatoires.',
        type: ToastType.error,
      );
      return;
    }

    setState(() {
      _erreurs = const {};
      _enCours = true;
    });

    // Le numero est conserve en modification : il figure sur le recu papier
    // deja classe par la Gerante.
    final piece =
        _enEdition?.numeroPiece ?? widget.vm.prochainNumeroPiece('DEP');

    final lignes = [
      LigneAEcrire(
        numeroCompte: _compteCharge!,
        debit: montant!,
        credit: 0,
        libelle: libelle,
        // Seule la ligne de CHARGE porte le centre : la contrepartie de
        // tresorerie n'appartient a aucune filiere.
        axeAnalytique: _centreAnalytique,
      ),
      LigneAEcrire(
        numeroCompte: _compteReglement!,
        debit: 0,
        credit: montant,
        libelle: libelle,
      ),
    ];

    final resultat = _enModification
        ? await widget.vm.remplacerPiece(
            numeroPiece: piece,
            date: _date,
            journalCode: CodeJournal.caisse,
            lignes: lignes,
          )
        : await widget.vm.enregistrerPiece(
            date: _date,
            journalCode: CodeJournal.caisse,
            numeroPiece: piece,
            lignes: lignes,
          );

    if (!mounted) return;
    setState(() => _enCours = false);

    switch (resultat) {
      case Succes():
        final etaitEnModification = _enModification;
        // `submitExpense()` reinitialise le formulaire apres succes : l'ecran
        // enchaine les saisies.
        widget.controleur.reinitialiser();
        if (!mounted) return;
        showAppToast(
          context,
          etaitEnModification
              ? 'Dépense $piece mise à jour — ${Formats.montant(montant)} '
                    'imputés au compte $_compteCharge.'
              : 'Dépense $piece enregistrée — ${Formats.montant(montant)} '
                    'imputés au compte $_compteCharge.',
        );
      case Echec(:final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final comptesCharge = vm.comptesDeCharge;
    final comptesTresorerie = vm.comptesDeTresorerie;
    final planIncomplet = comptesCharge.isEmpty || comptesTresorerie.isEmpty;
    final verrouille = vm.exerciceEstCloture;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg), // `p-lg`
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
          Row(
            children: [
              Icon(
                _enModification ? Symbols.edit : Symbols.add_circle,
                size: 20,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  _enModification
                      ? 'Modifier la dépense ${_enEdition!.numeroPiece}'
                      : 'Nouvelle Dépense',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 18, // `text-lg`
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
              if (_enModification)
                AppButton(
                  label: 'Annuler la modification',
                  variant: AppButtonVariant.outline,
                  height: 34,
                  onPressed: widget.controleur.reinitialiser,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _enModification
                ? 'Les deux lignes de cette pièce seront réécrites sous le '
                      'même numéro — il figure sur le reçu papier, le '
                      'renuméroter rendrait le classement inutilisable.'
                : 'Enregistrez une charge d\'exploitation de trésorerie '
                      'directe. L\'écriture comptable part immédiatement au '
                      'Journal : compte de charge au débit, compte de '
                      'règlement au crédit.',
            style: texteCompta.copyWith(color: AppColors.outline, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          if (planIncomplet)
            const _Avertissement(
              texte:
                  'Le plan comptable ne contient pas les comptes nécessaires '
                  '(classe 6 et classe 5). Complétez-le depuis Plan Comptable '
                  'avant de saisir une dépense.',
            )
          else if (verrouille)
            _Avertissement(
              texte:
                  'L\'exercice ${vm.exercice} est clôturé : aucune écriture ne '
                  'peut plus y être ajoutée ni modifiée.',
            )
          else
            _grille(vm, comptesCharge, comptesTresorerie),
        ],
      ),
    );
  }

  /// `grid grid-cols-1 md:grid-cols-2 gap-md` — 6 champs sur 2 colonnes, puis
  /// le bouton aligné à droite sur toute la largeur (`md:col-span-2`).
  Widget _grille(
    ComptabiliteViewModel vm,
    List<CompteComptable> comptesCharge,
    List<CompteComptable> comptesTresorerie,
  ) {
    // `md:` = 768 px (Doc K3 §4) — MediaQuery, jamais les contraintes locales.
    final deuxColonnes = AppBreakpoints.estMd(context);

    final champs = <Widget>[
      _Champ(
        libelle: 'DATE DE LA TRANSACTION *',
        erreur: _erreurs['date'],
        enfant: InkWell(
          onTap: () async {
            final choix = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(vm.exercice - 1),
              lastDate: DateTime(vm.exercice + 1, 12, 31),
              locale: const Locale('fr'),
            );
            if (choix != null) setState(() => _date = choix);
          },
          child: SizedBox(
            height: _hauteurChamp,
            child: InputDecorator(
              decoration: decorationCompta,
              child: Row(
                children: [
                  Expanded(
                    child: Text(Formats.date(_date), style: texteCompta),
                  ),
                  const Icon(
                    Symbols.calendar_month,
                    size: 18,
                    color: AppColors.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      _Champ(
        libelle: 'LIBELLÉ DE LA DÉPENSE *',
        erreur: _erreurs['libelle'],
        enfant: SizedBox(
          height: _hauteurChamp,
          child: TextField(
            controller: _libelleCtrl,
            style: texteCompta,
            decoration: decorationCompta.copyWith(
              hintText:
                  'ex : Transport livraison ou Entretien groupe électrogène',
            ),
          ),
        ),
      ),
      _Champ(
        libelle: 'CATÉGORIE DE CHARGES (SYSCOHADA) *',
        erreur: _erreurs['categorie'],
        enfant: SizedBox(
          height: _hauteurChamp,
          child: DropdownButtonFormField<String>(
            initialValue: _compteCharge,
            isExpanded: true,
            style: texteCompta,
            decoration: decorationCompta,
            hint: const Text('-- Sélectionner --', style: texteCompta),
            items: [
              for (final c in comptesCharge)
                DropdownMenuItem(
                  value: c.numero,
                  child: Text('${c.numero} - ${c.libelle}', style: texteCompta),
                ),
            ],
            onChanged: (v) => setState(() => _compteCharge = v),
          ),
        ),
      ),
      _Champ(
        libelle: 'MONTANT DÉCAISSÉ (FCFA) *',
        erreur: _erreurs['montant'],
        enfant: SizedBox(
          height: _hauteurChamp,
          child: TextField(
            controller: _montantCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: FormatteursSaisie.montant,
            style: texteCompta,
            decoration: decorationCompta.copyWith(hintText: 'ex : 12000'),
          ),
        ),
      ),
      _Champ(
        // ⚠️ Le prototype ecrit « Compte de Tresorerie DEBITE ». C'est
        // l'inverse : lors d'une depense la tresorerie est CREDITEE, elle
        // diminue. Sa mecanique, elle, etait juste.
        libelle: 'COMPTE DE TRÉSORERIE CRÉDITÉ *',
        erreur: _erreurs['reglement'],
        enfant: SizedBox(
          height: _hauteurChamp,
          child: DropdownButtonFormField<String>(
            initialValue: _compteReglement,
            isExpanded: true,
            style: texteCompta,
            decoration: decorationCompta,
            hint: const Text('-- Sélectionner --', style: texteCompta),
            items: [
              for (final c in comptesTresorerie)
                DropdownMenuItem(
                  value: c.numero,
                  child: Text('${c.libelle} (${c.numero})', style: texteCompta),
                ),
              // ECART_DELIBERE : sans ce choix, le statut « En attente » du
              // prototype est inatteignable et son filtre est decoratif.
              for (final c in vm.planActif.where(
                (c) => c.numero.startsWith('40'),
              ))
                DropdownMenuItem(
                  value: c.numero,
                  child: Text(
                    'À crédit — ${c.libelle} (${c.numero})',
                    style: texteCompta,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _compteReglement = v),
          ),
        ),
      ),
      _Champ(
        // Ajoute : sans lui, la Comptabilite Analytique ne ventile que ce que
        // le numero de compte laisse deviner, et une facture d'electricite
        // reste hors de toute filiere. Voir Doc F6.
        libelle: 'CENTRE ANALYTIQUE (FACULTATIF)',
        erreur: null,
        enfant: SizedBox(
          height: _hauteurChamp,
          child: DropdownButtonFormField<String?>(
            initialValue: _centreAnalytique,
            isExpanded: true,
            style: texteCompta,
            decoration: decorationCompta,
            hint: const Text('Non imputé', style: texteCompta),
            items: [
              const DropdownMenuItem<String?>(
                child: Text('Non imputé', style: texteCompta),
              ),
              for (final centre
                  in ComptabiliteViewModel.centresAnalytiquesConnus)
                DropdownMenuItem<String?>(
                  value: centre,
                  child: Text(centre, style: texteCompta),
                ),
            ],
            onChanged: (v) => setState(() => _centreAnalytique = v),
          ),
        ),
      ),
      _Champ(
        libelle: 'REÇU / FACTURE (PHOTO)',
        erreur: null,
        // Le prototype dessine une zone de depot en pointilles. Elle
        // n'enregistre rien : ni colonne de piece jointe en Doc D1, ni
        // stockage de fichier. La zone est conservee — c'est le layout — mais
        // elle dit ce qu'il en est au lieu de simuler un depot.
        enfant: Container(
          height: _hauteurChamp,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardRadius,
            border: Border.all(
              color: AppColors.outlineVariant,
              width: 2,
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Symbols.add_a_photo,
                size: 18,
                color: AppColors.outlineVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'Non repris : aucun stockage de fichier. Reportez le numéro '
                  'du reçu dans le libellé.',
                  style: texteCompta.copyWith(
                    fontSize: 11,
                    color: AppColors.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (deuxColonnes)
          for (var i = 0; i < champs.length; i += 2) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: champs[i]),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: i + 1 < champs.length
                      ? champs[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ]
        else
          for (final champ in champs) ...[
            champ,
            const SizedBox(height: AppSpacing.md),
          ],
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            label: _enCours
                ? 'Enregistrement…'
                : (_enModification
                      ? 'Mettre à Jour la Dépense'
                      : 'Enregistrer la Dépense'),
            icon: Symbols.save,
            onPressed: _enCours ? null : _valider,
          ),
        ),
      ],
    );
  }
}

/// `h-11` du prototype (44 px) — les champs de ce formulaire sont plus hauts
/// que les `h-10` des tableaux de bord.
const double _hauteurChamp = 44;

class _Avertissement extends StatelessWidget {
  const _Avertissement({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Symbols.warning, size: 18, color: AppColors.errorDeep),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              texte,
              style: texteCompta.copyWith(
                color: AppColors.errorDeep,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Champ extends StatelessWidget {
  const _Champ({
    required this.libelle,
    required this.enfant,
    required this.erreur,
  });

  final String libelle;
  final Widget enfant;
  final String? erreur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(libelle, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        enfant,
        if (erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(erreur!, style: AppTypography.invalidFeedback),
          ),
      ],
    );
  }
}
