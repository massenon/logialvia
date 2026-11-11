import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/depot_etat_synchronisation.dart';
import '../../../core/sync/depot_journal_synchronisation.dart';
import '../../../core/sync/planificateur_synchronisation.dart';

/// Écran « Synchronisation » : l'état du poste, l'historique des tentatives, les
/// lignes refusées par le serveur et le contrôle de cohérence.
class SynchronisationViewModel extends ChangeNotifier {
  SynchronisationViewModel(
    this._planificateur,
    this._journal,
    this._etat,
    this._dossierExport,
  ) {
    _planificateur.addListener(_surPlanificateur);
  }

  final PlanificateurSynchronisation _planificateur;
  final DepotJournalSynchronisation _journal;
  final DepotEtatSynchronisation _etat;
  final Directory _dossierExport;

  bool _chargement = true;
  bool _ferme = false;
  bool _etaitEnCours = false;
  bool get chargement => _chargement;

  List<EntreeJournalSynchro> _historique = const [];
  List<EntreeJournalSynchro> get historique => _historique;

  List<LigneRefusee> _refusees = const [];

  /// Lignes refusées, filtrées par [filtreTable].
  List<LigneRefusee> get refusees => filtreTable == null
      ? _refusees
      : _refusees.where((l) => l.table == filtreTable).toList();

  /// Tables qui ont au moins une ligne refusée (les filtres proposés).
  List<String> get tablesRefusees =>
      {for (final l in _refusees) l.table}.toList()..sort();

  String? _filtreTable;
  String? get filtreTable => _filtreTable;

  List<EtatTableSynchro> _parTable = const [];
  List<EtatTableSynchro> get parTable => _parTable;

  int get enAttente => _parTable.fold(0, (s, e) => s + e.enAttente);

  /// `null` tant que « Vérifier la cohérence » n'a pas été lancé.
  DateTime? _coherenceVerifieeLe;
  DateTime? get coherenceVerifieeLe => _coherenceVerifieeLe;

  DateTime? _derniereReception;
  DateTime? get derniereReception => _derniereReception;
  DateTime? _dernierEnvoi;
  DateTime? get dernierEnvoi => _dernierEnvoi;

  bool get synchronisationEnCours => _planificateur.enCours;

  String? _message;
  String? get message => _message;

  Future<void> charger() async {
    _historique = await _journal.dernieres(10);
    final recents = await _journal.dernieres(
      DepotJournalSynchronisation.conservees,
    );
    _derniereReception = recents
        .where((j) => j.recues > 0)
        .map((j) => j.debutLe)
        .firstOrNull;
    _dernierEnvoi = recents
        .where((j) => j.envoyees > 0)
        .map((j) => j.debutLe)
        .firstOrNull;
    _parTable = await _etat.parTable();
    _refusees = await _etat.refusees();
    if (_filtreTable != null && !tablesRefusees.contains(_filtreTable)) {
      _filtreTable = null;
    }
    _chargement = false;
    _notifier();
  }

  void filtrer(String? table) {
    _filtreTable = table;
    _notifier();
  }

  Future<void> synchroniser() async {
    if (_planificateur.enCours) return;
    await _planificateur.synchroniserMaintenant();
    await charger();
  }

  /// « Remettre en file » : une ligne, une table, ou toutes les lignes refusées
  /// affichées ; puis synchronise tout de suite.
  Future<int> remettreEnFile({String? table, String? id}) async {
    final n = await _etat.remettreEnFile(table: table, id: id);
    _message = n == 0
        ? 'Aucune ligne à remettre en file.'
        : '$n ligne(s) remise(s) en file : elles repartent à la synchronisation.';
    await charger();
    if (n > 0) await synchroniser();

    return n;
  }

  /// Contrôle local : recompte les lignes du poste par état.
  Future<void> verifierCoherence() async {
    _parTable = await _etat.parTable();
    _refusees = await _etat.refusees();
    _coherenceVerifieeLe = DateTime.now();
    _notifier();
  }

  /// Écrit le journal complet (CSV) dans le dossier d'export et renvoie le fichier.
  Future<File> exporterJournal() => _journal.exporterVers(_dossierExport);

  void _surPlanificateur() {
    // Une synchronisation vient de se terminer (de n'importe quel déclencheur) :
    // l'historique et les compteurs ont changé.
    final enCours = _planificateur.enCours;
    if (_etaitEnCours && !enCours) charger();
    _etaitEnCours = enCours;
    _notifier();
  }

  void _notifier() {
    if (!_ferme) notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    _planificateur.removeListener(_surPlanificateur);
    super.dispose();
  }
}

/// Libellé du déclencheur d'un cycle, pour l'historique.
String libelleDeclencheur(String declencheur) => switch (declencheur) {
  'ouverture' => 'À l\'ouverture',
  'routine' => 'Automatique',
  'saisie' => 'Après une saisie',
  'manuel' => 'Manuel',
  'demande' => 'Demande du serveur',
  'fermeture' => 'À la fermeture',
  'appairage' => 'Après l\'appairage',
  _ => declencheur,
};

/// Libellé du résultat d'un cycle, pour l'historique.
String libelleIssue(String issue) => switch (issue) {
  'terminee' => 'Réussie',
  'horsLigne' => 'Hors ligne',
  'revoque' => 'Poste révoqué',
  'refusee' => 'Refusée',
  'nonAppairee' => 'Non appairé',
  _ => issue,
};
