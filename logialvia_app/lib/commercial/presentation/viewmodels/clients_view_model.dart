import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../data/repositories/clients_repository_drift.dart';
import '../../domain/entities/client.dart';
import '../../domain/repositories/ventes_repository.dart';

/// Clients & Créances — Doc F4 Écran 3, fidèle à `relances-clients.html`.
class ClientsViewModel extends ChangeNotifier {
  ClientsViewModel(this._clients, this._ventes);

  final ClientsRepository _clients;
  final VentesRepository _ventes;

  /// Fenêtre des « Événements CRM » du KPI (7 jours).
  static const int fenetreCrmJours = 7;

  /// Seuil des « Soldes Anciens » du KPI (> 10 jours).
  static const int seuilAncienneteJours = 10;

  bool _chargement = true;
  bool get chargement => _chargement;

  List<Client> _liste = const [];
  List<Creance> _creances = const [];

  List<Client> get clients => _liste;
  List<Creance> get creances => _creances;

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    _liste = await _clients.chargerClients();
    _creances = await _clients.chargerCreances();
    _chargement = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 4 KPI
  // Libellés réels de `relances-clients.html` l.98-110 — ⚠️ 3 des 4 diffèrent
  // de ceux que listait Doc F4.

  /// « Clients Enregistrés »
  int get clientsEnregistres => _liste.length;

  /// « Solde Total Restant Dû »
  double get soldeTotalRestantDu =>
      _creances.fold(0, (s, c) => s + c.soldeRestantDu);

  /// « Soldes Anciens (>10j) »
  int get soldesAnciens {
    final maintenant = DateTime.now();
    return _creances.where((c) => c.estAncienne(maintenant)).length;
  }

  /// « Événements CRM (7j) »
  int get evenementsCrm => evenements.length;

  /// Événements CRM à venir — **dérivés de la date de naissance**, aucune table
  /// dédiée. Le prototype affiche un tableau d'événements sans en modéliser la
  /// source ; l'anniversaire est la seule information réellement disponible.
  List<EvenementCrm> get evenements {
    final maintenant = DateTime.now();
    final resultat = <EvenementCrm>[];

    for (final client in _liste) {
      final jours = client.joursAvantAnniversaire(maintenant);
      if (jours == null || jours > fenetreCrmJours) continue;

      final naissance = client.dateNaissance!;
      resultat.add(
        EvenementCrm(
          client: client.nom,
          type: EvenementCrm.anniversaire,
          date: DateTime(
            maintenant.year + (jours < 0 ? 1 : 0),
            naissance.month,
            naissance.day,
          ),
          joursRestants: jours,
          dernierContact: client.dernierContact,
        ),
      );
    }

    resultat.sort((a, b) => a.joursRestants.compareTo(b.joursRestants));
    return resultat;
  }

  Future<Resultat<Client>> creerClient({
    required String nom,
    String? telephone,
    DateTime? dateNaissance,
  }) async {
    if (nom.trim().isEmpty) {
      return const Echec('Le nom complet est obligatoire.');
    }
    if (_liste.any((c) => c.nom.toLowerCase() == nom.trim().toLowerCase())) {
      // Le nom sert de cle de rapprochement avec `VENTES.client` : deux
      // homonymes rendraient les agregats faux.
      return const Echec('Un client porte déjà ce nom.');
    }

    try {
      final client = await _clients.creerClient(
        nom: nom.trim(),
        telephone: telephone?.trim().isEmpty ?? true ? null : telephone!.trim(),
        dateNaissance: dateNaissance,
      );
      await charger();
      return Succes(client);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec creation client: $e');
      return const Echec('Impossible d\'enregistrer ce client.');
    }
  }

  /// « Enregistrer un Paiement » — Doc F4 Écran 3.
  Future<Resultat<void>> enregistrerPaiement({
    required String referenceVente,
    required double? montant,
  }) async {
    if (montant == null || montant <= 0) {
      return const Echec('Le montant recouvré doit être supérieur à 0.');
    }
    try {
      await _ventes.enregistrerPaiement(
        reference: referenceVente,
        montant: montant,
      );
      await charger();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec paiement creance: $e');
      return const Echec('Le paiement n\'a pas pu être enregistré.');
    }
  }

  /// Action « Relancer » du tableau CRM.
  ///
  /// ECART_DELIBERE : le prototype affiche un bouton « Relancer » sans aucune
  /// passerelle SMS ou téléphonie derrière (Doc B1 §6 : hors périmètre).
  /// Prétendre envoyer un message serait mensonger. L'action **horodate le
  /// dernier contact**, ce qui est réel et alimente la colonne « Dernier
  /// Contact » du tableau — la relance elle-même reste à faire par téléphone.
  Future<Resultat<void>> marquerContact(Client client) async {
    try {
      await _clients.enregistrerContact(client.id);
      await charger();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec enregistrement contact: $e');
      return const Echec('Impossible d\'enregistrer ce contact.');
    }
  }
}
