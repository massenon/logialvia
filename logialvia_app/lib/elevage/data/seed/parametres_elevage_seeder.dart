import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Socle des barèmes de rationnement et des calendriers de prophylaxie.
///
/// **Toutes les valeurs viennent de `parametres-elevage.html`**, aucune n'est
/// inventée. Les 12 rations sont exactement celles du tableau `RATIONS`
/// (l.81-94 du script) et les 11 échéances celles de `PROPHYLAXIE_STORE`
/// (l.172-192) — y compris le drapeau `confirme`, qui ne vaut `true` que pour
/// les 3 barèmes Lapins : le prototype les seuls à porter le badge
/// « Confirmé (Référence Cuniculture) ».
///
/// Cohérence vérifiée avec `ConfigurationsEspeces` : les rations Goliaths
/// (30 / 60 / 110 g/j) sont les mêmes que celles du tableau de rationnement de
/// `fiche-goliaths.html`. C'est bien la **même** donnée, configurée ici et
/// consommée là-bas — pas deux sources parallèles.
class ParametresElevageSeeder {
  const ParametresElevageSeeder(this._db);

  final AppDatabase _db;

  /// Les 12 barèmes réels — `RATIONS` du prototype, dans l'ordre.
  static const List<
    ({String espece, String stade, int ration, bool confirme})
  >
  baremes = [
    (espece: 'goliaths', stade: 'Poussins', ration: 30, confirme: false),
    (espece: 'goliaths', stade: 'Goliathau', ration: 60, confirme: false),
    (espece: 'goliaths', stade: 'Mature', ration: 110, confirme: false),
    (espece: 'pintades', stade: 'Alevins', ration: 30, confirme: false),
    (espece: 'pintades', stade: 'Pintadau', ration: 60, confirme: false),
    (espece: 'pintades', stade: 'Mature', ration: 110, confirme: false),
    (espece: 'lapins', stade: 'Sevré / Lapereaux', ration: 30, confirme: true),
    (espece: 'lapins', stade: 'Chair / Jeune', ration: 60, confirme: true),
    (espece: 'lapins', stade: 'Reproducteur', ration: 120, confirme: true),
    (espece: 'poissons-chats', stade: 'Alevin', ration: 8, confirme: false),
    (espece: 'poissons-chats', stade: 'Juvénile', ration: 25, confirme: false),
    (espece: 'poissons-chats', stade: 'Mature', ration: 45, confirme: false),
  ];

  /// Les 11 échéances réelles — `PROPHYLAXIE_STORE` du prototype.
  static const List<
    ({
      String espece,
      int jour,
      String traitement,
      String produit,
      int remanence,
    })
  >
  echeances = [
    (
      espece: 'goliaths',
      jour: 1,
      traitement: 'Déparasitage',
      produit: 'Levamisole Volaille',
      remanence: 7,
    ),
    (
      espece: 'goliaths',
      jour: 5,
      traitement: 'Anti-coccidien (1/4)',
      produit: 'Amprolium',
      remanence: 5,
    ),
    (
      espece: 'goliaths',
      jour: 15,
      traitement: 'Vaccin Newcastle (Rappel)',
      produit: 'Vaccin HB1',
      remanence: 0,
    ),
    (
      espece: 'pintades',
      jour: 1,
      traitement: 'Déparasitage',
      produit: 'Levamisole Volaille',
      remanence: 7,
    ),
    (
      espece: 'pintades',
      jour: 5,
      traitement: 'Anti-coccidien (1/4)',
      produit: 'Amprolium',
      remanence: 5,
    ),
    (
      espece: 'pintades',
      jour: 6,
      traitement: 'Complément Calcium',
      produit: 'CalciBoost',
      remanence: 0,
    ),
    (
      espece: 'pintades',
      jour: 12,
      traitement: 'Vaccin Gumboro (Rappel)',
      produit: 'Vaccin Gumboro',
      remanence: 0,
    ),
    (
      espece: 'lapins',
      jour: 1,
      traitement: 'Déparasitage',
      produit: 'Levalap',
      remanence: 7,
    ),
    (
      espece: 'lapins',
      jour: 9,
      traitement: 'Hépato-protection',
      produit: 'Hépaturyl',
      remanence: 0,
    ),
    (
      espece: 'poissons-chats',
      jour: 1,
      traitement: 'Traitement Antifongique (bassin)',
      produit: 'Bleu de Méthylène',
      remanence: 3,
    ),
    (
      espece: 'poissons-chats',
      jour: 14,
      traitement: 'Contrôle Oxygénation / Ammoniac',
      produit: '—',
      remanence: 0,
    ),
  ];

  /// Idempotent : ne fait rien si la Gérante a déjà ses propres barèmes.
  ///
  /// Le peuplement n'est **jamais** correctif ici, contrairement au plan
  /// comptable : une ration supprimée l'a été volontairement, la réintroduire à
  /// chaque démarrage rendrait la suppression impossible.
  Future<void> executer() async {
    final premierBareme = await (_db.select(
      _db.baremesRation,
    )..limit(1)).getSingleOrNull();

    if (premierBareme == null) {
      await _db.batch((batch) {
        batch.insertAll(
          _db.baremesRation,
          baremes.map(
            (b) => BaremesRationCompanion.insert(
              espece: b.espece,
              stade: b.stade,
              rationGrammesParJour: b.ration,
              confirme: Value(b.confirme),
            ),
          ),
        );
      });
    }

    final premiereEcheance = await (_db.select(
      _db.calendrierProphylaxie,
    )..limit(1)).getSingleOrNull();

    if (premiereEcheance == null) {
      await _db.batch((batch) {
        batch.insertAll(
          _db.calendrierProphylaxie,
          echeances.map(
            (e) => CalendrierProphylaxieCompanion.insert(
              espece: e.espece,
              jourCycle: e.jour,
              traitement: e.traitement,
              produit: e.produit,
              remanenceJours: Value(e.remanence),
            ),
          ),
        );
      });
    }
  }
}
