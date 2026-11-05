import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../domain/services/service_sauvegarde.dart';

/// Onglet « Sauvegardes de la Base de Données » — Paramètres Généraux.
class SauvegardesViewModel extends ChangeNotifier {
  SauvegardesViewModel(this._service);

  final ServiceSauvegarde _service;

  bool _chargement = true;
  bool get chargement => _chargement;

  /// Vrai pendant la génération : le bouton se bloque, sinon deux clics
  /// rapides produiraient deux copies de la même base à la seconde près.
  bool _generationEnCours = false;
  bool get generationEnCours => _generationEnCours;

  List<FichierSauvegarde> _sauvegardes = const [];
  List<FichierSauvegarde> get sauvegardes => _sauvegardes;

  String get cheminDossier => _service.dossier.path;
  List<String> get tablesExportables => _service.tablesExportables;

  /// Date de la dernière sauvegarde **complète**, `null` s'il n'y en a jamais
  /// eu. Un export CSV d'une table ne compte pas : il ne permet pas de
  /// restaurer l'exploitation.
  DateTime? get derniereSauvegardeComplete {
    for (final s in _sauvegardes) {
      if (s.estBaseComplete) return s.date;
    }
    return null;
  }

  /// Nombre de jours depuis la dernière sauvegarde complète.
  int? get joursDepuisDerniereSauvegarde {
    final derniere = derniereSauvegardeComplete;
    if (derniere == null) return null;
    final maintenant = DateTime.now();
    return DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
    ).difference(DateTime(derniere.year, derniere.month, derniere.day)).inDays;
  }

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    _sauvegardes = await _service.lister();
    _chargement = false;
    notifyListeners();
  }

  Future<Resultat<FichierSauvegarde>> genererBaseComplete() async {
    if (_generationEnCours) {
      return const Echec('Une sauvegarde est déjà en cours.');
    }
    _generationEnCours = true;
    notifyListeners();

    try {
      final sauvegarde = await _service.genererBaseComplete();
      await charger();
      return Succes(sauvegarde);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec sauvegarde: $e');
      return Echec(
        'La sauvegarde a échoué : $e. Vérifiez que le dossier '
        '$cheminDossier est accessible en écriture.',
      );
    } finally {
      _generationEnCours = false;
      notifyListeners();
    }
  }

  Future<Resultat<FichierSauvegarde>> exporterTable(String table) async {
    try {
      final export = await _service.exporterTable(table);
      await charger();
      return Succes(export);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec export table: $e');
      return Echec('L\'export de « $table » a échoué : $e');
    }
  }

  Future<Resultat<void>> supprimer(FichierSauvegarde sauvegarde) async {
    try {
      await _service.supprimer(sauvegarde);
      await charger();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec suppression sauvegarde: $e');
      return const Echec('Ce fichier n\'a pas pu être supprimé.');
    }
  }
}
