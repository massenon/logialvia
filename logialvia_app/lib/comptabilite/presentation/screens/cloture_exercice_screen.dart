import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../administration/presentation/viewmodels/auth_view_model.dart';
import '../../../core/widgets/carte_kpi_lisere.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import 'documents_comptables.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import '../../domain/services/report_a_nouveau.dart';
import '../viewmodels/comptabilite_view_model.dart';
import 'widgets/communs_compta.dart';
import '../../domain/plan_syscohada.dart';

/// Clôture — Doc F6 §3 et §9, fidèle à `cloture-exercice.html`.
///
/// ## Ajout par rapport au prototype : la clôture **périodique**
///
/// `cloture-exercice.html` ne traite que la clôture **annuelle**. Or Doc F6 §9
/// et BR-CPT-006 imposent un **double verrouillage** — exercice *et* mois — et
/// la table `CLOTURES_PERIODIQUES` existe pour cela. Sans écran, le verrou
/// mensuel serait du code mort et la déclôture réservée à l'administratrice
/// (BR-CPT-006) inaccessible. La grille des 12 mois ci-dessous est donc pilotée
/// par la règle métier, pas par le prototype ; elle est signalée comme telle.
class ClotureExerciceScreen extends StatelessWidget {
  const ClotureExerciceScreen({super.key});

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
                Symbols.event_repeat,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Clôture d\'Exercice',
                  style: AppTypography.pageTitle,
                ),
              ),
              SelecteurExercice(vm: vm),
              const SizedBox(width: AppSpacing.md),
              BoutonExportPdf(
                construire: () => DocumentsComptables.cloture(vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Verrouillage de l\'exercice fiscal et report à nouveau vers '
            'l\'exercice suivant.',
            style: texteCompta.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Frise(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          _KpisCloture(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          _ClotureMensuelle(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          _AssistantCloture(vm: vm),
        ],
      ),
    );
  }
}

class _Frise extends StatelessWidget {
  const _Frise({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    // Les exercices sont tries du plus recent au plus ancien ; la frise se lit
    // dans l'ordre chronologique.
    final annees = vm.exercices.reversed.toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < annees.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(
                  Symbols.arrow_forward,
                  size: 18,
                  color: AppColors.outlineVariant,
                ),
              ),
            _JetonExercice(
              annee: annees[i],
              actif: annees[i] == vm.exercice,
              vm: vm,
            ),
          ],
        ],
      ),
    );
  }
}

class _JetonExercice extends StatelessWidget {
  const _JetonExercice({
    required this.annee,
    required this.actif,
    required this.vm,
  });

  final int annee;
  final bool actif;
  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    // Un exercice anterieur a celui en cours et deja depasse est necessairement
    // cloture ou en retard ; seul l'exercice selectionne connait son etat exact.
    final cloture = actif && vm.exerciceEstCloture;

    return InkWell(
      onTap: () => vm.changerExercice(annee),
      borderRadius: AppRadius.cardRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: actif ? AppColors.brandNavy : AppColors.surfaceZebra,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(
            color: actif ? AppColors.brandNavy : AppColors.outlineVariant,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$annee',
              style: AppTypography.kpiValue.copyWith(
                fontSize: 20,
                color: actif ? Colors.white : AppColors.onSurface,
              ),
            ),
            Text(
              actif ? (cloture ? 'Clôturé' : 'En cours') : 'Exercice',
              style: texteCompta.copyWith(
                fontSize: 11,
                color: actif
                    ? Colors.white.withValues(alpha: 0.7)
                    : AppColors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpisCloture extends StatelessWidget {
  const _KpisCloture({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    // « Comptes de Gestion a Solder » : comptes de classe 6 et 7 mouvementes,
    // ce sont eux que l'ecriture de solde du resultat annule.
    final comptesGestion = vm.balance
        .where(
          (l) =>
              (l.numeroCompte.startsWith('6') ||
                  l.numeroCompte.startsWith('7')) &&
              (l.mouvementsDebit.abs() >= 0.01 ||
                  l.mouvementsCredit.abs() >= 0.01),
        )
        .length;

    return Row(
      children: [
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Résultat Provisoire',
            valeur: Formats.montant(vm.resultatNet),
            accent: vm.resultatNet < 0
                ? AppColors.errorDeep
                : AppColors.successDeep,
            icone: vm.resultatNet < 0
                ? Symbols.trending_down
                : Symbols.trending_up,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Comptes de Gestion à Solder',
            valeur: '$comptesGestion',
            accent: AppColors.infoBlue,
            icone: Symbols.receipt_long,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Balance',
            valeur: vm.balanceEstEquilibree
                ? 'Équilibrée'
                : 'Écart ${Formats.nombre(vm.balanceEcart.abs())}',
            accent: vm.balanceEstEquilibree
                ? AppColors.successDeep
                : AppColors.errorDeep,
            icone: Symbols.balance,
          ),
        ),
      ],
    );
  }
}

/// Grille des 12 mois — clôture périodique (BR-CPT-006).
class _ClotureMensuelle extends StatelessWidget {
  const _ClotureMensuelle({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final noms = DateFormat.MMMM('fr_FR');

    return CarteSection(
      titre: 'Clôture Périodique — exercice ${vm.exercice}',
      icone: Symbols.calendar_month,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Un mois clôturé refuse toute nouvelle écriture à sa date, y '
            'compris celles générées automatiquement par une vente ou un achat '
            'antidaté. Seule une administratrice peut le déclôturer, et le '
            'déblocage est tracé dans le journal d\'audit (BR-CPT-006).',
            style: texteCompta.copyWith(color: AppColors.outline, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var mois = 1; mois <= 12; mois++)
                _JetonMois(
                  vm: vm,
                  mois: mois,
                  nom: noms.format(DateTime(vm.exercice, mois)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JetonMois extends StatelessWidget {
  const _JetonMois({required this.vm, required this.mois, required this.nom});

  final ComptabiliteViewModel vm;
  final int mois;
  final String nom;

  @override
  Widget build(BuildContext context) {
    final cloture = vm.cloturesMois[mois] ?? false;
    final auth = context.read<AuthViewModel>();
    final session = auth.session;
    final estAdmin = session?.role.id == 'admin';

    return SizedBox(
      width: 168,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: cloture ? AppColors.surfaceZebra : AppColors.surfaceCard,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(
            color: cloture ? AppColors.outline : AppColors.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              cloture ? Symbols.lock : Symbols.lock_open,
              size: 16,
              color: cloture ? AppColors.outline : AppColors.successDeep,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                // `MMMM` de `fr_FR` renvoie « janvier » : la majuscule initiale
                // est ajoutee ici, comme partout ailleurs dans l'interface.
                nom.isEmpty ? '' : nom[0].toUpperCase() + nom.substring(1),
                style: grasCompta,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(cloture ? Symbols.lock_open : Symbols.lock, size: 16),
              visualDensity: VisualDensity.compact,
              color: cloture ? AppColors.errorDeep : AppColors.brandNavy,
              tooltip: cloture
                  ? (estAdmin
                        ? 'Déclôturer $nom'
                        : 'Déclôture réservée à l\'administratrice')
                  : 'Clôturer $nom',
              onPressed: vm.exerciceEstCloture
                  ? null
                  : () async {
                      final Resultat<void> resultat;
                      if (cloture) {
                        if (session == null) return;
                        resultat = await vm.decloturerMois(
                          mois: mois,
                          roleId: session.role.id,
                          utilisateurId: '${session.utilisateur.id}',
                        );
                      } else {
                        resultat = await vm.cloturerMois(mois);
                      }

                      if (!context.mounted) return;
                      switch (resultat) {
                        case Succes():
                          showAppToast(
                            context,
                            cloture
                                ? 'Mois de $nom déclôturé — action tracée dans '
                                      'le journal d\'audit.'
                                : 'Mois de $nom clôturé.',
                          );
                        case Echec(:final message):
                          showAppToast(
                            context,
                            message,
                            type: ToastType.error,
                          );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantCloture extends StatelessWidget {
  const _AssistantCloture({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final suivant = vm.exercice + 1;
    final tousMoisClotures = List.generate(
      12,
      (i) => vm.cloturesMois[i + 1] ?? false,
    ).every((c) => c);

    return CarteSection(
      titre:
          'Assistant de Clôture d\'Exercice (${vm.exercice} → $suivant)',
      icone: Symbols.checklist,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EtapeCloture(
            numero: 1,
            titre: 'Travaux d\'Inventaire & Régularisation',
            description:
                'Rapprochements Espèces/Mobile Money, inventaire physique des '
                'stocks (Gestion Stocks), vérification des soldes clients et '
                'fournisseurs.',
            faite: tousMoisClotures,
            statutFait: 'Les 12 mois de l\'exercice sont clôturés.',
            statutRestant:
                'Étape manuelle : clôturez les mois traités dans la grille '
                'ci-dessus au fur et à mesure.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _EtapeCloture(
            numero: 2,
            titre: 'Solde des Comptes de Gestion (Classes 6, 7 & 8)',
            description:
                'Calcul du résultat net (Produits − Charges) et écriture de '
                'solde vers le compte 131 (Bénéfice) ou 139 (Perte), journal CL '
                'au 31/12/${vm.exercice}. Les états de l\'exercice se lisent '
                '« avant affectation » : cette écriture ne les modifie pas.',
            faite: vm.exerciceEstCloture,
            statutFait:
                'Résultat net arrêté : ${Formats.montant(vm.resultatNet)} '
                '(Produits ${Formats.montant(vm.totalProduits)} − Charges '
                '${Formats.montant(vm.totalCharges)}).',
            statutRestant: vm.balanceEstEquilibree
                ? 'Résultat provisoire : ${Formats.montant(vm.resultatNet)} '
                      '(Produits ${Formats.montant(vm.totalProduits)} − Charges '
                      '${Formats.montant(vm.totalCharges)}) — écrit à la clôture.'
                : 'Balance déséquilibrée de '
                      '${Formats.montant(vm.balanceEcart.abs())} : le résultat ne '
                      'peut pas être arrêté (BR-CPT-004).',
          ),
          const SizedBox(height: AppSpacing.sm),
          _EtapeCloture(
            numero: 3,
            titre: 'Affectation du Résultat',
            description:
                'Bénéfice : réserves (111 légale, 118 autres), dividendes à payer '
                '(465), le reste en report à nouveau créditeur (121). Perte : '
                'report à nouveau débiteur (129). Décision de l\'Assemblée, saisie '
                'dans la fenêtre de clôture ci-dessous.',
            faite: vm.exerciceEstCloture,
            statutFait: _resumeAffectation(vm),
            statutRestant:
                'Par défaut, tout le résultat est reporté à nouveau '
                '(${vm.resultatNet < 0 ? PlanSyscohada.reportDebiteur : PlanSyscohada.reportCrediteur}).',
          ),
          const SizedBox(height: AppSpacing.sm),
          _EtapeCloture(
            numero: 4,
            titre: 'Génération des Écritures d\'À-Nouveaux (RAN)',
            description:
                'Création de l\'exercice $suivant et report des soldes de '
                'bilan (Classes 1 à 5) au 1ᵉʳ janvier $suivant, journal AN. Les '
                'classes 6, 7 et 8 ne sont jamais reportées. Verrouillage '
                'définitif de l\'exercice ${vm.exercice}.',
            faite: vm.exerciceEstCloture,
            statutFait: 'Exercice ${vm.exercice} clôturé et verrouillé.',
            statutRestant: null,
            action: vm.exerciceEstCloture
                ? _ActionsExerciceClos(vm: vm)
                : AppButton(
                    label: 'Clôturer l\'Exercice ${vm.exercice}',
                    icon: Symbols.lock,
                    onPressed: vm.balanceEstEquilibree
                        ? () => _confirmerCloture(context, vm)
                        : null,
                  ),
          ),
          if (vm.motifRefusCloture != null && !vm.exerciceEstCloture) ...[
            // La clôture est un fait lourd : le serveur a le dernier mot. Refusée,
            // l'exercice est resté (ou redevenu) ouvert ici, et le dit.
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Text(
                'Le serveur a refusé la clôture : ${vm.motifRefusCloture}',
                style: grasCompta.copyWith(color: AppColors.errorDeep),
              ),
            ),
          ],
          if (!vm.balanceEstEquilibree && !vm.exerciceEstCloture) ...[
            const SizedBox(height: AppSpacing.md),
            BandeauEquilibre(
              equilibre: false,
              ecart: vm.balanceEcart,
              libelle: 'Balance générale',
            ),
          ],
        ],
      ),
    );
  }
}

class _EtapeCloture extends StatelessWidget {
  const _EtapeCloture({
    required this.numero,
    required this.titre,
    required this.description,
    required this.faite,
    required this.statutFait,
    required this.statutRestant,
    this.action,
  });

  final int numero;
  final String titre;
  final String description;
  final bool faite;
  final String statutFait;
  final String? statutRestant;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: faite ? AppColors.successDeep : AppColors.outlineVariant,
            ),
            child: Text(
              '$numero',
              style: grasCompta.copyWith(
                color: faite ? Colors.white : AppColors.outline,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: AppTypography.sectionTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: texteCompta.copyWith(
                    color: AppColors.outline,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (faite)
                  Row(
                    children: [
                      const Icon(
                        Symbols.check_circle,
                        size: 16,
                        color: AppColors.successDeep,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          statutFait,
                          style: grasCompta.copyWith(
                            color: AppColors.successDeep,
                          ),
                        ),
                      ),
                    ],
                  )
                else if (statutRestant != null)
                  Row(
                    children: [
                      const Icon(
                        Symbols.pending,
                        size: 16,
                        color: AppColors.brandGold,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          statutRestant!,
                          style: texteCompta.copyWith(
                            color: AppColors.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(alignment: Alignment.centerLeft, child: action!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Résumé de l'affectation d'un exercice clôturé, pour l'étape 3.
String _resumeAffectation(ComptabiliteViewModel vm) {
  final r = vm.resultatNet;
  if (r < 0) {
    return 'Perte de ${Formats.montant(-r)} portée au report à nouveau débiteur (129).';
  }
  final a = vm.affectation;
  final parts = <String>[
    if (a.reserveLegale > 0)
      'réserve légale ${Formats.montant(a.reserveLegale)}',
    if (a.autresReserves > 0)
      'autres réserves ${Formats.montant(a.autresReserves)}',
    if (a.dividendes > 0) 'dividendes ${Formats.montant(a.dividendes)}',
    'report à nouveau ${Formats.montant(a.reportANouveau(r))}',
  ];
  return 'Bénéfice de ${Formats.montant(r)} affecté : ${parts.join(', ')}.';
}

/// Exercice clôturé : à-nouveaux de l'exercice suivant, et réouverture (administratrice).
class _ActionsExerciceClos extends StatelessWidget {
  const _ActionsExerciceClos({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final session = context.read<AuthViewModel>().session;
    final estAdmin = session?.role.id == 'admin';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          vm.ouvertureParANouveaux
              ? 'À-nouveaux de l\'exercice ${vm.exercice} écrits (journal AN).'
              : 'Cet exercice a été clôturé avant la génération des à-nouveaux : son '
                    'ouverture est reconstituée par une clôture virtuelle de l\'exercice '
                    'précédent.',
          style: texteCompta.copyWith(color: AppColors.outline),
        ),
        if (estAdmin) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Rouvrir l\'Exercice ${vm.exercice}',
            icon: Symbols.lock_open,
            variant: AppButtonVariant.outline,
            onPressed: () => _confirmerReouverture(context, vm),
          ),
        ],
      ],
    );
  }
}

Future<void> _confirmerReouverture(
  BuildContext context,
  ComptabiliteViewModel vm,
) async {
  final annee = vm.exercice;
  final confirme = await AppModal.show<bool>(
    context,
    title: 'Rouvrir l\'exercice $annee ?',
    maxWidth: 520,
    child: Text(
      'Les écritures de clôture (journal CL) de $annee et les à-nouveaux (journal AN) de '
      '${annee + 1} seront retirés, et l\'exercice $annee redeviendra modifiable. '
      'Vous pourrez le clôturer de nouveau : les à-nouveaux seront régénérés. '
      'L\'action est tracée dans le journal d\'audit.',
      style: texteCompta.copyWith(height: 1.6),
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
          label: 'Rouvrir l\'exercice $annee',
          variant: AppButtonVariant.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ),
    ],
  );
  if (confirme != true || !context.mounted) return;

  final session = context.read<AuthViewModel>().session;
  final resultat = await vm.rouvrirExercice(
    roleId: session?.role.id ?? '',
    utilisateurId: '${session?.utilisateur.id ?? ''}',
  );
  if (!context.mounted) return;
  switch (resultat) {
    case Succes():
      showAppToast(context, 'Exercice $annee rouvert.');
    case Echec(:final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

double _lireMontant(String texte) =>
    double.tryParse(texte.trim().replaceAll(' ', '').replaceAll(',', '.')) ?? 0;

Future<void> _confirmerCloture(
  BuildContext context,
  ComptabiliteViewModel vm,
) async {
  final annee = vm.exercice;
  final reserveLegale = TextEditingController();
  final autresReserves = TextEditingController();
  final dividendes = TextEditingController();

  AffectationResultat saisie() => AffectationResultat(
    reserveLegale: _lireMontant(reserveLegale.text),
    autresReserves: _lireMontant(autresReserves.text),
    dividendes: _lireMontant(dividendes.text),
  );

  Widget champ(String libelle, TextEditingController c, void Function() maj) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9 ,.]'))],
          onChanged: (_) => maj(),
          decoration: InputDecoration(
            labelText: libelle,
            isDense: true,
            suffixText: 'FCFA',
          ),
        ),
      );

  final confirme = await AppModal.show<bool>(
    context,
    title: 'Clôturer définitivement l\'exercice $annee ?',
    maxWidth: 600,
    child: StatefulBuilder(
      builder: (ctx, setState) {
        final affectation = saisie();
        final apercu = vm.apercuCloture(affectation);
        final resultat = apercu.resultat;
        final an = apercu.aNouveaux;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'La clôture annuelle est définitive (BR-CPT-001) :',
              style: grasCompta.copyWith(height: 1.6),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Puce(
              'toutes les écritures de $annee sont verrouillées — plus aucune '
              'vente, dépense ou correction ne pourra y être imputée ;',
            ),
            _Puce(
              'les comptes de gestion sont soldés vers le compte '
              '${resultat < 0 ? '139 (perte)' : '131 (bénéfice)'} : résultat net '
              'arrêté de ${Formats.montant(resultat)} ;',
            ),
            _Puce(
              'l\'exercice ${annee + 1} est ouvert avec ses à-nouveaux '
              '(${an?.lignes.length ?? 0} compte(s) de bilan reporté(s)).',
            ),
            const SizedBox(height: AppSpacing.md),
            if (resultat > ReportANouveau.tolerance) ...[
              const Text(
                'Affectation du bénéfice (décision de l\'Assemblée)',
                style: AppTypography.sectionTitle,
              ),
              const SizedBox(height: AppSpacing.sm),
              champ('Réserve légale (111)', reserveLegale, () => setState(() {})),
              champ('Autres réserves (118)', autresReserves, () => setState(() {})),
              champ('Dividendes à payer (465)', dividendes, () => setState(() {})),
              Text(
                'Report à nouveau créditeur (121) : '
                '${Formats.montant(affectation.reportANouveau(resultat))}',
                style: grasCompta,
              ),
              const SizedBox(height: AppSpacing.sm),
            ] else if (resultat < -ReportANouveau.tolerance) ...[
              const Text(
                'Perte : aucun dividende ; elle est portée au report à nouveau '
                'débiteur (129).',
                style: texteCompta,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (apercu.bloquee)
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: AppRadius.cardRadius,
                ),
                child: Text(
                  apercu.anomalies.join(' '),
                  style: grasCompta.copyWith(color: AppColors.errorDeep),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: AppRadius.cardRadius,
                ),
                child: Text(
                  'La clôture ne peut pas être annulée depuis l\'écran de clôture '
                  'une fois transmise au serveur.',
                  style: grasCompta.copyWith(color: AppColors.errorDeep),
                ),
              ),
          ],
        );
      },
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
          label: 'Clôturer l\'exercice $annee',
          variant: AppButtonVariant.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ),
    ],
  );

  final affectation = saisie();
  reserveLegale.dispose();
  autresReserves.dispose();
  dividendes.dispose();
  if (confirme != true || !context.mounted) return;

  final resultat = await vm.cloturerExercice(
    roleId: context.read<AuthViewModel>().session?.role.id ?? '',
    affectation: affectation,
  );
  if (!context.mounted) return;

  switch (resultat) {
    case Succes():
      showAppToast(
        context,
        'Exercice $annee clôturé. L\'exercice ${annee + 1} est ouvert avec ses à-nouveaux.',
      );
    case Echec(:final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

class _Puce extends StatelessWidget {
  const _Puce(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: texteCompta),
          Expanded(child: Text(texte, style: texteCompta.copyWith(height: 1.5))),
        ],
      ),
    );
  }
}
