import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Equivalent du `showToast(message, type)` du prototype — Doc E2 §5.
enum ToastType { success, error, warning }

/// Affiche un toast **en haut à droite**.
///
/// ## Pourquoi un `Overlay` et non un `SnackBar`
///
/// Un `SnackBar` Material est structurellement ancré en bas de l'écran : ni
/// `behavior`, ni `margin`, ni `width` ne le remontent. Or le prototype place
/// son `#toast-container` en `fixed bottom-4 right-4` sur une page web où le
/// contenu défile — et sur LogiALVIA, le bas droit est déjà occupé par les
/// deux boutons flottants (Accès Rapide et Visite Guidée) plus la barre
/// d'actions des modales. La Gérante a demandé le coin **haut droit** : c'est
/// le seul angle libre, et c'est là que le regard va après une action de la
/// barre du haut.
///
/// Les toasts s'empilent au lieu de se remplacer : deux enregistrements
/// enchaînés doivent tous deux être lus, alors qu'un `SnackBar` écrase le
/// précédent.
void showAppToast(
  BuildContext context,
  String message, {
  ToastType type = ToastType.success,
}) {
  final superposition = Overlay.maybeOf(context, rootOverlay: true);
  if (superposition == null) return;
  _FilePile.instance.ajouter(superposition, message, type);
}

/// Pile des toasts affichés, du plus ancien au plus récent.
///
/// Nécessaire parce que chaque toast doit connaître sa position verticale :
/// sans pile, deux toasts simultanés se superposeraient exactement.
class _FilePile {
  _FilePile._();

  static final _FilePile instance = _FilePile._();

  final List<_ToastEnCours> _actifs = [];

  /// Au-delà, les plus anciens sont retirés : un empilement sans fin
  /// masquerait l'écran au lieu de l'informer.
  static const int _maximumVisibles = 4;

  void ajouter(OverlayState superposition, String message, ToastType type) {
    if (_actifs.length >= _maximumVisibles) {
      _actifs.first.fermerImmediatement();
    }

    late final _ToastEnCours toast;
    final entree = OverlayEntry(
      builder: (context) => _ToastFlottant(
        message: message,
        type: type,
        rang: () => _actifs.indexOf(toast),
        onFermer: () => toast.fermerImmediatement(),
      ),
    );

    toast = _ToastEnCours(entree: entree, file: this);
    _actifs.add(toast);
    superposition.insert(entree);
    toast.programmerFermeture();
    _rafraichir();
  }

  void retirer(_ToastEnCours toast) {
    _actifs.remove(toast);
    _rafraichir();
  }

  /// Les toasts restants remontent quand l'un d'eux disparaît.
  void _rafraichir() {
    for (final toast in _actifs) {
      toast.entree.markNeedsBuild();
    }
  }
}

class _ToastEnCours {
  _ToastEnCours({required this.entree, required this.file});

  final OverlayEntry entree;
  final _FilePile file;
  Timer? _minuteur;
  bool _ferme = false;

  /// 3000 ms, identique au `setTimeout` du prototype (login.html l.156).
  void programmerFermeture() {
    _minuteur = Timer(const Duration(milliseconds: 3000), fermerImmediatement);
  }

  void fermerImmediatement() {
    if (_ferme) return;
    _ferme = true;
    _minuteur?.cancel();
    entree.remove();
    file.retirer(this);
  }
}

class _ToastFlottant extends StatefulWidget {
  const _ToastFlottant({
    required this.message,
    required this.type,
    required this.rang,
    required this.onFermer,
  });

  final String message;
  final ToastType type;

  /// Lu à chaque construction : la position change quand un toast plus ancien
  /// disparaît.
  final int Function() rang;

  final VoidCallback onFermer;

  @override
  State<_ToastFlottant> createState() => _ToastFlottantState();
}

class _ToastFlottantState extends State<_ToastFlottant>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controleur = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Les 3 couleurs sont celles du prototype (login.html l.149) :
    // success -> brand-navy, error -> error-deep, warning -> brand-gold.
    final (fond, icone) = switch (widget.type) {
      ToastType.success => (AppColors.brandNavy, Icons.check_circle),
      ToastType.error => (AppColors.errorDeep, Icons.error),
      ToastType.warning => (AppColors.brandGold, Icons.warning),
    };

    final rang = widget.rang();
    // Sous la barre du haut, pour ne pas masquer la recherche ni le profil.
    const hautDeDepart = 76.0;
    const hauteurToast = 60.0;

    return Positioned(
      top: hautDeDepart + rang * hauteurToast,
      right: AppSpacing.md,
      child: AnimatedBuilder(
        animation: _controleur,
        builder: (context, enfant) {
          final progression = Curves.easeOutCubic.transform(
            _controleur.value,
          );
          return Opacity(
            opacity: progression,
            // Entree par la droite — le toast vient du bord dont il est proche.
            child: Transform.translate(
              offset: Offset((1 - progression) * 40, 0),
              child: enfant,
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: fond,
                borderRadius: AppRadius.cardRadius,
                boxShadow: AppShadows.md,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icone, color: Colors.white, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Un message d'erreur long doit pouvoir etre ecarte tout de
                  // suite, sans attendre les 3 secondes.
                  InkWell(
                    onTap: widget.onFermer,
                    child: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
