import '../../../core/resultat/resultat.dart';
import '../entities/configuration_espece.dart';
import '../entities/journee_elevage.dart';
import '../repositories/fiche_elevage_repository.dart';
import '../services/calcul_fiche_journaliere.dart';
import 'enregistrer_journee_usecase.dart';

/// Un jour dont l'effectif enregistré ne découle pas de la veille.
class JourIncoherent {
  const JourIncoherent({
    required this.date,
    required this.effectifEnregistre,
    required this.effectifAttendu,
  });

  final DateTime date;
  final int effectifEnregistre;
  final int effectifAttendu;
}

/// Compte rendu d'un recalcul de chaîne.
class RapportChaine {
  const RapportChaine({
    required this.joursVerifies,
    required this.joursCorriges,
  });

  final int joursVerifies;

  /// Dates des jours réécrits (ceux dont une valeur calculée a changé).
  final List<DateTime> joursCorriges;

  bool get etaitCoherente => joursCorriges.isEmpty;
}

/// Chaîne d'effectifs d'une filière (`47e_`, décision D2 de `46a_`).
///
/// « Effectif du jour = veille + entrées − sorties », jour après jour dans l'ordre
/// chronologique. Quand une fiche d'un autre poste arrive, elle n'est PAS recalculée en
/// cascade (règle d'or : aucun effet de bord à l'absorption) ; la chaîne peut alors être
/// incohérente. Ce cas d'usage la **vérifie** (lecture seule) et la **recalcule** sur
/// demande (bouton « Recalculer la chaîne »).
///
/// Contrairement à la cascade automatique, qui s'arrête au premier jour non saisi, la
/// chaîne enchaîne les jours SAISIS : un jour non saisi laisse l'effectif de la dernière
/// fiche (même règle que `chargerJourneePrecedente` à la saisie).
class ChaineEffectifsUseCase {
  const ChaineEffectifsUseCase(this._repository, this._configuration);

  final FicheElevageRepository _repository;
  final ConfigurationEspece _configuration;

  /// Jours dont l'effectif (total ou par catégorie) ou le stock d'œufs ne découle pas de
  /// la veille. Ne modifie rien.
  Future<List<JourIncoherent>> verifier() async {
    final plan = await _calculer();
    return [
      for (final p in plan)
        if (p.corrige)
          JourIncoherent(
            date: p.original.date,
            effectifEnregistre: p.original.effectif,
            effectifAttendu: p.recalculee.effectif,
          ),
    ];
  }

  /// Réécrit, dans l'ordre, les seuls jours dont une valeur calculée change : réécrire un
  /// jour identique le daterait de maintenant et le ferait gagner contre une saisie d'un
  /// autre poste sans raison.
  Future<Resultat<RapportChaine>> recalculer() async {
    try {
      final plan = await _calculer();
      final corriges = <DateTime>[];
      for (final p in plan) {
        if (!p.corrige) continue;
        await _repository.enregistrerJour(p.recalculee);
        corriges.add(p.original.date);
      }
      return Succes(
        RapportChaine(joursVerifies: plan.length, joursCorriges: corriges),
      );
    } catch (_) {
      return const Echec('Impossible de recalculer la chaîne des effectifs.');
    }
  }

  Future<
    List<({JourneeElevage original, JourneeElevage recalculee, bool corrige})>
  >
  _calculer() async {
    final calcul = CalculFicheJournaliere(_configuration);
    final jours = await _repository.chargerJoursSaisis(
      _configuration.identifiant,
    );
    final plan =
        <
          ({JourneeElevage original, JourneeElevage recalculee, bool corrige})
        >[];
    JourneeElevage? precedente;
    for (final jour in jours) {
      final effectifs = calcul.calculerJour(
        effectifsVeille:
            precedente?.effectifsParCategorie ?? calcul.repartitionInitiale(0),
        effectifTotalVeille: precedente?.effectif ?? 0,
        mouvements: MouvementsJour(
          achat: jour.achat,
          ne: jour.ne,
          vente: jour.vente,
          mortsParCategorie: jour.mortsParCategorie,
          donsParCategorie: jour.donsParCategorie,
        ),
      );
      ResultatStockOeufs? oeufs;
      if (jour.oeufsPondus != null ||
          jour.oeufsCasses != null ||
          jour.sortiesPlateaux != null) {
        oeufs = CalculStockOeufs.calculerJour(
          srhOuverture: precedente?.stockFinalOeufs ?? 0,
          oeufsPondus: jour.oeufsPondus ?? 0,
          oeufsCasses: jour.oeufsCasses ?? 0,
          sortiesPlateaux: jour.sortiesPlateaux ?? 0,
        );
      }
      final recalculee = jour.copyWith(
        effectif: effectifs.effectifTotal,
        effectifsParCategorie: effectifs.parCategorie,
        srh: oeufs?.srh,
        totalStock: oeufs?.totalStock,
        stockFinalOeufs: oeufs?.stockFinal,
      );
      final corrige =
          recalculee.effectif != jour.effectif ||
          !_memeListe(
            recalculee.effectifsParCategorie,
            jour.effectifsParCategorie,
          ) ||
          (oeufs != null &&
              (recalculee.srh != jour.srh ||
                  recalculee.totalStock != jour.totalStock ||
                  recalculee.stockFinalOeufs != jour.stockFinalOeufs));
      plan.add((original: jour, recalculee: recalculee, corrige: corrige));
      precedente = recalculee;
    }
    return plan;
  }

  static bool _memeListe(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Résout une fiche « modifiée ailleurs » : l'utilisatrice choisit la version à garder,
/// jamais la machine (`47e_`).
class ResoudreDivergenceUseCase {
  const ResoudreDivergenceUseCase(this._repository, this._configuration);

  final FicheElevageRepository _repository;
  final ConfigurationEspece _configuration;

  /// Garde [choisie] : si c'est la version courante, la fiche est simplement confirmée ;
  /// sinon la version choisie est saisie de nouveau (effectifs recalculés à partir de la
  /// veille de CE poste, cascade comprise). Dans les deux cas la fiche repart avec
  /// l'indication « résolue » qui efface les variantes partout.
  Future<Resultat<void>> executer({
    required DateTime date,
    required VersionJournee choisie,
  }) async {
    final espece = _configuration.identifiant;
    final versions = await _repository.versionsEnDivergence(
      espece: espece,
      date: date,
    );
    if (versions.isEmpty) {
      return const Echec("Cette fiche n'a pas de divergence à résoudre.");
    }
    if (!choisie.estCourante) {
      final j = choisie.journee;
      final saisie =
          await EnregistrerJourneeUseCase(_repository, _configuration).executer(
            date: date,
            mouvements: MouvementsJour(
              achat: j.achat,
              ne: j.ne,
              vente: await _repository.venteDuJour(espece: espece, date: date),
              mortsParCategorie: j.mortsParCategorie,
              donsParCategorie: j.donsParCategorie,
            ),
            poidsGeneralG: j.poidsGeneralG,
            traitementObs: j.traitementObs,
            traitementValide: j.traitementValide,
            stockOeufs: _configuration.identifiant == 'pondeuses'
                ? SaisieStockOeufs(
                    oeufsPondus: j.oeufsPondus ?? 0,
                    oeufsCasses: j.oeufsCasses ?? 0,
                    sortiesPlateaux: j.sortiesPlateaux ?? 0,
                  )
                : null,
            // Le choix est celui de l'utilisatrice : on ne le re-juge pas.
            controlerVraisemblance: false,
          );
      if (saisie is Echec<JourneeElevage>) return Echec(saisie.message);
    }
    await _repository.marquerDivergenceResolue(espece: espece, date: date);
    return const Succes(null);
  }
}
