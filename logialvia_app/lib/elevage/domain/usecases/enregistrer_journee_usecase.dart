import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../entities/configuration_espece.dart';
import '../entities/journee_elevage.dart';
import '../repositories/fiche_elevage_repository.dart';
import '../services/calcul_fiche_journaliere.dart';

/// Saisies du suivi du stock d'œufs — Pondeuses uniquement (Doc H2).
class SaisieStockOeufs {
  const SaisieStockOeufs({
    this.oeufsPondus = 0,
    this.oeufsCasses = 0,
    this.sortiesPlateaux = 0,
  });

  final int oeufsPondus;
  final int oeufsCasses;

  /// En plateaux de 30 œufs.
  final int sortiesPlateaux;
}

/// Enregistre une journée de fiche d'élevage, puis propage la cascade.
///
/// ## Invariants garantis ici, pas dans l'UI (Doc C1 §3)
/// - Aucun effectif ne peut devenir négatif (BR-ELV-001) — assuré par le
///   `clamp` de [CalculFicheJournaliere].
/// - `effectif` et les sous-effectifs sont **toujours recalculés**, jamais
///   repris de la saisie (BR-ELV-007, Doc 05 §6).
/// - Toute modification d'un jour passé recalcule les jours suivants déjà
///   saisis (Doc 05 §5) — sinon leur base de départ (J-1) devient fausse
///   silencieusement.
class EnregistrerJourneeUseCase {
  const EnregistrerJourneeUseCase(this._repository, this._configuration);

  final FicheElevageRepository _repository;
  final ConfigurationEspece _configuration;

  Future<Resultat<JourneeElevage>> executer({
    required DateTime date,
    required MouvementsJour mouvements,
    int? poidsGeneralG,
    String? traitementObs,
    bool traitementValide = false,
    SaisieStockOeufs? stockOeufs,
  }) async {
    // Validation AVANT tout calcul (Doc E6 §3) : calculer sur des valeurs
    // invalides produirait un effectif incohérent, sans erreur visible.
    final erreurs = valider(mouvements, stockOeufs: stockOeufs);
    if (erreurs.isNotEmpty) return Echec(erreurs.first);

    try {
      final calcul = CalculFicheJournaliere(_configuration);
      final espece = _configuration.identifiant;

      final veille = await _repository.chargerJourneePrecedente(
        espece: espece,
        date: date,
      );
      final effectifsVeille =
          veille?.effectifsParCategorie ??
          calcul.repartitionInitiale(0);

      final effectifs = calcul.calculerJour(
        effectifsVeille: effectifsVeille,
        effectifTotalVeille: veille?.effectif ?? 0,
        mouvements: mouvements,
      );

      // Suivi du stock d'oeufs (Pondeuses) — Doc 05 §4, Doc H2.
      // ⚠️ Le SRH d'ouverture est le **Stock Final** de la veille, jamais son
      // Total Stock. Il est capture ici, avant tout calcul.
      ResultatStockOeufs? oeufs;
      if (stockOeufs != null) {
        oeufs = CalculStockOeufs.calculerJour(
          srhOuverture: veille?.stockFinalOeufs ?? 0,
          oeufsPondus: stockOeufs.oeufsPondus,
          oeufsCasses: stockOeufs.oeufsCasses,
          sortiesPlateaux: stockOeufs.sortiesPlateaux,
        );
      }

      final journee = JourneeElevage(
        espece: espece,
        date: date,
        achat: mouvements.achat,
        ne: mouvements.ne,
        vente: mouvements.vente,
        mortsParCategorie: mouvements.mortsParCategorie,
        donsParCategorie: mouvements.donsParCategorie,
        effectif: effectifs.effectifTotal,
        effectifsParCategorie: effectifs.parCategorie,
        isRecorded: true,
        poidsGeneralG: poidsGeneralG,
        traitementObs: traitementObs,
        traitementValide: traitementValide,
        srh: oeufs?.srh,
        totalStock: oeufs?.totalStock,
        stockFinalOeufs: oeufs?.stockFinal,
        oeufsPondus: stockOeufs?.oeufsPondus,
        oeufsCasses: stockOeufs?.oeufsCasses,
        sortiesPlateaux: stockOeufs?.sortiesPlateaux,
      );

      await _repository.enregistrerJour(journee);
      await _recalculerCascade(date);

      return Succes(journee);
    } catch (e, pile) {
      // Un `catch` muet a reellement masque ici une violation de contrainte
      // `UNIQUE(espece, date)` : l'enregistrement echouait en silence et
      // l'ecran affichait l'ancienne valeur sans erreur. Le message utilisateur
      // reste generique (Doc I3 §3), mais le detail technique est visible en
      // developpement — sans quoi ce genre de bug redevient invisible.
      if (kDebugMode) {
        debugPrint('Echec enregistrement journee elevage: $e\n$pile');
      }
      return const Echec(
        'Impossible d\'enregistrer la saisie du jour. Réessayez.',
      );
    }
  }

  /// Doc 05 §5 — recalcule les jours suivants déjà saisis, en s'arrêtant au
  /// premier jour non saisi.
  Future<void> _recalculerCascade(DateTime depuis) async {
    final calcul = CalculFicheJournaliere(_configuration);
    final espece = _configuration.identifiant;

    final suivantes = await _repository.chargerJourneesSuivantes(
      espece: espece,
      date: depuis,
    );

    var precedente = await _repository.chargerJour(
      espece: espece,
      date: depuis,
    );

    for (final journee in suivantes) {
      if (precedente == null) break;

      final effectifs = calcul.calculerJour(
        effectifsVeille: precedente.effectifsParCategorie,
        effectifTotalVeille: precedente.effectif,
        mouvements: MouvementsJour(
          achat: journee.achat,
          ne: journee.ne,
          vente: journee.vente,
          mortsParCategorie: journee.mortsParCategorie,
          donsParCategorie: journee.donsParCategorie,
        ),
      );

      // ⚠️ Doc 05 §5, point de vigilance n°2 : « Pour Pondeuses, cette même
      // cascade doit EN PLUS recalculer SRH/TS/Stock Final, pas seulement les
      // sous-effectifs. » Recalculer les seuls effectifs laisserait le stock
      // d'oeufs des jours suivants figé sur l'ancien SRH — une incohérence
      // parfaitement silencieuse, exactement le bug historique du projet.
      ResultatStockOeufs? oeufsRecalcules;
      if (journee.oeufsPondus != null ||
          journee.oeufsCasses != null ||
          journee.sortiesPlateaux != null) {
        oeufsRecalcules = CalculStockOeufs.calculerJour(
          srhOuverture: precedente.stockFinalOeufs ?? 0,
          oeufsPondus: journee.oeufsPondus ?? 0,
          oeufsCasses: journee.oeufsCasses ?? 0,
          sortiesPlateaux: journee.sortiesPlateaux ?? 0,
        );
      }

      final recalculee = journee.copyWith(
        effectif: effectifs.effectifTotal,
        effectifsParCategorie: effectifs.parCategorie,
        srh: oeufsRecalcules?.srh,
        totalStock: oeufsRecalcules?.totalStock,
        stockFinalOeufs: oeufsRecalcules?.stockFinal,
      );
      await _repository.enregistrerJour(recalculee);
      precedente = recalculee;
    }
  }

  /// Validations du formulaire journalier — Doc E6 §3 et Doc H2.
  List<String> valider(
    MouvementsJour mouvements, {
    SaisieStockOeufs? stockOeufs,
  }) {
    final erreurs = <String>[];

    if (stockOeufs != null) {
      if (stockOeufs.oeufsPondus < 0) {
        erreurs.add('Les œufs pondus ne peuvent être négatifs.');
      }
      if (stockOeufs.oeufsCasses < 0) {
        erreurs.add('Les œufs cassés ne peuvent être négatifs.');
      }
      // Doc H2 : « Œufs Cassés : ≥ 0, ≤ Œufs Pondus ».
      if (stockOeufs.oeufsCasses > stockOeufs.oeufsPondus) {
        erreurs.add(
          'Les œufs cassés (${stockOeufs.oeufsCasses}) ne peuvent dépasser '
          'les œufs pondus (${stockOeufs.oeufsPondus}).',
        );
      }
      if (stockOeufs.sortiesPlateaux < 0) {
        erreurs.add('Les sorties ne peuvent être négatives.');
      }
    }

    if (mouvements.achat < 0 || mouvements.ne < 0 || mouvements.vente < 0) {
      erreurs.add('Les mouvements ne peuvent être négatifs.');
    }
    for (var i = 0; i < mouvements.mortsParCategorie.length; i++) {
      if (mouvements.mortsParCategorie[i] < 0) {
        erreurs.add(
          'Mortalité ${_configuration.categories[i].libelle} invalide.',
        );
      }
    }
    for (var i = 0; i < mouvements.donsParCategorie.length; i++) {
      if (mouvements.donsParCategorie[i] < 0) {
        erreurs.add('Dons ${_configuration.categories[i].libelle} invalide.');
      }
    }
    return erreurs;
  }
}
