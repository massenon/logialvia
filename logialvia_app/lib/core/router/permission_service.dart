/// Matrice des droits d'acces (RBAC) — Doc I1 §4.
///
/// Ce dictionnaire est la traduction fidele des attributs `data-role-group="..."`
/// de `assets/js/sidebar.js`. Toute modification de la navigation web doit etre
/// repercutee ici — source unique de verite des permissions (Strict Avoid §12).
class PermissionService {
  PermissionService._();

  static const Map<String, Set<String>> _routesAutoriseesParRole = {
    'admin': {'*'}, // acces total
    'caissier': {
      '/dashboard',
      '/ventes',
      '/clients',
      // L'Inventaire est range dans « Ventes & Clients », groupe ouvert a
      // l'Agent de Vente : sans ce droit, l'entree s'afficherait dans sa barre
      // laterale et le renverrait sur un refus — un menu qui ne mene nulle
      // part.
      //
      // ✓ ARBITRE PAR LA GERANTE : l'ecran reste **visible pour les deux
      // roles**. Il expose les couts de revient et la valorisation totale du
      // stock ; la question a ete posee, la reponse est de les montrer aussi
      // au point de vente. Ce n'etait pas un choix technique, et il est
      // consigne ici pour qu'on ne le « corrige » pas par prudence plus tard.
      '/inventaire',
      // La facturation normalisee se fait au comptoir, la ou la vente a lieu.
      // L'avoir aussi : c'est l'Agent de Vente qui commet l'erreur de
      // facturation, et lui demander d'aller chercher l'administratrice pour
      // la corriger reviendrait a laisser vivre la facture fausse. Meme
      // arbitrage que pour l'annulation d'une vente, deja ouverte a ce role.
      '/factures-mecef',
      '/profil',
      '/aide',
      '/contact',
    },
    'animalier': {
      '/dashboard',
      '/elevage/dashboard',
      '/elevage/couveuse',
      '/elevage/mirages',
      '/elevage/goliaths',
      '/elevage/pintades',
      '/elevage/poissons-chats',
      '/elevage/lapins',
      '/elevage/escargots',
      '/elevage/bovins',
      '/elevage/poulets-pondeuses',
      '/elevage/soins',
      '/parametres/elevage',
      '/profil',
      '/aide',
      '/contact',
    },
  };

  static bool estAutorise(String role, String route) {
    final routes = _routesAutoriseesParRole[role];
    if (routes == null) return false;
    return routes.contains('*') || routes.contains(route);
  }
}
