import '../../domain/services/service_archivage.dart';
import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../domain/entities/parametres_entreprise.dart';
import '../../domain/entities/role_utilisateur.dart';
import '../../domain/entities/utilisateur.dart';
import '../../domain/repositories/parametres_repository.dart';

/// Paramètres Généraux — Doc F8, 4 onglets.
class ParametresGenerauxViewModel extends ChangeNotifier {
  ParametresGenerauxViewModel(this._repository);

  final ParametresRepository _repository;

  bool _chargement = true;
  bool get chargement => _chargement;

  ParametresEntrepriseModele _parametres = const ParametresEntrepriseModele(
    raisonSociale: 'ALLMANY ET COMPAGNIE',
  );
  ParametresEntrepriseModele get parametres => _parametres;

  List<UtilisateurAvecRole> _utilisateurs = const [];
  List<UtilisateurAvecRole> get utilisateurs => _utilisateurs;

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    _parametres = await _repository.charger();
    _utilisateurs = await _repository.chargerUtilisateurs();
    _chargement = false;
    notifyListeners();
  }

  /// Modifie l'état local sans persister — l'enregistrement se fait au bouton
  /// « Enregistrer les Modifications » (F8 Onglet 2).
  void mettreAJour(ParametresEntrepriseModele nouveau) {
    _parametres = nouveau;
    notifyListeners();
  }

  Future<Resultat<void>> enregistrerParametres() async {
    // Champs requis de l'onglet 2 (F8).
    if (_parametres.raisonSociale.trim().isEmpty) {
      return const Echec('La raison sociale est obligatoire.');
    }
    final ifu = _parametres.ifu?.trim() ?? '';
    if (ifu.isEmpty) {
      return const Echec('L\'Identifiant Fiscal Unique (IFU) est obligatoire.');
    }
    // F8 Onglet 2 : « chiffres uniquement ».
    if (!RegExp(r'^\d+$').hasMatch(ifu)) {
      return const Echec('L\'IFU ne doit contenir que des chiffres.');
    }
    final email = _parametres.email?.trim() ?? '';
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return const Echec('Le format de l\'adresse e-mail est invalide.');
    }

    try {
      await _repository.enregistrer(_parametres);
      _parametres = await _repository.charger();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec enregistrement parametres: $e');
      return const Echec('Impossible d\'enregistrer les paramètres.');
    }
  }

  /// BR-ADM-004 — la bascule MeCeF est refusée tant que IFU et RCCM manquent.
  Resultat<void> basculerMecef({required bool actif}) {
    if (actif && !_parametres.mecefActivable) {
      return const Echec(
        'Renseignez l\'IFU et le RCCM avant d\'activer le module MeCeF.',
      );
    }
    _parametres = _parametres.copyWith(mecefActif: actif);
    notifyListeners();
    return const Succes(null);
  }

  /// Rôles attribuables depuis cet écran : `admin` en est volontairement exclu
  /// (Doc F8 Onglet 3 — il n'est attribué que par le seeder initial).
  static const List<RoleUtilisateur> rolesAttribuables = [
    RoleUtilisateur(id: RoleUtilisateur.idCaissier, libelle: 'Agent de Vente'),
    RoleUtilisateur(
      id: RoleUtilisateur.idAnimalier,
      libelle: 'Agent d\'Élevage',
    ),
  ];

  Future<Resultat<Utilisateur>> creerUtilisateur({
    required String nom,
    required String identifiant,
    required String? roleId,
    required String motDePasse,
    required String confirmation,
  }) async {
    if (nom.trim().isEmpty) {
      return const Echec('Le nom complet est obligatoire.');
    }
    if (identifiant.trim().isEmpty) {
      return const Echec('L\'identifiant de connexion est obligatoire.');
    }
    if (roleId == null) return const Echec('Le rôle est obligatoire.');
    if (motDePasse.length < 8) {
      return const Echec(
        'Le mot de passe doit contenir au moins 8 caractères.',
      );
    }
    if (motDePasse != confirmation) {
      return const Echec('Les deux mots de passe ne correspondent pas.');
    }
    if (await _repository.identifiantExiste(identifiant.trim())) {
      return const Echec('Cet identifiant est déjà utilisé.');
    }

    try {
      final utilisateur = await _repository.creerUtilisateur(
        nom: nom.trim(),
        identifiant: identifiant.trim(),
        roleId: roleId,
        motDePasse: motDePasse,
      );
      await charger();
      return Succes(utilisateur);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec creation utilisateur: $e');
      return const Echec('Impossible de créer l\'utilisateur.');
    }
  }

  Future<Resultat<void>> supprimerUtilisateur(
    UtilisateurAvecRole cible, {
    AuteurArchivage? auteur,
  }) async {
    // Garde-fou absent du prototype : supprimer le dernier administrateur
    // rendrait l'application definitivement inadministrable.
    final administrateurs = _utilisateurs
        .where((u) => u.role.id == RoleUtilisateur.idAdmin)
        .length;
    if (cible.role.id == RoleUtilisateur.idAdmin && administrateurs <= 1) {
      return const Echec(
        'Impossible de supprimer le dernier compte administrateur.',
      );
    }

    try {
      await _repository.supprimerUtilisateur(
        cible.utilisateur.id,
        auteurId: auteur?.id,
        auteurNom: auteur?.nom,
      );
      await charger();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec suppression utilisateur: $e');
      return const Echec('Impossible de supprimer cet utilisateur.');
    }
  }
}
