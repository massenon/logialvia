import '../entities/configuration_espece.dart';
import '../entities/cycle_incubation.dart';
import 'calcul_fiche_journaliere.dart';
import 'reperes_zootechniques.dart';

/// Résultat d'un contrôle de vraisemblance.
///
/// - [erreurs] : saisie **impossible** (plus de morts que de sujets, plus d'œufs que de
///   pondeuses…). Elle est refusée : l'enregistrer fausserait toute la chaîne d'effectifs.
/// - [avertissements] : saisie **improbable** mais possible (pesée hors repères, mortalité
///   du jour élevée, ventes supérieures à l'effectif connu…). Affichée en direct, jamais
///   bloquante : l'éleveur sait des choses que la machine ignore.
class ResultatControle {
  const ResultatControle({
    this.erreurs = const [],
    this.avertissements = const [],
  });

  final List<String> erreurs;
  final List<String> avertissements;

  bool get estValide => erreurs.isEmpty;
}

/// Contrôle de vraisemblance d'expert d'une journée de fiche d'élevage (`47e_`).
///
/// Complète `EnregistrerJourneeUseCase.valider` (qui ne refuse que le négatif) : les
/// règles ci-dessous demandent l'effectif de la veille et les repères de la filière.
/// Les messages sont en français et disent quoi faire.
class ControleVraisemblance {
  const ControleVraisemblance(this.configuration);

  final ConfigurationEspece configuration;

  /// Entier sans séparateur de milliers ; décimale à la virgule (même rendu qu'au web).
  String _fmt(num v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',');

  ResultatControle controlerJournee({
    required List<int> effectifsVeille,
    required MouvementsJour mouvements,
    required EffectifsJour effectifsDuJour,
    int effectifTotalVeille = 0,
    int? poidsTotalGrammes,
    int? oeufsPondus,
    int? oeufsCasses,
    int? sortiesPlateaux,
    int stockOeufsDisponible = 0,
  }) {
    final erreurs = <String>[];
    final avertissements = <String>[];
    final categories = configuration.categories;

    // --- Impossible : plus de morts et de dons que de sujets dans la catégorie.
    for (var i = 0; i < categories.length; i++) {
      final categorie = categories[i];
      final veille = i < effectifsVeille.length ? effectifsVeille[i] : 0;
      final entrees = categorie.recoitAchatEtNaissances
          ? mouvements.achat + mouvements.ne
          : 0;
      final disponible = veille + entrees;
      final retires =
          mouvements.mortsCategorie(i) + mouvements.donsCategorie(i);
      if (retires > disponible) {
        erreurs.add(
          'Morts et dons de « ${categorie.libelle} » (${_fmt(retires)}) : '
          'supérieurs à l\'effectif disponible (${_fmt(disponible)}). '
          'Saisissez d\'abord les entrées (achats, naissances) ou corrigez la '
          'mortalité.',
        );
      }
      // --- Improbable : ventes au-delà de la catégorie commercialisée.
      if (categorie.deduiteDesVentes) {
        final apresRetraits = disponible - retires;
        if (mouvements.vente > apresRetraits && mouvements.vente > 0) {
          avertissements.add(
            'Les ventes du jour (${_fmt(mouvements.vente)}) dépassent l\'effectif '
            'de « ${categorie.libelle} » (${_fmt(apresRetraits < 0 ? 0 : apresRetraits)}) : '
            'la fiche sera ramenée à 0. Vérifiez les entrées déjà saisies.',
          );
        }
      }
    }

    // --- Impossible : plus d'œufs que de pondeuses (une poule pond au plus un œuf/jour).
    if (oeufsPondus != null && oeufsPondus > 0) {
      final indexPondeuse = configuration.indexCategorieCommercialisee;
      final pondeuses =
          indexPondeuse >= 0 && indexPondeuse < effectifsVeille.length
          ? effectifsVeille[indexPondeuse]
          : 0;
      if (pondeuses > 0) {
        if (oeufsPondus > pondeuses) {
          erreurs.add(
            'Les œufs pondus (${_fmt(oeufsPondus)}) dépassent le nombre de '
            'pondeuses (${_fmt(pondeuses)}) : une poule pond au plus un œuf par '
            'jour.',
          );
        } else {
          final taux = oeufsPondus / pondeuses * 100;
          if (taux > ReperesZootechniques.tauxPonteExceptionnel) {
            avertissements.add(
              'Taux de ponte de ${_fmt(double.parse(taux.toStringAsFixed(1)))} % : '
              'au-delà de ${_fmt(ReperesZootechniques.tauxPonteExceptionnel)} % '
              'c\'est exceptionnel. Vérifiez le décompte des œufs.',
            );
          }
        }
      }
      if (oeufsCasses != null && oeufsCasses <= oeufsPondus) {
        final part = oeufsCasses / oeufsPondus * 100;
        if (part > ReperesZootechniques.partOeufsCassesAVerifier) {
          avertissements.add(
            'Œufs cassés : ${_fmt(double.parse(part.toStringAsFixed(1)))} % des '
            'œufs pondus (un élevage maîtrisé reste sous '
            '${_fmt(ReperesZootechniques.partOeufsCassesAVerifier / 2)} %). '
            'Vérifiez les pondoirs et la collecte.',
          );
        }
      }
    }
    if (sortiesPlateaux != null &&
        sortiesPlateaux * CalculStockOeufs.oeufsParPlateau >
            stockOeufsDisponible &&
        sortiesPlateaux > 0) {
      avertissements.add(
        'Les sorties (${_fmt(sortiesPlateaux * CalculStockOeufs.oeufsParPlateau)} '
        'œufs) dépassent le stock disponible (${_fmt(stockOeufsDisponible)}) : '
        'le stock final sera ramené à 0.',
      );
    }

    // --- Improbable : pesée hors repères.
    if (poidsTotalGrammes != null && poidsTotalGrammes > 0) {
      final effectif = effectifsDuJour.effectifTotal;
      if (effectif <= 0) {
        avertissements.add(
          'Une pesée est saisie alors qu\'aucun sujet vivant n\'est comptabilisé.',
        );
      } else {
        final moyen = poidsTotalGrammes / effectif;
        final repere = ReperesZootechniques.poidsMoyenPlausibleG(
          configuration.identifiant,
        );
        if (moyen < repere.min || moyen > repere.max) {
          avertissements.add(
            'Poids moyen de ${_fmt(moyen.round())} g par sujet : hors des '
            'repères ${configuration.libelle} (${_fmt(repere.min)} à '
            '${_fmt(repere.max)} g). Vérifiez l\'unité (la pesée se saisit en '
            'grammes) et l\'effectif.',
          );
        }
      }
    }

    // --- Mortalité du jour (DV-13).
    if (effectifTotalVeille > 0 && mouvements.totalMorts > 0) {
      final taux = mouvements.totalMorts / effectifTotalVeille * 100;
      final affiche = _fmt(double.parse(taux.toStringAsFixed(1)));
      switch (ReperesZootechniques.niveauMortaliteJour(taux)) {
        case NiveauAlerte.critique:
          avertissements.add(
            'Mortalité du jour de $affiche % : seuil critique '
            '(${_fmt(ReperesZootechniques.mortaliteJourCritique)} %) dépassé. '
            'Isolez les sujets malades et prévenez le vétérinaire.',
          );
        case NiveauAlerte.avertissement:
          avertissements.add(
            'Mortalité du jour de $affiche % : au-dessus du seuil '
            'd\'avertissement (${_fmt(ReperesZootechniques.mortaliteJourAvertissement)} %).',
          );
        case NiveauAlerte.normal:
          break;
      }
    }

    return ResultatControle(erreurs: erreurs, avertissements: avertissements);
  }
}

/// Contrôles d'expert de la couveuse (`47e_`) : un mirage ou une éclosion saisis à une
/// date où ils ne peuvent pas avoir eu lieu sont refusés avec un message qui dit pourquoi.
class ControleVraisemblanceCouveuse {
  const ControleVraisemblanceCouveuse._();

  /// Message de refus d'un mirage prématuré, `null` s'il est possible. Le mirage à J+7
  /// ne distingue rien avant J+5, celui de J+14 avant J+12.
  static String? erreurMirage({
    required CycleIncubation lot,
    required int jour,
    required DateTime date,
  }) {
    final age = lot.ageJours(date);
    final minimum = jour == EspeceCouvable.jourMirage1
        ? ReperesZootechniques.mirage1AuPlusTot
        : ReperesZootechniques.mirage2AuPlusTot;
    if (age >= minimum) return null;
    return 'Le mirage à J+$jour ne peut pas se faire avant J+$minimum : ce lot '
        "n'a que $age jour${age > 1 ? 's' : ''} d'incubation.";
  }

  /// Message de refus d'une éclosion prématurée, `null` si elle est possible. Une
  /// éclosion plus de 4 jours avant le terme de l'espèce (21 j la poule, 28 j la pintade)
  /// n'existe pas : c'est une erreur de lot ou de date.
  static String? erreurEclosion({
    required CycleIncubation lot,
    required DateTime date,
  }) {
    final age = lot.ageJours(date);
    final duree = lot.espece.dureeIncubationJours;
    final premiere = duree - ReperesZootechniques.eclosionAvanceMaximaleJours;
    if (age >= premiere) return null;
    return "Éclosion impossible : ce lot n'a que $age jour${age > 1 ? 's' : ''} "
        "d'incubation, ${lot.espece.libelle} incube $duree jours (éclosion "
        'possible à partir de J+$premiere).';
  }
}
