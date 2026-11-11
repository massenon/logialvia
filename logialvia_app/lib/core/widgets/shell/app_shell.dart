import 'package:provider/provider.dart';

import '../../../administration/data/repositories/preferences_poste_repository.dart';
import '../../database/app_database.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/app_colors.dart';
import '../../tour/superposition_tour.dart';
import 'acces_rapide.dart';
import 'app_sidebar.dart';
import 'app_top_bar.dart';

/// Coquille commune aux ecrans internes — Doc E3 §1.
///
/// La barre laterale et la barre du haut sont **hors du `Navigator` interne** :
/// elles ne sont pas reconstruites a chaque changement d'ecran, exactement
/// comme cote web ou `sidebar.js` n'est inclus qu'une fois par page. C'est le
/// role du `ShellRoute` de `go_router` (Doc E3 §3).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.routeActive, required this.child});

  final String routeActive;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// `toggleSidebarDesktop()` du prototype : la barre laterale se replie
  /// entierement, elle ne passe pas en mode icones.
  bool _sidebarVisible = true;

  /// `applyStoredSidebarState()` (`common.js` l.27-42) restaure l'etat replie
  /// au chargement de chaque page. Cote Flutter, la barre repartait depliee a
  /// chaque lancement : le reglage etait a refaire tous les matins, alors que
  /// c'est justement sur les petits ecrans qu'on la replie pour gagner de la
  /// place.
  PreferencesPosteRepository? _preferences;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restaurerBarre());
  }

  Future<void> _restaurerBarre() async {
    final preferences = PreferencesPosteRepository(context.read<AppDatabase>());
    _preferences = preferences;
    final repliee = await preferences.barreLateraleRepliee();
    if (!mounted || !repliee) return;
    setState(() => _sidebarVisible = false);
  }

  void _basculerBarre() {
    setState(() => _sidebarVisible = !_sidebarVisible);
    _preferences?.definirBarreLateraleRepliee(repliee: !_sidebarVisible);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBg,
      body: Stack(
        children: [
          _corps(),
          // Menu flottant « Acces Rapide » — independant de la barre laterale,
          // c'est tout son interet : replier la barre ne doit pas couper la
          // navigation (`toggleSpeciesQuickNav()` du prototype).
          AccesRapide(sidebarRepliee: !_sidebarVisible),
          // Bouton d'aide flottant — `sidebar.js` l.107, `bottom:144px;
          // right:16px`, bleu info, au-dessus du bouton d'Acces Rapide. Il se
          // decale de la meme facon quand la barre laterale est repliee.
          _BoutonVisiteGuidee(
            sidebarRepliee: !_sidebarVisible,
            routeActive: widget.routeActive,
          ),
        ],
      ),
    );
  }

  Widget _corps() {
    return Row(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _sidebarVisible
              ? AppSidebar(routeActive: widget.routeActive)
              : const SizedBox(width: 0, height: double.infinity),
        ),
        Expanded(
          child: Column(
            children: [
              AppTopBar(
                routeActive: widget.routeActive,
                onBasculerSidebar: () =>
                    _basculerBarre(),
              ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bouton « Visite guidée de cette page » — `startTourGuide()`.
///
/// Toujours visible, y compris sur les écrans sans scénario : c'est là que le
/// message honnête du prototype prend son sens. Un bouton qui disparaîtrait
/// sur ces pages laisserait croire que la visite n'existe nulle part.
class _BoutonVisiteGuidee extends StatelessWidget {
  const _BoutonVisiteGuidee({
    required this.sidebarRepliee,
    required this.routeActive,
  });

  final bool sidebarRepliee;
  final String routeActive;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 144,
      right: sidebarRepliee ? 80 : 16,
      child: Tooltip(
        message: 'Visite guidée de cette page',
        child: Material(
          color: AppColors.infoBlue,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => TourGuide.demarrer(context, routeActive),
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(Symbols.help, size: 24, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
