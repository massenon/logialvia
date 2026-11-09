import '../../../core/database/app_database.dart';
import '../../../core/sync/adresse_serveur.dart';
import '../../../core/sync/identifiant_poste.dart';

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
  static const String _cleIdentifiantPoste = 'poste.identifiant';
  static const String _cleAdresseServeur = 'sync.adresse_serveur';
  static const String _cleCodePoste = 'sync.code_poste';
  static const String _cleCodeAttribue = 'poste.code_attribue';
  static const String _cleCompteAppaire = 'sync.compte';
  static const String _cleAppaireLe = 'sync.appaire_le';
  static const String _cleCurseurTirage = 'sync.curseur';
  static const String _cleMarqueRemiseAZero = 'sync.marque_remise_a_zero';

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

  // ------------------------------------------------------------------ Poste

  /// Identifiant de CE poste : un UUID tiré **une seule fois**, jamais
  /// régénéré (`46_` §1, blueprint §2). Il nomme le jeton côté serveur ; une
  /// constante partagée rendrait deux postes indiscernables.
  ///
  /// ⚠️ Copier la base sur un autre ordinateur (restauration d'une sauvegarde)
  /// copie aussi cet identifiant : deux machines se feraient passer pour un
  /// seul poste. Une restauration sur une AUTRE machine doit être suivie d'un
  /// nouvel appairage (TODO(dette): proposer de régénérer l'identifiant).
  Future<String> identifiantPoste() async {
    final existant = await _lire(_cleIdentifiantPoste);
    if (existant != null && existant.isNotEmpty) return existant;
    final nouveau = genererUuidV4();
    await _ecrire(_cleIdentifiantPoste, nouveau);
    return nouveau;
  }

  /// Adresse du serveur, déjà normalisée. `null` tant qu'elle n'est pas saisie.
  Future<String?> adresseServeur() => _lire(_cleAdresseServeur);

  /// Enregistre l'adresse normalisée ; renvoie `null` si elle est invalide
  /// (rien n'est alors écrit).
  Future<String?> definirAdresseServeur(String saisie) async {
    final propre = normaliserAdresseServeur(saisie);
    if (propre == null) return null;
    await _ecrire(_cleAdresseServeur, propre);
    return propre;
  }

  /// Code attribué par le serveur à l'appairage (`P1`, `P2`… : DV-21).
  Future<String?> codePoste() => _lire(_cleCodePoste);

  /// Code attribué une fois pour toutes par le serveur (`P1`, `P2`…), conservé
  /// même après une déconnexion. `null` : poste jamais appairé (références au
  /// format sans code, `V-AAAA-NNN`).
  Future<String?> codeAttribue() => _lire(_cleCodeAttribue);

  /// Compte WEB utilisé pour l'appairage — jamais son mot de passe.
  Future<String?> compteAppaire() => _lire(_cleCompteAppaire);

  Future<DateTime?> appaireLe() async {
    final v = await _lire(_cleAppaireLe);
    return v == null ? null : DateTime.tryParse(v);
  }

  Future<void> memoriserAppairage({
    required String codePoste,
    required String compte,
    required DateTime le,
  }) async {
    await _ecrire(_cleCodePoste, codePoste);
    // Le code est STABLE (DV-21) : il survit a la deconnexion. Un poste qui se
    // deconnecte ne repasse pas au format sans code, ses refs resteraient sinon
    // melangees avec celles d'avant l'appairage.
    await _ecrire(_cleCodeAttribue, codePoste);
    await _ecrire(_cleCompteAppaire, compte);
    await _ecrire(_cleAppaireLe, le.toIso8601String());
  }

  /// Oublie l'appairage (le code reste attribué côté serveur ; l'identifiant
  /// du poste et l'adresse sont conservés pour se reconnecter).
  Future<void> oublierAppairage() async {
    await _ecrire(_cleCodePoste, null);
    await _ecrire(_cleCompteAppaire, null);
    await _ecrire(_cleAppaireLe, null);
  }

  // ---------------------------------------------------------- Synchronisation

  /// `server_time` de la **dernière page** du dernier tirage complet — rendu par
  /// le SERVEUR, jamais l'horloge du poste (trop lente : on re-reçoit tout ;
  /// trop rapide : on saute des lignes). `null` : le prochain tirage est complet.
  Future<String?> curseurTirage() => _lire(_cleCurseurTirage);

  Future<void> definirCurseurTirage(String? curseur) =>
      _ecrire(_cleCurseurTirage, curseur);

  /// Marque de remise à zéro connue du poste (`46_` §4.2). `null` jusqu'au
  /// premier tirage ; un envoi la porte, le serveur refuse (409) toute marque
  /// qu'il ne reconnaît pas.
  Future<String?> marqueRemiseAZero() => _lire(_cleMarqueRemiseAZero);

  Future<void> definirMarqueRemiseAZero(String marque) =>
      _ecrire(_cleMarqueRemiseAZero, marque);
}
