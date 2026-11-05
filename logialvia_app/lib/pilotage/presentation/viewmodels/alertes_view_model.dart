import 'package:flutter/foundation.dart';

import '../../../elevage/domain/services/rappels_prophylaxie.dart';
import '../../domain/entities/tableau_bord_principal.dart';
import '../../domain/repositories/tableau_bord_repository.dart';

/// Alertes reelles de l'application — alimente a la fois la cloche de la barre
/// du haut et le panneau « Alertes Critiques » du tableau de bord.
///
/// Une seule source pour les deux affichages : le prototype les alimentait
/// separement avec deux listes ecrites en dur, ce qui les laissait diverger
/// (Strict Avoid §12).
///
/// Enregistre globalement dans `main.dart` — la barre du haut est presente sur
/// tous les ecrans (Doc K4 §5).
class AlertesViewModel extends ChangeNotifier {
  AlertesViewModel(this._repository);

  final TableauBordRepository _repository;

  List<AlerteCritique> _alertes = const [];
  List<AlerteCritique> get alertes => _alertes;

  /// Les articles sous leur seuil, tels quels.
  ///
  /// La liste des messages ne suffit pas a la popup de stock : elle a besoin
  /// du stock, du seuil et de l'unite pour dire **combien il manque**. Reparser
  /// la phrase pour en extraire les nombres serait absurde.
  List<ArticleEnAlerte> _articlesSousSeuil = const [];
  List<ArticleEnAlerte> get articlesSousSeuil => _articlesSousSeuil;

  /// Les echeances de prophylaxie echues et non planifiees.
  List<RappelProphylaxie> _rappelsProphylaxie = const [];
  List<RappelProphylaxie> get rappelsProphylaxie => _rappelsProphylaxie;

  int get nombre => _alertes.length;

  bool _chargement = false;
  bool get chargement => _chargement;

  Future<void> rafraichir() async {
    _chargement = true;
    notifyListeners();

    final construites = <AlerteCritique>[];

    _articlesSousSeuil = await _repository.articlesSousSeuil();
    for (final article in _articlesSousSeuil) {
      construites.add(
        AlerteCritique(
          message:
              'Stock de ${article.libelle} sous le seuil critique '
              '(${article.stock} ${article.unite} pour un seuil de ${article.seuil}).',
          severite: SeveriteAlerte.critique,
          icone: 'inventory_2',
          route: article.estIntrant ? '/stocks' : '/catalogue',
        ),
      );
    }

    final couveuse = await _repository.statistiquesCouveuse();
    if (couveuse.eclosionImminente != null) {
      construites.add(
        AlerteCritique(
          message:
              'Éclosion imminente — Cycle ${couveuse.eclosionImminente}, sous 3 jours.',
          severite: SeveriteAlerte.critique,
          icone: 'egg',
          route: '/elevage/couveuse',
        ),
      );
    }

    final encours = await _repository.encoursClients();
    if (encours.nombreVentes > 0) {
      construites.add(
        AlerteCritique(
          message:
              'Soldes restant dus — ${encours.nombreVentes} vente(s) en avance non soldée(s).',
          severite: SeveriteAlerte.avertissement,
          icone: 'request_quote',
          route: '/clients',
        ),
      );
    }

    // Les echeances du calendrier qui n'ont jamais ete planifiees. Elles ne
    // figurent dans aucun registre : sans cette alerte, elles passent.
    _rappelsProphylaxie = await _repository.rappelsProphylaxie(DateTime.now());
    if (_rappelsProphylaxie.isNotEmpty) {
      final especes = RappelsProphylaxie.especesConcernees(_rappelsProphylaxie);
      final enRetard = _rappelsProphylaxie.where((r) => r.enRetard).length;
      construites.add(
        AlerteCritique(
          message:
              '${_rappelsProphylaxie.length} echeance(s) de prophylaxie non '
              'planifiee(s) sur ${especes.length} filiere(s)'
              '${enRetard > 0 ? ", dont $enRetard en retard" : ""}.',
          severite: SeveriteAlerte.critique,
          icone: 'event_busy',
          route: '/elevage/soins',
        ),
      );
    }

    final soinsEnRetard = await _repository.nombreAlertesSanitaires();
    if (soinsEnRetard > 0) {
      construites.add(
        AlerteCritique(
          message: '$soinsEnRetard soin(s) vétérinaire(s) en retard.',
          severite: SeveriteAlerte.critique,
          icone: 'vaccines',
          route: '/elevage/soins',
        ),
      );
    }

    _alertes = construites;
    _chargement = false;
    notifyListeners();
  }
}
