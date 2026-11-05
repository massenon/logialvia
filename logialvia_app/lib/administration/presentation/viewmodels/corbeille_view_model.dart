import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../data/seed/seed_demonstration.dart';
import '../../domain/services/service_archivage.dart';
import '../../domain/services/service_reinitialisation.dart';

/// Onglets « Corbeille » et « Données de Test » des Paramètres Généraux.
class CorbeilleViewModel extends ChangeNotifier {
  CorbeilleViewModel(
    this._archivage,
    this._reinitialisation,
    this._demonstration,
  );

  final ServiceArchivage _archivage;
  final ServiceReinitialisation _reinitialisation;

  /// Peuplement de demonstration — sous le meme double verrou que la remise a
  /// zero : mode « Donnees de Test » actif, et administratrice.
  final SeedDemonstration _demonstration;

  bool _chargement = true;
  bool get chargement => _chargement;

  List<ElementArchive> _elements = const [];

  /// Filtre par module — la corbeille mélange les 5 modules.
  String? _filtreModule;
  String? get filtreModule => _filtreModule;

  void definirFiltreModule(String? module) {
    _filtreModule = module;
    notifyListeners();
  }

  List<ElementArchive> get elements => _filtreModule == null
      ? _elements
      : _elements.where((e) => e.module == _filtreModule).toList();

  /// Modules réellement présents dans la corbeille — proposer un filtre qui ne
  /// ramène rien serait trompeur.
  List<String> get modules =>
      (_elements.map((e) => e.module).toSet().toList()..sort());

  int get total => _elements.length;

  Map<String, int> _apercuReinitialisation = const {};
  Map<String, int> get apercuReinitialisation => _apercuReinitialisation;

  int get lignesAEffacer =>
      _apercuReinitialisation.values.fold(0, (s, n) => s + n);

  bool _enCours = false;
  bool get enCours => _enCours;

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    _elements = await _archivage.lister();
    _apercuReinitialisation = await _reinitialisation.apercu();
    _chargement = false;
    notifyListeners();
  }

  Future<Resultat<void>> restaurer(
    ElementArchive element, {
    required bool estAdmin,
  }) async {
    try {
      await _archivage.restaurer(element.id, estAdmin: estAdmin);
      await charger();
      return const Succes(null);
    } on EchecRestauration catch (e) {
      return Echec(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec restauration: $e');
      return const Echec('Cet élément n\'a pas pu être restauré.');
    }
  }

  Future<Resultat<void>> purger(
    ElementArchive element, {
    required bool estAdmin,
  }) async {
    try {
      await _archivage.purger(element.id, estAdmin: estAdmin);
      await charger();
      return const Succes(null);
    } on EchecRestauration catch (e) {
      return Echec(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec purge: $e');
      return const Echec('Cet élément n\'a pas pu être supprimé.');
    }
  }

  Future<Resultat<void>> viderCorbeille({required bool estAdmin}) async {
    try {
      await _archivage.purgerTout(estAdmin: estAdmin);
      await charger();
      return const Succes(null);
    } on EchecRestauration catch (e) {
      return Echec(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec vidage corbeille: $e');
      return const Echec('La corbeille n\'a pas pu être vidée.');
    }
  }

  /// Remet l'activité à zéro. Le garde-fou est **double** : le mode doit être
  /// activé dans les Paramètres, et l'utilisatrice doit être administratrice.
  Future<Resultat<BilanReinitialisation>> reinitialiser({
    required bool estAdmin,
    required bool modeActif,
    String parIdentifiant = '',
  }) async {
    if (!modeActif) {
      return const Echec(
        'Le mode « Données de Test » est désactivé. Activez-le dans '
        'Modules Actifs avant de réinitialiser.',
      );
    }
    if (!estAdmin) {
      return const Echec(
        'Seule une administratrice peut réinitialiser les données.',
      );
    }
    if (_enCours) return const Echec('Une réinitialisation est déjà en cours.');

    _enCours = true;
    notifyListeners();
    try {
      final bilan = await _reinitialisation.executer(
        parIdentifiant: parIdentifiant,
      );
      await charger();
      return Succes(bilan);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec reinitialisation: $e');
      return Echec('La réinitialisation a échoué : $e');
    } finally {
      _enCours = false;
      notifyListeners();
    }
  }

  /// Peuple un mois d'activite credible.
  ///
  /// Meme double verrou que la remise a zero, et pour la meme raison : ce sont
  /// des donnees fictives, elles n'ont rien a faire dans une exploitation en
  /// service. Les melanger a de vraies ventes rendrait la comptabilite fausse
  /// sans que rien ne le signale.
  Future<Resultat<BilanDemonstration>> peuplerDemonstration({
    required bool estAdmin,
    required bool modeActif,
  }) async {
    if (!modeActif) {
      return const Echec(
        'Le mode « Données de Test » est désactivé. Activez-le dans '
        'Modules Actifs avant de peupler des données de démonstration.',
      );
    }
    if (!estAdmin) {
      return const Echec(
        'Seule une administratrice peut peupler des données de test.',
      );
    }
    if (_enCours) return const Echec('Une opération est déjà en cours.');

    _enCours = true;
    notifyListeners();
    try {
      final bilan = await _demonstration.executer();
      await charger();
      return Succes(bilan);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec peuplement demonstration: $e');
      return Echec('Le peuplement a échoué : $e');
    } finally {
      _enCours = false;
      notifyListeners();
    }
  }
}
