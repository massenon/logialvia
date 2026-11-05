import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/router/navigation_model.dart';
import 'package:logialvia_app/core/router/permission_service.dart';

/// La matrice des droits, et l'invariant qui la relie au menu.
///
/// ## L'invariant
///
/// Une entrée de barre latérale visible pour un rôle **doit** être autorisée
/// pour ce rôle. Sinon le menu mène à un refus : l'utilisateur voit une porte,
/// la pousse, et se fait renvoyer. C'est exactement la « fonctionnalité
/// décorative » que le projet interdit, sous une autre forme.
///
/// Ce test le vérifie sur **toute** la barre latérale : ajouter une entrée sans
/// ouvrir la route correspondante casse ici, pas chez la Gérante.
void main() {
  group('Menu et droits ne peuvent pas diverger', () {
    test('toute entrée visible pour un rôle lui est autorisée', () {
      for (final groupe in NavigationModel.groupes) {
        for (final role in groupe.roles) {
          for (final entree in groupe.entrees) {
            expect(
              PermissionService.estAutorise(role, entree.route),
              isTrue,
              reason:
                  'Le groupe « ${groupe.titre} » montre '
                  '« ${entree.libelle} » au rôle « $role », mais la route '
                  '${entree.route} lui est refusée : le menu mènerait à un mur.',
            );
          }
        }
      }
    });
  });

  group('Décisions de la Gérante, verrouillées', () {
    test('l\'Inventaire reste visible pour l\'Agent de Vente', () {
      // ✓ Arbitre : l'ecran expose les couts de revient et la valorisation
      // totale du stock. La question a ete posee parce qu'elle releve de la
      // gestion, pas de la technique — et la reponse est de les montrer aussi
      // au point de vente.
      //
      // Ce test existe pour qu'une relecture « securitaire » ne defasse pas la
      // decision en croyant corriger un oubli.
      expect(PermissionService.estAutorise('caissier', '/inventaire'), isTrue);
      expect(PermissionService.estAutorise('admin', '/inventaire'), isTrue);
    });

    test('l\'Animalier n\'a pas accès aux écrans commerciaux', () {
      for (final route in const ['/ventes', '/clients', '/inventaire']) {
        expect(
          PermissionService.estAutorise('animalier', route),
          isFalse,
          reason: 'L\'Agent d\'Élevage ne touche pas au commercial.',
        );
      }
    });

    test('l\'Agent de Vente n\'a pas accès aux écrans d\'élevage', () {
      for (final route in const [
        '/elevage/couveuse',
        '/elevage/mirages',
        '/elevage/goliaths',
      ]) {
        expect(PermissionService.estAutorise('caissier', route), isFalse);
      }
    });

    test('un rôle inconnu n\'a droit à rien', () {
      // Refus par defaut : une faute de frappe dans un role ne doit pas ouvrir
      // l'application, elle doit la fermer.
      expect(PermissionService.estAutorise('inconnu', '/dashboard'), isFalse);
    });
  });
}
