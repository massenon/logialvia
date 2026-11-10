import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../domain/entities/bande.dart';
import '../../domain/entities/configuration_espece.dart';
import '../../domain/entities/journee_elevage.dart';
import '../../domain/entities/parametres_elevage.dart';
import '../../domain/entities/soin.dart';
import '../../data/repositories/parametres_elevage_repository_drift.dart';
import '../../domain/repositories/bandes_repository.dart';
import '../../domain/repositories/fiche_elevage_repository.dart';
import '../../domain/repositories/soins_repository.dart';
import '../../domain/services/calcul_fiche_journaliere.dart';
import '../../domain/services/controle_vraisemblance.dart';
import '../../domain/services/reperes_zootechniques.dart';
import '../../domain/services/prophylaxie_de_la_bande.dart';
import '../../domain/usecases/chaine_effectifs_usecases.dart';
import '../../domain/usecases/enregistrer_journee_usecase.dart';

export '../../domain/services/prophylaxie_de_la_bande.dart'
    show EcheanceProjetee;

export '../../domain/usecases/chaine_effectifs_usecases.dart'
    show JourIncoherent, RapportChaine;
export '../../domain/usecases/enregistrer_journee_usecase.dart'
    show SaisieStockOeufs;

/// Écran de fiche d'élevage — Doc F3, patron commun aux 5 fiches.
///
/// Un seul ViewModel paramétré par [ConfigurationEspece], jamais 5 copies
/// (Strict Avoid §5 et §15).
class FicheEspeceViewModel extends ChangeNotifier {
  FicheEspeceViewModel({
    required this.configuration,
    required FicheElevageRepository repository,
    required this.parametresRepository,
    required this.bandesRepository,
    required this.soinsRepository,
  }) : _repository = repository,
       _usecase = EnregistrerJourneeUseCase(repository, configuration),
       _calcul = CalculFicheJournaliere(configuration);

  final ConfigurationEspece configuration;
  final FicheElevageRepository _repository;

  /// Source des baremes de rationnement — Parametres Elevage (Doc F3).
  /// Public parce qu'il n'est pas re-passe a un usecase : le rendre prive
  /// declencherait `prefer_initializing_formals` sans rien apporter.
  final ParametresElevageRepository parametresRepository;

  /// Depot des bandes — la mise en place qui donne son J1 au cycle. Public
  /// pour la meme raison que [parametresRepository].
  final BandesRepository bandesRepository;

  /// Lecture des soins, pour savoir quelles echeances sont deja planifiees.
  final SoinsRepository soinsRepository;
  final EnregistrerJourneeUseCase _usecase;

  /// Reconstruit a chaque rafraichissement avec les rations configurees dans
  /// **Parametres Elevage** : une ration modifiee la-bas doit changer la
  /// provende calculee ici, sinon l'ecran de parametres serait decoratif.
  CalculFicheJournaliere _calcul;

  bool _chargement = true;
  bool get chargement => _chargement;

  DateTime _jourActif = DateTime.now();
  DateTime get jourActif => _jourActif;

  /// Les journées du mois affiché, indexées par numéro de jour.
  Map<int, JourneeElevage> _journeesDuMois = const {};
  Map<int, JourneeElevage> get journeesDuMois => _journeesDuMois;

  /// Journée du jour actif, éventuellement vierge.
  JourneeElevage get journeeActive =>
      _journeesDuMois[_jourActif.day] ??
      JourneeElevage.vierge(
        espece: configuration.identifiant,
        date: _jourActif,
        nombreCategories: configuration.nombreCategories,
      );

  /// Effectifs de la veille — base de tous les calculs en direct.
  JourneeElevage? _veille;
  List<int> get effectifsVeille =>
      _veille?.effectifsParCategorie ?? _calcul.repartitionInitiale(0);
  int get effectifTotalVeille => _veille?.effectif ?? 0;

  /// Ventes du jour issues du POS — champ en lecture seule dans le formulaire
  /// (`day-vente` est `readonly` dans le prototype : la vente vient du POS,
  /// jamais d'une saisie manuelle sur la fiche).
  int _venteDuJour = 0;
  int get venteDuJour => _venteDuJour;

  int get nombreJoursDuMois =>
      DateTime(_jourActif.year, _jourActif.month + 1, 0).day;

  // ------------------------------------------------- Bande & prophylaxie

  Bande? _bande;
  List<EcheanceProphylaxie> _echeances = const [];
  List<Soin> _soins = const [];
  FormatsNumerotation _formats = const FormatsNumerotation();

  /// Bande qui couvre le jour affiche, `null` si aucune n'a ete declaree.
  Bande? get bande => _bande;

  /// Jour de cycle du jour affiche, `null` sans bande.
  ///
  /// C'est cette valeur, et elle seule, qui permet de lire le calendrier de
  /// prophylaxie : il est indexe sur le jour du **cycle**, pas du mois.
  int? get jourDeCycle => _bande?.jourDeCycle(_jourActif);

  ProphylaxieDeLaBande? get _projection {
    final bande = _bande;
    if (bande == null) return null;
    return ProphylaxieDeLaBande(
      bande: bande,
      echeances: _echeances,
      soins: _soins,
    );
  }

  /// Les echeances qui tombent le jour affiche — section « Traitements &
  /// Prophylaxie » de la saisie journaliere.
  List<EcheanceProjetee> get prophylaxieDuJour =>
      _projection?.duJour(_jourActif) ?? const [];

  /// Tout le calendrier de la bande, date.
  List<EcheanceProjetee> get prophylaxieDeLaBande =>
      _projection?.toutes() ?? const [];

  /// Vrai quand la filiere a un calendrier mais aucune bande pour le dater.
  bool get calendrierSansBande =>
      _bande == null &&
      _echeances.any((e) => e.espece == configuration.identifiant);

  /// Prochain code de bande libre, selon le prefixe des Parametres Elevage.
  Future<String> prochainCodeBande() async {
    final existantes = await bandesRepository.chargerBandes(
      configuration.identifiant,
    );
    final prefixe = _formats.bande;
    final pris = existantes.map((b) => b.code).toSet();
    var n = existantes.length + 1;
    while (pris.contains('$prefixe$n')) {
      n++;
    }
    return '$prefixe$n';
  }

  Future<Resultat<Bande>> declarerBande({
    required String code,
    required DateTime dateMiseEnBande,
    int? effectifInitial,
    String? observations,
  }) async {
    if (code.trim().isEmpty) {
      return const Echec('Le code de la bande est obligatoire.');
    }
    if (effectifInitial != null && effectifInitial < 0) {
      return const Echec("L'effectif mis en place ne peut etre negatif.");
    }
    try {
      final bande = await bandesRepository.creerBande(
        espece: configuration.identifiant,
        code: code.trim(),
        dateMiseEnBande: dateMiseEnBande,
        effectifInitial: effectifInitial,
        observations: (observations ?? '').trim().isEmpty
            ? null
            : observations!.trim(),
      );
      await _rafraichir();
      notifyListeners();
      return Succes(bande);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec creation bande: $e');
      return const Echec(
        'Impossible de declarer la bande. Ce code existe peut-etre deja pour '
        'cette filiere.',
      );
    }
  }

  Future<Resultat<void>> cloturerBande(DateTime date) async {
    final bande = _bande;
    if (bande == null) return const Echec('Aucune bande en cours.');
    if (date.isBefore(bande.dateMiseEnBande)) {
      return const Echec(
        'La cloture ne peut pas preceder la mise en place de la bande.',
      );
    }
    try {
      await bandesRepository.cloturerBande(id: bande.id, dateCloture: date);
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec cloture bande: $e');
      return const Echec('Impossible de cloturer la bande.');
    }
  }

  /// Cree un soin planifie a partir d'une echeance du calendrier.
  ///
  /// Le **type d'action** est demande a l'utilisateur : `TypeSoin` est une
  /// liste fermee (Vaccination, Traitement curatif, Vermifuge, Vitamines) et le
  /// calendrier ne le porte pas. Le deduire du libelle marcherait pour
  /// « Vaccin Newcastle » et se tromperait sur « Controle Oxygenation ».
  Future<Resultat<Soin>> planifierEcheance({
    required EcheanceProjetee projetee,
    required String typeSoin,
  }) async {
    final bande = _bande;
    if (bande == null) return const Echec('Aucune bande en cours.');
    if (projetee.estPlanifie) {
      return const Echec('Cette echeance est deja planifiee.');
    }
    if (!TypeSoin.tous.contains(typeSoin)) {
      return const Echec("Ce type d'action n'existe pas.");
    }
    try {
      final soin = await soinsRepository.enregistrerSoin(
        espece: configuration.identifiant,
        date: projetee.datePrevue,
        typeSoin: typeSoin,
        statut: StatutSoin.planifie,
        produit: projetee.echeance.produit,
        dose: projetee.echeance.dose,
        remanenceJours: projetee.echeance.remanenceJours,
        symptomes: null,
        bandeId: bande.id,
        echeanceProphylaxieId: projetee.echeance.id,
      );
      await _rafraichir();
      notifyListeners();
      return Succes(soin);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec planification echeance: $e');
      return const Echec('Impossible de planifier ce soin.');
    }
  }

  // ------------------------------------------- Chaine, divergence, recodage (`47e_`)

  List<JourIncoherent> _joursIncoherents = const [];

  /// Jours dont l'effectif ne découle pas de la veille (fiches d'un autre poste arrivées
  /// sans cascade). Vide quand la chaîne est cohérente.
  List<JourIncoherent> get joursIncoherents => _joursIncoherents;

  List<VersionJournee> _versions = const [];

  /// Versions en présence quand la fiche du jour est « modifiée ailleurs ».
  List<VersionJournee> get versionsEnDivergence => _versions;

  /// Recalcule toute la chaîne d'effectifs de la filière, dans l'ordre chronologique.
  Future<Resultat<RapportChaine>> recalculerChaine() async {
    final resultat = await ChaineEffectifsUseCase(
      _repository,
      configuration,
    ).recalculer();
    await _rafraichir();
    notifyListeners();
    return resultat;
  }

  /// Garde [choisie] pour la fiche du jour (la machine ne tranche jamais).
  Future<Resultat<void>> resoudreDivergence(VersionJournee choisie) async {
    final resultat = await ResoudreDivergenceUseCase(
      _repository,
      configuration,
    ).executer(date: _jourActif, choisie: choisie);
    await _rafraichir();
    notifyListeners();
    return resultat;
  }

  /// Code de recodage proposé pour la bande en conflit (`B2` -> `B2-P2`).
  Future<String?> codeRecodageBandePropose() async {
    final b = _bande;
    if (b == null) return null;
    final toutes = await bandesRepository.chargerBandes(configuration.identifiant);
    return Bande.proposerCodeRecodage(
      b.code,
      codePoste: await bandesRepository.codePoste(),
      codesPris: toutes.map((x) => x.code).toSet(),
    );
  }

  Future<Resultat<void>> recoderBande(String nouveauCode) async {
    final b = _bande;
    if (b == null) return const Echec('Aucune bande en cours.');
    if (nouveauCode.trim().isEmpty) {
      return const Echec('Le code de la bande est obligatoire.');
    }
    try {
      await bandesRepository.recoderBande(id: b.id, nouveauCode: nouveauCode);
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } on StateError catch (e) {
      return Echec(e.message);
    } catch (_) {
      return const Echec('Impossible de recoder la bande.');
    }
  }

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    await _rafraichir();
    _chargement = false;
    notifyListeners();
  }

  Future<void> changerJour(DateTime date) async {
    _jourActif = date;
    await _rafraichir();
    notifyListeners();
  }

  Future<void> _rafraichir() async {
    final journees = await _repository.chargerMois(
      espece: configuration.identifiant,
      annee: _jourActif.year,
      mois: _jourActif.month,
    );
    _journeesDuMois = {for (final j in journees) j.date.day: j};

    _veille = await _repository.chargerJourneePrecedente(
      espece: configuration.identifiant,
      date: _jourActif,
    );
    _venteDuJour = await _repository.venteDuJour(
      espece: configuration.identifiant,
      date: _jourActif,
    );

    _joursIncoherents = await ChaineEffectifsUseCase(
      _repository,
      configuration,
    ).verifier();
    _versions = journeeActive.modifieeAilleurs
        ? await _repository.versionsEnDivergence(
            espece: configuration.identifiant,
            date: _jourActif,
          )
        : const [];

    _bande = await bandesRepository.bandeCouvrant(
      espece: configuration.identifiant,
      date: _jourActif,
    );
    _echeances = await parametresRepository.chargerProphylaxie();
    _formats = await parametresRepository.chargerFormatsNumerotation();
    _soins = await soinsRepository.chargerSoins();

    final baremes = await parametresRepository.chargerBaremes();
    final taux = await parametresRepository.chargerTauxPoids();
    _calcul = CalculFicheJournaliere(
      configuration,
      rationsConfigurees: {
        for (final b in baremes)
          if (b.espece == configuration.identifiant)
            b.stade: b.rationGrammesParJour,
      },
      tauxParClasse: taux,
    );
  }

  /// Ration effective d'une categorie — barème configure, ou valeur de
  /// reference de [ConfigurationEspece] a defaut.
  int rationCategorie(int index) => _calcul.rationCategorie(index);

  /// Calcul en direct pendant la saisie, sans rien persister — équivalent de
  /// `computeEffectifAndFeedLive()` du prototype.
  EffectifsJour calculerEnDirect(MouvementsJour mouvements) {
    return _calcul.calculerJour(
      effectifsVeille: effectifsVeille,
      effectifTotalVeille: effectifTotalVeille,
      mouvements: mouvements,
    );
  }

  int provendeTotaleGrammes(List<int> effectifs, {int? poidsTotalGrammes}) =>
      _calcul.provendeTotaleGrammes(
        effectifs,
        poidsTotalGrammes: poidsTotalGrammes,
      );

  /// Provende du jour avec son mode de calcul (poids vif ou ration par tête).
  ProvendeJour provendeDuJour(List<int> effectifs, {int? poidsTotalGrammes}) =>
      _calcul.provendeDuJour(effectifs, poidsTotalGrammes: poidsTotalGrammes);

  /// Stock d'œufs de la veille — ouverture (SRH) du jour actif.
  /// **Stock Final de la veille, jamais son Total Stock** (Doc 05 §4).
  int get srhOuverture => _veille?.stockFinalOeufs ?? 0;

  /// Calcul en direct du stock d'œufs, sans rien persister.
  ResultatStockOeufs calculerStockOeufsEnDirect(SaisieStockOeufs saisie) {
    return CalculStockOeufs.calculerJour(
      srhOuverture: srhOuverture,
      oeufsPondus: saisie.oeufsPondus,
      oeufsCasses: saisie.oeufsCasses,
      sortiesPlateaux: saisie.sortiesPlateaux,
    );
  }

  /// Contrôle de vraisemblance en direct (`47e_`) : erreurs (la saisie sera refusée) et
  /// avertissements (affichés, jamais bloquants), sans rien persister.
  ResultatControle controlerEnDirect(
    MouvementsJour mouvements, {
    int? poidsTotalGrammes,
    SaisieStockOeufs? stockOeufs,
  }) {
    final effectifs = calculerEnDirect(mouvements);
    return ControleVraisemblance(configuration).controlerJournee(
      effectifsVeille: effectifsVeille,
      mouvements: mouvements,
      effectifsDuJour: effectifs,
      effectifTotalVeille: effectifTotalVeille,
      poidsTotalGrammes: poidsTotalGrammes,
      oeufsPondus: stockOeufs?.oeufsPondus,
      oeufsCasses: stockOeufs?.oeufsCasses,
      sortiesPlateaux: stockOeufs?.sortiesPlateaux,
      stockOeufsDisponible:
          srhOuverture +
          ((stockOeufs?.oeufsPondus ?? 0) - (stockOeufs?.oeufsCasses ?? 0))
              .clamp(0, 999999),
    );
  }

  Future<Resultat<JourneeElevage>> enregistrer({
    required MouvementsJour mouvements,
    int? poidsGeneralG,
    String? traitementObs,
    bool traitementValide = false,
    SaisieStockOeufs? stockOeufs,
  }) async {
    final resultat = await _usecase.executer(
      date: _jourActif,
      mouvements: mouvements,
      poidsGeneralG: poidsGeneralG,
      traitementObs: traitementObs,
      traitementValide: traitementValide,
      stockOeufs: stockOeufs,
    );
    if (resultat is Succes<JourneeElevage>) {
      await _rafraichir();
    }
    notifyListeners();
    return resultat;
  }

  // ------------------------------------------------------------------- KPIs

  /// Les 4 KPI de la fiche — Doc F3 §1, libellés relevés dans le HTML réel
  /// (`fiche-goliaths.html` l.117-130).

  /// Effectif du dernier jour saisi du mois.
  int get effectifVivant => _derniereJourneeSaisie?.effectif ?? 0;

  /// Catégorie 3 : « Matures (Éligibles Vente) ».
  int get effectifMatures =>
      _derniereJourneeSaisie?.effectifsParCategorie.elementAtOrNull(2) ?? 0;

  /// Catégorie 2 : « Goliathaux / Pintadaux (Immatures) ».
  int get effectifImmatures =>
      _derniereJourneeSaisie?.effectifsParCategorie.elementAtOrNull(1) ?? 0;

  /// Taux de mortalité cumulé du mois = morts du mois ÷ (effectif de début de mois +
  /// entrées du mois) : l'effectif **exposé** au risque (`47e_`). Ignorer les entrées du
  /// mois surestimait le taux (et le faisait dépasser 100 % quand une bande arrivait en
  /// cours de mois).
  double get tauxMortaliteCumul =>
      ReperesZootechniques.tauxMortaliteCumule(
        morts: _journeesSaisies.fold<int>(0, (s, j) => s + j.totalMorts),
        effectifDepart: effectifReportMois,
        entrees: _journeesSaisies.fold<int>(0, (s, j) => s + j.achat + j.ne),
      ) ??
      0;

  /// Niveau d'alerte du taux cumulé : 10 % avertissement, 20 % critique (DV-13).
  NiveauAlerte get niveauMortaliteCumul =>
      ReperesZootechniques.niveauMortaliteCumul(tauxMortaliteCumul);

  /// Effectif de report au **début du mois affiché**.
  ///
  /// C'est le point de départ de la première semaine de la Vue Hebdomadaire.
  /// Il n'est pas stocké : on le reconstitue depuis la première journée saisie
  /// du mois, en lui rendant ce qu'elle a retiré et en lui retirant ce qu'elle
  /// a ajouté. Sans journée saisie, il n'y a rien à reporter.
  int get effectifReportMois {
    final premiere = _journeesSaisies.firstOrNull;
    if (premiere == null) return 0;
    return premiere.effectif -
        premiere.achat -
        premiere.ne +
        premiere.totalMorts +
        premiere.vente +
        premiere.totalDons;
  }

  bool get aDesDonnees => _journeesSaisies.isNotEmpty;

  List<JourneeElevage> get _journeesSaisies {
    final saisies = _journeesDuMois.values.where((j) => j.isRecorded).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return saisies;
  }

  JourneeElevage? get _derniereJourneeSaisie =>
      _journeesSaisies.isEmpty ? null : _journeesSaisies.last;
}
