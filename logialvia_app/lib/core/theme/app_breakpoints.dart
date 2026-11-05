import 'package:flutter/widgets.dart';

/// Breakpoints Tailwind — Doc E8 §2.
///
/// **Toujours comparer la largeur de la FENETRE** (`MediaQuery`), jamais celle
/// du conteneur (`constraints.maxWidth`) : un breakpoint Tailwind est une
/// *media query*, il ne depend pas de l'element qui porte la classe.
///
/// L'erreur a ete commise puis corrigee sur le bandeau KPI du tableau de bord :
/// mesurer le conteneur donnait ~1100 px sur une fenetre de 1440 (288 px de
/// barre laterale + marges), donc 2 colonnes au lieu des 4 du web.
///
/// Les contraintes du `LayoutBuilder` restent utiles pour **dimensionner** les
/// elements une fois le nombre de colonnes decide — pas pour le decider.
///
/// Regle Doc E8 §2 : ne jamais reecrire 768/1024/1280 en dur dans un ecran.
class AppBreakpoints {
  AppBreakpoints._();

  static const double sm = 640;
  static const double md = 768;
  static const double lg = 1024;
  static const double xl = 1280;

  static bool estSm(BuildContext context) => _largeur(context) >= sm;
  static bool estMd(BuildContext context) => _largeur(context) >= md;
  static bool estLg(BuildContext context) => _largeur(context) >= lg;
  static bool estXl(BuildContext context) => _largeur(context) >= xl;

  static double _largeur(BuildContext context) =>
      MediaQuery.sizeOf(context).width;
}
