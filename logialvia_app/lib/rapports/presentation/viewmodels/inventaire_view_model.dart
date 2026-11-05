import 'package:flutter/foundation.dart';

import '../../data/repositories/inventaire_repository_drift.dart';
import '../../domain/entities/inventaire.dart';

/// Écran Inventaire — état daté des stocks, valorisé au coût.
class InventaireViewModel extends ChangeNotifier {
  InventaireViewModel(this._repository, {DateTime? maintenant})
    : _reference = maintenant ?? DateTime.now() {
    _appliquerPeriode(PeriodeInventaire.jour);
  }

  final InventaireRepositoryDrift _repository;

  /// « Aujourd'hui » du point de vue de l'écran. Injectable pour que les tests
  /// soient déterministes.
  final DateTime _reference;

  bool _chargement = true;
  bool get chargement => _chargement;

  Inventaire? _inventaire;
  Inventaire? get inventaire => _inventaire;

  PeriodeInventaire _periode = PeriodeInventaire.jour;
  PeriodeInventaire get periode => _periode;

  late DateTime _debut;
  late DateTime _fin;
  DateTime get debut => _debut;
  DateTime get fin => _fin;

  /// Filtre de recherche appliqué aux deux tableaux.
  String _recherche = '';
  String get recherche => _recherche;

  void definirRecherche(String valeur) {
    _recherche = valeur.trim().toLowerCase();
    notifyListeners();
  }

  void _appliquerPeriode(PeriodeInventaire periode) {
    _periode = periode;
    final jour = DateTime(_reference.year, _reference.month, _reference.day);
    switch (periode) {
      case PeriodeInventaire.jour:
        _debut = jour;
        _fin = jour;
      case PeriodeInventaire.semaine:
        // Semaine calendaire, du lundi au jour affiche : c'est la maille des
        // reunions d'exploitation.
        _debut = jour.subtract(Duration(days: jour.weekday - 1));
        _fin = jour;
      case PeriodeInventaire.mois:
        _debut = DateTime(jour.year, jour.month);
        _fin = jour;
      case PeriodeInventaire.plage:
        // La plage garde les bornes deja choisies.
        break;
    }
  }

  Future<void> changerPeriode(PeriodeInventaire periode) async {
    _appliquerPeriode(periode);
    await charger();
  }

  /// Bornes libres — bascule automatiquement en « plage personnalisée ».
  Future<void> definirPlage({DateTime? debut, DateTime? fin}) async {
    _periode = PeriodeInventaire.plage;
    // La derniere borne choisie fait foi, et entraine l'autre si besoin.
    // Echanger les deux, comme on le fait souvent, donnerait une periode que
    // personne n'a demandee : choisir « du 20 » alors que la fin est au 12
    // veut dire « je commence le 20 », pas « je finis le 20 ».
    if (debut != null) {
      _debut = DateTime(debut.year, debut.month, debut.day);
      if (_fin.isBefore(_debut)) _fin = _debut;
    }
    if (fin != null) {
      _fin = DateTime(fin.year, fin.month, fin.day);
      if (_fin.isBefore(_debut)) _debut = _fin;
    }
    await charger();
  }

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    _inventaire = await _repository.construire(debut: _debut, fin: _fin);
    _chargement = false;
    notifyListeners();
  }

  // ------------------------------------------------------------- filtrage

  List<LigneInventaireIntrant> get intrants {
    final tout = _inventaire?.intrants ?? const <LigneInventaireIntrant>[];
    if (_recherche.isEmpty) return tout;
    return tout
        .where(
          (l) =>
              l.article.toLowerCase().contains(_recherche) ||
              l.code.toLowerCase().contains(_recherche) ||
              l.categorie.toLowerCase().contains(_recherche),
        )
        .toList();
  }

  List<LigneInventaireProduit> get produits {
    final tout = _inventaire?.produits ?? const <LigneInventaireProduit>[];
    if (_recherche.isEmpty) return tout;
    return tout
        .where(
          (l) =>
              l.produit.toLowerCase().contains(_recherche) ||
              l.sku.toLowerCase().contains(_recherche) ||
              l.categorie.toLowerCase().contains(_recherche),
        )
        .toList();
  }

  /// Libellé de la période, tel qu'il figure en tête du document imprimé.
  String get libellePeriode {
    if (_debut == _fin) return 'Situation au ${_jour(_fin)}';
    return 'Du ${_jour(_debut)} au ${_jour(_fin)}';
  }

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
