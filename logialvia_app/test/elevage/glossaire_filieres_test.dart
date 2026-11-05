import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';

/// Glossaire des libellés de la saisie journalière.
///
/// Chaque HTML du prototype écrit **ses** libellés ; les coder en dur dans
/// l'écran appliquait le vocabulaire avicole à toutes les filières.
void main() {
  ConfigurationEspece config(String id) =>
      ConfigurationsEspeces.parIdentifiant[id]!;

  group('Le mode d\'arrivée des jeunes diffère par filière', () {
    test('les volailles naissent en couveuse', () {
      expect(config('goliaths').libelleNaissances, 'Nés (Couveuse)');
      expect(config('pintades').libelleNaissances, 'Nés (Couveuse)');
    });

    test('les lapins naissent d\'une mise bas', () {
      expect(config('lapins').libelleNaissances, 'Nés (Mise bas)');
    });

    test('les poissons-chats n\'ont pas de couveuse — ÉCART_DELIBERE', () {
      final poissons = config('poissons-chats');

      expect(poissons.libelleNaissances, 'Nés');
      expect(
        poissons.libelleNaissances.toLowerCase(),
        isNot(contains('couveuse')),
        reason:
            'C\'etait le defaut signale par la Gerante : l\'ecran codait '
            '« Nes (Couveuse) » pour les cinq fiches.',
      );
      expect(
        poissons.libelleNaissances.toLowerCase(),
        isNot(contains('alevin')),
        reason:
            '`fiche-poissons-chats.html` l.161 disait « Alevins '
            '(Naissance/Empoissonnement) ». « Alevin » est deja le nom de la '
            'premiere categorie, et l\'empoissonnement se saisit en Achats — '
            'le libelle du prototype melangeait les deux entrees que la ligne '
            'separe.',
      );
    });

    test('poulets et pondeuses reçoivent aussi des transferts', () {
      expect(config('poulets').libelleNaissances, 'Nés / Transferts');
      expect(config('pondeuses').libelleNaissances, 'Nés / Transferts');
    });

    test('seules les Pondeuses ont un libellé d\'achats particulier', () {
      expect(config('pondeuses').libelleAchats, 'Achats / Entrées');
      for (final id in const [
        'goliaths',
        'pintades',
        'lapins',
        'poissons-chats',
        'poulets',
      ]) {
        expect(config(id).libelleAchats, 'Achats', reason: id);
      }
    });
  });

  group('Aucune filière ne parle du vocabulaire d\'une autre', () {
    test('« couveuse » n\'apparaît que chez les volailles couvées', () {
      for (final entree in ConfigurationsEspeces.parIdentifiant.entries) {
        final mentionneCouveuse =
            entree.value.libelleNaissances.toLowerCase().contains('couveuse') ||
            entree.value.etapesCycle.any(
              (e) => e.toLowerCase().contains('couveuse'),
            );
        if (mentionneCouveuse) {
          expect(
            entree.key,
            anyOf('goliaths', 'pintades'),
            reason:
                '${entree.key} ne passe pas par une couveuse : ni les lapins, '
                'ni les poissons-chats, ni les poulets achetes poussins.',
          );
        }
      }
    });

    test('tous les libellés sont renseignés et non vides', () {
      for (final entree in ConfigurationsEspeces.parIdentifiant.entries) {
        expect(
          entree.value.libelleAchats.trim(),
          isNotEmpty,
          reason: entree.key,
        );
        expect(
          entree.value.libelleNaissances.trim(),
          isNotEmpty,
          reason: entree.key,
        );
      }
    });

    test('la première catégorie est bien celle qui reçoit ces entrées', () {
      // Le libelle de la colonne 2 doit designer les jeunes de la filiere :
      // c'est `indexCategorieJeune` qui les recoit.
      for (final entree in ConfigurationsEspeces.parIdentifiant.entries) {
        expect(
          entree.value.indexCategorieJeune,
          isNonNegative,
          reason:
              '${entree.key} : sans categorie « jeune », les achats et les '
              'naissances n\'auraient nulle part ou aller.',
        );
      }
    });
  });
}
