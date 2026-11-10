import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import 'identifiants_elevage.dart';
import 'outils_sync_elevage.dart';

/// `fiche_journee` — fait saisi au poste, **dernier écrivain gagne, ligne entière**
/// (`46_` §2.3, `46a_`), **sans jamais perdre une saisie en silence** (`47e_`) : quand deux
/// postes saisissent la même fiche sans s'être vus, la version la plus récente reste
/// courante mais l'autre est CONSERVÉE comme « variante » et la fiche est marquée
/// « modifiée ailleurs » jusqu'à ce que l'utilisatrice choisisse. Une saisie locale non
/// envoyée n'est plus jamais écrasée par une version différente du serveur.
///
/// ## Convergence de deux postes
///
/// Une fiche est unique par (espèce, date). Son UUID est **déterministe** de cette clé
/// (`identifiantFicheJournee`) : deux postes qui saisissent le même jour écrivent la
/// MÊME ligne ; la plus récente à l'instant de SAISIE l'emporte, en bloc (jamais un
/// mélange champ par champ : les effectifs sont calculés du jour d'avant, mélanger deux
/// saisies produirait un effectif qu'aucun des deux postes n'a calculé).
///
/// ## Aucun effet de bord à l'absorption (règle d'or)
///
/// Absorber la fiche d'un autre poste ne recalcule **rien** : ni la cascade des jours
/// suivants, ni le stock d'œufs, ni les ventes du jour. La ligne arrive avec ses valeurs
/// calculées ; les jours suivants arrivent par leurs propres lignes (le poste qui a
/// saisi les a recalculés et envoyés). Limite assumée : voir `46a_` §« Limites ».
class TableFichesJourneePoste implements TablePoste {
  const TableFichesJourneePoste(this._db);

  final AppDatabase _db;

  @override
  String get nom => 'fiche_journee';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications =>
      _db.tableUpdates(TableUpdateQuery.onTable(_db.ficheJournee)).map((_) {});

  /// Colonnes du CONTENU d'une fiche (tout sauf identité et instants), dans l'ordre de
  /// l'envoi : ce sont elles qu'on compare pour savoir si deux versions diffèrent.
  static const colonnesContenu = [
    'espece',
    'date',
    'achat',
    'ne',
    'vente',
    'mort_cat1',
    'mort_cat2',
    'mort_cat3',
    'mort_cat4',
    'don_cat1',
    'don_cat2',
    'don_cat3',
    'don_cat4',
    'effectif',
    'eff_cat1_day',
    'eff_cat2_day',
    'eff_cat3_day',
    'eff_cat4_day',
    'srh',
    'ts',
    'stock_final_oeufs',
    'oeufs_pondus',
    'oeufs_casses',
    'sorties_plateaux',
    'poids_general_g',
    'traitement_obs',
    'traitement_valide',
    'is_recorded',
  ];

  /// Le contenu d'une ligne locale, au format de l'envoi.
  static Map<String, dynamic> contenuDe(FicheJourneeRow f) => {
    'espece': f.espece,
    'date': jourCivil(f.date),
    'achat': f.achat,
    'ne': f.ne,
    'vente': f.vente,
    'mort_cat1': f.mortCat1,
    'mort_cat2': f.mortCat2,
    'mort_cat3': f.mortCat3,
    'mort_cat4': f.mortCat4,
    'don_cat1': f.donCat1,
    'don_cat2': f.donCat2,
    'don_cat3': f.donCat3,
    'don_cat4': f.donCat4,
    'effectif': f.effectif,
    'eff_cat1_day': f.effCat1Day,
    'eff_cat2_day': f.effCat2Day,
    'eff_cat3_day': f.effCat3Day,
    'eff_cat4_day': f.effCat4Day,
    'srh': f.srh,
    'ts': f.ts,
    'stock_final_oeufs': f.stockFinalOeufs,
    'oeufs_pondus': f.oeufsPondus,
    'oeufs_casses': f.oeufsCasses,
    'sorties_plateaux': f.sortiesPlateaux,
    'poids_general_g': f.poidsGeneralG,
    'traitement_obs': f.traitementObs,
    'traitement_valide': f.traitementValide,
    'is_recorded': f.isRecorded,
  };

  /// Le contenu d'une ligne du serveur (mêmes clés que [contenuDe]).
  static Map<String, dynamic> contenuDeLigne(Map<String, dynamic> l) => {
    for (final c in colonnesContenu)
      c: c == 'date' ? (l[c] as String).substring(0, 10) : l[c],
  };

  /// Deux versions ont-elles le même contenu ? (`null` et absent se valent.)
  static bool contenuIdentique(Map<String, dynamic> a, Map<String, dynamic> b) =>
      colonnesContenu.every((c) => a[c] == b[c]);

  /// Les variantes stockées (JSON), `[]` si absentes ou illisibles. Chaque élément :
  /// `{origine, updated_at, contenu}`.
  static List<Map<String, dynamic>> lireVariantes(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decode = jsonDecode(json);
      if (decode is! List) return const [];
      return [
        for (final v in decode)
          if (v is Map &&
              v['origine'] is String &&
              v['updated_at'] is String &&
              v['contenu'] is Map)
            Map<String, dynamic>.from(v),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Variantes d'une ligne du serveur (`variantes` : `{device_id, updated_at, contenu}`),
  /// au format local. Un élément illisible est ignoré (jamais lissé).
  static List<Map<String, dynamic>> variantesDuServeur(Object? brut) {
    if (brut is! List) return const [];
    return [
      for (final v in brut)
        if (v is Map &&
            v['updated_at'] is String &&
            v['contenu'] is Map &&
            DateTime.tryParse(v['updated_at'] as String) != null)
          {
            'origine': v['device_id'] is String
                ? 'Poste ${(v['device_id'] as String).substring(0, 8)}'
                : 'Autre poste',
            'updated_at': v['updated_at'],
            'contenu': Map<String, dynamic>.from(v['contenu'] as Map),
          },
    ];
  }

  /// Ajoute [nouvelles] à [existantes] sans doublon (même instant et même contenu).
  static List<Map<String, dynamic>> fusionner(
    List<Map<String, dynamic>> existantes,
    List<Map<String, dynamic>> nouvelles,
  ) {
    final resultat = [...existantes];
    for (final n in nouvelles) {
      final instantN = DateTime.tryParse(n['updated_at'] as String);
      final deja = resultat.any(
        (e) =>
            DateTime.tryParse(e['updated_at'] as String) == instantN &&
            contenuIdentique(
              Map<String, dynamic>.from(e['contenu'] as Map),
              Map<String, dynamic>.from(n['contenu'] as Map),
            ),
      );
      if (!deja) resultat.add(n);
    }
    return resultat;
  }

  /// Entiers obligatoires (≥ 0) d'une ligne.
  static const _obligatoires = [
    'achat',
    'ne',
    'vente',
    'mort_cat1',
    'mort_cat2',
    'mort_cat3',
    'don_cat1',
    'don_cat2',
    'don_cat3',
    'effectif',
    'eff_cat1_day',
    'eff_cat2_day',
    'eff_cat3_day',
  ];

  /// Entiers facultatifs (`null` ou ≥ 0).
  static const _facultatifs = [
    'mort_cat4',
    'don_cat4',
    'eff_cat4_day',
    'srh',
    'ts',
    'stock_final_oeufs',
    'oeufs_pondus',
    'oeufs_casses',
    'sorties_plateaux',
    'poids_general_g',
  ];

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      const supplantees = 0;

      for (final l in lignes) {
        final jour = OutilsSyncElevage.jour(l['date']);
        final instant = OutilsSyncElevage.instant(l['updated_at']);
        final espece = l['espece'];

        // Strict : une ligne incohérente est REFUSÉE et comptée, jamais lissée.
        if (!OutilsSyncElevage.estUuid(l['id']) ||
            !OutilsSyncElevage.especeConnue(espece) ||
            jour == null ||
            instant == null ||
            // L'identité d'une fiche est sa clé (espèce, date) : un UUID qui n'en est
            // pas le calcul romprait la convergence entre postes.
            l['id'] != identifiantFicheJournee(espece as String, jour) ||
            _obligatoires.any((c) => !OutilsSyncElevage.entierPositif(l[c])) ||
            _facultatifs.any((c) => !OutilsSyncElevage.entierOuNull(l[c])) ||
            l['traitement_valide'] is! bool ||
            l['is_recorded'] is! bool ||
            (l['traitement_obs'] != null && l['traitement_obs'] is! String)) {
          refusees++;
          continue;
        }
        final id = l['id'] as String;

        final locale = await (_db.select(
          _db.ficheJournee,
        )..where((f) => f.id.equals(id))).getSingleOrNull();

        // Une ligne qui porte déjà ce (espèce, date) sous un AUTRE identifiant ne
        // peut pas coexister (UNIQUE) : refusée, jamais écrasée.
        if (locale == null) {
          final homonyme =
              await (_db.select(_db.ficheJournee)..where(
                    (f) => f.espece.equals(espece) & f.date.equals(jour),
                  ))
                  .getSingleOrNull();
          if (homonyme != null) {
            refusees++;
            continue;
          }
        }

        final contenuEntrant = contenuDeLigne(l);
        final instantIso = instant.toUtc().toIso8601String();
        var variantes = variantesDuServeur(l['variantes']);

        if (locale != null && locale.syncStatus != 'synced') {
          if (contenuIdentique(contenuDe(locale), contenuEntrant)) {
            // Le serveur a deja MA version : la fiche est synchronisee, rien ne diverge.
            await (_db.update(_db.ficheJournee)
                  ..where((f) => f.id.equals(id)))
                .write(
                  FicheJourneeCompanion(
                    syncStatus: const Value('synced'),
                    syncMotif: const Value(null),
                    baseMaj: Value(instantIso),
                    variantes: Value(
                      variantes.isEmpty ? null : jsonEncode(variantes),
                    ),
                    updatedAt: Value(instantIso),
                  ),
                );
            absorbees++;
            continue;
          }
          // Version DIFFERENTE alors que ma saisie n'est pas partie : on ne l'ecrase
          // JAMAIS (`47e_`). La version du serveur est gardee comme variante visible ;
          // quand ma saisie partira, le serveur dira qu'elle divergeait.
          if (locale.baseMaj != instantIso) {
            variantes = fusionner(
              fusionner(lireVariantes(locale.variantes), variantes),
              [
                {
                  'origine': 'Serveur',
                  'updated_at': instantIso,
                  'contenu': contenuEntrant,
                },
              ],
            );
            await (_db.update(_db.ficheJournee)..where((f) => f.id.equals(id)))
                .write(FicheJourneeCompanion(variantes: Value(jsonEncode(variantes))));
          }
          conservees++;
          continue;
        }

        await _db
            .into(_db.ficheJournee)
            .insertOnConflictUpdate(
              FicheJourneeCompanion(
                id: Value(id),
                espece: Value(espece),
                date: Value(jour),
                achat: Value(l['achat'] as int),
                ne: Value(l['ne'] as int),
                vente: Value(l['vente'] as int),
                mortCat1: Value(l['mort_cat1'] as int),
                mortCat2: Value(l['mort_cat2'] as int),
                mortCat3: Value(l['mort_cat3'] as int),
                mortCat4: Value(l['mort_cat4'] as int?),
                donCat1: Value(l['don_cat1'] as int),
                donCat2: Value(l['don_cat2'] as int),
                donCat3: Value(l['don_cat3'] as int),
                donCat4: Value(l['don_cat4'] as int?),
                effectif: Value(l['effectif'] as int),
                effCat1Day: Value(l['eff_cat1_day'] as int),
                effCat2Day: Value(l['eff_cat2_day'] as int),
                effCat3Day: Value(l['eff_cat3_day'] as int),
                effCat4Day: Value(l['eff_cat4_day'] as int?),
                srh: Value(l['srh'] as int?),
                ts: Value(l['ts'] as int?),
                stockFinalOeufs: Value(l['stock_final_oeufs'] as int?),
                oeufsPondus: Value(l['oeufs_pondus'] as int?),
                oeufsCasses: Value(l['oeufs_casses'] as int?),
                sortiesPlateaux: Value(l['sorties_plateaux'] as int?),
                poidsGeneralG: Value(l['poids_general_g'] as int?),
                traitementObs: Value(l['traitement_obs'] as String?),
                traitementValide: Value(l['traitement_valide'] as bool),
                isRecorded: Value(l['is_recorded'] as bool),
                syncStatus: const Value('synced'),
                syncMotif: const Value(null),
                updatedAt: Value(instantIso),
                baseMaj: Value(instantIso),
                variantes: Value(
                  variantes.isEmpty ? null : jsonEncode(variantes),
                ),
                resolution: const Value(false),
              ),
            );
        absorbees++;
      }
      return ResultatAbsorption(
        absorbees: absorbees,
        refusees: refusees,
        conservees: conservees,
        supplantees: supplantees,
      );
    });
  }

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final lignes =
        await (_db.select(_db.ficheJournee)
              ..where((f) => f.syncStatus.equals('pending'))
              ..orderBy([(f) => OrderingTerm.asc(f.updatedAt)]))
            .get();
    return [
      for (final f in lignes)
        LigneAEnvoyer(
          id: f.id,
          instantSaisie: f.updatedAt,
          corps: {
            'id': f.id,
            'espece': f.espece,
            // Date civile envoyée telle quelle, sans fuseau.
            'date': jourCivil(f.date),
            'achat': f.achat,
            'ne': f.ne,
            'vente': f.vente,
            'mort_cat1': f.mortCat1,
            'mort_cat2': f.mortCat2,
            'mort_cat3': f.mortCat3,
            'mort_cat4': f.mortCat4,
            'don_cat1': f.donCat1,
            'don_cat2': f.donCat2,
            'don_cat3': f.donCat3,
            'don_cat4': f.donCat4,
            'effectif': f.effectif,
            'eff_cat1_day': f.effCat1Day,
            'eff_cat2_day': f.effCat2Day,
            'eff_cat3_day': f.effCat3Day,
            'eff_cat4_day': f.effCat4Day,
            'srh': f.srh,
            'ts': f.ts,
            'stock_final_oeufs': f.stockFinalOeufs,
            'oeufs_pondus': f.oeufsPondus,
            'oeufs_casses': f.oeufsCasses,
            'sorties_plateaux': f.sortiesPlateaux,
            'poids_general_g': f.poidsGeneralG,
            'traitement_obs': f.traitementObs,
            'traitement_valide': f.traitementValide,
            'is_recorded': f.isRecorded,
            'updated_at': f.updatedAt,
            // La version dont cette fiche est partie : le serveur en deduit si le poste
            // avait VU la version courante (suite normale) ou non (divergence, `47e_`).
            'base_updated_at': f.baseMaj,
            'resolution': f.resolution,
          },
        ),
    ];
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    // Seulement si la fiche n'a pas bougé depuis l'envoi : une saisie faite pendant
    // que le réseau répondait doit repartir au prochain envoi.
    await (_db.update(
      _db.ficheJournee,
    )..where((f) => f.id.equals(id) & f.updatedAt.equals(instantEnvoye))).write(
      FicheJourneeCompanion(
        syncStatus: const Value('synced'),
        syncMotif: const Value(null),
        // Le serveur detient desormais ma version : c'est celle dont partira la suite.
        baseMaj: Value(instantEnvoye),
        resolution: const Value(false),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(_db.ficheJournee)..where((f) => f.id.equals(id))).write(
      FicheJourneeCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur : les fiches s'en vont avec lui ; celles qui n'avaient
  /// pas été envoyées sont comptées comme perdues.
  @override
  Future<int> purger() async {
    final nonEnvoyees = await (_db.select(
      _db.ficheJournee,
    )..where((f) => f.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.ficheJournee).go();
    return nonEnvoyees.length;
  }
}
