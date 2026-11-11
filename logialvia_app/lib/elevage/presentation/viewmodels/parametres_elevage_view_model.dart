import '../../../administration/domain/services/service_archivage.dart';
import 'package:flutter/foundation.dart';

import '../../../core/formatage/formats.dart';
import '../../../core/resultat/resultat.dart';
import '../../data/repositories/parametres_elevage_repository_drift.dart';
import '../../domain/entities/configuration_espece.dart';
import '../../domain/entities/parametres_elevage.dart';

/// Paramètres Élevage — Doc F3, `parametres-elevage.html` (4 onglets).
///
/// Un seul ViewModel pour les 4 onglets : ils configurent le même objet
/// métier — la manière dont les fiches journalières calculent et rappellent.
class ParametresElevageViewModel extends ChangeNotifier {
  ParametresElevageViewModel(this._repository);

  final ParametresElevageRepository _repository;

  bool _chargement = true;
  bool get chargement => _chargement;

  List<BaremeRation> _baremes = const [];
  List<TauxRationPoids> _taux = const [];
  List<EcheanceProphylaxie> _echeances = const [];
  List<TypeProvende> _provendes = const [];
  FormatsNumerotation _formats = const FormatsNumerotation();

  List<BaremeRation> get baremes => _baremes;
  List<TauxRationPoids> get tauxPoids => _taux;
  List<TypeProvende> get provendes => _provendes;
  FormatsNumerotation get formats => _formats;

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    await _rafraichir();
    // Le brouillon de numerotation part de l'etat persiste ; il n'est jamais
    // reinitialise par les rafraichissements des autres onglets, sans quoi une
    // saisie en cours serait perdue au moindre enregistrement de ration.
    _brouillon = _formats;
    _chargement = false;
    notifyListeners();
  }

  Future<void> _rafraichir() async {
    _baremes = await _repository.chargerBaremes();
    _taux = await _repository.chargerTauxPoids();
    _echeances = await _repository.chargerProphylaxie();
    _provendes = await _repository.chargerTypesProvende();
    _formats = await _repository.chargerFormatsNumerotation();
  }

  // ------------------------------------------------- Onglet 1 : Rationnement

  String _rechercheRation = '';
  String? _especeRation;
  String get rechercheRation => _rechercheRation;
  String? get especeRation => _especeRation;

  void definirRechercheRation(String valeur) {
    _rechercheRation = valeur;
    notifyListeners();
  }

  void definirEspeceRation(String? valeur) {
    _especeRation = valeur;
    notifyListeners();
  }

  void reinitialiserFiltresRation() {
    _rechercheRation = '';
    _especeRation = null;
    notifyListeners();
  }

  List<BaremeRation> get baremesFiltres {
    final terme = _rechercheRation.trim().toLowerCase();
    return _baremes.where((b) {
      if (_especeRation != null && b.espece != _especeRation) return false;
      if (terme.isEmpty) return true;
      return b.stade.toLowerCase().contains(terme) ||
          EspecesParametrables.libelle(b.espece).toLowerCase().contains(terme);
    }).toList();
  }

  /// Plafond de ration par tête de l'espèce (5 kg, 4 kg pour un ovin).
  static int _plafondRation(String espece) =>
      ConfigurationsEspeces.parIdentifiant[espece]?.rationMaxGrammesParJour ??
      5000;

  Future<Resultat<void>> ajouterBareme({
    required String espece,
    required String stade,
    required String ration,
  }) async {
    final valeur = int.tryParse(ration.trim());
    if (stade.trim().isEmpty || valeur == null || valeur <= 0) {
      return const Echec('Veuillez renseigner le stade et la ration.');
    }
    // Une ration de plusieurs kilos par tete et par jour est une faute de
    // frappe, pas un bareme : la plus forte du prototype est 120 g.
    final plafond = _plafondRation(espece);
    if (valeur > plafond) {
      return Echec(
        'Une ration de plus de ${Formats.nombre(plafond)} g par tête et par '
        'jour est invraisemblable.',
      );
    }

    try {
      await _repository.creerBareme(
        espece: espece,
        stade: stade.trim(),
        rationGrammesParJour: valeur,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec ajout bareme: $e');
      return const Echec('Ce barème n\'a pas pu être enregistré.');
    }
  }

  /// Statut d'un repère après une modification : « Valider » le confirme, une
  /// valeur changée le ramène à « à valider » (la validation portait sur
  /// l'ancienne valeur), une valeur inchangée le laisse tel quel.
  static bool statutApresModification({
    required bool confirmeAvant,
    required bool valeurChangee,
    required bool valider,
  }) => valider ? true : (valeurChangee ? false : confirmeAvant);

  Future<Resultat<void>> modifierRation({
    required BaremeRation bareme,
    required String ration,
    bool valider = false,
  }) async {
    final valeur = int.tryParse(ration.trim());
    if (valeur == null || valeur <= 0) {
      return const Echec('La ration doit être un nombre de grammes positif.');
    }
    final plafond = _plafondRation(bareme.espece);
    if (valeur > plafond) {
      return Echec(
        'Une ration de plus de ${Formats.nombre(plafond)} g par tête et par '
        'jour est invraisemblable.',
      );
    }

    try {
      await _repository.modifierRation(
        id: bareme.id,
        rationGrammesParJour: valeur,
        confirme: statutApresModification(
          confirmeAvant: bareme.confirme,
          valeurChangee: valeur != bareme.rationGrammesParJour,
          valider: valider,
        ),
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec modification ration: $e');
      return const Echec('Cette ration n\'a pas pu être modifiée.');
    }
  }

  Future<Resultat<void>> supprimerBareme(
    BaremeRation bareme, {
    AuteurArchivage? auteur,
  }) async {
    try {
      await _repository.supprimerBareme(
        bareme.id,
        utilisateurId: auteur?.id,
        utilisateurNom: auteur?.nom,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec suppression bareme: $e');
      return const Echec('Ce barème n\'a pas pu être supprimé.');
    }
  }

  // ------------------------------------- Rationnement : classes de poids vif

  /// Espèces rationnées en % du poids vif (aujourd'hui : les ovins) — les
  /// seules à qui le tableau « Taux de ration par classe de poids » s'applique.
  static List<({String id, String libelle})> get especesSurPoidsVif => [
    for (final e in EspecesParametrables.toutes)
      if (rationneSurPoidsVif(e.id)) (id: e.id, libelle: e.libelle),
  ];

  static bool rationneSurPoidsVif(String espece) =>
      ConfigurationsEspeces
          .parIdentifiant[espece]
          ?.rationEnPourcentagePoidsVif ??
      false;

  /// Le tableau suit le filtre d'espèce du rationnement ; sans filtre, il
  /// montre toutes les espèces concernées.
  List<TauxRationPoids> get tauxPoidsFiltres => [
    for (final t in _taux)
      if (_especeRation == null || t.espece == _especeRation) t,
  ];

  /// Le tableau n'a de sens que pour une espèce rationnée sur le poids vif : le
  /// montrer pour les goliaths laisserait croire qu'ils en dépendent.
  bool get afficherTauxPoids =>
      _especeRation == null || rationneSurPoidsVif(_especeRation!);

  static double? _nombre(String texte) =>
      double.tryParse(texte.trim().replaceAll(',', '.'));

  Future<Resultat<void>> enregistrerTauxPoids({
    TauxRationPoids? existant,
    required String espece,
    required String poidsMin,
    required String poidsMax,
    required String taux,
    bool valider = false,
  }) async {
    if (!rationneSurPoidsVif(espece)) {
      return const Echec(
        'Cette espèce n\'est pas rationnée sur le poids vif : le tableau ne '
        's\'applique qu\'aux ovins et aux poissons-chats.',
      );
    }
    // Bornes saisies dans l'unite de la filiere (kg pour un ovin, g pour un
    // poisson) ; la base les garde en grammes.
    final unite = ConfigurationsEspeces.parIdentifiant[espece]!;
    final facteur = unite.grammesParUniteClassePoids;
    final minKg = _nombre(poidsMin.isEmpty ? '0' : poidsMin);
    final tauxValeur = _nombre(taux);
    if (minKg == null || minKg < 0 || tauxValeur == null) {
      return const Echec('Veuillez renseigner le poids minimum et le taux.');
    }
    double? maxKg;
    if (poidsMax.trim().isNotEmpty) {
      maxKg = _nombre(poidsMax);
      if (maxKg == null) {
        return Echec(
          'Le poids maximum doit être un nombre de '
          '${unite.uniteClassePoids == 'g' ? 'grammes' : 'kilos'}.',
        );
      }
      if (maxKg <= minKg) {
        return const Echec('Le poids maximum doit dépasser le poids minimum.');
      }
    }
    final tauxMax = unite.tauxPoidsMaxPourcent;
    if (tauxValeur <= 0 || tauxValeur > tauxMax) {
      return Echec(
        'Le taux doit être compris entre 0 et ${tauxMax.toStringAsFixed(0)} % '
        'du poids vif (ou de la biomasse) par jour.',
      );
    }

    final minG = (minKg * facteur).round();
    final maxG = maxKg == null ? null : (maxKg * facteur).round();

    // Deux classes qui se chevauchent donneraient deux taux pour un meme
    // animal : le calcul de provende dependrait de l'ordre d'affichage.
    for (final autre in _taux) {
      if (autre.espece != espece || autre.id == existant?.id) continue;
      final autreMax = autre.poidsMaxG;
      final seChevauchent =
          (autreMax == null || minG < autreMax) &&
          (maxG == null || autre.poidsMinG < maxG);
      if (seChevauchent) {
        return Echec(
          'Cette classe chevauche « ${autre.libelleClasse} » : un animal '
          'aurait deux taux.',
        );
      }
    }

    try {
      await _repository.enregistrerTauxPoids(
        id: existant?.id,
        espece: existant?.espece ?? espece,
        poidsMinG: minG,
        poidsMaxG: maxG,
        tauxPourcent: tauxValeur,
        confirme: existant == null
            ? null
            : statutApresModification(
                confirmeAvant: existant.confirme,
                valeurChangee:
                    minG != existant.poidsMinG ||
                    maxG != existant.poidsMaxG ||
                    tauxValeur != existant.tauxPourcent,
                valider: valider,
              ),
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec taux de ration par poids: $e');
      return const Echec('Cette classe de poids n\'a pas pu être enregistrée.');
    }
  }

  Future<Resultat<void>> supprimerTauxPoids(
    TauxRationPoids taux, {
    AuteurArchivage? auteur,
  }) async {
    try {
      await _repository.supprimerTauxPoids(
        taux.id,
        utilisateurId: auteur?.id,
        utilisateurNom: auteur?.nom,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec suppression taux de ration: $e');
      return const Echec('Cette classe de poids n\'a pas pu être supprimée.');
    }
  }

  // ------------------------------------------------- Onglet 2 : Prophylaxie

  String _especeProphylaxie = EspecesParametrables.toutes.first.id;
  String _rechercheProphylaxie = '';
  String get especeProphylaxie => _especeProphylaxie;
  String get rechercheProphylaxie => _rechercheProphylaxie;

  void changerEspeceProphylaxie(String espece) {
    _especeProphylaxie = espece;
    notifyListeners();
  }

  void definirRechercheProphylaxie(String valeur) {
    _rechercheProphylaxie = valeur;
    notifyListeners();
  }

  List<EcheanceProphylaxie> get echeancesFiltrees {
    final terme = _rechercheProphylaxie.trim().toLowerCase();
    return _echeances.where((e) {
      if (e.espece != _especeProphylaxie) return false;
      if (terme.isEmpty) return true;
      return e.traitement.toLowerCase().contains(terme) ||
          e.produit.toLowerCase().contains(terme);
    }).toList();
  }

  /// Dernier jour du cycle accepte par le calendrier de prophylaxie.
  static const int joursCycleMax = 365;

  Future<Resultat<void>> enregistrerEcheance({
    EcheanceProphylaxie? existante,
    required String jour,
    required String traitement,
    required String produit,
    required String remanence,
    String dose = '',
  }) async {
    final jourCycle = int.tryParse(jour.trim());
    if (jourCycle == null ||
        traitement.trim().isEmpty ||
        produit.trim().isEmpty) {
      return const Echec(
        'Veuillez renseigner le jour, le traitement et le produit.',
      );
    }
    // Le prototype bornait le formulaire a 31 jours, ce qui convient a une
    // volaille mais pas a un ovin : vaccins de rappel a J180 et J365. La
    // borne est portee a une annee.
    if (jourCycle < 1 || jourCycle > joursCycleMax) {
      return const Echec(
        'Le jour du cycle doit être compris entre 1 et $joursCycleMax.',
      );
    }
    final remanenceJours = int.tryParse(remanence.trim()) ?? 0;
    if (remanenceJours < 0) {
      return const Echec('La rémanence ne peut pas être négative.');
    }

    try {
      await _repository.enregistrerEcheance(
        id: existante?.id,
        espece: existante?.espece ?? _especeProphylaxie,
        jourCycle: jourCycle,
        traitement: traitement.trim(),
        produit: produit.trim(),
        remanenceJours: remanenceJours,
        dose: dose.trim().isEmpty ? null : dose.trim(),
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec echeance prophylaxie: $e');
      return const Echec('Cette échéance n\'a pas pu être enregistrée.');
    }
  }

  Future<Resultat<void>> supprimerEcheance(
    EcheanceProphylaxie echeance, {
    AuteurArchivage? auteur,
  }) async {
    try {
      await _repository.supprimerEcheance(
        echeance.id,
        utilisateurId: auteur?.id,
        utilisateurNom: auteur?.nom,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec suppression echeance: $e');
      return const Echec('Cette échéance n\'a pas pu être supprimée.');
    }
  }

  // ---------------------------------------------------- Onglet 3 : Provende

  String _rechercheProvende = '';
  String get rechercheProvende => _rechercheProvende;

  void definirRechercheProvende(String valeur) {
    _rechercheProvende = valeur;
    notifyListeners();
  }

  List<TypeProvende> get provendesFiltrees {
    final terme = _rechercheProvende.trim().toLowerCase();
    if (terme.isEmpty) return _provendes;
    return _provendes
        .where((p) => p.nom.toLowerCase().contains(terme))
        .toList();
  }

  // ------------------------------------------------ Onglet 4 : Numérotation

  /// Aperçu en direct pendant la frappe, **avant** enregistrement — le
  /// prototype recalcule ses aperçus à chaque `oninput`.
  FormatsNumerotation _brouillon = const FormatsNumerotation();
  FormatsNumerotation get brouillon => _brouillon;

  bool get numerotationModifiee =>
      _brouillon.enclos != _formats.enclos ||
      _brouillon.cage != _formats.cage ||
      _brouillon.bande != _formats.bande ||
      _brouillon.bassin != _formats.bassin ||
      _brouillon.bac != _formats.bac ||
      _brouillon.parc != _formats.parc;

  /// Aligne le brouillon sur l'état persisté — appelé à l'ouverture de l'onglet.
  void reinitialiserBrouillon() {
    _brouillon = _formats;
    notifyListeners();
  }

  void modifierBrouillon({
    String? enclos,
    String? cage,
    String? bande,
    String? bassin,
    String? bac,
    String? parc,
  }) {
    _brouillon = _brouillon.copyWith(
      enclos: enclos,
      cage: cage,
      bande: bande,
      bassin: bassin,
      bac: bac,
      parc: parc,
    );
    notifyListeners();
  }

  Future<Resultat<void>> enregistrerNumerotation() async {
    // Un prefixe vide produirait des identifiants « 1, 2, 3 » indistinguables
    // d'une cage a un bassin. Le prototype retombe silencieusement sur sa valeur
    // par defaut ; ici le refus est explicite.
    final vides = <String>[
      if (_brouillon.enclos.trim().isEmpty) 'Enclos',
      if (_brouillon.cage.trim().isEmpty) 'Cage',
      if (_brouillon.bande.trim().isEmpty) 'Bande',
      if (_brouillon.bassin.trim().isEmpty) 'Bassin',
      if (_brouillon.bac.trim().isEmpty) 'Bac',
      if (_brouillon.parc.trim().isEmpty) 'Parc',
    ];
    if (vides.isNotEmpty) {
      return Echec(
        'Préfixe manquant : ${vides.join(', ')}. Un préfixe vide rendrait les '
        'identifiants indistinguables d\'une filière à l\'autre.',
      );
    }

    try {
      final nettoye = FormatsNumerotation(
        enclos: _brouillon.enclos.trim(),
        cage: _brouillon.cage.trim(),
        bande: _brouillon.bande.trim(),
        bassin: _brouillon.bassin.trim(),
        bac: _brouillon.bac.trim(),
        parc: _brouillon.parc.trim(),
      );
      await _repository.enregistrerFormatsNumerotation(nettoye);
      await _rafraichir();
      _brouillon = _formats;
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec numerotation: $e');
      return const Echec(
        'Les formats de numérotation n\'ont pas pu être enregistrés.',
      );
    }
  }
}
