import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../administration/data/repositories/parametres_repository_drift.dart';
import '../../../administration/presentation/viewmodels/parametres_generaux_view_model.dart';
import '../../../core/database/app_database.dart';
import '../../data/repositories/comptabilite_repository_drift.dart';
import '../viewmodels/comptabilite_view_model.dart';
import 'balance_generale_screen.dart';
import 'bilan_entreprise_screen.dart';
import 'cloture_exercice_screen.dart';
import 'comptabilite_analytique_screen.dart';
import 'comptabilite_hub_screen.dart';
import 'etats_financiers_screen.dart';
import 'grand_livre_screen.dart';
import 'journal_comptable_screen.dart';
import 'plan_comptable_screen.dart';
import 'saisie_depenses_screen.dart';

/// Enveloppe commune aux 9 écrans du module Comptabilité — Doc F6.
///
/// **Un seul ViewModel** pour tout le module : les 9 écrans lisent la même
/// table `ECRITURE_COMPTABLE` et doivent afficher le **même** Résultat Net
/// (BR-CPT-005). Des ViewModels séparés auraient chacun leur copie des
/// écritures, donc leur propre version du résultat — exactement ce que la règle
/// interdit.
class _PageCompta extends StatelessWidget {
  const _PageCompta({required this.enfant});

  final Widget enfant;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ComptabiliteViewModel>(
      create: (context) => ComptabiliteViewModel(
        ComptabiliteRepositoryDrift(context.read<AppDatabase>()),
      )..charger(),
      child: enfant,
    );
  }
}

class PageComptabiliteHub extends StatelessWidget {
  const PageComptabiliteHub({super.key});

  @override
  Widget build(BuildContext context) {
    // Le bandeau MeCeF du hub dépend de l'IFU et du RCCM saisis dans Paramètres
    // Généraux (Doc F8 Onglet 2) : le hub a donc besoin des deux ViewModels.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ParametresGenerauxViewModel>(
          create: (context) => ParametresGenerauxViewModel(
            ParametresRepositoryDrift(context.read<AppDatabase>()),
          )..charger(),
        ),
      ],
      child: const _PageCompta(enfant: ComptabiliteHubScreen()),
    );
  }
}

class PageJournalComptable extends StatelessWidget {
  const PageJournalComptable({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompta(enfant: JournalComptableScreen());
}

class PageGrandLivre extends StatelessWidget {
  const PageGrandLivre({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompta(enfant: GrandLivreScreen());
}

class PageBalanceGenerale extends StatelessWidget {
  const PageBalanceGenerale({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompta(enfant: BalanceGeneraleScreen());
}

class PageBilanEntreprise extends StatelessWidget {
  const PageBilanEntreprise({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompta(enfant: BilanEntrepriseScreen());
}

class PagePlanComptable extends StatelessWidget {
  const PagePlanComptable({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompta(enfant: PlanComptableScreen());
}

class PageEtatsFinanciers extends StatelessWidget {
  const PageEtatsFinanciers({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompta(enfant: EtatsFinanciersScreen());
}

class PageClotureExercice extends StatelessWidget {
  const PageClotureExercice({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompta(enfant: ClotureExerciceScreen());
}

class PageComptabiliteAnalytique extends StatelessWidget {
  const PageComptabiliteAnalytique({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompta(enfant: ComptabiliteAnalytiqueScreen());
}

class PageSaisieDepenses extends StatelessWidget {
  const PageSaisieDepenses({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompta(enfant: SaisieDepensesScreen());
}
