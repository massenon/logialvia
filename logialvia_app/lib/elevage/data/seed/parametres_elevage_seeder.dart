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
  static const List<({String espece, String stade, int ration, bool confirme})>
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

  // ------------------------------------------------ escargots et bovins (v27)
  //
  // ⚠️ Contrairement aux 12 barèmes et 11 échéances ci-dessus, ces valeurs ne
  // viennent PAS du prototype : les deux filières ont été ajoutées après lui
  // (decisions DV-16 et DV-17, `docs/logialvia/16_DECISIONS_VALIDEES.md` §3b).
  // Ce sont des REPÈRES d'élevage usuels, validés par l'animalier, qu'il
  // modifie dans Paramètres Élevage. La NOTICE DU PRODUIT UTILISÉ PRÉVAUT sur
  // toute dose ci-dessous ; les rémanences sont prudentes (jamais plus courtes
  // que l'usage courant). Aucune n'est marquée « confirmée ».
  //
  // Bovins : les rations en g/tête/j sont INDICATIVES (taux de matière sèche
  // × poids moyen de référence : 3,5 % de 100 kg, 3 % de 230 kg, 2,5 % de
  // 350 kg, complément seul). Le tableau en % du poids vif par classe de poids
  // (DV-17) n'existe pas encore au poste.

  /// Barèmes des deux filières ajoutées.
  static const List<({String espece, String stade, int ration, bool confirme})>
  baremesNouvellesFilieres = [
    (espece: 'escargots', stade: 'Naissain', ration: 1, confirme: false),
    (espece: 'escargots', stade: 'Marchand', ration: 5, confirme: false),
    (espece: 'escargots', stade: 'Reproducteur', ration: 8, confirme: false),
    (espece: 'bovins', stade: 'Veau', ration: 1500, confirme: false),
    (espece: 'bovins', stade: 'Embouche', ration: 7000, confirme: false),
    (espece: 'bovins', stade: 'Reproducteur', ration: 9000, confirme: false),
  ];

  /// Échéances des deux filières ajoutées : 21 pour les escargots (hygiène et
  /// soins, sur les 90 premiers jours), 9 pour les bovins.
  static List<
    ({
      String espece,
      int jour,
      String traitement,
      String produit,
      String dose,
      int remanence,
    })
  >
  get echeancesNouvellesFilieres => [
    ..._echeancesEscargots,
    ..._echeancesBovins,
  ];

  static List<
    ({
      String espece,
      int jour,
      String traitement,
      String produit,
      String dose,
      int remanence,
    })
  >
  get _echeancesEscargots {
    const e = 'escargots';
    ({
      String espece,
      int jour,
      String traitement,
      String produit,
      String dose,
      int remanence,
    })
    ligne(int jour, String traitement, String produit, String dose) => (
      espece: e,
      jour: jour,
      traitement: traitement,
      produit: produit,
      dose: dose,
      remanence: 0,
    );

    return [
      ligne(
        1,
        'Contrôle sanitaire et mise en quarantaine',
        'Observation (aucun produit)',
        'Bac séparé pendant 14 jours',
      ),
      for (final j in const [5, 35, 65])
        ligne(
          j,
          'Complément calcium',
          'Coquilles broyées ou chaux alimentaire',
          'À volonté, en bol permanent',
        ),
      for (var j = 7; j <= 84; j += 7)
        ligne(
          j,
          'Nettoyage hebdomadaire du bac',
          'Eau propre (aucun produit)',
          'Bac vidé, rincé, substrat humide renouvelé',
        ),
      ligne(
        14,
        'Fin de quarantaine',
        'Observation (aucun produit)',
        'Contrôle des sujets ; les sujets sains rejoignent le parc',
      ),
      for (final j in const [30, 60, 90])
        ligne(
          j,
          'Désinfection mensuelle du bac',
          'Eau de Javel diluée',
          '1 volume pour 10 volumes d\'eau ; bac vide, rincé à grande eau, '
              'séché 24 h avant remise des sujets',
        ),
      ligne(
        60,
        'Renouvellement du substrat',
        'Terreau propre et humide',
        'Remplacement complet',
      ),
    ];
  }

  static const List<
    ({
      String espece,
      int jour,
      String traitement,
      String produit,
      String dose,
      int remanence,
    })
  >
  _echeancesBovins = [
    (
      espece: 'bovins',
      jour: 1,
      traitement: 'Déparasitage interne',
      produit: 'Albendazole',
      dose: '7,5 mg par kg de poids vif, voie orale',
      remanence: 14,
    ),
    (
      espece: 'bovins',
      jour: 7,
      traitement: 'Détiquage (lutte contre les tiques)',
      produit: 'Deltaméthrine, bain ou pulvérisation',
      dose: 'Dilution selon la notice du fabricant',
      remanence: 7,
    ),
    (
      espece: 'bovins',
      jour: 15,
      traitement: 'Vaccin péripneumonie contagieuse bovine (PPCB)',
      produit: 'Vaccin T1/44',
      dose: '1 dose selon la notice, voie sous-cutanée',
      remanence: 0,
    ),
    (
      espece: 'bovins',
      jour: 30,
      traitement: 'Vaccin charbon bactéridien et symptomatique',
      produit: 'Vaccin charbon',
      dose: '1 à 2 mL selon la notice, voie sous-cutanée',
      remanence: 0,
    ),
    (
      espece: 'bovins',
      jour: 45,
      traitement: 'Vaccin pasteurellose',
      produit: 'Vaccin Pasteurella',
      dose: '2 mL selon la notice, voie sous-cutanée',
      remanence: 0,
    ),
    (
      espece: 'bovins',
      jour: 60,
      traitement: 'Déparasitage interne et externe',
      produit: 'Ivermectine 1 %',
      dose: '1 mL pour 50 kg de poids vif (0,2 mg/kg), voie sous-cutanée',
      remanence: 35,
    ),
    (
      espece: 'bovins',
      jour: 90,
      traitement: 'Détiquage (rappel)',
      produit: 'Deltaméthrine, bain ou pulvérisation',
      dose: 'Dilution selon la notice du fabricant',
      remanence: 7,
    ),
    (
      espece: 'bovins',
      jour: 180,
      traitement: 'Déparasitage interne (rappel semestriel)',
      produit: 'Albendazole',
      dose: '7,5 mg par kg de poids vif, voie orale',
      remanence: 14,
    ),
    (
      espece: 'bovins',
      jour: 365,
      traitement: 'Rappel annuel PPCB et charbon',
      produit: 'Vaccin T1/44 et vaccin charbon',
      dose: '1 dose de chacun selon la notice',
      remanence: 0,
    ),
  ];

  /// Taux de ration des bovins par classe de poids vif (DV-17), en grammes et
  /// en % de matière sèche par jour. Repères validés par l'animalier : jamais
  /// « confirmés » tant qu'il ne les a pas validés dans Paramètres Élevage.
  ///
  /// Classes `[min, max[` : un animal de 300 kg pile tombe dans la dernière.
  static const List<
    ({String espece, int minG, int? maxG, double taux, bool confirme})
  >
  tauxPoidsInitiaux = [
    (espece: 'bovins', minG: 0, maxG: 150000, taux: 3.5, confirme: false),
    (espece: 'bovins', minG: 150000, maxG: 300000, taux: 3.0, confirme: false),
    (espece: 'bovins', minG: 300000, maxG: null, taux: 2.5, confirme: false),
  ];

  static Iterable<TauxRationPoidsCompanion> _tauxPoids(String? espece) =>
      tauxPoidsInitiaux
          .where((t) => espece == null || t.espece == espece)
          .map(
            (t) => TauxRationPoidsCompanion.insert(
              espece: t.espece,
              poidsMinG: t.minG,
              poidsMaxG: Value(t.maxG),
              tauxPourcent: t.taux,
              confirme: Value(t.confirme),
            ),
          );

  /// Migration v28 : sème les classes de poids des bovins si la filière n'en a
  /// aucune. Réservée à la migration, comme [ajouterNouvellesFilieres].
  static Future<void> ajouterTauxPoidsParDefaut(AppDatabase db) async {
    final existant =
        await (db.select(db.tauxRationPoids)
              ..where((t) => t.espece.equals('bovins'))
              ..limit(1))
            .getSingleOrNull();
    if (existant != null) return;
    await db.batch((batch) {
      batch.insertAll(db.tauxRationPoids, _tauxPoids('bovins').toList());
    });
  }

  /// Migration v27 : ajoute escargots et bovins à une base **déjà en service**.
  ///
  /// N'écrase rien : une filière qui a déjà au moins une ration (ou une
  /// échéance) est laissée telle quelle. Réservée à la migration — appelée au
  /// démarrage ordinaire, elle ressusciterait des lignes que l'animalier a
  /// supprimées volontairement.
  static Future<void> ajouterNouvellesFilieres(AppDatabase db) async {
    for (final espece in const ['escargots', 'bovins']) {
      final aDesRations =
          await (db.select(db.baremesRation)
                ..where((b) => b.espece.equals(espece))
                ..limit(1))
              .getSingleOrNull();
      if (aDesRations == null) {
        await db.batch((batch) {
          batch.insertAll(
            db.baremesRation,
            baremesNouvellesFilieres
                .where((b) => b.espece == espece)
                .map(
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

      final aDesEcheances =
          await (db.select(db.calendrierProphylaxie)
                ..where((c) => c.espece.equals(espece))
                ..limit(1))
              .getSingleOrNull();
      if (aDesEcheances == null) {
        await db.batch((batch) {
          batch.insertAll(
            db.calendrierProphylaxie,
            echeancesNouvellesFilieres
                .where((e) => e.espece == espece)
                .map(_versCompagnon),
          );
        });
      }
    }
  }

  static CalendrierProphylaxieCompanion _versCompagnon(
    ({
      String espece,
      int jour,
      String traitement,
      String produit,
      String dose,
      int remanence,
    })
    e,
  ) => CalendrierProphylaxieCompanion.insert(
    espece: e.espece,
    jourCycle: e.jour,
    traitement: e.traitement,
    produit: e.produit,
    remanenceJours: Value(e.remanence),
    dose: Value(e.dose),
  );

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
          [...baremes, ...baremesNouvellesFilieres].map(
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

    final premierTaux = await (_db.select(
      _db.tauxRationPoids,
    )..limit(1)).getSingleOrNull();
    if (premierTaux == null) {
      await _db.batch((batch) {
        batch.insertAll(_db.tauxRationPoids, _tauxPoids(null).toList());
      });
    }

    final premiereEcheance = await (_db.select(
      _db.calendrierProphylaxie,
    )..limit(1)).getSingleOrNull();

    if (premiereEcheance == null) {
      await _db.batch((batch) {
        batch.insertAll(_db.calendrierProphylaxie, [
          ...echeances.map(
            (e) => CalendrierProphylaxieCompanion.insert(
              espece: e.espece,
              jourCycle: e.jour,
              traitement: e.traitement,
              produit: e.produit,
              remanenceJours: Value(e.remanence),
            ),
          ),
          ...echeancesNouvellesFilieres.map(_versCompagnon),
        ]);
      });
    }
  }
}
