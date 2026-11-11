import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';

/// Typographie — Doc 01 §2.
/// Poids reellement observes dans le prototype : 400 / 600 / 700 / 800.
/// Aucun poids 500 ni 300 n'est utilise cote web — ne pas en introduire.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Roboto';

  /// `text-xs` du prototype — **13,6 px et non 12**.
  ///
  /// `assets/css/common.css` l.44 pose
  /// `.text-xs { font-size: 0.85rem !important; }`. La racine vaut 16 px :
  /// la classe la plus employée du prototype (1381 emplois) vaut donc
  /// 13,6 px, et le `!important` bat la règle utilitaire de Tailwind.
  ///
  /// ⚠️ **Correction d'une lecture fautive du portage.** Ce fichier CSS
  /// est chargé par **35 des 41 pages** — toutes les pages applicatives.
  /// La surcharge est donc globale ; elle n'est pas propre aux trois
  /// écrans d'authentification, qui se contentent de la redeclarer en
  /// ligne. Le portage n'appliquait 13,6 px qu'au Splash, à l'Accueil et
  /// à la Connexion, et 12 px partout ailleurs : tout le reste de
  /// l'application était rendu 12 % trop petit.
  ///
  /// Mesuré par `outils/audit_typographie.py`.
  static const double textXs = 13.6;

  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: AppColors.onSurface,
  );

  static const TextStyle modalTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.brandNavy,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    color: AppColors.onSurface,
  );

  /// Cellule de tableau — `<td class="text-xs">`.
  ///
  /// Sur les 338 cellules du prototype qui posent explicitement leur
  /// taille, **327 sont en `text-xs`**, soit 13,6 px. Les en-têtes, eux,
  /// sont en `text-[12px]` : le prototype fait donc ses cellules **plus
  /// grandes** que ses en-têtes, là où le portage les avait égalisées.
  static const TextStyle tableCell = TextStyle(
    fontFamily: fontFamily,
    fontSize: textXs,
    color: AppColors.onSurface,
  );

  /// `text-[12px] text-outline font-bold uppercase` — **282 emplois**.
  ///
  /// Un seul style pour deux usages, dans le prototype comme ici : les
  /// **en-têtes de tableau** (196 relevés) et les **intitulés de KPI** (86).
  /// Les distinguer par deux définitions jumelles finirait par les faire
  /// diverger.
  ///
  /// ⚠️ La couleur est `outline`, pas `brand-navy` : c'est ce qui le sépare
  /// de [label], qui a la même taille et la même graisse.
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.outline,
  );

  /// En-tête de tableau — `<th>`. Voir [caption].
  static const TextStyle tableHeader = caption;


  /// Libellé de champ de formulaire.
  ///
  /// `<label class="block text-[12px] text-brand-navy font-bold uppercase
  /// mb-xs">` — relevé **147 fois** dans le prototype, de loin la forme
  /// dominante des libellés.
  ///
  /// ⚠️ **Deux corrections.** Le portage posait 10 px : les libellés étaient
  /// 17 % trop petits. Et il ajoutait un `letterSpacing: 0.4` que le prototype
  /// **ne demande nulle part** — `uppercase` n'ajoute aucun crénage, et les
  /// classes `tracking-*` n'apparaissent que sur une poignée d'éléments
  /// décoratifs des écrans d'accueil, jamais sur un libellé de champ.
  ///
  /// Les libellés centrés de 9 px (`text-[9px] text-outline`, 36 emplois) sont
  /// une autre forme : ils ont leur propre taille là où ils servent.
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.brandNavy,
  );

  static const TextStyle kpiValue = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: AppColors.onSurface,
  );

  /// `.invalid-feedback{color:#B33A3A;font-size:11px;margin-top:2px;}` — login.html l.18.
  static const TextStyle invalidFeedback = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    color: AppColors.errorDeep,
  );
}
