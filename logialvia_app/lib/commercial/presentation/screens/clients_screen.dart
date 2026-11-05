import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/events/domain_event.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import 'documents_commercial.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../data/repositories/clients_repository_drift.dart';
import '../../data/repositories/ventes_repository_drift.dart';
import '../../domain/entities/client.dart';
import '../viewmodels/clients_view_model.dart';
import '../../../core/saisie/formats_saisie.dart';

class PageClients extends StatelessWidget {
  const PageClients({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ClientsViewModel>(
      create: (context) {
        final db = context.read<AppDatabase>();
        return ClientsViewModel(
          ClientsRepositoryDrift(db),
          VentesRepositoryDrift(db, context.read<EventBus>()),
        )..charger();
      },
      child: const ClientsScreen(),
    );
  }
}

/// Clients et Créances — Doc F4 Écran 3, fidèle à `relances-clients.html`.
///
/// ⚠️ **3 tableaux** (Clients, Créances, Événements CRM) et 4 KPI dont **3
/// diffèrent** de ceux que listait Doc F4.
class ClientsScreen extends StatelessWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ClientsViewModel>();

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
                Symbols.payments,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Clients et Créances',
                  style: AppTypography.pageTitle,
                ),
              ),
              BoutonExportPdf(
                construire: () => DocumentsCommercial.creancesClients(vm),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Ajouter un Client',
                icon: Symbols.person_add,
                onPressed: () => _ajouterClient(context, vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _BandeauKpi(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          _TableauClients(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          _TableauCreances(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          _TableauCrm(vm: vm),
        ],
      ),
    );
  }

  Future<void> _ajouterClient(BuildContext context, ClientsViewModel vm) async {
    final resultat = await AppModal.show<Resultat<Client>>(
      context,
      title: 'Ajouter un Client',
      maxWidth: 400,
      child: _FormulaireClient(vm: vm),
    );
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes<Client>():
        showAppToast(context, 'Client enregistré.');
      case Echec<Client>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

class _BandeauKpi extends StatelessWidget {
  const _BandeauKpi({required this.vm});

  final ClientsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cartes = [
      KpiCard(
        libelle: 'Clients Enregistrés',
        valeur: '${vm.clientsEnregistres}',
        accent: AppColors.brandNavy,
        icone: Symbols.group,
      ),
      KpiCard(
        libelle: 'Solde Total Restant Dû',
        valeur: Formats.nombre(vm.soldeTotalRestantDu),
        unite: 'FCFA',
        accent: AppColors.errorDeep,
        icone: Symbols.request_quote,
      ),
      KpiCard(
        libelle: 'Soldes Anciens (>10j)',
        valeur: '${vm.soldesAnciens}',
        accent: AppColors.brandGold,
        icone: Symbols.schedule,
      ),
      KpiCard(
        libelle: 'Événements CRM (7j)',
        valeur: '${vm.evenementsCrm}',
        accent: AppColors.successDeep,
        icone: Symbols.celebration,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeur = (constraints.maxWidth - AppSpacing.md * 3) / 4;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final carte in cartes) SizedBox(width: largeur, child: carte),
          ],
        );
      },
    );
  }
}

class _TableauClients extends StatelessWidget {
  const _TableauClients({required this.vm});

  final ClientsViewModel vm;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      cibleTour: 'clients-tableau',
      titre: 'Clients',
      child: vm.clients.isEmpty
          ? const EtatVide(
              message:
                  'Aucun client enregistré. Les ventes au comptoir peuvent se '
                  'faire sans fiche client ; enregistrez-en une pour suivre '
                  'les créances et les anniversaires.',
            )
          : Column(
              children: [
                const _EnteteTableau(
                  colonnes: [
                    ('Nom', 2, TextAlign.left),
                    ('Téléphone', 2, TextAlign.left),
                    ('Date de Naissance', 2, TextAlign.left),
                    ('Total Achats', 2, TextAlign.right),
                    ('Solde Actuel', 2, TextAlign.right),
                  ],
                ),
                for (var i = 0; i < vm.clients.length; i++)
                  _Ligne(
                    zebre: i.isOdd,
                    cellules: [
                      (Text(vm.clients[i].nom, style: _gras), 2, null),
                      (
                        Text(vm.clients[i].telephone ?? '—', style: _texte),
                        2,
                        null,
                      ),
                      (
                        Text(
                          vm.clients[i].dateNaissance == null
                              ? '—'
                              : Formats.date(vm.clients[i].dateNaissance!),
                          style: _texte,
                        ),
                        2,
                        null,
                      ),
                      (
                        Text(
                          Formats.nombre(vm.clients[i].totalAchats),
                          textAlign: TextAlign.right,
                          style: _texte,
                        ),
                        2,
                        null,
                      ),
                      (
                        Text(
                          Formats.nombre(vm.clients[i].soldeActuel),
                          textAlign: TextAlign.right,
                          style: _gras.copyWith(
                            color: vm.clients[i].aUneCreance
                                ? AppColors.errorDeep
                                : AppColors.successDeep,
                          ),
                        ),
                        2,
                        null,
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}

class _TableauCreances extends StatelessWidget {
  const _TableauCreances({required this.vm});

  final ClientsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final maintenant = DateTime.now();

    return CarteSection(
      titre: 'Créances Ouvertes',
      icone: Symbols.request_quote,
      couleurIcone: AppColors.errorDeep,
      child: vm.creances.isEmpty
          ? const EtatVide(
              message:
                  'Aucune créance ouverte. Les ventes réglées en « Avance » '
                  'apparaissent ici jusqu\'à leur solde complet.',
            )
          : Column(
              children: [
                const _EnteteTableau(
                  colonnes: [
                    ('Client', 2, TextAlign.left),
                    ('Référence Vente', 2, TextAlign.left),
                    ('Montant Total', 2, TextAlign.right),
                    ('Déjà Réglé', 2, TextAlign.right),
                    ('Solde Restant Dû', 2, TextAlign.right),
                    ('Ancienneté', 1, TextAlign.center),
                    ('Action', 2, TextAlign.right),
                  ],
                ),
                for (var i = 0; i < vm.creances.length; i++)
                  () {
                    final creance = vm.creances[i];
                    final jours = creance.ancienneteJours(maintenant);
                    return _Ligne(
                      zebre: i.isOdd,
                      cellules: [
                        (Text(creance.client, style: _gras), 2, null),
                        (Text(creance.referenceVente, style: _texte), 2, null),
                        (
                          Text(
                            Formats.nombre(creance.montantTotal),
                            textAlign: TextAlign.right,
                            style: _texte,
                          ),
                          2,
                          null,
                        ),
                        (
                          Text(
                            Formats.nombre(creance.dejaRegle),
                            textAlign: TextAlign.right,
                            style: _texte,
                          ),
                          2,
                          null,
                        ),
                        (
                          Text(
                            Formats.nombre(creance.soldeRestantDu),
                            textAlign: TextAlign.right,
                            style: _gras.copyWith(color: AppColors.errorDeep),
                          ),
                          2,
                          null,
                        ),
                        (
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: creance.estAncienne(maintenant)
                                    ? AppColors.errorContainer
                                    : AppColors.surfaceZebra,
                                borderRadius: AppRadius.pill,
                              ),
                              child: Text(
                                '$jours j',
                                style: TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: creance.estAncienne(maintenant)
                                      ? AppColors.errorDeep
                                      : AppColors.outline,
                                ),
                              ),
                            ),
                          ),
                          1,
                          null,
                        ),
                        (
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _encaisser(context, vm, creance),
                              child: const Text(
                                'Enregistrer un Paiement',
                                style: TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          2,
                          null,
                        ),
                      ],
                    );
                  }(),
              ],
            ),
    );
  }

  Future<void> _encaisser(
    BuildContext context,
    ClientsViewModel vm,
    Creance creance,
  ) async {
    final resultat = await AppModal.show<Resultat<void>>(
      context,
      title: 'Enregistrer un Paiement',
      maxWidth: 400,
      child: _FormulairePaiement(vm: vm, creance: creance),
    );
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes<void>():
        showAppToast(context, 'Paiement enregistré.');
      case Echec<void>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

class _TableauCrm extends StatelessWidget {
  const _TableauCrm({required this.vm});

  final ClientsViewModel vm;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Événements CRM à Venir',
      icone: Symbols.celebration,
      couleurIcone: AppColors.successDeep,
      child: vm.evenements.isEmpty
          ? const EtatVide(
              message:
                  'Aucun événement dans les 7 prochains jours. Les '
                  'anniversaires sont déduits de la date de naissance des '
                  'clients — renseignez-la pour les voir apparaître.',
            )
          : Column(
              children: [
                const _EnteteTableau(
                  colonnes: [
                    ('Client', 2, TextAlign.left),
                    ('Type d\'Événement', 2, TextAlign.left),
                    ('Date', 2, TextAlign.left),
                    ('Jours Restants', 1, TextAlign.center),
                    ('Dernier Contact', 2, TextAlign.left),
                    ('Action', 2, TextAlign.right),
                  ],
                ),
                for (var i = 0; i < vm.evenements.length; i++)
                  () {
                    final evenement = vm.evenements[i];
                    final client = vm.clients.firstWhere(
                      (c) => c.nom == evenement.client,
                    );
                    return _Ligne(
                      zebre: i.isOdd,
                      cellules: [
                        (Text(evenement.client, style: _gras), 2, null),
                        (Text(evenement.type, style: _texte), 2, null),
                        (
                          Text(Formats.date(evenement.date), style: _texte),
                          2,
                          null,
                        ),
                        (
                          Center(
                            child: Text(
                              evenement.joursRestants == 0
                                  ? 'Aujourd\'hui'
                                  : '${evenement.joursRestants} j',
                              style: _gras.copyWith(
                                color: evenement.joursRestants <= 1
                                    ? AppColors.errorDeep
                                    : AppColors.brandNavy,
                              ),
                            ),
                          ),
                          1,
                          null,
                        ),
                        (
                          Text(
                            evenement.dernierContact == null
                                ? 'Jamais'
                                : Formats.date(evenement.dernierContact!),
                            style: _texte,
                          ),
                          2,
                          null,
                        ),
                        (
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () async {
                                final resultat = await vm.marquerContact(
                                  client,
                                );
                                if (!context.mounted) return;
                                switch (resultat) {
                                  case Succes<void>():
                                    showAppToast(
                                      context,
                                      'Contact horodaté. La relance elle-même '
                                      'reste à faire par téléphone.',
                                    );
                                  case Echec<void>(message: final m):
                                    showAppToast(
                                      context,
                                      m,
                                      type: ToastType.error,
                                    );
                                }
                              },
                              // ECART_DELIBERE : le prototype affiche
                              // « Relancer » alors qu'aucune passerelle SMS ou
                              // telephonie n'existe (Doc B1 §6). Le libelle dit
                              // ce que l'action fait reellement.
                              child: const Text(
                                'Marquer contacté',
                                style: TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          2,
                          null,
                        ),
                      ],
                    );
                  }(),
              ],
            ),
    );
  }
}

class _EnteteTableau extends StatelessWidget {
  const _EnteteTableau({required this.colonnes});

  final List<(String, int, TextAlign)> colonnes;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceZebra,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          for (final (libelle, flex, alignement) in colonnes)
            Expanded(
              flex: flex,
              child: Text(
                libelle,
                textAlign: alignement,
                style: _texte.copyWith(color: AppColors.outline),
              ),
            ),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.cellules, required this.zebre});

  final List<(Widget, int, void)> cellules;
  final bool zebre;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: zebre ? AppColors.surfaceZebra : null,
        border: const Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          for (final (widget, flex, _) in cellules)
            Expanded(flex: flex, child: widget),
        ],
      ),
    );
  }
}

class _FormulaireClient extends StatefulWidget {
  const _FormulaireClient({required this.vm});

  final ClientsViewModel vm;

  @override
  State<_FormulaireClient> createState() => _FormulaireClientState();
}

class _FormulaireClientState extends State<_FormulaireClient> {
  final _nom = TextEditingController();
  final _telephone = TextEditingController();
  DateTime? _naissance;
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.creerClient(
      nom: _nom.text,
      telephone: _telephone.text,
      dateNaissance: _naissance,
    );
    if (!mounted) return;

    if (resultat is Echec<Client>) {
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
        const SizedBox(height: AppSpacing.sm),
        _champ('Téléphone', _telephone),
        const SizedBox(height: AppSpacing.sm),
        const Text('DATE DE NAISSANCE', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton.icon(
          onPressed: () async {
            final choisie = await showDatePicker(
              context: context,
              initialDate: _naissance ?? DateTime(1990),
              firstDate: DateTime(1920),
              lastDate: DateTime.now(),
              locale: const Locale('fr'),
            );
            if (choisie != null) setState(() => _naissance = choisie);
          },
          icon: const Icon(Symbols.calendar_month, size: 16),
          label: Text(
            _naissance == null ? 'Non renseignée' : Formats.date(_naissance!),
          ),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size(double.infinity, 40),
            foregroundColor: AppColors.onSurface,
            side: const BorderSide(color: AppColors.outlineVariant),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Sert à générer les événements CRM (anniversaires).',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            color: AppColors.outline,
          ),
        ),
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
              label: _enCours ? 'Enregistrement…' : 'Enregistrer',
              onPressed: _enCours ? null : _valider,
            ),
          ],
        ),
      ],
    );
  }

  Widget _champ(String libelle, TextEditingController controleur) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(libelle.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controleur,
          style: _texte,
          decoration: _decoration,
        ),
      ],
    );
  }
}

class _FormulairePaiement extends StatefulWidget {
  const _FormulairePaiement({required this.vm, required this.creance});

  final ClientsViewModel vm;
  final Creance creance;

  @override
  State<_FormulairePaiement> createState() => _FormulairePaiementState();
}

class _FormulairePaiementState extends State<_FormulairePaiement> {
  final _montant = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.enregistrerPaiement(
      referenceVente: widget.creance.referenceVente,
      montant: double.tryParse(_montant.text),
    );
    if (!mounted) return;

    if (resultat is Echec<void>) {
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
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceZebra,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.creance.client} · ${widget.creance.referenceVente}',
                style: _gras,
              ),
              Text(
                'Solde restant dû : '
                '${Formats.montant(widget.creance.soldeRestantDu)}',
                style: _texte.copyWith(color: AppColors.errorDeep),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('MONTANT RECOUVRÉ (FCFA) *', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _montant,
          keyboardType: TextInputType.number,
          inputFormatters: FormatteursSaisie.montant,
          style: _texte,
          decoration: _decoration,
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Un versement supérieur au solde est automatiquement borné au reste '
          'dû. La vente passera en « Payée » une fois soldée.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            color: AppColors.outline,
          ),
        ),
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
              label: _enCours ? 'Enregistrement…' : 'Enregistrer',
              onPressed: _enCours ? null : _valider,
            ),
          ],
        ),
      ],
    );
  }
}

const TextStyle _texte = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

final TextStyle _gras = _texte.copyWith(fontWeight: FontWeight.w700);

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
