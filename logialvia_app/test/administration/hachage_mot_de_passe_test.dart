import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/domain/services/hachage_mot_de_passe.dart';

void main() {
  group('HachageMotDePasse', () {
    test('le hash ne contient jamais le mot de passe en clair', () {
      const motDePasse = 'ALLMANY2026';
      final sel = HachageMotDePasse.genererSel();
      final hash = HachageMotDePasse.hacher(motDePasse, sel);

      expect(hash.contains(motDePasse), isFalse);
      expect(hash.length, 64); // SHA-256 en hexadecimal
    });

    test('deux comptes avec le meme mot de passe ont des hash differents', () {
      const motDePasse = 'ALLMANY2026';
      final hashA = HachageMotDePasse.hacher(
        motDePasse,
        HachageMotDePasse.genererSel(),
      );
      final hashB = HachageMotDePasse.hacher(
        motDePasse,
        HachageMotDePasse.genererSel(),
      );

      expect(hashA, isNot(equals(hashB)));
    });

    test('verifier accepte le bon mot de passe', () {
      const motDePasse = 'ALLMANY2026';
      final sel = HachageMotDePasse.genererSel();
      final hash = HachageMotDePasse.hacher(motDePasse, sel);

      expect(
        HachageMotDePasse.verifier(
          motDePasseSaisi: motDePasse,
          sel: sel,
          hashAttendu: hash,
        ),
        isTrue,
      );
    });

    test('verifier refuse un mot de passe errone', () {
      final sel = HachageMotDePasse.genererSel();
      final hash = HachageMotDePasse.hacher('ALLMANY2026', sel);

      expect(
        HachageMotDePasse.verifier(
          motDePasseSaisi: 'logialvia@2026', // casse differente
          sel: sel,
          hashAttendu: hash,
        ),
        isFalse,
      );
    });

    test('verifier refuse le bon mot de passe avec un mauvais sel', () {
      const motDePasse = 'ALLMANY2026';
      final hash = HachageMotDePasse.hacher(
        motDePasse,
        HachageMotDePasse.genererSel(),
      );

      expect(
        HachageMotDePasse.verifier(
          motDePasseSaisi: motDePasse,
          sel: HachageMotDePasse.genererSel(),
          hashAttendu: hash,
        ),
        isFalse,
      );
    });

    test('verifier refuse un hash de longueur incoherente', () {
      expect(
        HachageMotDePasse.verifier(
          motDePasseSaisi: 'x',
          sel: 'sel',
          hashAttendu: 'trop-court',
        ),
        isFalse,
      );
    });
  });
}
