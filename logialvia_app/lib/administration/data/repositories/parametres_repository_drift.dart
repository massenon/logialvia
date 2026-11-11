import '../../domain/services/service_archivage.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../sync/depot_demandes_referentiel.dart';
import '../../domain/entities/parametres_entreprise.dart';
import '../../domain/entities/role_utilisateur.dart';
import '../../domain/entities/utilisateur.dart';
import '../../domain/repositories/parametres_repository.dart';
import '../../domain/services/hachage_mot_de_passe.dart';

class ParametresRepositoryDrift implements ParametresRepository {
  const ParametresRepositoryDrift(this._db);

  final AppDatabase _db;

  /// Identifiant de l'unique ligne de paramètres.
  static const int _idUnique = 1;

  @override
  Future<ParametresEntrepriseModele> charger() async {
    final ligne = await (_db.select(
      _db.parametresEntreprise,
    )..where((p) => p.id.equals(_idUnique))).getSingleOrNull();

    if (ligne == null) {
      // Valeurs par defaut de `parametres-generaux.html` (F8 Onglet 2).
      return const ParametresEntrepriseModele(
        raisonSociale: 'ALLMANY ET COMPAGNIE',
        nomPromoteur: 'SIDI ALI Raïmatou',
        adresseSiege: 'Natitingou, Bénin',
        telephone: '+229 97 00 00 00',
      );
    }

    return ParametresEntrepriseModele(
      raisonSociale: ligne.raisonSociale,
      nomPromoteur: ligne.nomPromoteur,
      adresseSiege: ligne.adresseSiege,
      telephone: ligne.telephone,
      email: ligne.email,
      ifu: ligne.ifu,
      rccm: ligne.rccm,
      mecefActif: ligne.mecefActif,
      mecefUrl: ligne.mecefUrl,
      mecefNim: ligne.mecefNim,
      smtpServeur: ligne.smtpServeur,
      smtpPort: ligne.smtpPort,
      smtpSecurite: ligne.smtpSecurite,
      delaiPaiementJours: ligne.delaiPaiementJours,
      modeDonneesTest: ligne.modeDonneesTest,
      cheminLogo: ligne.cheminLogo,
      cheminFavicon: ligne.cheminFavicon,
    );
  }

  @override
  Future<void> enregistrer(ParametresEntrepriseModele parametres) async {
    // Table a ligne unique : le conflit porte sur la cle primaire `id`, qui
    // vaut toujours 1 — ici `insertOnConflictUpdate` est donc correct, a la
    // difference du cas `FICHE_JOURNEE` (Doc K3 §6-TER).
    await _db
        .into(_db.parametresEntreprise)
        .insertOnConflictUpdate(
          ParametresEntrepriseCompanion.insert(
            id: const Value(_idUnique),
            raisonSociale: Value(parametres.raisonSociale),
            nomPromoteur: Value(parametres.nomPromoteur),
            adresseSiege: Value(parametres.adresseSiege),
            telephone: Value(parametres.telephone),
            email: Value(parametres.email),
            ifu: Value(parametres.ifu),
            rccm: Value(parametres.rccm),
            // BR-ADM-004 applique a la persistance, pas seulement a l'UI :
            // MeCeF ne peut pas rester actif si l'IFU ou le RCCM disparait.
            mecefUrl: Value(parametres.mecefUrl),
            mecefNim: Value(parametres.mecefNim),
            mecefActif: Value(
              parametres.mecefActif && parametres.mecefActivable,
            ),
            smtpServeur: Value(parametres.smtpServeur),
            smtpPort: Value(parametres.smtpPort),
            smtpSecurite: Value(parametres.smtpSecurite),
            delaiPaiementJours: Value(parametres.delaiPaiementJours),
            modeDonneesTest: Value(parametres.modeDonneesTest),
            cheminLogo: Value(parametres.cheminLogo),
            cheminFavicon: Value(parametres.cheminFavicon),
          ),
        );
    // Les parametres appartiennent au serveur : le poste les PROPOSE (`46_` §4.3).
    await DepotDemandesReferentiel(_db).proposerParametres();
  }

  @override
  Future<List<UtilisateurAvecRole>> chargerUtilisateurs() async {
    final utilisateurs = _db.utilisateurs;
    final roles = _db.roles;

    final requete = _db.select(utilisateurs).join([
      innerJoin(roles, roles.id.equalsExp(utilisateurs.roleId)),
    ])..orderBy([OrderingTerm.asc(utilisateurs.nom)]);

    return [
      for (final ligne in await requete.get())
        () {
          final u = ligne.readTable(utilisateurs);
          final r = ligne.readTable(roles);
          return UtilisateurAvecRole(
            utilisateur: Utilisateur(
              id: u.id,
              nom: u.nom,
              identifiant: u.identifiant,
              roleId: u.roleId,
            ),
            role: RoleUtilisateur(id: r.id, libelle: r.libelle),
          );
        }(),
    ];
  }

  @override
  Future<bool> identifiantExiste(String identifiant) async {
    final ligne = await (_db.select(
      _db.utilisateurs,
    )..where((u) => u.identifiant.equals(identifiant))).getSingleOrNull();
    return ligne != null;
  }

  @override
  Future<Utilisateur> creerUtilisateur({
    required String nom,
    required String identifiant,
    required String roleId,
    required String motDePasse,
  }) async {
    final sel = HachageMotDePasse.genererSel();
    final id = await _db
        .into(_db.utilisateurs)
        .insert(
          UtilisateursCompanion.insert(
            nom: nom,
            identifiant: identifiant,
            roleId: roleId,
            motDePasseHash: HachageMotDePasse.hacher(motDePasse, sel),
            sel: sel,
          ),
        );

    return Utilisateur(
      id: id,
      nom: nom,
      identifiant: identifiant,
      roleId: roleId,
    );
  }

  @override
  Future<void> supprimerUtilisateur(
    int utilisateurId, {
    String? auteurId,
    String? auteurNom,
  }) async {
    final ligne = await (_db.select(
      _db.utilisateurs,
    )..where((u) => u.id.equals(utilisateurId))).getSingleOrNull();

    await ServiceArchivage(_db).archiver(
      type: TypeArchivable.utilisateurs,
      cle: utilisateurId,
      designation: ligne == null
          ? 'Utilisateur #$utilisateurId'
          : '${ligne.nom} (${ligne.identifiant})',
      utilisateurId: auteurId,
      utilisateurNom: auteurNom,
    );
  }
}
