import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Une entree de navigation de la barre laterale.
class EntreeNavigation {
  const EntreeNavigation({
    required this.libelle,
    required this.icone,
    required this.route,
    this.moduleId,
  });

  final String libelle;
  final IconData icone;
  final String route;

  /// Identifiant `data-module` du prototype. Si renseigne, l'entree n'est
  /// visible que lorsque le module correspondant est actif (Doc I2 §3).
  final String? moduleId;
}

/// Un groupe de navigation, avec son en-tete et les roles qui y ont acces.
class GroupeNavigation {
  const GroupeNavigation({
    required this.titre,
    required this.roles,
    required this.entrees,
  });

  final String titre;

  /// Traduction directe de l'attribut `data-role-group="..."` de `sidebar.js`.
  final Set<String> roles;

  final List<EntreeNavigation> entrees;
}

/// Arborescence de la barre laterale — transcription **fidele et ordonnee** de
/// `prototype_html/assets/js/sidebar.js`.
///
/// Toute modification de `sidebar.js` doit etre repercutee ici ET dans
/// `PermissionService` (Doc I1 §4) — ce sont les deux faces d'une meme regle.
///
/// ECART_DELIBERE sur 3 routes de Comptabilite : `sidebar.js` pointe vers
/// `grand-livre.html`, `balance-generale.html` et `etats-financiers.html`,
/// alors que l'arborescence de Doc E3 §2 nommait `/comptabilite/journal`,
/// `/plan`, `/analytique`, `/cloture`, `/bilan`. Les routes ci-dessous suivent
/// la barre laterale reelle ; les ecrans de Doc E3 absents du menu restent
/// atteignables par navigation contextuelle, comme cote web.
class NavigationModel {
  NavigationModel._();

  static const List<GroupeNavigation> groupes = [
    GroupeNavigation(
      titre: 'PILOTAGE',
      roles: {'admin', 'animalier', 'caissier'},
      entrees: [
        EntreeNavigation(
          libelle: 'Tableau de Bord',
          icone: Symbols.dashboard,
          route: '/dashboard',
        ),
      ],
    ),
    GroupeNavigation(
      titre: 'ÉLEVAGE & COUVEUSE',
      roles: {'admin', 'animalier'},
      entrees: [
        EntreeNavigation(
          libelle: 'Cycle Couveuse',
          icone: Symbols.egg,
          route: '/elevage/couveuse',
        ),
        // AJOUT hors prototype — les mirages etaient saisis sans que personne
        // ne puisse les lire ensemble. Voir `StatistiquesMirages`.
        EntreeNavigation(
          libelle: 'Statistiques Mirages',
          icone: Symbols.visibility,
          route: '/elevage/mirages',
        ),
        EntreeNavigation(
          libelle: 'Fiche Goliaths',
          icone: Symbols.pets,
          route: '/elevage/goliaths',
        ),
        EntreeNavigation(
          libelle: 'Fiche Pintades',
          icone: Symbols.pets,
          route: '/elevage/pintades',
        ),
        EntreeNavigation(
          libelle: 'Fiche Poissons-Chats',
          icone: Symbols.set_meal,
          route: '/elevage/poissons-chats',
          moduleId: 'pisciculture',
        ),
        EntreeNavigation(
          libelle: 'Fiche Lapins',
          icone: Symbols.cruelty_free,
          route: '/elevage/lapins',
          moduleId: 'cuniculture',
        ),
        EntreeNavigation(
          libelle: 'Fiche Escargots',
          icone: Symbols.eco,
          route: '/elevage/escargots',
          moduleId: 'heliciculture',
        ),
        EntreeNavigation(
          libelle: 'Fiche Bovins',
          icone: Symbols.grass,
          route: '/elevage/bovins',
          moduleId: 'bovins',
        ),
        EntreeNavigation(
          libelle: 'Fiche Poulets/Pondeuses',
          icone: Symbols.egg_alt,
          route: '/elevage/poulets-pondeuses',
          moduleId: 'aviculture_classique',
        ),
        EntreeNavigation(
          libelle: 'Dashboard Élevage',
          icone: Symbols.monitoring,
          route: '/elevage/dashboard',
        ),
        EntreeNavigation(
          libelle: 'Paramètres Élevage',
          icone: Symbols.tune,
          route: '/parametres/elevage',
        ),
        EntreeNavigation(
          libelle: 'Soins & Calendrier',
          icone: Symbols.vaccines,
          route: '/elevage/soins',
        ),
      ],
    ),
    GroupeNavigation(
      titre: 'VENTES & CLIENTS',
      roles: {'admin', 'caissier'},
      entrees: [
        EntreeNavigation(
          libelle: 'Ventes',
          icone: Symbols.point_of_sale,
          route: '/ventes',
        ),
        EntreeNavigation(
          libelle: 'Clients et Créances',
          icone: Symbols.payments,
          route: '/clients',
        ),
        // AJOUT hors prototype — l'inventaire date et valorise n'existe dans
        // aucune page HTML. Il est range ici a la demande de la Gerante : il
        // se consulte au moment de faire les comptes, avec les ventes.
        EntreeNavigation(
          libelle: 'Inventaire',
          icone: Symbols.inventory,
          route: '/inventaire',
        ),
        // Conformite fiscale. `moduleId` la rend invisible tant que le module
        // MeCeF n'est pas actif : une entree de menu qui mene a un ecran sans
        // objet vaut moins que pas d'entree du tout.
        EntreeNavigation(
          libelle: 'Facturation MeCeF',
          icone: Symbols.receipt_long,
          route: '/factures-mecef',
          moduleId: 'mecef',
        ),
      ],
    ),
    GroupeNavigation(
      titre: 'ACHATS & FOURNISSEURS',
      roles: {'admin'},
      entrees: [
        EntreeNavigation(
          libelle: 'Achats & Commandes',
          icone: Symbols.local_shipping,
          route: '/achats',
        ),
        EntreeNavigation(
          libelle: 'Fournisseurs',
          icone: Symbols.contact_page,
          route: '/fournisseurs',
        ),
        EntreeNavigation(
          libelle: 'Saisie Dépenses',
          icone: Symbols.receipt,
          route: '/depenses',
        ),
      ],
    ),
    GroupeNavigation(
      titre: 'STOCKS & CATALOGUE',
      roles: {'admin'},
      entrees: [
        EntreeNavigation(
          libelle: 'Gestion Stocks',
          icone: Symbols.inventory_2,
          route: '/stocks',
        ),
        EntreeNavigation(
          libelle: 'Catalogue & Seuils',
          icone: Symbols.category,
          route: '/catalogue',
        ),
      ],
    ),
    GroupeNavigation(
      titre: 'COMPTABILITÉ',
      roles: {'admin'},
      entrees: [
        EntreeNavigation(
          libelle: 'Comptabilité',
          icone: Symbols.account_balance,
          route: '/comptabilite',
        ),
        EntreeNavigation(
          libelle: 'Grand Livre',
          icone: Symbols.import_contacts,
          route: '/comptabilite/grand-livre',
        ),
        EntreeNavigation(
          libelle: 'Balance Générale',
          icone: Symbols.balance,
          route: '/comptabilite/balance',
        ),
        EntreeNavigation(
          libelle: 'États Financiers',
          icone: Symbols.description,
          route: '/comptabilite/etats-financiers',
        ),
        // Demande de la Gerante apres la recette K2. `comptabilite-hub.html`
        // l.140 portait pourtant un « CORRECTIF : remplace bilan-entreprise
        // .html — page unifiee des 4 etats » : le prototype avait supprime cet
        // ecran. La suppression etait une erreur — les Etats Financiers
        // s'adressent au comptable, ce bilan-ci a la Gerante. Voir
        // `BilanEntrepriseCalculator`.
        EntreeNavigation(
          libelle: 'Bilan de l\'Entreprise',
          icone: Symbols.account_balance_wallet,
          route: '/comptabilite/bilan',
        ),
      ],
    ),
    GroupeNavigation(
      titre: 'PARAMÈTRES',
      roles: {'admin'},
      entrees: [
        EntreeNavigation(
          libelle: 'Paramètres Général',
          icone: Symbols.settings,
          route: '/parametres/generaux',
        ),
      ],
    ),
    GroupeNavigation(
      titre: 'ÉDITIONS',
      roles: {'admin'},
      entrees: [
        EntreeNavigation(
          libelle: 'Rapports & États',
          icone: Symbols.picture_as_pdf,
          route: '/rapports',
        ),
      ],
    ),
  ];

  // ⚠️ Les quatre raccourcis de `dashboard.html` l.320-334 n'ont PAS
  // d'equivalent ici, et c'est délibéré : cote web ils forment une barre
  // BASSE, qui n'apparait qu'en dessous de 1024 px. Sur une application
  // de bureau, elle ne s'afficherait jamais.
  //
  // Les transposer ailleurs — en tete de la barre laterale, par exemple —
  // reviendrait a inventer une rubrique que le prototype ne demande pas.
  // Cela a ete tente, puis retire a la demande de la Gerante.

  /// Fil d'Ariane affiche dans la barre du haut : groupe parent puis libelle.
  /// Retourne une liste vide si la route n'appartient a aucun groupe.
  static List<String> filDAriane(String route) {
    for (final groupe in groupes) {
      for (final entree in groupe.entrees) {
        if (entree.route == route) {
          // Le prototype n'affiche pas le groupe pour le Tableau de Bord
          // (dashboard.html l.29 : un seul segment).
          return groupe.entrees.length == 1
              ? [entree.libelle]
              : [_titreLisible(groupe.titre), entree.libelle];
        }
      }
    }
    return const [];
  }

  /// "ÉLEVAGE & COUVEUSE" -> "Élevage & Couveuse", forme utilisee dans le fil
  /// d'Ariane (elevage-dashboard.html l.26).
  static String _titreLisible(String titre) {
    return titre
        .split(' ')
        .map(
          (mot) => mot.length <= 1
              ? mot
              : mot[0] + mot.substring(1).toLowerCase(),
        )
        .join(' ');
  }
}
