import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../data/repositories/bandes_repository_drift.dart';
import '../../data/repositories/fiche_elevage_repository_drift.dart';
import '../../data/repositories/parametres_elevage_repository_drift.dart';
import '../../data/repositories/soins_repository_drift.dart';
import '../../domain/entities/configuration_espece.dart';
import '../viewmodels/fiche_espece_view_model.dart';
import 'fiche_espece_screen.dart';

/// Point d'entrée d'une fiche d'élevage : crée le ViewModel propre à l'espèce,
/// puis délègue à l'écran générique.
///
/// ECART ASSUME avec Doc K4 §5 (« tout Provider est global ») : un
/// [FicheEspeceViewModel] est **spécifique à une espèce** et porte l'état de
/// saisie d'un mois. En enregistrer 6 exemplaires globaux chargerait 6 mois de
/// données à chaque démarrage, et deux fiches ouvertes successivement
/// partageraient un état incohérent. La règle de K4 §5 vise les ViewModels dont
/// une **modale partagée** dépend — ce n'est pas le cas ici : aucune modale
/// commune n'accède à la fiche d'une espèce donnée. Le jour où ce sera le cas,
/// ce Provider devra remonter dans `main.dart`.
class PageFicheEspece extends StatelessWidget {
  const PageFicheEspece({super.key, required this.configuration});

  final ConfigurationEspece configuration;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FicheEspeceViewModel>(
      // `key` sur l'espèce : passer d'une fiche à l'autre doit reconstruire le
      // ViewModel, jamais réutiliser celui de l'espèce précédente.
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
