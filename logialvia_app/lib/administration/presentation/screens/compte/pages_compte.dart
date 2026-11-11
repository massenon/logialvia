import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../data/repositories/compte_repository_drift.dart';
import '../../viewmodels/auth_view_model.dart';
import '../../viewmodels/compte_view_model.dart';
import 'aide_a_propos_screen.dart';
import 'contact_editeur_screen.dart';
import 'mon_profil_screen.dart';

/// Enveloppe commune aux 3 écrans du module Compte Utilisateur — Doc F9.
///
/// Un seul ViewModel : les 3 écrans dépendent de la même session ouverte, et le
/// formulaire de contact a besoin de l'identité de l'expéditrice pour composer
/// un message signé.
class _PageCompte extends StatelessWidget {
  const _PageCompte({required this.enfant});

  final Widget enfant;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CompteViewModel>(
      create: (context) => CompteViewModel(
        CompteRepositoryDrift(context.read<AppDatabase>()),
        context.read<AuthViewModel>().session,
      )..charger(),
      child: enfant,
    );
  }
}

class PageMonProfil extends StatelessWidget {
  const PageMonProfil({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompte(enfant: MonProfilScreen());
}

class PageAideAPropos extends StatelessWidget {
  const PageAideAPropos({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompte(enfant: AideAProposScreen());
}

class PageContactEditeur extends StatelessWidget {
  const PageContactEditeur({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageCompte(enfant: ContactEditeurScreen());
}
