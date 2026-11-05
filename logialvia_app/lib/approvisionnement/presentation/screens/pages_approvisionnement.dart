import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../data/repositories/approvisionnement_repository_drift.dart';
import '../viewmodels/approvisionnement_view_model.dart';
import 'achats_fournisseurs_screens.dart';
import 'gestion_stocks_screen.dart';

/// Enveloppe commune aux 3 écrans du module Approvisionnement.
///
/// Ils partagent **un seul ViewModel** : ils lisent les mêmes tables, et une
/// commande réceptionnée depuis l'écran Achats doit se voir immédiatement dans
/// les Stocks. Trois ViewModels séparés auraient chacun leur copie, donc leur
/// propre version de la vérité.
class _PageAppro extends StatelessWidget {
  const _PageAppro({required this.enfant});

  final Widget enfant;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ApprovisionnementViewModel>(
      create: (context) => ApprovisionnementViewModel(
        ApprovisionnementRepositoryDrift(context.read<AppDatabase>()),
      )..charger(),
      child: enfant,
    );
  }
}

class PageGestionStocks extends StatelessWidget {
  const PageGestionStocks({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageAppro(enfant: GestionStocksScreen());
}

class PageAchats extends StatelessWidget {
  const PageAchats({super.key});

  @override
  Widget build(BuildContext context) => const _PageAppro(enfant: AchatsScreen());
}

class PageFournisseurs extends StatelessWidget {
  const PageFournisseurs({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageAppro(enfant: FournisseursScreen());
}
