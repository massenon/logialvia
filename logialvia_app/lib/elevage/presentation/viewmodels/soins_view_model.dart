import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../domain/entities/soin.dart';
import '../../domain/repositories/soins_repository.dart';
import '../../domain/usecases/reporter_deces_infirmerie_usecase.dart';

/// Calendrier de Soins — Doc F3, fidèle à `soins-calendrier.html`.
class SoinsViewModel extends ChangeNotifier {
  SoinsViewModel(this._repository, this._reporterDeces);

  final SoinsRepository _repository;

  /// Report d'un deces sur la fiche d'elevage de la filiere concernee.
  final ReporterDecesInfirmerieUseCase _reporterDeces;

  bool _chargement = true;
  bool get chargement => _chargement;

  List<Soin> _soins = const [];
  List<EntreeInfirmerie> _infirmerie = const [];

  String? _filtreCategorie;
  String? _filtreEspece;
  String? get filtreCategorie => _filtreCategorie;
  String? get filtreEspece => _filtreEspece;

  List<Soin> get soins => _soins.where((s) {
    if (_filtreCategorie != null && s.typeSoin != _filtreCategorie) return false;
    if (_filtreEspece != null && s.espece != _filtreEspece) return false;
    return true;
  }).toList();

  List<EntreeInfirmerie> get infirmerie => _infirmerie;

  void definirFiltreCategorie(String? valeur) {
    _filtreCategorie = valeur;
    notifyListeners();
  }

  void definirFiltreEspece(String? valeur) {
    _filtreEspece = valeur;
    notifyListeners();
  }

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    _soins = await _repository.chargerSoins();
    _infirmerie = await _repository.chargerInfirmerie();
    _chargement = false;
    notifyListeners();
  }

  // ------------------------------------------------------------------- KPIs
  // Les 4 KPI reels de `soins-calendrier.html` l.95-107 — ⚠️ aucun des quatre
  // ne correspond a ceux que listait Doc F3.

  DateTime get _debutMois {
    final maintenant = DateTime.now();
    return DateTime(maintenant.year, maintenant.month);
  }

  /// « Doses Administrées (Mois) » — soins effectués dans le mois courant.
  int get dosesAdministreesMois => _soins
      .where(
        (s) => s.estEffectue && !s.datePrevue.isBefore(_debutMois),
      )
      .length;

  /// « Planifiées à Venir » — échéances futures non encore réalisées.
  int get planifieesAVenir {
    final aujourdhui = _minuit(DateTime.now());
    return _soins
        .where(
          (s) => !s.estEffectue && !s.datePrevue.isBefore(aujourdhui),
        )
        .length;
  }

  /// « En Quarantaine / Traitement » — entrées d'infirmerie ouvertes, plus les
  /// soins en traitement en cours.
  int get enQuarantaineOuTraitement =>
      _infirmerie.where((e) => e.estEnCours).length +
      _soins.where((s) => s.statut == StatutSoin.traitementEnCours).length;

  /// « Coût Vétérinaire (Mois) », en FCFA.
  int get coutVeterinaireMois => _soins
      .where((s) => !s.datePrevue.isBefore(_debutMois))
      .fold<int>(0, (somme, s) => somme + s.coutFcfa);

  /// Soins en retard — utilisé par le Dashboard Élevage (Doc F2).
  int get soinsEnRetard => _soins.where((s) => s.estEnRetard).length;

  /// Soins dont le délai d'attente court encore : leurs produits ne sont pas
  /// commercialisables. Aucune alerte de ce type n'existe dans le prototype,
  /// mais la rémanence y est saisie — l'exposer évite qu'elle reste une donnée
  /// morte.
  List<Soin> get remanencesActives {
    final maintenant = DateTime.now();
    return _soins.where((s) => s.remanenceActive(maintenant)).toList();
  }

  Future<Resultat<Soin>> enregistrerSoin({
    required String? espece,
    required DateTime? date,
    required String? typeSoin,
    String? produit,
    String? dose,
    int remanenceJours = 0,
    String? veterinaire,
    String? symptomes,
    int coutFcfa = 0,
    required bool dejaEffectue,
  }) async {
    // Les 3 champs marqués `*` / `data-required` dans la modale réelle.
    if (espece == null) return const Echec('Le lot / la bande est obligatoire.');
    if (date == null) return const Echec('La date du soin est obligatoire.');
    if (typeSoin == null) return const Echec('Le type d\'action est obligatoire.');
    if (remanenceJours < 0) {
      return const Echec('Le délai d\'attente ne peut être négatif.');
    }
    if (coutFcfa < 0) return const Echec('Le coût ne peut être négatif.');

    try {
      final soin = await _repository.enregistrerSoin(
        espece: espece,
        date: date,
        typeSoin: typeSoin,
        statut: dejaEffectue ? StatutSoin.effectue : StatutSoin.planifie,
        produit: produit,
        dose: dose,
        remanenceJours: remanenceJours,
        veterinaire: veterinaire,
        symptomes: symptomes,
        coutFcfa: coutFcfa,
      );
      await charger();
      return Succes(soin);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec enregistrement soin: $e');
      return const Echec('Impossible d\'enregistrer le soin. Réessayez.');
    }
  }

  Future<Resultat<void>> confirmerAdministration(Soin soin) async {
    if (soin.estEffectue) {
      return const Echec('Ce soin est déjà marqué comme effectué.');
    }
    try {
      await _repository.confirmerAdministration(soin.id);
      await charger();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec confirmation soin: $e');
      return const Echec('Impossible de confirmer l\'administration.');
    }
  }

  Future<Resultat<EntreeInfirmerie>> enregistrerEntreeInfirmerie({
    required String sujet,
    required String motif,
    required String niveauIsolement,
    String? espece,
  }) async {
    if (sujet.trim().isEmpty) {
      return const Echec('Le lot / sujet est obligatoire.');
    }
    if (motif.trim().isEmpty) return const Echec('Le motif est obligatoire.');

    try {
      final entree = await _repository.enregistrerEntreeInfirmerie(
        sujet: sujet.trim(),
        motif: motif.trim(),
        niveauIsolement: niveauIsolement,
        dateEntree: DateTime.now(),
        espece: espece,
      );
      await charger();
      return Succes(entree);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec entree infirmerie: $e');
      return const Echec('Impossible d\'enregistrer l\'entrée.');
    }
  }

  /// Clôture une entrée d'infirmerie.
  ///
  /// ⚠️ La modale de décès du prototype annonce : *« Cette action clôture
  /// l'entrée d'infirmerie et sera reflétée dans le décompte de mortalité de la
  /// fiche d'élevage correspondante »* (l.326). Côté web, **rien n'est
  /// répercuté** — c'est une promesse non tenue. Le répercuter réellement
  /// supposerait de décider sur quelle catégorie imputer la mort, information
  /// que l'infirmerie ne capture pas (le champ « Lot / Sujet » est du texte
  /// libre). Point signalé plutôt qu'improvisé.
  ///
  /// TODO(dette): brancher un événement de domaine vers la fiche d'élevage une
  /// fois la catégorie du sujet connue (Doc C1 §4).
  /// Clôture une entrée d'infirmerie.
  ///
  /// [categorieMortalite] n'a de sens qu'avec le statut « Décédé » : c'est
  /// l'index de la catégorie d'effectif où la perte est portée sur la fiche
  /// d'élevage. `null` laisse la fiche inchangée — le cas de l'animalier qui a
  /// déjà saisi la perte lui-même.
  ///
  /// ## Ordre des opérations, et pourquoi il compte
  ///
  /// La clôture est écrite **avant** le report, et la marque « reportée » n'est
  /// posée qu'**après** lui. Un échec en cours de route laisse donc une entrée
  /// close et non reportée — état honnête, que l'écran affiche — plutôt qu'une
  /// perte comptée deux fois à la reprise.
  Future<Resultat<void>> cloturerEntree({
    required EntreeInfirmerie entree,
    required String statut,
    int? categorieMortalite,
  }) async {
    if (!entree.estEnCours) {
      return const Echec('Cette entrée est déjà clôturée.');
    }
    if (categorieMortalite != null && statut != StatutInfirmerie.decede) {
      return const Echec(
        "Une catégorie de mortalité ne se renseigne que sur un décès.",
      );
    }
    final espece = entree.espece;
    if (categorieMortalite != null && espece == null) {
      return const Echec(
        "Cette entrée ne désigne aucune filière : le décès ne peut être porté "
        "sur aucune fiche.",
      );
    }
    try {
      await _repository.cloturerEntree(
        entreeId: entree.id,
        statut: statut,
        dateSortie: DateTime.now(),
      );

      if (categorieMortalite != null && espece != null) {
        final report = await _reporterDeces.executer(
          espece: espece,
          indexCategorie: categorieMortalite,
          date: DateTime.now(),
        );
        if (report case Echec<void>(message: final message)) {
          await charger();
          return Echec(
            "Entrée clôturée, mais la perte n'a pas été portée sur la fiche "
            "($message) Saisissez-la sur la fiche d'élevage.",
          );
        }
        await _repository.marquerDecesReporte(
          entreeId: entree.id,
          categorieMortalite: categorieMortalite,
        );
      }

      await charger();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec cloture entree: $e');
      return const Echec('Impossible de clôturer l\'entrée.');
    }
  }

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);
}
