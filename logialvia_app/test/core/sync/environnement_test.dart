import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/sync/environnement.dart';

void main() {
  test('production propose le serveur d\'ALLMANY en https', () {
    final env = Environnement.depuisCode('production');

    expect(env.code, 'production');
    expect(env.adresseProposee, 'https://logialvia.digitonpro.com');
  });

  test('recette, dev, inconnu et vide ne proposent aucune adresse', () {
    for (final code in ['recette', 'dev', 'n-importe-quoi', '', null]) {
      expect(
        Environnement.depuisCode(code).adresseProposee,
        isNull,
        reason: '$code',
      );
    }
    expect(Environnement.depuisCode('inconnu').code, 'dev');
  });

  test('sans --dart-define (tests, flutter run) : dev', () {
    expect(Environnement.courant.code, 'dev');
  });
}
