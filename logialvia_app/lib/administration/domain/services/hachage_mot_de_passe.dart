import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Hachage des mots de passe — Doc F1 "Point Ouvert", mecanisme confirme :
/// SHA-256 avec un sel aleatoire propre a chaque compte.
///
/// Le mot de passe en clair n'est jamais persiste ni journalise, nulle part
/// (Strict Avoid §1, Doc I3 §3).
class HachageMotDePasse {
  HachageMotDePasse._();

  static const int _longueurSelOctets = 16;

  /// Genere un sel cryptographiquement sur, encode en base64.
  static String genererSel() {
    final aleatoire = Random.secure();
    final octets = List<int>.generate(
      _longueurSelOctets,
      (_) => aleatoire.nextInt(256),
    );
    return base64Encode(octets);
  }

  /// SHA-256 hexadecimal de la concatenation `sel + motDePasse`.
  static String hacher(String motDePasse, String sel) {
    return sha256.convert(utf8.encode('$sel$motDePasse')).toString();
  }

  /// Compare en temps constant : une comparaison `==` classique s'arrete au
  /// premier caractere different et fuiterait de l'information par son temps
  /// d'execution.
  static bool verifier({
    required String motDePasseSaisi,
    required String sel,
    required String hashAttendu,
  }) {
    final hashCalcule = hacher(motDePasseSaisi, sel);
    if (hashCalcule.length != hashAttendu.length) return false;

    var difference = 0;
    for (var i = 0; i < hashCalcule.length; i++) {
      difference |= hashCalcule.codeUnitAt(i) ^ hashAttendu.codeUnitAt(i);
    }
    return difference == 0;
  }
}
