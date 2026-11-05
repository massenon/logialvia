import 'package:flutter/foundation.dart';

import '../../data/repositories/rapports_repository_drift.dart';
import '../../domain/entities/rapports.dart';

/// Rapports & États — Doc F7, 6 onglets sur une période commune.
///
/// Un seul ViewModel : les 6 onglets partagent le sélecteur de période affiché
/// en permanence en haut de l'écran, et plusieurs de leurs chiffres doivent
/// concorder (le Résultat Net de l'onglet 1 est celui de la Comptabilité, la
/// Trésorerie Nette de l'onglet 2 est celle du Bilan).
class RapportsViewModel extends ChangeNotifier {
  RapportsViewModel(this._repository, {DateTime? aujourdhui})
    : _aujourdhui = aujourdhui ?? DateTime.now() {
    // Periode par defaut : le mois civil en cours. Le prototype fige
    // « 01/08/2026 au 08/08/2026 », ce qui n'a de sens qu'a sa date de capture.
    final maintenant = _aujourdhui;
    _debut = DateTime(maintenant.year, maintenant.month);
    _fin = maintenant;
  }

  final RapportsRepository _repository;
  final DateTime _aujourdhui;

  bool _chargement = true;
  bool get chargement => _chargement;

  late DateTime _debut;
  late DateTime _fin;
  DateTime get debut => _debut;
  DateTime get fin => _fin;

  DonneesRapports _donnees = DonneesRapports.vide;
  DonneesRapports get donnees => _donnees;

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    _donnees = await _repository.charger(
      debut: _debut,
      fin: _fin,
      aujourdhui: _aujourdhui,
    );
    _chargement = false;
    notifyListeners();
  }

  Future<void> changerPeriode({DateTime? debut, DateTime? fin}) async {
    if (debut != null) _debut = debut;
    if (fin != null) _fin = fin;
    // Une periode inversee ne renvoie rien : on la remet d'aplomb plutot que
    // d'afficher six onglets vides sans explication.
    if (_fin.isBefore(_debut)) {
      final tampon = _debut;
      _debut = _fin;
      _fin = tampon;
    }
    await charger();
  }

  // ------------------------------------- Onglet 1 : Recettes et Dépenses

  String? _filtreCentre;
  String? get filtreCentre => _filtreCentre;

  void definirFiltreCentre(String? valeur) {
    _filtreCentre = valeur;
    notifyListeners();
  }

  List<LigneRecetteDepense> get recettesDepensesFiltrees => _donnees
      .recettesDepenses
      .where((l) => _filtreCentre == null || l.centre == _filtreCentre)
      .toList();

  double get totalRecettes =>
      _donnees.recettesDepenses.fold(0, (s, l) => s + l.encaissement);

  double get totalDepenses =>
      _donnees.recettesDepenses.fold(0, (s, l) => s + l.decaissement);

  /// Recettes − Dépenses. C'est **le même nombre** que le Résultat Net du
  /// Compte de Résultat (BR-CPT-005) : les deux se calculent sur les mêmes
  /// classes 7 et 6 des mêmes écritures.
  double get resultatNet => totalRecettes - totalDepenses;

  /// « Résultat Net / Total Recettes » — libellé exact du KPI du prototype.
  double? get tauxMargeBrute =>
      totalRecettes.abs() < 0.01 ? null : resultatNet / totalRecettes * 100;

  /// Solde cumulé, colonne de droite du tableau. Il se calcule sur les lignes
  /// **affichées** : filtrer par centre de profit produit le cumul de ce
  /// centre, ce que le prototype fait aussi.
  List<double> get soldesCumules {
    final cumuls = <double>[];
    var cumul = 0.0;
    for (final ligne in recettesDepensesFiltrees) {
      cumul += ligne.encaissement - ligne.decaissement;
      cumuls.add(cumul);
    }
    return cumuls;
  }

  // ----------------------------------------- Onglet 2 : État de Trésorerie

  String? _filtreCompte;
  String? get filtreCompte => _filtreCompte;

  void definirFiltreCompte(String? valeur) {
    _filtreCompte = valeur;
    notifyListeners();
  }

  /// Comptes retenus par le filtre, dans l'ordre du plan comptable.
  List<CompteTresorerie> get comptesAffiches => _donnees.comptesTresorerie
      .where(
        (c) =>
            _filtreCompte == null ||
            CompteTresorerie.libelleCourt(c.numero) == _filtreCompte,
      )
      .toList();

  /// Libellés courts proposés au filtre, déduits des comptes réellement
  /// présents — jamais une liste figée qui proposerait un compte inexistant.
  List<String> get libellesComptesTresorerie => {
    for (final c in _donnees.comptesTresorerie)
      CompteTresorerie.libelleCourt(c.numero),
  }.toList();

  double soldeOuverture(String libelleCourt) => _donnees.comptesTresorerie
      .where((c) => CompteTresorerie.libelleCourt(c.numero) == libelleCourt)
      .fold(0, (s, c) => s + c.soldeOuverture);

  /// Solde de clôture d'un compte : ouverture + mouvements de la période.
  double soldeCloture(String libelleCourt) {
    var solde = soldeOuverture(libelleCourt);
    for (final m in _donnees.mouvementsTresorerie) {
      if (m.compte == libelleCourt) solde += m.entree - m.sortie;
    }
    return solde;
  }

  double get tresorerieNetteGlobale => libellesComptesTresorerie.fold(
    0,
    (s, libelle) => s + soldeCloture(libelle),
  );

  List<MouvementTresorerie> get mouvementsFiltres => _donnees
      .mouvementsTresorerie
      .where((m) => _filtreCompte == null || m.compte == _filtreCompte)
      .toList();

  /// Solde progressif **par compte** : chaque ligne affiche le solde du compte
  /// qu'elle mouvemente, jamais un cumul mêlant Caisse et Mobile Money.
  List<double> get soldesProgressifsTresorerie {
    final soldes = <String, double>{
      for (final libelle in libellesComptesTresorerie)
        libelle: soldeOuverture(libelle),
    };
    final resultat = <double>[];
    for (final m in _donnees.mouvementsTresorerie) {
      soldes[m.compte] = (soldes[m.compte] ?? 0) + m.entree - m.sortie;
      if (_filtreCompte == null || m.compte == _filtreCompte) {
        resultat.add(soldes[m.compte] ?? 0);
      }
    }
    return resultat;
  }

  // -------------------------------------------- Onglet 3 : Créances Clients

  String? _filtreStatutCreance;
  String? get filtreStatutCreance => _filtreStatutCreance;

  void definirFiltreStatutCreance(String? valeur) {
    _filtreStatutCreance = valeur;
    notifyListeners();
  }

  List<CreanceClient> get creancesFiltrees => _donnees.creances
      .where(
        (c) => _filtreStatutCreance == null || c.statut == _filtreStatutCreance,
      )
      .toList();

  double get creancesEnCours =>
      _donnees.creances.fold(0, (s, c) => s + c.soldeDu);

  double get creancesEnRetard => _donnees.creances
      .where((c) => c.enRetard)
      .fold(0, (s, c) => s + c.soldeDu);

  /// Nombre de **clients** débiteurs, pas de factures : un client avec 3
  /// factures impayées reste un seul débiteur.
  int get clientsDebiteurs =>
      _donnees.creances.map((c) => c.client).toSet().length;

  /// « Acomptes / Montant Initial » — libellé exact du KPI du prototype.
  double? get tauxRecouvrement {
    final initial = _donnees.creances.fold<double>(
      0,
      (s, c) => s + c.montantInitial,
    );
    if (initial.abs() < 0.01) return null;
    final acomptes = _donnees.creances.fold<double>(
      0,
      (s, c) => s + c.acomptes,
    );
    return acomptes / initial * 100;
  }

  // ---------------------------------------- Onglet 4 : Dettes Fournisseurs

  String? _filtreStatutDette;
  String? get filtreStatutDette => _filtreStatutDette;

  void definirFiltreStatutDette(String? valeur) {
    _filtreStatutDette = valeur;
    notifyListeners();
  }

  List<DetteFournisseur> get dettesFiltrees => _donnees.dettes
      .where(
        (d) => _filtreStatutDette == null || d.statut == _filtreStatutDette,
      )
      .toList();

  double get totalDettes =>
      _donnees.dettes.fold(0, (s, d) => s + d.soldeRestant);

  double get dettesUrgentes => _donnees.dettes
      .where((d) => d.urgente)
      .fold(0, (s, d) => s + d.soldeRestant);

  int get fournisseursCrediteurs =>
      _donnees.dettes.map((d) => d.fournisseur).toSet().length;

  // ------------------------------------------- Onglet 6 : Rapport de Stocks

  String? _filtreCategorieStock;
  String? get filtreCategorieStock => _filtreCategorieStock;

  void definirFiltreCategorieStock(String? valeur) {
    _filtreCategorieStock = valeur;
    notifyListeners();
  }

  List<LigneStock> get stocksFiltres => _donnees.stocks
      .where(
        (s) =>
            _filtreCategorieStock == null ||
            s.categorie == _filtreCategorieStock,
      )
      .toList();

  /// ⚠️ Calculés sur **tout** le stock, pas sur les lignes filtrées — le
  /// prototype fait de même (`valeurTotale` s'incrémente avant le `return` du
  /// filtre) : les KPI décrivent le stock, la table en montre une partie.
  /// Somme des seules lignes **réellement valorisées**.
  ///
  /// Les produits finis sans coût de revient n'y entrent pas — voir
  /// [articlesNonValorises]. Leur substituer le prix de vente, comme le fait
  /// le prototype, gonflerait ce total d'une marge non réalisée.
  double get valeurTotaleStock =>
      _donnees.stocks.fold(0, (s, l) => s + (l.valeurTotale ?? 0));

  /// Articles dont le coût unitaire est inconnu : ils existent en stock mais
  /// ne pèsent rien dans [valeurTotaleStock]. Le KPI doit le dire.
  int get articlesNonValorises =>
      _donnees.stocks.where((l) => l.nonValorise).length;

  int get articlesEnAlerte => _donnees.stocks.where((l) => l.critique).length;

  int get referencesActives => _donnees.stocks.length;

  void reinitialiserFiltres() {
    _filtreCentre = null;
    _filtreCompte = null;
    _filtreStatutCreance = null;
    _filtreStatutDette = null;
    _filtreCategorieStock = null;
    notifyListeners();
  }

  /// Trace de diagnostic — utilisée uniquement en débogage.
  void journaliserEtat() {
    if (!kDebugMode) return;
    debugPrint(
      'Rapports ${_debut.toIso8601String()} → ${_fin.toIso8601String()} : '
      '${_donnees.recettesDepenses.length} lignes de gestion, '
      '${_donnees.creances.length} créances, ${_donnees.dettes.length} dettes.',
    );
  }
}
