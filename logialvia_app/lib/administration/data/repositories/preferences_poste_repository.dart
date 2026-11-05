import '../../../core/database/app_database.dart';

/// Accès aux préférences locales du poste — voir `PreferencesPoste`.
///
/// Volontairement une poignée d'accesseurs typés plutôt qu'un `get(String)`
/// générique : chaque clé a un sens, une valeur par défaut et une justification
/// qui méritent d'être écrites une fois pour toutes, pas répétées à chaque
/// appel.
class PreferencesPosteRepository {
  const PreferencesPosteRepository(this._db);

  final AppDatabase _db;

  static const String _cleIdentifiantMemorise = 'identifiant_memorise';
  static const String _cleBarreLateraleRepliee = 'barre_laterale_repliee';

  Future<String?> _lire(String cle) async {
    final ligne = await (_db.select(
      _db.preferencesPoste,
    )..where((p) => p.cle.equals(cle))).getSingleOrNull();
    return ligne?.valeur;
  }

  Future<void> _ecrire(String cle, String? valeur) async {
    if (valeur == null) {
      await (_db.delete(
        _db.preferencesPoste,
      )..where((p) => p.cle.equals(cle))).go();
      return;
    }
    await _db
        .into(_db.preferencesPoste)
        .insertOnConflictUpdate(
          PreferencesPosteCompanion.insert(cle: cle, valeur: valeur),
        );
  }

  /// Identifiant de la dernière connexion, quand « Se souvenir de moi » était
  /// coché. `null` sinon.
  ///
  /// ## ⚠️ On mémorise l'identifiant, jamais la session
  ///
  /// « Se souvenir de moi » ne rouvre **pas** la session : le mot de passe
  /// reste exigé à chaque lancement. La case pré-remplit le champ
  /// identifiant, ce que son libellé promet — *se souvenir de moi*, pas
  /// *reste connectée*.
  ///
  /// Le choix n'est pas de la prudence de principe. LogiALVIA tourne sur **un
  /// poste partagé** entre trois rôles (Gérante, Agent de Vente, Agent
  /// d'Élevage), dont un point de vente qui manipule des espèces. Une session
  /// rouverte automatiquement donnerait à quiconque ouvre l'ordinateur les
  /// droits du dernier connecté, et viderait de leur sens le verrouillage
  /// après 5 tentatives, la journalisation `AUDIT_LOGS` et le RBAC entier.
  ///
  /// Le gain réel — ne pas retaper son identifiant chaque matin — est conservé
  /// sans rien céder de tout cela.
  Future<String?> identifiantMemorise() => _lire(_cleIdentifiantMemorise);

  /// Mémorise l'identifiant, ou l'efface si [identifiant] est `null`.
  Future<void> memoriserIdentifiant(String? identifiant) {
    final propre = identifiant?.trim();
    return _ecrire(
      _cleIdentifiantMemorise,
      (propre == null || propre.isEmpty) ? null : propre,
    );
  }

  /// État de la barre latérale — `localStorage.logialvia_sidebar_hidden`
  /// (`common.js` l.25 et `applyStoredSidebarState()` l.27-42).
  ///
  /// Le prototype la restaure au chargement de chaque page. Côté Flutter elle
  /// repartait dépliée à chaque lancement, ce qui annulait le réglage sur les
  /// petits écrans où la Gérante la replie justement pour gagner de la place.
  Future<bool> barreLateraleRepliee() async =>
      await _lire(_cleBarreLateraleRepliee) == '1';

  Future<void> definirBarreLateraleRepliee({required bool repliee}) =>
      _ecrire(_cleBarreLateraleRepliee, repliee ? '1' : '0');
}
