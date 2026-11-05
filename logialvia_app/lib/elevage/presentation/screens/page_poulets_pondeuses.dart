import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../data/repositories/bandes_repository_drift.dart';
import '../../data/repositories/fiche_elevage_repository_drift.dart';
import '../../data/repositories/parametres_elevage_repository_drift.dart';
import '../../data/repositories/soins_repository_drift.dart';
import '../../domain/entities/configuration_espece.dart';
import '../viewmodels/fiche_espece_view_model.dart';
import 'fiche_espece_screen.dart';

/// Fiche Poulets / Pondeuses — **le seul écran à onglets internes du module
/// Élevage** (Doc F0, Doc H2).
///
/// Les 2 onglets sont gérés par un `TabController`, **pas par des sous-routes**
/// (Doc E3 §4, contrainte 1:1 écran ↔ fichier HTML).
///
/// Chaque onglet a son propre [FicheEspeceViewModel] : ce sont deux espèces
/// distinctes en base (`poulets` et `pondeuses`), avec des historiques, des
/// catégories et — pour les Pondeuses — un suivi de stock d'œufs séparés.
/// Les partager mélangerait deux fiches.
class PagePouletsPondeuses extends StatefulWidget {
  const PagePouletsPondeuses({super.key});

  @override
  State<PagePouletsPondeuses> createState() => _PagePouletsPondeusesState();
}

class _PagePouletsPondeusesState extends State<PagePouletsPondeuses>
    with SingleTickerProviderStateMixin {
  late final TabController _controleur = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.surfaceCard,
          child: TabBar(
            controller: _controleur,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.brandNavy,
            unselectedLabelColor: AppColors.outline,
            indicatorColor: AppColors.brandNavy,
            labelStyle: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            tabs: const [Tab(text: 'Poulets'), Tab(text: 'Pondeuses')],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _controleur,
            children: const [
              _OngletFiche(configuration: ConfigurationsEspeces.poulets),
              _OngletFiche(configuration: ConfigurationsEspeces.pondeuses),
            ],
          ),
        ),
      ],
    );
  }
}

class _OngletFiche extends StatelessWidget {
  const _OngletFiche({required this.configuration});

  final ConfigurationEspece configuration;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FicheEspeceViewModel>(
      key: ValueKey(configuration.identifiant),
      create: (context) => FicheEspeceViewModel(
        configuration: configuration,
        repository: FicheElevageRepositoryDrift(
          context.read<AppDatabase>(),
          configuration,
        ),
        parametresRepository: ParametresElevageRepositoryDrift(
          context.read<AppDatabase>(),
        ),
        bandesRepository: BandesRepositoryDrift(context.read<AppDatabase>()),
        soinsRepository: SoinsRepositoryDrift(context.read<AppDatabase>()),
      )..charger(),
      child: FicheEspeceScreen(configuration: configuration),
    );
  }
}
