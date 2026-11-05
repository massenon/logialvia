import '../../../core/resultat/resultat.dart';
import '../entities/configuration_espece.dart';
import '../entities/journee_elevage.dart';
import '../repositories/fiche_elevage_repository.dart';
import '../services/calcul_fiche_journaliere.dart';
import 'enregistrer_journee_usecase.dart';

/// Porte un deces d'infirmerie dans la fiche d'elevage de la filiere.
///
/// ## Pourquoi un cas d'usage, et non un `UPDATE` sur `FICHE_JOURNEE`
///
/// Incrementer directement `mortCatN` laisserait `effectif` et les
/// sous-effectifs du jour — et de **tous** les jours saisis ensuite —
/// inchanges. C'est exactement le bug cardinal du projet (Doc 05 §5) : une
/// incoherence silencieuse, qu'aucun ecran ne signale.
///
/// Le report passe donc par [EnregistrerJourneeUseCase], qui recalcule les
/// effectifs et propage la cascade. Le deces est ajoute aux mouvements deja
/// saisis du jour, jamais substitue a eux.
///
/// La journee est creee si elle n'existe pas : un deces survenu un jour non
/// encore saisi doit compter malgre tout. Elle est alors marquee comme saisie
/// — sans quoi la cascade s'arreterait sur elle et l'effectif resterait faux.
/// L'animalier retrouvera la perte deja renseignee en ouvrant sa fiche, ce qui
/// est aussi ce qui empeche le double comptage.
class ReporterDecesInfirmerieUseCase {
  const ReporterDecesInfirmerieUseCase(this._fabriqueDepot);

  /// Le depot de fiche est lie a une filiere (il traduit des listes indexees
  /// en colonnes fixes) : ce cas d'usage en traverse plusieurs, il recoit donc
  /// une fabrique. Voir `fabriqueFicheElevage`.
  final FicheElevageRepository Function(ConfigurationEspece) _fabriqueDepot;

  Future<Resultat<void>> executer({
    required String espece,
    required int indexCategorie,
    required DateTime date,
  }) async {
    final configuration = ConfigurationsEspeces.parIdentifiant[espece];
    if (configuration == null) {
      return const Echec(
        "Filiere inconnue : le deces n'a pas pu etre porte sur une fiche.",
      );
    }
    final nombre = configuration.nombreCategories;
    if (indexCategorie < 0 || indexCategorie >= nombre) {
      return const Echec(
        "Categorie d'effectif inconnue pour cette filiere.",
      );
    }

    final depot = _fabriqueDepot(configuration);
    final jour = DateTime(date.year, date.month, date.day);
    final existante = await depot.chargerJour(espece: espece, date: jour);

    final morts = _aLaTaille(existante?.mortsParCategorie, nombre);
    morts[indexCategorie] += 1;

    final resultat = await EnregistrerJourneeUseCase(depot, configuration)
        .executer(
          date: jour,
          mouvements: MouvementsJour(
            achat: existante?.achat ?? 0,
            ne: existante?.ne ?? 0,
            // Les ventes viennent du POS, jamais de la fiche (BR-ELV-005) :
            // les relire evite qu'un report de deces les remette a zero sur
            // une journee pas encore saisie.
            vente: await depot.venteDuJour(espece: espece, date: jour),
            mortsParCategorie: morts,
            donsParCategorie: _aLaTaille(existante?.donsParCategorie, nombre),
          ),
          poidsGeneralG: existante?.poidsGeneralG,
          traitementObs: existante?.traitementObs,
          traitementValide: existante?.traitementValide ?? false,
          stockOeufs: configuration.identifiant == 'pondeuses'
              ? SaisieStockOeufs(
                  oeufsPondus: existante?.oeufsPondus ?? 0,
                  oeufsCasses: existante?.oeufsCasses ?? 0,
                  sortiesPlateaux: existante?.sortiesPlateaux ?? 0,
                )
              : null,
        );

    return switch (resultat) {
      Succes<JourneeElevage>() => const Succes<void>(null),
      Echec<JourneeElevage>(message: final message) => Echec<void>(message),
    };
  }

  /// Recopie une liste de mouvements a la taille attendue par la filiere.
  static List<int> _aLaTaille(List<int>? valeurs, int taille) => [
    for (var i = 0; i < taille; i++)
      valeurs != null && i < valeurs.length ? valeurs[i] : 0,
  ];
}
