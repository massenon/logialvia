import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_toast.dart';
import 'scenarios_tour.dart';
import 'tour_guide.dart';

/// Pilote de la visite guidée — `startTourGuide()`, `tourStep()`,
/// `endTourGuide()` de `common.js` §16.
class TourGuide {
  TourGuide._();

  static OverlayEntry? _entree;

  static bool get enCours => _entree != null;

  /// Démarre la visite de la route courante.
  ///
  /// Reproduit le filtre du prototype : `steps.filter(s =>
  /// document.querySelector(s.selector))`. Une étape dont la cible n'est pas
  /// affichée est écartée, et si aucune ne subsiste, le message honnête prévu
  /// par le prototype est affiché — pas un tour vide.
  static void demarrer(BuildContext context, String route) {
    if (enCours) return;

    final etapes = ScenariosTour.pour(
      route,
    ).where((e) => RegistreTour.existe(e.cible)).toList();

    if (etapes.isEmpty) {
      showAppToast(
        context,
        'Aucune visite guidée n\'est encore configurée pour cette page.',
        type: ToastType.warning,
      );
      return;
    }

    final superposition = Overlay.of(context, rootOverlay: true);
    _entree = OverlayEntry(
      builder: (_) => _SuperpositionTour(etapes: etapes, onFin: terminer),
    );
    superposition.insert(_entree!);
  }

  static void terminer() {
    _entree?.remove();
    _entree = null;
  }
}

class _SuperpositionTour extends StatefulWidget {
  const _SuperpositionTour({required this.etapes, required this.onFin});

  final List<EtapeTour> etapes;
  final VoidCallback onFin;

  @override
  State<_SuperpositionTour> createState() => _SuperpositionTourState();
}

class _SuperpositionTourState extends State<_SuperpositionTour> {
  int _index = 0;

  EtapeTour get _etape => widget.etapes[_index];

  void _aller(int delta) {
    final suivant = _index + delta;
    if (suivant < 0) return;
    if (suivant >= widget.etapes.length) {
      widget.onFin();
      return;
    }
    setState(() => _index = suivant);
  }

  /// Rectangle de la cible en coordonnées écran, ou `null` si elle a disparu
  /// entre-temps (un onglet refermé, une liste rechargée).
  Rect? get _zone {
    final rendu = RegistreTour.rendu(_etape.cible);
    if (rendu == null) return null;
    final origine = rendu.localToGlobal(Offset.zero);
    return origine & rendu.size;
  }

  @override
  Widget build(BuildContext context) {
    final ecran = MediaQuery.sizeOf(context);
    final zone = _zone;

    // `box-shadow: 0 0 0 4px #B58B2A, 0 0 0 9999px rgba(0,0,0,0.6)` de
    // `.tour-spotlight` : un anneau dore, et tout le reste assombri.
    const marge = 4.0;
    final trou = zone?.inflate(marge);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              // Cliquer hors de la carte ne ferme pas : le prototype impose la
              // croix ou « Terminer ». Le geste est capte pour que l'ecran
              // en dessous ne reagisse pas pendant la visite.
              onTap: () {},
              child: CustomPaint(painter: _PeintreVoile(trou: trou)),
            ),
          ),
          if (trou != null)
            Positioned(
              left: trou.left,
              top: trou.top,
              width: trou.width,
              height: trou.height,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.brandGold, width: 4),
                  ),
                ),
              ),
            ),
          _positionnerCarte(ecran, trou),
        ],
      ),
    );
  }

  /// Reprend le placement de `__renderTourStep()` : sous la cible, ou au-dessus
  /// si la carte déborderait du bas, et jamais collée aux bords.
  Widget _positionnerCarte(Size ecran, Rect? trou) {
    const largeur = 384.0; // `max-w-sm`
    const hauteurEstimee = 200.0;
    const ecart = 12.0;

    if (trou == null) {
      return Center(child: SizedBox(width: largeur, child: _carte()));
    }

    var haut = trou.bottom + ecart;
    if (haut + hauteurEstimee > ecran.height - ecart) {
      haut = (trou.top - hauteurEstimee - ecart).clamp(
        ecart,
        ecran.height - hauteurEstimee - ecart,
      );
    }
    final gauche = trou.left.clamp(ecart, ecran.width - largeur - ecart);

    return Positioned(
      left: gauche,
      top: haut,
      width: largeur,
      child: _carte(),
    );
  }

  Widget _carte() {
    final derniere = _index == widget.etapes.length - 1;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: AppRadius.cardRadius,
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 24, spreadRadius: 4),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Étape ${_index + 1} / ${widget.etapes.length}',
                  style: AppTypography.label.copyWith(
                    color: AppColors.brandNavy,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              InkWell(
                onTap: widget.onFin,
                child: const Icon(
                  Symbols.close,
                  size: 18,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _etape.titre,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavyDark,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _etape.texte,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              height: 1.6,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // `visibility:hidden` a la premiere etape : le bouton garde sa
              // place pour que « Suivant » ne se deplace pas d'une etape a
              // l'autre.
              Visibility(
                visible: _index > 0,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: _BoutonTour(
                  libelle: 'Précédent',
                  principal: false,
                  onTap: () => _aller(-1),
                ),
              ),
              _BoutonTour(
                libelle: derniere ? 'Terminer' : 'Suivant',
                principal: true,
                onTap: () => _aller(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Voile sombre percé d'un trou sur la cible — l'ombre de 9999 px du prototype.
class _PeintreVoile extends CustomPainter {
  const _PeintreVoile({required this.trou});

  final Rect? trou;

  @override
  void paint(Canvas toile, Size taille) {
    final voile = Paint()..color = const Color(0x99000000); // black/60
    final tout = Path()..addRect(Offset.zero & taille);

    if (trou == null) {
      toile.drawPath(tout, voile);
      return;
    }

    final decoupe = Path()
      ..addRRect(RRect.fromRectAndRadius(trou!, const Radius.circular(8)));
    toile.drawPath(
      Path.combine(PathOperation.difference, tout, decoupe),
      voile,
    );
  }

  @override
  bool shouldRepaint(_PeintreVoile ancien) => ancien.trou != trou;
}

class _BoutonTour extends StatelessWidget {
  const _BoutonTour({
    required this.libelle,
    required this.principal,
    required this.onTap,
  });

  final String libelle;
  final bool principal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.cardRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: principal ? AppColors.brandNavy : null,
          border: principal
              ? null
              : Border.all(color: AppColors.outlineVariant),
          borderRadius: AppRadius.cardRadius,
        ),
        child: Text(
          libelle,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: principal ? FontWeight.w700 : FontWeight.w600,
            color: principal ? Colors.white : AppColors.outline,
          ),
        ),
      ),
    );
  }
}
