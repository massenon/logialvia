import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../domain/entities/configuration_espece.dart';
import '../../domain/entities/journee_elevage.dart';
import '../../domain/repositories/fiche_elevage_repository.dart';
import '../sync/identifiants_elevage.dart';

/// Implementation Drift du depot des fiches d'elevage.
///
/// `FICHE_JOURNEE` stocke les categories dans des colonnes fixes
/// (`mortCat1..4`, `effCat1..4Day`), la ou le domaine manipule des listes
/// indexees. La conversion se fait ici, dans la couche `data/` — le domaine
/// n'a pas a connaitre cette contrainte de schema.
class FicheElevageRepositoryDrift implements FicheElevageRepository {
  const FicheElevageRepositoryDrift(this._db, this._configuration);

  final AppDatabase _db;
  final ConfigurationEspece _configuration;

  int get _nombreCategories => _configuration.nombreCategories;

  @override
  Future<List<JourneeElevage>> chargerMois({
    required String espece,
    required int annee,
    required int mois,
  }) async {
    final debut = DateTime(annee, mois);
    final fin = DateTime(annee, mois + 1).subtract(const Duration(days: 1));

    final lignes =
        await (_db.select(_db.ficheJournee)
              ..where(
                (f) =>
                    f.espece.equals(espece) &
                    f.date.isBiggerOrEqualValue(debut) &
                    f.date.isSmallerOrEqualValue(fin),
              )
              ..orderBy([(f) => OrderingTerm.asc(f.date)]))
            .get();

    return lignes.map(_versDomaine).toList();
  }

  @override
  Future<JourneeElevage?> chargerJour({
    required String espece,
    required DateTime date,
  }) async {
    final ligne =
        await (_db.select(_db.ficheJournee)..where(
              (f) => f.espece.equals(espece) & f.date.equals(_minuit(date)),
            ))
            .getSingleOrNull();
    return ligne == null ? null : _versDomaine(ligne);
  }

  @override
  Future<JourneeElevage?> chargerJourneePrecedente({
    required String espece,
    required DateTime date,
  }) async {
    final ligne =
        await (_db.select(_db.ficheJournee)
              ..where(
                (f) =>
                    f.espece.equals(espece) &
                    f.isRecorded.equals(true) &
                    f.date.isSmallerThanValue(_minuit(date)),
              )
              ..orderBy([(f) => OrderingTerm.desc(f.date)])
              ..limit(1))
            .getSingleOrNull();
    return ligne == null ? null : _versDomaine(ligne);
  }

  @override
  Future<List<JourneeElevage>> chargerJourneesSuivantes({
    required String espece,
    required DateTime date,
  }) async {
    final lignes =
        await (_db.select(_db.ficheJournee)
              ..where(
                (f) =>
                    f.espece.equals(espece) &
                    f.date.isBiggerThanValue(_minuit(date)),
              )
              ..orderBy([(f) => OrderingTerm.asc(f.date)]))
            .get();

    // La cascade s'arrete au premier jour non saisi (Doc 05 §5) : au-dela, la
    // continuite est rompue et rien ne doit etre recalcule.
    final resultat = <JourneeElevage>[];
    for (final ligne in lignes) {
      if (!ligne.isRecorded) break;
      resultat.add(_versDomaine(ligne));
    }
    return resultat;
  }

  @override
  Future<void> enregistrerJour(JourneeElevage journee) async {
    final morts = _remplir(journee.mortsParCategorie);
    final effectifs = _remplir(journee.effectifsParCategorie);
    final dons = _remplir(journee.donsParCategorie);

    // PIEGE DRIFT RENCONTRE ET CORRIGE : `insertOnConflictUpdate()` cible la
    // **cle primaire**, ici `id` auto-incremente — qui n'entre donc jamais en
    // conflit. La contrainte reellement pertinente est `UNIQUE(espece, date)`
    // (Doc D1), et chaque reenregistrement d'un meme jour creait une violation
    // au lieu d'une mise a jour. Le `target` doit etre explicite.
    final companion = FicheJourneeCompanion.insert(
      // UUID deterministe de (espece, date) : deux postes qui saisissent le meme
      // jour convergent sur la meme ligne (`46a_`).
      id: Value(identifiantFicheJournee(journee.espece, journee.date)),
      espece: journee.espece,
      date: _minuit(journee.date),
      achat: Value(journee.achat),
      ne: Value(journee.ne),
      vente: Value(journee.vente),
      mortCat1: Value(morts[0]),
      mortCat2: Value(morts[1]),
      mortCat3: Value(morts[2]),
      mortCat4: Value(_nombreCategories > 3 ? morts[3] : null),
      donCat1: Value(dons[0]),
      donCat2: Value(dons[1]),
      donCat3: Value(dons[2]),
      donCat4: Value(_nombreCategories > 3 ? dons[3] : null),
      effectif: Value(journee.effectif),
      effCat1Day: Value(effectifs[0]),
      effCat2Day: Value(effectifs[1]),
      effCat3Day: Value(effectifs[2]),
      effCat4Day: Value(_nombreCategories > 3 ? effectifs[3] : null),
      srh: Value(journee.srh),
      ts: Value(journee.totalStock),
      stockFinalOeufs: Value(journee.stockFinalOeufs),
      oeufsPondus: Value(journee.oeufsPondus),
      oeufsCasses: Value(journee.oeufsCasses),
      sortiesPlateaux: Value(journee.sortiesPlateaux),
      poidsGeneralG: Value(journee.poidsGeneralG),
      traitementObs: Value(journee.traitementObs),
      traitementValide: Value(journee.traitementValide),
      isRecorded: Value(journee.isRecorded),
      // Toute ecriture locale (saisie, cascade) remet la ligne a envoyer, avec son
      // instant de SAISIE : c'est lui qui departage deux postes (`46_` §1).
      syncStatus: const Value('pending'),
      syncMotif: const Value(null),
      updatedAt: Value(instantSaisie()),
    );

    await _db
        .into(_db.ficheJournee)
        .insert(
          companion,
          onConflict: DoUpdate(
            (_) => companion,
            target: [_db.ficheJournee.espece, _db.ficheJournee.date],
          ),
        );
  }

  /// Ventes du jour : la **somme** des compteurs de tous les postes (le mien et
  /// ceux des autres, `46a_`). Chaque poste ne tient que son propre compteur ; rien
  /// n'est compte deux fois puisque la vente d'un autre poste n'incremente jamais
  /// le mien.
  @override
  Future<int> venteDuJour({
    required String espece,
    required DateTime date,
  }) async {
    final lignes =
        await (_db.select(_db.ficheVentesJour)..where(
              (f) => f.espece.equals(espece) & f.date.equals(_minuit(date)),
            ))
            .get();
    return lignes.fold<int>(0, (somme, l) => somme + l.qte);
  }

  // ---------------------------------------------------------------- internes

  JourneeElevage _versDomaine(FicheJourneeRow ligne) {
    List<int> extraire(int c1, int c2, int c3, int? c4) => [
      c1,
      c2,
      c3,
      if (_nombreCategories > 3) c4 ?? 0,
    ];

    return JourneeElevage(
      espece: ligne.espece,
      date: ligne.date,
      achat: ligne.achat,
      ne: ligne.ne,
      vente: ligne.vente,
      mortsParCategorie: extraire(
        ligne.mortCat1,
        ligne.mortCat2,
        ligne.mortCat3,
        ligne.mortCat4,
      ),
      donsParCategorie: extraire(
        ligne.donCat1,
        ligne.donCat2,
        ligne.donCat3,
        ligne.donCat4,
      ),
      effectif: ligne.effectif,
      effectifsParCategorie: extraire(
        ligne.effCat1Day,
        ligne.effCat2Day,
        ligne.effCat3Day,
        ligne.effCat4Day,
      ),
      isRecorded: ligne.isRecorded,
      poidsGeneralG: ligne.poidsGeneralG,
      traitementObs: ligne.traitementObs,
      traitementValide: ligne.traitementValide,
      srh: ligne.srh,
      totalStock: ligne.ts,
      stockFinalOeufs: ligne.stockFinalOeufs,
      oeufsPondus: ligne.oeufsPondus,
      oeufsCasses: ligne.oeufsCasses,
      sortiesPlateaux: ligne.sortiesPlateaux,
    );
  }

  /// Complete a 4 elements, pour alimenter les colonnes fixes du schema.
  List<int> _remplir(List<int> valeurs) => [
    for (var i = 0; i < 4; i++) i < valeurs.length ? valeurs[i] : 0,
  ];

  /// Les dates sont normalisees a minuit : `UNIQUE(espece, date)` ne doit pas
  /// distinguer deux saisies du meme jour a des heures differentes.
  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Fabrique un depot de fiche pour la filiere demandee.
///
/// [FicheElevageRepositoryDrift] est lie a une [ConfigurationEspece] : il lui
/// faut le nombre de categories pour traduire les listes du domaine en
/// colonnes fixes. Les cas d'usage qui traversent plusieurs filieres — le
/// report d'un deces d'infirmerie, par exemple — recoivent donc cette fabrique
/// plutot qu'un depot deja lie a une espece.
FicheElevageRepository Function(ConfigurationEspece) fabriqueFicheElevage(
  AppDatabase db,
) => (configuration) => FicheElevageRepositoryDrift(db, configuration);
