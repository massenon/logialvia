import '../../../elevage/domain/entities/cycle_incubation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../commercial/presentation/screens/documents_commercial.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/carte_section.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import 'documents_rapports.dart';
import '../../data/repositories/rapports_repository_drift.dart';
import '../../domain/entities/rapports.dart';
import '../viewmodels/rapports_view_model.dart';
import 'widgets/communs_rapports.dart';

/// Page Rapports & États — fournit le ViewModel partagé par les 6 onglets.
class PageRapports extends StatelessWidget {
  const PageRapports({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RapportsViewModel>(
      create: (context) => RapportsViewModel(
        RapportsRepositoryDrift(context.read<AppDatabase>()),
      )..charger(),
      child: const RapportsExportsScreen(),
    );
  }
}

/// Rapports & États — Doc F7, fidèle à `rapports-exports.html`.
///
/// 6 onglets sur une période commune. **Aucune valeur n'est recopiée du
/// prototype** : les 142 000 F de recettes, les 312 000 F de trésorerie et les
/// 184 sujets de son HTML sont des constantes de maquette. Ici tout provient
/// des écritures, des ventes, des achats et des fiches réellement saisies.
class RapportsExportsScreen extends StatefulWidget {
  const RapportsExportsScreen({super.key});

  @override
  State<RapportsExportsScreen> createState() => _RapportsExportsScreenState();
}

class _RapportsExportsScreenState extends State<RapportsExportsScreen> {
  int _onglet = 0;

  static const List<String> _titres = [
    'Recettes et Dépenses',
    'État de Trésorerie',
    'Créances Clients',
    'Dettes Fournisseurs',
    'Rapport Élevage',
    'Rapport de Stocks',
  ];

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RapportsViewModel>();

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
                Symbols.picture_as_pdf,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text('Rapports & États', style: AppTypography.pageTitle),
              ),
              _SelecteurPeriode(vm: vm),
              const SizedBox(width: AppSpacing.md),
              // Un seul bouton, qui exporte l'onglet affiche avec ses filtres —
              // le prototype clone le panneau DOM actif (Doc F7).
              BoutonExportPdf(
                construire: () => DocumentsRapports.pourOnglet(_onglet, vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'États de synthèse, période du ${Formats.date(vm.debut)} au '
            '${Formats.date(vm.fin)}.',
            style: texteRapport.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.md),
          BarreOnglets(
            cibleTour: 'onglets-rapports',
            titres: _titres,
            actif: _onglet,
            onChange: (i) => setState(() => _onglet = i),
          ),
          const SizedBox(height: AppSpacing.md),
          switch (_onglet) {
            0 => _OngletRecettesDepenses(vm: vm),
            1 => _OngletTresorerie(vm: vm),
            2 => _OngletCreances(vm: vm),
            3 => _OngletDettes(vm: vm),
            4 => _OngletElevage(vm: vm),
            _ => _OngletStocks(vm: vm),
          },
        ],
      ),
    );
  }
}

class _SelecteurPeriode extends StatelessWidget {
  const _SelecteurPeriode({required this.vm});

  final RapportsViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Symbols.calendar_month,
            size: 18,
            color: AppColors.brandNavy,
          ),
          const SizedBox(width: AppSpacing.xs),
          _BoutonDate(
            valeur: vm.debut,
            onChange: (d) => vm.changerPeriode(debut: d),
          ),
          Text(' au ', style: texteRapport.copyWith(color: AppColors.outline)),
          _BoutonDate(
            valeur: vm.fin,
            onChange: (d) => vm.changerPeriode(fin: d),
          ),
        ],
      ),
    );
  }
}

class _BoutonDate extends StatelessWidget {
  const _BoutonDate({required this.valeur, required this.onChange});

  final DateTime valeur;
  final ValueChanged<DateTime> onChange;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final choix = await showDatePicker(
          context: context,
          initialDate: valeur,
          firstDate: DateTime(valeur.year - 5),
          lastDate: DateTime(valeur.year + 5, 12, 31),
          locale: const Locale('fr', 'FR'),
        );
        if (choix != null) onChange(choix);
      },
      borderRadius: AppRadius.cardRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 4,
        ),
        child: Text(
          Formats.date(valeur),
          style: grasRapport.copyWith(color: AppColors.brandNavy),
        ),
      ),
    );
  }
}

// ============================================================ Onglet 1

class _OngletRecettesDepenses extends StatelessWidget {
  const _OngletRecettesDepenses({required this.vm});

  final RapportsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final lignes = vm.recettesDepensesFiltrees;
    final cumuls = vm.soldesCumules;
    final maximum = [
      vm.totalRecettes,
      vm.totalDepenses,
    ].fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Total Recettes',
                valeur: Formats.montant(vm.totalRecettes),
                detail: 'Avicole + Commerce Annexe',
                accent: AppColors.successDeep,
                icone: Symbols.trending_up,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Total Dépenses',
                valeur: Formats.montant(vm.totalDepenses),
                detail: 'Intrants + Charges diverses',
                accent: AppColors.errorDeep,
                icone: Symbols.trending_down,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Résultat Net',
                valeur: Formats.montant(vm.resultatNet),
                detail: 'Recettes − Dépenses',
                accent: AppColors.brandGold,
                icone: Symbols.calculate,
                fond: AppColors.brandGold.withValues(alpha: 0.1),
                couleurValeur: vm.resultatNet < 0
                    ? AppColors.errorDeep
                    : AppColors.brandNavy,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Taux de Marge Brute',
                valeur: vm.tauxMargeBrute == null
                    ? '—'
                    : Formats.pourcentage(vm.tauxMargeBrute!),
                detail: 'Résultat Net / Total Recettes',
                accent: AppColors.infoBlue,
                icone: Symbols.percent,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Chiffre d\'Affaires vs Charges',
          icone: Symbols.bar_chart,
          child: maximum < 0.01
              ? const EtatVide(
                  message:
                      'Aucun produit ni charge sur la période sélectionnée.',
                )
              : Column(
                  children: [
                    BarreComparative(
                      libelle: 'Recettes',
                      montant: vm.totalRecettes,
                      maximum: maximum,
                      couleur: AppColors.successDeep,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    BarreComparative(
                      libelle: 'Dépenses',
                      montant: vm.totalDepenses,
                      maximum: maximum,
                      couleur: AppColors.errorDeep,
                    ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Détail par catégorie SYSCOHADA',
          icone: Symbols.receipt_long,
          action: FiltreRapport(
            valeur: vm.filtreCentre,
            libelleTous: 'Tous les centres de profit',
            options: const [
              (CentresProfit.aviculture, 'Aviculture (Goliaths/Pintades)'),
              (CentresProfit.commerceAnnexe, 'Commerce Annexe'),
              (CentresProfit.chargeGenerale, 'Charge Générale'),
            ],
            onChange: vm.definirFiltreCentre,
          ),
          child: lignes.isEmpty
              ? EtatVide(
                  message: vm.donnees.recettesDepenses.isEmpty
                      ? 'Aucune écriture de gestion sur la période. Les ventes '
                            'et les dépenses enregistrées apparaissent ici '
                            'automatiquement.'
                      : 'Aucune ligne ne correspond à ce centre de profit.',
                )
              : Column(
                  children: [
                    const EnteteRapport(
                      colonnes: [
                        ('PÉRIODE', 3, TextAlign.left),
                        ('N° PIÈCE', 2, TextAlign.left),
                        ('CATÉGORIE SYSCOHADA', 6, TextAlign.left),
                        ('CENTRE DE PROFIT', 3, TextAlign.left),
                        ('ENCAISSEMENT', 2, TextAlign.right),
                        ('DÉCAISSEMENT', 2, TextAlign.right),
                        ('SOLDE CUMULÉ', 2, TextAlign.right),
                      ],
                    ),
                    for (var i = 0; i < lignes.length; i++)
                      LigneRapport(
                        zebre: i.isOdd,
                        cellules: [
                          (Text(lignes[i].periode, style: texteRapport), 3),
                          (
                            Text(
                              lignes[i].numeroPiece,
                              style: monoRapport,
                              overflow: TextOverflow.ellipsis,
                            ),
                            2,
                          ),
                          (
                            Text(
                              lignes[i].categorie,
                              style: texteRapport,
                              overflow: TextOverflow.ellipsis,
                            ),
                            6,
                          ),
                          (Text(lignes[i].centre, style: texteRapport), 3),
                          (
                            MontantRapport(
                              lignes[i].encaissement,
                              couleur: AppColors.successDeep,
                            ),
                            2,
                          ),
                          (
                            MontantRapport(
                              lignes[i].decaissement,
                              couleur: AppColors.errorDeep,
                            ),
                            2,
                          ),
                          (
                            Text(
                              Formats.nombre(cumuls[i]),
                              textAlign: TextAlign.right,
                              style: monoRapport.copyWith(
                                color: cumuls[i] < 0
                                    ? AppColors.errorDeep
                                    : null,
                              ),
                            ),
                            2,
                          ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ============================================================ Onglet 2

class _OngletTresorerie extends StatelessWidget {
  const _OngletTresorerie({required this.vm});

  final RapportsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final mouvements = vm.mouvementsFiltres;
    final soldes = vm.soldesProgressifsTresorerie;
    final libelles = vm.libellesComptesTresorerie;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final libelle in libelles) ...[
              Expanded(
                child: CarteKpiRapport(
                  libelle: libelle == 'Caisse' ? 'Caisse Espèces' : libelle,
                  valeur: Formats.montant(vm.soldeCloture(libelle)),
                  detail: 'Solde au ${Formats.date(vm.fin)}',
                  accent: libelle == 'Caisse'
                      ? AppColors.brandNavy
                      : AppColors.brandGold,
                  icone: libelle == 'Caisse'
                      ? Symbols.payments
                      : Symbols.smartphone,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Trésorerie Nette Globale',
                valeur: Formats.montant(vm.tresorerieNetteGlobale),
                detail: 'Cumul de tous les comptes de classe 5',
                accent: AppColors.successDeep,
                icone: Symbols.account_balance_wallet,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Mouvements de trésorerie',
          icone: Symbols.swap_vert,
          action: FiltreRapport(
            valeur: vm.filtreCompte,
            libelleTous: 'Tous les comptes',
            options: [
              for (final l in libelles)
                (l, l == 'Caisse' ? 'Caisse Espèces' : l),
            ],
            onChange: vm.definirFiltreCompte,
          ),
          child: Column(
            children: [
              const EnteteRapport(
                colonnes: [
                  ('DATE', 2, TextAlign.left),
                  ('COMPTE', 2, TextAlign.left),
                  ('TYPE D\'OPÉRATION', 3, TextAlign.left),
                  ('LIBELLÉ', 5, TextAlign.left),
                  ('ENTRÉE', 2, TextAlign.right),
                  ('SORTIE', 2, TextAlign.right),
                  ('SOLDE PROGRESSIF', 3, TextAlign.right),
                ],
              ),
              // Lignes de solde d'ouverture, comme le prototype : sans elles,
              // la premiere valeur du solde progressif sortirait de nulle part.
              for (final libelle in vm.comptesAffiches.map(
                (c) => CompteTresorerie.libelleCourt(c.numero),
              ))
                LigneRapport(
                  zebre: false,
                  couleurFond: AppColors.surfaceZebra,
                  cellules: [
                    (Text(Formats.date(vm.debut), style: texteRapport), 2),
                    (Text(libelle, style: texteRapport), 2),
                    (
                      Text(
                        'Solde d\'Ouverture',
                        style: grasRapport.copyWith(color: AppColors.outline),
                      ),
                      8,
                    ),
                    (const SizedBox.shrink(), 2),
                    (const SizedBox.shrink(), 2),
                    (
                      Text(
                        Formats.nombre(vm.soldeOuverture(libelle)),
                        textAlign: TextAlign.right,
                        style: monoRapport,
                      ),
                      3,
                    ),
                  ],
                ),
              if (mouvements.isEmpty)
                const EtatVide(
                  message:
                      'Aucun mouvement de trésorerie sur la période. Les '
                      'encaissements de vente et les décaissements d\'achat '
                      'apparaissent ici automatiquement.',
                )
              else
                for (var i = 0; i < mouvements.length; i++)
                  LigneRapport(
                    zebre: i.isEven,
                    cellules: [
                      (
                        Text(
                          Formats.date(mouvements[i].date),
                          style: texteRapport,
                        ),
                        2,
                      ),
                      (Text(mouvements[i].compte, style: texteRapport), 2),
                      (
                        Text(
                          mouvements[i].typeOperation,
                          style: texteRapport,
                          overflow: TextOverflow.ellipsis,
                        ),
                        3,
                      ),
                      (
                        Text(
                          mouvements[i].libelle,
                          style: texteRapport,
                          overflow: TextOverflow.ellipsis,
                        ),
                        5,
                      ),
                      (
                        MontantRapport(
                          mouvements[i].entree,
                          couleur: AppColors.successDeep,
                          gras: true,
                        ),
                        2,
                      ),
                      (
                        MontantRapport(
                          mouvements[i].sortie,
                          couleur: AppColors.errorDeep,
                          gras: true,
                        ),
                        2,
                      ),
                      (
                        Text(
                          Formats.nombre(soldes[i]),
                          textAlign: TextAlign.right,
                          style: monoRapport,
                        ),
                        3,
                      ),
                    ],
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================ Onglet 3

class _OngletCreances extends StatelessWidget {
  const _OngletCreances({required this.vm});

  final RapportsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final creances = vm.creancesFiltrees;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Créances En Cours',
                valeur: Formats.montant(vm.creancesEnCours),
                detail: 'Toutes créances actives',
                accent: AppColors.errorDeep,
                icone: Symbols.request_quote,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Créances en Retard',
                valeur: Formats.montant(vm.creancesEnRetard),
                detail: 'Échéance dépassée',
                accent: AppColors.errorDeep,
                icone: Symbols.schedule,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Clients Débiteurs',
                valeur: '${vm.clientsDebiteurs}',
                detail: 'Sur la clientèle active',
                accent: AppColors.brandGold,
                icone: Symbols.group,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Taux de Recouvrement',
                valeur: vm.tauxRecouvrement == null
                    ? '—'
                    : Formats.pourcentage(vm.tauxRecouvrement!),
                detail: 'Acomptes / Montant Initial',
                accent: AppColors.infoBlue,
                icone: Symbols.percent,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Créances client',
          icone: Symbols.request_quote,
          action: FiltreRapport(
            valeur: vm.filtreStatutCreance,
            libelleTous: 'Tous les statuts',
            options: const [
              ('En Retard', 'En Retard'),
              ('À Échoir', 'À Échoir'),
            ],
            onChange: vm.definirFiltreStatutCreance,
          ),
          child: creances.isEmpty
              ? EtatVide(
                  message: vm.donnees.creances.isEmpty
                      ? 'Aucune créance en cours : toutes les ventes sont '
                            'intégralement réglées.'
                      : 'Aucune créance ne correspond à ce statut.',
                )
              : Column(
                  children: [
                    const EnteteRapport(
                      colonnes: [
                        ('CODE', 2, TextAlign.left),
                        ('CLIENT', 4, TextAlign.left),
                        ('N° FACTURE', 3, TextAlign.left),
                        ('DATE VENTE', 2, TextAlign.left),
                        ('ÉCHÉANCE', 2, TextAlign.left),
                        ('MONTANT INITIAL', 2, TextAlign.right),
                        ('ACOMPTES', 2, TextAlign.right),
                        ('SOLDE DÛ', 2, TextAlign.right),
                        ('RETARD', 2, TextAlign.center),
                        ('STATUT', 2, TextAlign.center),
                        ('ACTIONS', 2, TextAlign.right),
                      ],
                    ),
                    for (var i = 0; i < creances.length; i++)
                      LigneRapport(
                        zebre: i.isOdd,
                        cellules: [
                          (Text(creances[i].code, style: monoRapport), 2),
                          (
                            Text(
                              creances[i].client,
                              style: grasRapport,
                              overflow: TextOverflow.ellipsis,
                            ),
                            4,
                          ),
                          (
                            Text(
                              creances[i].numeroFacture,
                              style: monoRapport,
                              overflow: TextOverflow.ellipsis,
                            ),
                            3,
                          ),
                          (
                            Text(
                              Formats.date(creances[i].dateVente),
                              style: texteRapport,
                            ),
                            2,
                          ),
                          (
                            Text(
                              creances[i].echeance == null
                                  ? '—'
                                  : Formats.date(creances[i].echeance!),
                              style: texteRapport,
                            ),
                            2,
                          ),
                          (MontantRapport(creances[i].montantInitial), 2),
                          (MontantRapport(creances[i].acomptes), 2),
                          (
                            MontantRapport(
                              creances[i].soldeDu,
                              gras: true,
                              couleur: AppColors.errorDeep,
                            ),
                            2,
                          ),
                          (
                            Text(
                              creances[i].enRetard
                                  ? '${creances[i].joursDeRetard}j'
                                  : '—',
                              textAlign: TextAlign.center,
                              style: creances[i].enRetard
                                  ? grasRapport.copyWith(
                                      color: AppColors.errorDeep,
                                    )
                                  : texteRapport.copyWith(
                                      color: AppColors.outline,
                                    ),
                            ),
                            2,
                          ),
                          (
                            BadgeRapport(
                              libelle: creances[i].statut,
                              alerte: creances[i].enRetard,
                            ),
                            2,
                          ),
                          // Colonne Actions de `rapports-exports.html` l.640.
                          // `exportLettreRelance()` etait deja ecrit dans
                          // `DocumentsCommercial` mais n'etait branche nulle
                          // part : le document existait sans porte d'entree.
                          (_ActionsCreance(creance: creances[i]), 2),
                        ],
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    const NoteEcheance(
                      texte:
                          'La colonne « Échéance » reprend la date de vente : '
                          'ni le point de vente ni la table VENTES ne saisissent '
                          'de délai de paiement. Le prototype fait de même — sa '
                          'seule créance porte la même date dans les deux '
                          'colonnes. Un délai contractuel supposerait un champ '
                          'que le modèle de données ne prévoit pas.',
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Colonne Actions d'une créance — `rapports-exports.html` l.640-641.
///
/// Deux gestes, exactement ceux du prototype : imprimer la lettre de relance,
/// et aller saisir l'encaissement. Le second est un lien de navigation côté
/// web (`window.location.href = 'relances-clients.html'`), pas une action :
/// l'encaissement se saisit dans Clients & Créances, qui tient le suivi et
/// écrit l'écriture comptable. Le dupliquer ici créerait un second chemin
/// d'encaissement, donc un risque de double règlement.
class _ActionsCreance extends StatelessWidget {
  const _ActionsCreance({required this.creance});

  final CreanceClient creance;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconeExportPdf(
          icone: Symbols.mail,
          infobulle: creance.sansEcheance
              ? 'Rappel de solde PDF — aucune échéance convenue'
              : 'Lettre de relance PDF',
          construire: () => DocumentsCommercial.lettreRelance(
            client: creance.client,
            reference: creance.numeroFacture,
            solde: creance.soldeDu,
            echeance: creance.echeance,
          ),
        ),
        IconButton(
          icon: const Icon(Symbols.payments, size: 16),
          color: AppColors.successDeep,
          tooltip: 'Saisir l\'encaissement',
          visualDensity: VisualDensity.compact,
          onPressed: () => context.go('/clients'),
        ),
      ],
    );
  }
}

// ============================================================ Onglet 4

class _OngletDettes extends StatelessWidget {
  const _OngletDettes({required this.vm});

  final RapportsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final dettes = vm.dettesFiltrees;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Total Dettes Fournisseurs',
                valeur: Formats.montant(vm.totalDettes),
                detail: 'Toutes dettes actives',
                accent: AppColors.errorDeep,
                icone: Symbols.local_shipping,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Dettes Urgentes',
                valeur: Formats.montant(vm.dettesUrgentes),
                detail: 'Échéance dépassée',
                accent: AppColors.brandGold,
                icone: Symbols.priority_high,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Fournisseurs Créditeurs',
                valeur: '${vm.fournisseursCrediteurs}',
                detail: 'Sur la base fournisseurs',
                accent: AppColors.infoBlue,
                icone: Symbols.store,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Dettes fournisseurs',
          icone: Symbols.local_shipping,
          action: FiltreRapport(
            valeur: vm.filtreStatutDette,
            libelleTous: 'Tous les statuts',
            options: const [('Urgent', 'Urgent'), ('Normal', 'Normal')],
            onChange: vm.definirFiltreStatutDette,
          ),
          child: dettes.isEmpty
              ? EtatVide(
                  message: vm.donnees.dettes.isEmpty
                      ? 'Aucune dette fournisseur : tous les achats sont '
                            'intégralement réglés.'
                      : 'Aucune dette ne correspond à ce statut.',
                )
              : Column(
                  children: [
                    const EnteteRapport(
                      colonnes: [
                        ('CODE', 2, TextAlign.left),
                        ('FOURNISSEUR', 5, TextAlign.left),
                        ('N° BON/FACTURE', 3, TextAlign.left),
                        ('DATE ACHAT', 2, TextAlign.left),
                        ('ÉCHÉANCE', 2, TextAlign.left),
                        ('MONTANT TOTAL', 2, TextAlign.right),
                        ('RÉGLÉ', 2, TextAlign.right),
                        ('SOLDE RESTANT', 2, TextAlign.right),
                        ('STATUT', 2, TextAlign.center),
                      ],
                    ),
                    for (var i = 0; i < dettes.length; i++)
                      LigneRapport(
                        zebre: i.isOdd,
                        cellules: [
                          (Text(dettes[i].code, style: monoRapport), 2),
                          (
                            Text(
                              dettes[i].fournisseur,
                              style: grasRapport,
                              overflow: TextOverflow.ellipsis,
                            ),
                            5,
                          ),
                          (
                            Text(
                              dettes[i].reference,
                              style: monoRapport,
                              overflow: TextOverflow.ellipsis,
                            ),
                            3,
                          ),
                          (
                            Text(
                              Formats.date(dettes[i].dateAchat),
                              style: texteRapport,
                            ),
                            2,
                          ),
                          (
                            Text(
                              dettes[i].echeance == null
                                  ? '—'
                                  : Formats.date(dettes[i].echeance!),
                              style: texteRapport,
                            ),
                            2,
                          ),
                          (MontantRapport(dettes[i].montantTotal), 2),
                          (MontantRapport(dettes[i].regle), 2),
                          (
                            MontantRapport(
                              dettes[i].soldeRestant,
                              gras: true,
                              couleur: AppColors.errorDeep,
                            ),
                            2,
                          ),
                          (
                            BadgeRapport(
                              libelle: dettes[i].statut,
                              alerte: dettes[i].urgente,
                            ),
                            2,
                          ),
                        ],
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    const NoteEcheance(
                      texte:
                          'Même limite que pour les créances : ACHATS ne porte '
                          'pas d\'échéance. La valeur du prototype n\'a pas été '
                          'reproduite — sa dette unique était datée du '
                          '06/08/2026 avec une échéance au 05/08/2026, donc '
                          'exigible la veille de son propre engagement.',
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ============================================================ Onglet 5

class _OngletElevage extends StatelessWidget {
  const _OngletElevage({required this.vm});

  final RapportsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final donnees = vm.donnees;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Effectif Total',
                valeur: '${donnees.effectifTotal}',
                detail: 'Toutes filières suivies',
                accent: AppColors.brandNavy,
                icone: Symbols.pets,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Sujets Malades',
                valeur: '${donnees.sujetsMalades}',
                detail: 'Infirmerie active',
                accent: donnees.sujetsMalades > 0
                    ? AppColors.errorDeep
                    : AppColors.successDeep,
                icone: Symbols.coronavirus,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Taux Éclosion Moyen',
                valeur: donnees.tauxEclosionMoyen == null
                    ? '—'
                    : Formats.pourcentage(donnees.tauxEclosionMoyen!),
                detail: donnees.tauxEclosionMoyen == null
                    ? 'Aucun cycle éclos à ce jour'
                    : 'Sur les cycles éclos',
                accent: AppColors.brandGold,
                icone: Symbols.egg,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Cycles en Cours',
                valeur: '${donnees.cyclesEnCours}',
                detail: 'Couveuse active',
                accent: AppColors.infoBlue,
                icone: Symbols.event_repeat,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Tableau 1 — Recensement & Structure du Cheptel',
          icone: Symbols.groups,
          child: donnees.recensement.isEmpty
              ? const EtatVide(
                  message:
                      'Aucune journée d\'élevage saisie sur la période. Le '
                      'recensement se construit à partir des fiches '
                      'journalières.',
                )
              : Column(
                  children: [
                    const EnteteRapport(
                      colonnes: [
                        ('LOT / SOUCHE', 3, TextAlign.left),
                        ('EFFECTIF TOTAL', 2, TextAlign.right),
                        ('GÉNITEURS / MATURES', 3, TextAlign.right),
                        ('JEUNES', 3, TextAlign.right),
                        ('MORTS (PÉRIODE)', 2, TextAlign.right),
                        ('DONS (PÉRIODE)', 2, TextAlign.right),
                        ('EFFECTIF MALADE', 3, TextAlign.center),
                      ],
                    ),
                    for (var i = 0; i < donnees.recensement.length; i++)
                      () {
                        final r = donnees.recensement[i];
                        return LigneRapport(
                          zebre: i.isOdd,
                          cellules: [
                            (Text(r.lot, style: grasRapport), 3),
                            (
                              Text(
                                '${r.effectifTotal}',
                                textAlign: TextAlign.right,
                                style: monoRapport,
                              ),
                              2,
                            ),
                            (
                              Text(
                                '${r.effectifMatures}',
                                textAlign: TextAlign.right,
                                style: monoRapport.copyWith(
                                  color: AppColors.successDeep,
                                ),
                              ),
                              3,
                            ),
                            (
                              Text(
                                '${r.effectifJeunes}',
                                textAlign: TextAlign.right,
                                style: monoRapport,
                              ),
                              3,
                            ),
                            (
                              Text(
                                '${r.mortsPeriode}',
                                textAlign: TextAlign.right,
                                style: monoRapport.copyWith(
                                  color: r.mortsPeriode > 0
                                      ? AppColors.errorDeep
                                      : null,
                                ),
                              ),
                              2,
                            ),
                            (
                              Text(
                                '${r.donsPeriode}',
                                textAlign: TextAlign.right,
                                style: monoRapport,
                              ),
                              2,
                            ),
                            (
                              Text(
                                '${r.effectifMalade}',
                                textAlign: TextAlign.center,
                                style: monoRapport.copyWith(
                                  color: r.effectifMalade > 0
                                      ? AppColors.brandGold
                                      : null,
                                ),
                              ),
                              3,
                            ),
                          ],
                        );
                      }(),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Tableau 2 — Mouvements, Traitements & Ventes',
          icone: Symbols.local_shipping,
          child: donnees.mouvementsElevage.isEmpty
              ? const EtatVide(
                  message:
                      'Aucun mouvement d\'élevage sur la période sélectionnée.',
                )
              : Column(
                  children: [
                    const EnteteRapport(
                      colonnes: [
                        ('LOT', 3, TextAlign.left),
                        ('QTÉ VENDUE', 2, TextAlign.right),
                        ('MONTANT VENTE', 3, TextAlign.right),
                        ('EFFECTIF FINAL', 2, TextAlign.right),
                        ('TRAITEMENT ADMINISTRÉ', 4, TextAlign.left),
                        ('SIGNES OBSERVÉS', 4, TextAlign.left),
                        ('PROVENDE SERVIE (G/J)', 3, TextAlign.right),
                      ],
                    ),
                    for (var i = 0; i < donnees.mouvementsElevage.length; i++)
                      () {
                        final m = donnees.mouvementsElevage[i];
                        return LigneRapport(
                          zebre: i.isOdd,
                          cellules: [
                            (Text(m.lot, style: grasRapport), 3),
                            (
                              Text(
                                '${m.quantiteVendue}',
                                textAlign: TextAlign.right,
                                style: monoRapport,
                              ),
                              2,
                            ),
                            (
                              MontantRapport(
                                m.montantVente,
                                couleur: AppColors.successDeep,
                              ),
                              3,
                            ),
                            (
                              Text(
                                '${m.effectifFinal}',
                                textAlign: TextAlign.right,
                                style: monoRapport,
                              ),
                              2,
                            ),
                            (
                              Text(
                                m.traitementAdministre,
                                style: texteRapport,
                                overflow: TextOverflow.ellipsis,
                              ),
                              4,
                            ),
                            (
                              Text(
                                m.signesObserves,
                                style: texteRapport.copyWith(
                                  color: AppColors.outline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              4,
                            ),
                            (
                              Text(
                                Formats.nombre(m.provendeServieGrammes),
                                textAlign: TextAlign.right,
                                style: monoRapport,
                              ),
                              3,
                            ),
                          ],
                        );
                      }(),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Tableau 3 — Couvoir & Suivi d\'Incubation',
          icone: Symbols.egg,
          child: donnees.couvoir.isEmpty
              ? const EtatVide(
                  message:
                      'Aucun cycle d\'incubation enregistré. Ils se créent '
                      'depuis l\'écran Cycle Couveuse.',
                )
              : Column(
                  children: [
                    const EnteteRapport(
                      colonnes: [
                        ('CODE LOT', 3, TextAlign.left),
                        ('MISE EN COUVOIR', 3, TextAlign.left),
                        ('ÉCLOSION ATTENDUE', 3, TextAlign.left),
                        ('ŒUFS COUVÉS', 2, TextAlign.right),
                        ('NÉS', 2, TextAlign.right),
                        ('TAUX D\'ÉCLOSION', 3, TextAlign.right),
                        ('MORTS AU DÉMARRAGE', 3, TextAlign.right),
                        ('STATUT', 2, TextAlign.center),
                      ],
                    ),
                    for (var i = 0; i < donnees.couvoir.length; i++)
                      () {
                        final c = donnees.couvoir[i];
                        return LigneRapport(
                          zebre: i.isOdd,
                          cellules: [
                            (Text(c.codeLot, style: monoRapport), 3),
                            (
                              Text(
                                Formats.date(c.miseEnCouvoir),
                                style: texteRapport,
                              ),
                              3,
                            ),
                            (
                              Text(
                                Formats.date(c.eclosionAttendue),
                                style: texteRapport,
                              ),
                              3,
                            ),
                            (
                              Text(
                                '${c.oeufsCouves}',
                                textAlign: TextAlign.right,
                                style: monoRapport,
                              ),
                              2,
                            ),
                            (
                              Text(
                                c.nes == null ? '—' : '${c.nes}',
                                textAlign: TextAlign.right,
                                style: monoRapport,
                              ),
                              2,
                            ),
                            (
                              Text(
                                c.tauxEclosion == null
                                    ? '—'
                                    : Formats.pourcentage(c.tauxEclosion!),
                                textAlign: TextAlign.right,
                                style: monoRapport.copyWith(
                                  color: c.tauxEclosion == null
                                      ? AppColors.outline
                                      : AppColors.successDeep,
                                ),
                              ),
                              3,
                            ),
                            (
                              Text(
                                c.mortsAuDemarrage == null
                                    ? '—'
                                    : '${c.mortsAuDemarrage}',
                                textAlign: TextAlign.right,
                                style: monoRapport.copyWith(
                                  color: (c.mortsAuDemarrage ?? 0) > 0
                                      ? AppColors.errorDeep
                                      : null,
                                ),
                              ),
                              3,
                            ),
                            (
                              BadgeRapport(
                                libelle: c.statut,
                                alerte: false,
                                succes:
                                    c.statut == StatutCycle.eclosionEffectuee,
                              ),
                              2,
                            ),
                          ],
                        );
                      }(),
                  ],
                ),
        ),
      ],
    );
  }
}

// ============================================================ Onglet 6

class _OngletStocks extends StatelessWidget {
  const _OngletStocks({required this.vm});

  final RapportsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final stocks = vm.stocksFiltres;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Valeur Totale du Stock',
                valeur: Formats.montant(vm.valeurTotaleStock),
                // Le KPI dit ce qu'il ne compte pas : un total muet sur 6
                // articles non valorises se lirait comme un total complet.
                detail: vm.articlesNonValorises == 0
                    ? 'Intrants au PMP + produits finis au coût de revient'
                    : 'Hors ${vm.articlesNonValorises} article(s) sans coût '
                          'de revient renseigné',
                accent: AppColors.brandNavy,
                icone: Symbols.inventory_2,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Articles en Alerte',
                valeur: '${vm.articlesEnAlerte}',
                detail: 'Sous le seuil critique',
                accent: AppColors.errorDeep,
                icone: Symbols.warning,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: CarteKpiRapport(
                libelle: 'Références Actives',
                valeur: '${vm.referencesActives}',
                detail: 'Intrants + Produits finis',
                accent: AppColors.infoBlue,
                icone: Symbols.category,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Inventaire valorisé',
          icone: Symbols.inventory_2,
          action: FiltreRapport(
            valeur: vm.filtreCategorieStock,
            libelleTous: 'Toutes catégories',
            options: const [
              (LigneStock.categorieIntrant, 'Intrants Provende'),
              (LigneStock.categorieProduitFini, 'Produits Finis'),
            ],
            onChange: vm.definirFiltreCategorieStock,
          ),
          child: stocks.isEmpty
              ? const EtatVide(
                  message: 'Aucun article ne correspond à cette catégorie.',
                )
              : Column(
                  children: [
                    const EnteteRapport(
                      colonnes: [
                        ('SKU', 2, TextAlign.left),
                        ('DÉSIGNATION', 5, TextAlign.left),
                        ('CATÉGORIE', 3, TextAlign.left),
                        ('STOCK FINAL', 2, TextAlign.right),
                        ('UNITÉ', 2, TextAlign.left),
                        ('CMUP', 2, TextAlign.right),
                        ('VALEUR TOTALE', 3, TextAlign.right),
                        ('STATUT', 2, TextAlign.center),
                      ],
                    ),
                    for (var i = 0; i < stocks.length; i++)
                      LigneRapport(
                        zebre: i.isOdd,
                        cellules: [
                          (Text(stocks[i].sku, style: monoRapport), 2),
                          (
                            Text(
                              stocks[i].designation,
                              style: grasRapport,
                              overflow: TextOverflow.ellipsis,
                            ),
                            5,
                          ),
                          (Text(stocks[i].categorie, style: texteRapport), 3),
                          (
                            Text(
                              Formats.nombre(stocks[i].stockFinal),
                              textAlign: TextAlign.right,
                              style: stocks[i].critique
                                  ? monoRapport.copyWith(
                                      color: AppColors.errorDeep,
                                    )
                                  : monoRapport,
                            ),
                            2,
                          ),
                          (Text(stocks[i].unite, style: texteRapport), 2),
                          (
                            stocks[i].cmup == null
                                ? Text(
                                    '—',
                                    textAlign: TextAlign.right,
                                    style: texteRapport.copyWith(
                                      color: AppColors.outline,
                                    ),
                                  )
                                : MontantRapport(stocks[i].cmup!),
                            2,
                          ),
                          (
                            stocks[i].valeurTotale == null
                                ? Text(
                                    'Non valorisé',
                                    textAlign: TextAlign.right,
                                    style: texteRapport.copyWith(
                                      color: AppColors.outline,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  )
                                : MontantRapport(
                                    stocks[i].valeurTotale!,
                                    gras: true,
                                  ),
                            3,
                          ),
                          (
                            BadgeRapport(
                              libelle: stocks[i].statut,
                              alerte: stocks[i].critique,
                              succes: !stocks[i].critique,
                            ),
                            2,
                          ),
                        ],
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    const NoteEcheance(
                      texte:
                          'Le CMUP des intrants est le Prix Moyen Pondéré tenu '
                          'par Gestion Stocks. Celui des produits finis est '
                          'leur prix de vente indicatif : le catalogue ne porte '
                          'aucun coût de revient, et en inventer un fausserait '
                          'la valorisation. La valeur des produits finis est '
                          'donc une valeur de marché, pas un coût.',
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
