import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Le jeton Sanctum de ce poste — **hors de la base**.
///
/// La base se recopie à chaque sauvegarde et voyage sur une clé USB ; un jeton
/// qui y serait descendu donnerait à qui la trouve le droit de parler au serveur
/// en se faisant passer pour ce poste. Même règle que `DepotJetonMecef`.
abstract class DepotJetonSync {
  /// `null` si absent **ou illisible** : un magasin qui ne répond pas équivaut à
  /// un poste non appairé (on se reconnecte), jamais à un écran blanc.
  Future<String?> lire();

  /// Lève si le magasin refuse : un appairage dont le jeton n'a pas pu être
  /// gardé est un appairage raté, et doit être dit comme tel.
  Future<void> ecrire(String jeton);

  Future<void> effacer();
}

class DepotJetonSyncSecurise implements DepotJetonSync {
  const DepotJetonSyncSecurise([this._stockage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _stockage;

  static const String _cle = 'sync_jeton';

  @override
  Future<String?> lire() async {
    try {
      return await _stockage.read(key: _cle);
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> ecrire(String jeton) =>
      _stockage.write(key: _cle, value: jeton.trim());

  @override
  Future<void> effacer() async {
    try {
      await _stockage.delete(key: _cle);
    } on Exception {
      // Rien à effacer si le magasin ne répond pas.
    }
  }
}

/// Pour les tests : le magasin système n'existe pas hors d'une vraie fenêtre.
class DepotJetonSyncMemoire implements DepotJetonSync {
  DepotJetonSyncMemoire({this.refuseEcriture = false});

  String? _jeton;
  final bool refuseEcriture;

  @override
  Future<String?> lire() async => _jeton;

  @override
  Future<void> ecrire(String jeton) async {
    if (refuseEcriture) throw Exception('Magasin sécurisé indisponible.');
    _jeton = jeton;
  }

  @override
  Future<void> effacer() async => _jeton = null;
}
