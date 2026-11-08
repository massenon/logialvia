import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// Traduit un nom d'icone Material Symbols (tel qu'il apparait dans le HTML du
/// prototype et dans les donnees persistees) en `IconData`.
///
/// Les noms sont identiques cote web et cote Dart (Doc 01 §5, decision actee) :
/// cette table ne sert donc qu'a passer d'une **chaine** — inevitable quand
/// l'icone vient de la base, comme `PRODUITS_VENDABLES.icon` — a la constante
/// correspondante. Ce n'est pas une table de correspondance de noms.
class IconeSymbole {
  IconeSymbole._();

  static const Map<String, IconData> _table = {
    'account_balance': Symbols.account_balance,
    'account_balance_wallet': Symbols.account_balance_wallet,
    'agriculture': Symbols.agriculture,
    'backpack': Symbols.backpack,
    'bar_chart': Symbols.bar_chart,
    'cake': Symbols.cake,
    'category': Symbols.category,
    'checkroom': Symbols.checkroom,
    'child_care': Symbols.child_care,
    'coronavirus': Symbols.coronavirus,
    'cruelty_free': Symbols.cruelty_free,
    'eco': Symbols.eco,
    'egg': Symbols.egg,
    'egg_alt': Symbols.egg_alt,
    'event_repeat': Symbols.event_repeat,
    'footprint': Symbols.footprint,
    'inventory_2': Symbols.inventory_2,
    'lock': Symbols.lock,
    'medical_information': Symbols.medical_information,
    'monitoring': Symbols.monitoring,
    'pets': Symbols.pets,
    'point_of_sale': Symbols.point_of_sale,
    'query_stats': Symbols.query_stats,
    'receipt': Symbols.receipt,
    'receipt_long': Symbols.receipt_long,
    'request_quote': Symbols.request_quote,
    'savings': Symbols.savings,
    'school': Symbols.school,
    'set_meal': Symbols.set_meal,
    'shopping_cart': Symbols.shopping_cart,
    'trending_up': Symbols.trending_up,
    'vaccines': Symbols.vaccines,
    'verified': Symbols.verified,
    'warning': Symbols.warning,
  };

  /// Retourne `Symbols.help` si le nom est inconnu — un nom d'icone absent de
  /// cette table est un oubli a corriger, pas une raison de planter l'ecran.
  static IconData depuisNom(String nom) => _table[nom] ?? Symbols.help;
}

/// Couleurs d'accent semantique des KPI — Doc E7 §4.
class AccentCouleurs {
  AccentCouleurs._();

  static const Color navy = AppColors.brandNavy;
  static const Color info = AppColors.infoBlue;
  static const Color or = AppColors.brandGold;
  static const Color succes = AppColors.successDeep;
  static const Color erreur = AppColors.errorDeep;
}
