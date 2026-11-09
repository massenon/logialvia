import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/resultat/resultat.dart';
import '../../data/repositories/factures_mecef_repository_drift.dart';
import '../../domain/entities/facture_mecef.dart';
import '../../domain/services/transmission_mecef.dart';

/// Écran Facturation MeCeF.
///
/// ## Une règle qui gouverne tout cet écran
///
/// Rien n'est déclaré normalisé sans preuve. Le statut affiché suit ce que la
/// DGI a réellement rendu, jamais ce que l'on espérait qu'elle rende. Une
/// transmission qui échoue laisse la facture « À transmettre » et affiche
/// l'erreur ; elle ne la marque pas normalisée « en attendant ».
class FacturesMecefViewModel extends ChangeNotifier {
  FacturesMecefViewModel(
    this._repository,
    this._db, {
    this.jetons = const DepotJetonMecef(),
    ClientMecef Function({
      required String urlBase,
      required String jeton,
      String? ifuEmetteur,
    })?
    fabriqueClient,
  }) : _fabriqueClient = fabriqueClient ?? _clientHttp;

  final FacturesMecefRepositoryDrift _repository;
  final AppDatabase _db;
  final DepotJetonMecef jetons;

  /// Injectable : les tests ne doivent pas ouvrir de connexion réseau.
  final ClientMecef Function({
    required String urlBase,
    required String jeton,
    String? ifuEmetteur,
  })
  _fabriqueClient;

  static ClientMecef _clientHttp({
    required String urlBase,
    required String jeton,
    String? ifuEmetteur,
  }) =>
      ClientMecefHttp(urlBase: urlBase, jeton: jeton, ifuEmetteur: ifuEmetteur);

  bool _chargement = true;
  bool get chargement => _chargement;

  List<FactureMecef> _factures = const [];
  List<FactureMecef> get factures => _factures;

  List<GroupeTaxe> _groupes = const [];
  List<GroupeTaxe> get groupesTaxe => _groupes;

  List<VenteRow> _ventesSansFacture = const [];
  List<VenteRow> get ventesSansFacture => _ventesSansFacture;

  String? _mecefUrl;
  String? _mecefNim;
  String? _ifu;
  bool _jetonRenseigne = false;

  String? get mecefUrl => _mecefUrl;
  String? get mecefNim => _mecefNim;
  bool get jetonRenseigne => _jetonRenseigne;

  /// La transmission automatique n'est possible que si les trois éléments sont
  /// là. Sinon la saisie manuelle prend le relais — et le dit.
  bool get transmissionConfiguree =>
      (_mecefUrl?.isNotEmpty ?? false) && _jetonRenseigne;

  String _recherche = '';
  String get recherche => _recherche;

  void definirRecherche(String valeur) {
    _recherche = valeur.trim().toLowerCase();
    notifyListeners();
  }

  /// `null` = tous les statuts.
  StatutFacture? _filtreStatut;
  StatutFacture? get filtreStatut => _filtreStatut;

  void definirFiltreStatut(StatutFacture? statut) {
    _filtreStatut = statut;
    notifyListeners();
  }

  List<FactureMecef> get facturesFiltrees => [
    for (final f in _factures)
      if ((_filtreStatut == null || f.statut == _filtreStatut) &&
          (_recherche.isEmpty ||
              f.reference.toLowerCase().contains(_recherche) ||
              f.client.toLowerCase().contains(_recherche)))
        f,
  ];

  // ------------------------------------------------------------ indicateurs

  int get nombreATransmettre =>
      _factures.where((f) => f.statut == StatutFacture.aTransmettre).length;

  int get nombreNormalisees => _factures.where((f) => f.estNormalisee).length;

  int get nombreRejetees =>
      _factures.where((f) => f.statut == StatutFacture.rejetee).length;

  /// Le facturé net : les factures de vente moins les avoirs.
  ///
  /// Additionner les deux gonflerait le chiffre — un avoir retire du chiffre
  /// d'affaires, il ne s'y ajoute pas.
  double get totalFactureNet => _factures.fold(
    0,
    (s, f) => s + (f.type == TypeFacture.vente ? f.totalTtc : -f.totalTtc),
  );

  // --------------------------------------------------------------- chargement

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();

    _factures = await _repository.toutes();
    _groupes = await _repository.groupesTaxe();
    _ventesSansFacture = await _repository.ventesSansFacture();

    final parametres = await _db
        .select(_db.parametresEntreprise)
        .getSingleOrNull();
    _mecefUrl = parametres?.mecefUrl;
    _mecefNim = parametres?.mecefNim;
    _ifu = parametres?.ifu;
    _jetonRenseigne = await jetons.renseigne;

    _chargement = false;
    notifyListeners();
  }

  // ------------------------------------------------------------------ actions

  Future<Resultat<FactureMecef>> emettrePourVente({
    required String venteRef,
    String? clientIfu,
    String? clientAdresse,
  }) async {
    try {
      final facture = await _repository.emettrePourVente(
        venteRef: venteRef,
        clientIfu: clientIfu,
        clientAdresse: clientAdresse,
      );
      await charger();
      return Succes(facture);
    } on StateError catch (e) {
      return Echec(e.message);
    }
  }

  Future<Resultat<FactureMecef>> emettreAvoir({
    required String factureOrigine,
    required String motif,
    List<LigneFacture> lignes = const [],
  }) async {
    try {
      final avoir = await _repository.emettreAvoir(
        factureOrigine: factureOrigine,
        motif: motif,
        lignes: lignes,
      );
      await charger();
      return Succes(avoir);
    } on StateError catch (e) {
      return Echec(e.message);
    }
  }

  /// Une seule machine normalise une facture : celle qui l'a émise.
  static const String messageAutrePoste =
      'Cette facture a été émise sur un autre poste : elle se transmet à la '
      'DGI depuis ce poste, pour qu\'elle ne soit pas normalisée deux fois.';

  /// Transmet une facture à e-MECeF.
  Future<Resultat<void>> transmettre(String reference) async {
    final aTransmettre = await _repository.parReference(reference);
    if (aTransmettre != null && aTransmettre.estDUnAutrePoste) {
      return const Echec(messageAutrePoste);
    }
    if (!transmissionConfiguree) {
      return const Echec(
        'Transmission non configurée : renseignez l\'URL e-MECeF et le jeton '
        'dans Paramètres Général, ou saisissez le code de normalisation à la '
        'main.',
      );
    }
    final facture = await _repository.parReference(reference);
    if (facture == null) return const Echec('Facture introuvable.');

    final jeton = await jetons.lire();
    if (jeton == null || jeton.isEmpty) {
      return const Echec('Jeton e-MECeF absent.');
    }

    try {
      final reponse = await _fabriqueClient(
        urlBase: _mecefUrl!,
        jeton: jeton,
        ifuEmetteur: _ifu,
      ).transmettre(facture);

      await _repository.normaliser(
        reference: reference,
        codeMecef: reponse.codeMecef,
        nim: reponse.nim,
        compteur: reponse.compteur,
        lienVerification: reponse.lienVerification,
        dateNormalisation: reponse.dateNormalisation,
      );
      await charger();
      return const Succes(null);
    } on EchecTransmission catch (e) {
      await _repository.marquerRejetee(reference: reference, erreur: e.message);
      await charger();
      return Echec(e.message);
    }
  }

  /// Reporte à la main le retour de la DGI, quand la transmission a eu lieu
  /// par un autre canal.
  Future<Resultat<void>> normaliserManuellement({
    required String reference,
    required String codeMecef,
    required String nim,
    String? compteur,
    String? lienVerification,
  }) async {
    try {
      await _repository.normaliser(
        reference: reference,
        codeMecef: codeMecef,
        nim: nim,
        compteur: compteur,
        lienVerification: lienVerification,
      );
      await charger();
      return const Succes(null);
    } on StateError catch (e) {
      return Echec(e.message);
    }
  }
}
