import 'package:flutter/material.dart';

/// Rayons de bordure — Doc 01 §4.
class AppRadius {
  AppRadius._();

  /// `rounded-lg` du prototype : cartes, modales, champs, boutons rectangulaires.
  static const double card = 8.0;

  /// `rounded-2xl`, observe uniquement sur la carte de connexion (login.html).
  static const double loginCard = 16.0;

  static BorderRadius get cardRadius => BorderRadius.circular(card);
  static BorderRadius get loginCardRadius => BorderRadius.circular(loginCard);

  /// `rounded-full` : badges de statut, boutons pilule.
  static BorderRadius get pill => BorderRadius.circular(9999);
}
