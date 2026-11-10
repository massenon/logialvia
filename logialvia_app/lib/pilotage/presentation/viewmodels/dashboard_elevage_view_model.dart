import 'package:flutter/foundation.dart';

import '../../../elevage/domain/services/reperes_zootechniques.dart';
import '../../domain/entities/tableau_bord_principal.dart';
import '../../domain/repositories/tableau_bord_repository.dart';

/// Dashboard Élevage — Doc F2 Ecran 2, fidele a `elevage-dashboard.html`.
class DashboardElevageViewModel extends ChangeNotifier {
  DashboardElevageViewModel(this._repository);

  final TableauBordRepository _repository;

  bool _chargement = true;
  bool get chargement => _chargement;

  List<RecensementFiliere> _filieres = const [];
  List<RecensementFiliere> get filieres => _filieres;

  /// GMQ par filiere sur 4 semaines (`47e_`) ; une filiere sans deux pesees en est absente.
  Map<String, ResultatGmq> _gmq = const {};
  Map<String, ResultatGmq> get gmq => _gmq;

  RecensementCouveuse? _couveuse;
  RecensementCouveuse? get couveuse => _couveuse;

  List<ProchainSoin> _prochainsSoins = const [];
  List<ProchainSoin> get prochainsSoins => _prochainsSoins;

  List<AlerteCritique> _alertesSanitaires = const [];
  List<AlerteCritique> get alertesSanitaires => _alertesSanitaires;

  double _revenusElevage = 0;

  /// Revenus de la filiere elevage du mois : ventes d'activite « Avicole »
  /// (elevage-dashboard.html l.264 : « Revenus = ventes Avicole du Dashboard
  /// principal »).
  double get revenusElevage => _revenusElevage;

  /// Les couts d'elevage (intrants provende + veterinaire de la periode)
  /// dependent du module Achats (Doc F5), non implemente — la marge nette n'est
  /// donc pas calculable, et n'est pas affichee comme valant le seul revenu.
  bool get coutsDisponibles => false;

  Future<void> charger(Set<String> especesActives) async {
    _chargement = true;
    notifyListeners();

    _filieres = [
      for (final espece in especesActives)
        ?await _repository.recensementFiliere(espece),
    ];

    _gmq = await _repository.gmqParFiliere(especesActives);

    final stats = await _repository.statistiquesCouveuse();
    _couveuse = RecensementCouveuse(
      cyclesEnCours: stats.cyclesEnCours,
      oeufsCharges: stats.oeufsCharges,
      tauxEclosionMoyen: stats.tauxEclosionMoyen,
      poussinsAttendus: stats.poussinsAttendus,
    );

    _prochainsSoins = await _repository.prochainsSoins();

    _alertesSanitaires = [
      for (final soin in _prochainsSoins.where((s) => s.estEnRetard))
        AlerteCritique(
          message:
              '${soin.typeSoin} — ${soin.espece} (En Retard, prévu le '
              '${soin.datePrevue.day.toString().padLeft(2, '0')}/'
              '${soin.datePrevue.month.toString().padLeft(2, '0')}/'
              '${soin.datePrevue.year})',
          severite: SeveriteAlerte.critique,
          icone: 'vaccines',
          route: '/elevage/soins',
        ),
      for (final article in (await _repository.articlesSousSeuil()).where(
        (a) => a.estIntrant,
      ))
        AlerteCritique(
          message:
              'Stock de ${article.libelle} sous le seuil critique — impact '
              'direct sur le rationnement des filières.',
          severite: SeveriteAlerte.critique,
          icone: 'inventory_2',
          route: '/stocks',
        ),
    ];

    final maintenant = DateTime.now();
    final debutMois = DateTime(maintenant.year, maintenant.month);
    _revenusElevage = (await _repository.chiffreAffaires(
      debut: debutMois,
      fin: maintenant,
    )).avicole;

    _chargement = false;
    notifyListeners();
  }
}
