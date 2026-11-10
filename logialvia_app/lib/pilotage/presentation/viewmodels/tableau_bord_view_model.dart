import 'package:flutter/foundation.dart';

import '../../../core/formatage/formats.dart';
import '../../domain/entities/tableau_bord_principal.dart';
import '../../domain/repositories/tableau_bord_repository.dart';

/// Tableau de Bord Principal — Doc F2 Ecran 1, fidele a `dashboard.html`.
class TableauBordViewModel extends ChangeNotifier {
  TableauBordViewModel(this._repository);

  final TableauBordRepository _repository;

  /// Filieres structurelles, toujours comptees (Doc I2 §2).
  static const Set<String> especesPermanentes = {'goliaths', 'pintades'};

  /// Detail affiche sur les KPI dont la source de donnee n'existe pas encore.
  /// Dire « module non disponible » est plus honnete qu'un « 0 FCFA » nu, qui
  /// se lirait comme un vrai zero metier (Master Prompt §2.2).
  static const String _sourceIndisponible =
      'Disponible avec le module Comptabilité';

  bool _chargement = true;
  bool get chargement => _chargement;

  DateTime _debutPeriode = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  DateTime _finPeriode = DateTime.now();
  DateTime get debutPeriode => _debutPeriode;
  DateTime get finPeriode => _finPeriode;

  List<IndicateurCle> _indicateurs = const [];
  List<IndicateurCle> get indicateurs => _indicateurs;

  List<RecensementFiliere> _filieres = const [];
  List<RecensementFiliere> get filieres => _filieres;

  RecensementCouveuse? _couveuse;
  RecensementCouveuse? get couveuse => _couveuse;

  List<PointMensuel> _evolutionMensuelle = const [];
  List<PointMensuel> get evolutionMensuelle => _evolutionMensuelle;

  List<PointJournalier> _evolutionJournaliere = const [];
  List<PointJournalier> get evolutionJournaliere => _evolutionJournaliere;

  List<TransactionRecente> _ventesRecentes = const [];
  List<TransactionRecente> get ventesRecentes => _ventesRecentes;

  List<ActiviteJournal> _activites = const [];
  List<ActiviteJournal> get activites => _activites;

  List<MeilleureVente> _meilleuresVentes = const [];
  List<MeilleureVente> get meilleuresVentes => _meilleuresVentes;

  double _recettesSemaine = 0;
  double get recettesSemaine => _recettesSemaine;

  /// Change la periode du filtre de dates, puis recharge.
  Future<void> definirPeriode(
    DateTime debut,
    DateTime fin,
    Set<String> especesActives,
  ) async {
    _debutPeriode = debut;
    _finPeriode = fin;
    await charger(especesActives);
  }

  Future<void> charger(Set<String> especesActives) async {
    _chargement = true;
    notifyListeners();

    final ca = await _repository.chiffreAffaires(
      debut: _debutPeriode,
      fin: _finPeriode,
    );
    final encours = await _repository.encoursClients();
    final alertes = await _repository.articlesSousSeuil();
    final effectif = await _repository.effectifCheptel(especesActives);
    final statsCouveuse = await _repository.statistiquesCouveuse();

    _indicateurs = _construireIndicateurs(
      ca: ca,
      encours: encours,
      alertes: alertes,
      effectif: effectif,
      couveuse: statsCouveuse,
    );

    _couveuse = RecensementCouveuse(
      cyclesEnCours: statsCouveuse.cyclesEnCours,
      oeufsCharges: statsCouveuse.oeufsCharges,
      tauxEclosionMoyen: statsCouveuse.tauxEclosionMoyen,
      poussinsAttendus: statsCouveuse.poussinsAttendus,
    );

    _filieres = [
      for (final espece in especesActives)
        ?await _repository.recensementFiliere(espece),
    ];

    _evolutionMensuelle = await _repository.evolutionMensuelle();
    _evolutionJournaliere = await _repository.evolutionJournaliere();
    _ventesRecentes = await _repository.ventesRecentes();
    _activites = await _repository.activitesDuJour();
    _meilleuresVentes = await _repository.meilleuresVentes(
      debut: _debutPeriode,
      fin: _finPeriode,
    );

    final debutSemaine = DateTime.now().subtract(const Duration(days: 7));
    _recettesSemaine = (await _repository.chiffreAffaires(
      debut: debutSemaine,
      fin: DateTime.now(),
    )).total;

    _chargement = false;
    notifyListeners();
  }

  /// Les 8 indicateurs de `dashboard.html` l.135-174, dans l'ordre exact.
  List<IndicateurCle> _construireIndicateurs({
    required VentilationChiffreAffaires ca,
    required EncoursClients encours,
    required List<ArticleEnAlerte> alertes,
    required int effectif,
    required StatistiquesCouveuse couveuse,
  }) {
    final intrantsEnAlerte = alertes.where((a) => a.estIntrant).toList();

    return [
      IndicateurCle(
        libelle: 'Chiffre d\'Affaires',
        valeur: Formats.nombre(ca.total),
        unite: 'FCFA',
        detail:
            'Avicole : ${Formats.nombre(ca.avicole)} · '
            'Commerce annexe : ${Formats.nombre(ca.commerceAnnexe)}',
        icone: 'trending_up',
        accent: AccentKpi.navy,
      ),
      const IndicateurCle(
        libelle: 'Trésorerie',
        valeur: '—',
        unite: '',
        // Le solde de caisse se lit sur le compte 571 du plan comptable (SYSCOHADA)
        // (Doc F2, Doc F6) — aucune ecriture comptable ne peut exister tant que
        // ce module n'est pas implemente.
        detail: _sourceIndisponible,
        icone: 'account_balance_wallet',
        accent: AccentKpi.info,
        calculable: false,
      ),
      const IndicateurCle(
        libelle: 'Dépenses',
        valeur: '—',
        unite: '',
        detail: 'Disponible avec les modules Achats et Comptabilité',
        icone: 'shopping_cart',
        accent: AccentKpi.or,
        calculable: false,
      ),
      const IndicateurCle(
        libelle: 'Résultat Net',
        valeur: '—',
        unite: '',
        // Resultat = CA - depenses. Les depenses etant indisponibles, afficher
        // le seul CA sous ce libelle serait faux.
        detail: 'Nécessite les dépenses de la période',
        icone: 'savings',
        accent: AccentKpi.succes,
        calculable: false,
      ),
      IndicateurCle(
        libelle: 'Soldes Restant Dus',
        valeur: Formats.nombre(encours.montant),
        unite: 'FCFA',
        detail: encours.nombreVentes == 0
            ? 'Aucune vente en avance non soldée'
            : '${encours.nombreVentes} vente(s) en avance non soldée(s)',
        icone: 'request_quote',
        accent: AccentKpi.erreur,
      ),
      IndicateurCle(
        libelle: 'Stock Critique',
        valeur: '${intrantsEnAlerte.length}',
        unite: intrantsEnAlerte.length > 1 ? 'intrants' : 'intrant',
        detail: intrantsEnAlerte.isEmpty
            ? 'Aucun intrant sous son seuil'
            : '${intrantsEnAlerte.map((a) => a.libelle).join(', ')} '
                  'sous le seuil d\'alerte',
        icone: 'warning',
        accent: AccentKpi.erreur,
      ),
      IndicateurCle(
        libelle: 'Effectif Cheptel',
        valeur: '$effectif',
        unite: effectif > 1 ? 'têtes' : 'tête',
        detail: effectif == 0
            ? 'Aucune journée d\'élevage encore saisie'
            : 'Filières actives, tous stades',
        icone: 'pets',
        accent: AccentKpi.navy,
      ),
      IndicateurCle(
        libelle: 'Cycles Couveuse en Cours',
        valeur: '${couveuse.cyclesEnCours}',
        unite: couveuse.cyclesEnCours > 1 ? 'cycles' : 'cycle',
        detail: couveuse.eclosionImminente != null
            ? '1 éclosion prévue sous 3 jours'
            : 'Aucune éclosion imminente',
        icone: 'egg',
        accent: AccentKpi.or,
      ),
    ];
  }
}
