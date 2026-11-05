import 'package:flutter/material.dart';

/// Ombres — Doc 01 §4.
class AppShadows {
  AppShadows._();

  /// `shadow-sm` : cartes au repos, en-tete.
  static List<BoxShadow> get sm => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];

  /// `shadow-md` : etat survole des cartes cliquables
  /// (`hover:shadow-md` des tuiles de `comptabilite-hub.html`).
  static List<BoxShadow> get md => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.1),
      blurRadius: 6,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  /// `shadow-xl` : modales.
  static List<BoxShadow> get xl => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.15),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  /// `shadow-2xl` : observe uniquement sur la carte de connexion (login.html).
  static List<BoxShadow> get xxl => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.25),
      blurRadius: 50,
      offset: const Offset(0, 25),
    ),
  ];
}
