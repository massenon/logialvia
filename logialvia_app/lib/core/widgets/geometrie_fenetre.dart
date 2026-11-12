import 'dart:math' as math;
import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Taille souhaitee de la fenetre restauree (breakpoint xl du prototype).
const Size tailleFenetreSouhaitee = Size(1440, 900);

/// Taille minimale de la fenetre (breakpoint lg).
const Size tailleFenetreMinimale = Size(1024, 700);

/// Rectangle de la fenetre restauree : jamais plus grand que la zone de travail
/// (bureau sans la barre des taches) et centre dedans, de sorte que la barre de
/// titre (reduire / agrandir / fermer) reste toujours visible.
Rect rectangleFenetreRestauree(Rect zoneTravail) {
  final largeur = math.min(tailleFenetreSouhaitee.width, zoneTravail.width * 0.92);
  final hauteur = math.min(tailleFenetreSouhaitee.height, zoneTravail.height * 0.92);
  return Rect.fromLTWH(
    zoneTravail.left + (zoneTravail.width - largeur) / 2,
    zoneTravail.top + (zoneTravail.height - hauteur) / 2,
    largeur,
    hauteur,
  );
}

/// Ramene [rect] dans [zoneTravail] : taille reduite si elle depasse, puis position
/// corrigee pour que le haut (barre de titre) et la fenetre entiere restent a l'ecran.
Rect ramenerDansZone(Rect rect, Rect zoneTravail) {
  final largeur = math.min(rect.width, zoneTravail.width);
  final hauteur = math.min(rect.height, zoneTravail.height);
  final gauche = rect.left.clamp(zoneTravail.left, zoneTravail.right - largeur);
  final haut = rect.top.clamp(zoneTravail.top, zoneTravail.bottom - hauteur);
  return Rect.fromLTWH(gauche.toDouble(), haut.toDouble(), largeur, hauteur);
}

/// Zone de travail de l'ecran principal (hors barre des taches), en pixels logiques.
Future<Rect?> zoneTravailEcran() async {
  try {
    final ecran = await screenRetriever.getPrimaryDisplay();
    final taille = ecran.visibleSize ?? ecran.size;
    final position = ecran.visiblePosition ?? Offset.zero;
    return position & taille;
  } on Object {
    return null;
  }
}

/// Corrige la fenetre (non agrandie) si elle deborde de l'ecran. Sans effet si elle est
/// agrandie, reduite dans la barre des taches ou deja correctement placee.
Future<void> garderFenetreDansEcran() async {
  if (await windowManager.isMaximized() ||
      await windowManager.isMinimized() ||
      await windowManager.isFullScreen()) {
    return;
  }
  final zone = await zoneTravailEcran();
  if (zone == null) return;
  final actuel = await windowManager.getBounds();
  final corrige = ramenerDansZone(actuel, zone);
  if (corrige != actuel) await windowManager.setBounds(corrige);
}
