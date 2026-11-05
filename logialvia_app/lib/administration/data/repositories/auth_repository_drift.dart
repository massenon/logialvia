import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../domain/entities/role_utilisateur.dart';
import '../../domain/entities/secret_utilisateur.dart';
import '../../domain/entities/utilisateur.dart';
import '../../domain/repositories/auth_repository.dart';

/// Implementation Drift de [AuthRepository] — Doc C1 §6.
///
/// Uniquement l'API typee de Drift : aucune requete construite par
/// concatenation de chaine (Doc I3 §1, Strict Avoid §1).
class AuthRepositoryDrift implements AuthRepository {
  const AuthRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Future<Utilisateur?> trouverParIdentifiant(String identifiant) async {
    final ligne = await (_db.select(
      _db.utilisateurs,
    )..where((u) => u.identifiant.equals(identifiant))).getSingleOrNull();
    if (ligne == null) return null;
    return Utilisateur(
      id: ligne.id,
      nom: ligne.nom,
      identifiant: ligne.identifiant,
      roleId: ligne.roleId,
    );
  }

  @override
  Future<SecretUtilisateur?> chargerSecret(int utilisateurId) async {
    final ligne = await (_db.select(
      _db.utilisateurs,
    )..where((u) => u.id.equals(utilisateurId))).getSingleOrNull();
    if (ligne == null) return null;
    return SecretUtilisateur(
      utilisateurId: ligne.id,
      motDePasseHash: ligne.motDePasseHash,
      sel: ligne.sel,
    );
  }

  @override
  Future<RoleUtilisateur?> trouverRole(String roleId) async {
    final ligne = await (_db.select(
      _db.roles,
    )..where((r) => r.id.equals(roleId))).getSingleOrNull();
    if (ligne == null) return null;
    return RoleUtilisateur(id: ligne.id, libelle: ligne.libelle);
  }

  @override
  Future<void> journaliserEchecConnexion({
    required String identifiantTente,
    String? detail,
  }) async {
    await _db
        .into(_db.securityLogs)
        .insert(
          SecurityLogsCompanion.insert(
            horodatage: DateTime.now(),
            typeEvenement: 'echec_connexion',
            identifiantTente: Value(identifiantTente),
            detail: Value(detail),
          ),
        );
  }

  @override
  Future<void> journaliserConnexion(Utilisateur utilisateur) =>
      _journaliserEvenementSession(utilisateur, 'connexion');

  @override
  Future<void> journaliserDeconnexion(Utilisateur utilisateur) =>
      _journaliserEvenementSession(utilisateur, 'deconnexion');

  /// `AUDIT_LOGS.action` n'accepte que les 5 valeurs listees en Doc D1, dont
  /// `connexion` — la deconnexion, exigee par Doc I3 §6, est donc journalisee
  /// sous cette meme action et distinguee par le champ `details`.
  Future<void> _journaliserEvenementSession(
    Utilisateur utilisateur,
    String evenement,
  ) async {
    await _db
        .into(_db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            horodatage: DateTime.now(),
            utilisateurId: utilisateur.id.toString(),
            action: 'connexion',
            entiteConcernee: 'Session',
            entiteId: utilisateur.identifiant,
            details: Value('{"evenement":"$evenement"}'),
          ),
        );
  }
}
