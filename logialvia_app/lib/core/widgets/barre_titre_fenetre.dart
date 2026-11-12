import 'dart:async';
import 'dart:io' show Platform;

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'geometrie_fenetre.dart';

/// Barre de titre du poste Windows, aux couleurs LogiALVIA (remplace le cadre natif).
///
/// Logo ALLMANY a gauche, titre, puis les trois boutons a droite : reduire,
/// agrandir/restaurer, fermer. La zone libre deplace la fenetre ; un double clic
/// l'agrandit ou la restaure. Le redimensionnement par les bords et l'accrochage
/// Windows restent ceux du systeme (`TitleBarStyle.hidden`).
///
/// La fermeture passe par `windowManager.close()` : elle declenche `onWindowClose`
/// (derniere synchronisation, puis `destroy`), comme le bouton du cadre natif.
class BarreTitreFenetre extends StatefulWidget {
  const BarreTitreFenetre({super.key});

  /// Seul Windows retire le cadre natif (voir `main.dart`).
  static bool get active => Platform.isWindows;

  @override
  State<BarreTitreFenetre> createState() => _BarreTitreFenetreState();
}

class _BarreTitreFenetreState extends State<BarreTitreFenetre>
    with WindowListener {
  bool _maximisee = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_lireEtat());
  }

  Future<void> _lireEtat() async {
    final etat = await windowManager.isMaximized();
    if (mounted) setState(() => _maximisee = etat);
  }

  @override
  void onWindowMaximize() => setState(() => _maximisee = true);

  @override
  void onWindowUnmaximize() {
    setState(() => _maximisee = false);
    // Restauration : ramene la fenetre dans le bureau (barre de titre visible).
    unawaited(garderFenetreDansEcran());
  }

  @override
  void onWindowResized() => unawaited(garderFenetreDansEcran());

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _basculer() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BarreTitreVue(
      maximisee: _maximisee,
      onReduire: () => unawaited(windowManager.minimize()),
      onBasculer: () => unawaited(_basculer()),
      onFermer: () => unawaited(windowManager.close()),
    );
  }
}

/// Partie visuelle, sans dependance au gestionnaire de fenetre (testable).
class BarreTitreVue extends StatelessWidget {
  const BarreTitreVue({
    super.key,
    required this.maximisee,
    required this.onReduire,
    required this.onBasculer,
    required this.onFermer,
  });

  final bool maximisee;
  final VoidCallback onReduire;
  final VoidCallback onBasculer;
  final VoidCallback onFermer;

  static const double hauteur = 36;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandNavyDark,
      child: SizedBox(
        height: hauteur,
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: onBasculer,
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      Image.asset(
                        'assets/images/icone_barre_titre.png',
                        width: 22,
                        height: 22,
                        filterQuality: FilterQuality.medium,
                        semanticLabel: 'ALLMANY ET COMPAGNIE',
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'LogiALVIA — ALLMANY ET COMPAGNIE',
                        key: Key('titre-fenetre'),
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _BoutonFenetre(
              cle: 'fenetre-reduire',
              icone: Icons.remove,
              onTap: onReduire,
            ),
            _BoutonFenetre(
              cle: 'fenetre-agrandir',
              icone: maximisee ? Icons.filter_none : Icons.crop_square,
              taille: maximisee ? 13 : 15,
              onTap: onBasculer,
            ),
            _BoutonFenetre(
              cle: 'fenetre-fermer',
              icone: Icons.close,
              survol: const Color(0xFFE81123),
              onTap: onFermer,
            ),
          ],
        ),
      ),
    );
  }
}

class _BoutonFenetre extends StatefulWidget {
  const _BoutonFenetre({
    required this.cle,
    required this.icone,
    required this.onTap,
    this.taille = 16,
    this.survol,
  });

  final String cle;
  final IconData icone;
  final VoidCallback onTap;
  final double taille;
  final Color? survol;

  @override
  State<_BoutonFenetre> createState() => _BoutonFenetreState();
}

class _BoutonFenetreState extends State<_BoutonFenetre> {
  bool _dessus = false;

  @override
  Widget build(BuildContext context) {
    final fond = _dessus
        ? (widget.survol ?? Colors.white.withValues(alpha: 0.14))
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _dessus = true),
      onExit: (_) => setState(() => _dessus = false),
      child: GestureDetector(
        key: Key(widget.cle),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: BarreTitreVue.hauteur,
          color: fond,
          alignment: Alignment.center,
          child: Icon(widget.icone, size: widget.taille, color: Colors.white),
        ),
      ),
    );
  }
}
