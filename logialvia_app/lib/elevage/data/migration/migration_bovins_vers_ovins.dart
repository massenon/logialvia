import 'package:drift/drift.dart';

import '../../../administration/data/repositories/preferences_poste_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../seed/parametres_elevage_seeder.dart';
import '../sync/identifiants_elevage.dart';
import '../sync/identifiants_parametres_elevage.dart';

/// Schéma v51 (DV-22) : la filière **Bovins** devient **Ovins** à la demande du client.
///
/// Un poste déjà en service peut porter des lignes `bovins` dans toutes les tables qui
/// connaissent l'espèce ou le module. Cette migration les renomme en `ovins` :
///
/// - **idempotente et rejouable** : une fois renommé, il ne reste plus rien à faire ;
/// - **sans doublon** : si la ligne `ovins` existe déjà (même clé), elle l'emporte et la ligne
///   `bovins` est retirée ;
/// - **identifiants déterministes recalculés** (fiches journalières, compteurs de ventes,
///   barèmes, taux, échéances) : le serveur les recalcule à partir de l'espèce, une ligne
///   dont l'UUID n'est pas celui de sa clé serait refusée. Une ligne saisie par l'utilisatrice
///   (UUID aléatoire) garde le sien ;
/// - **faits remis à envoyer** (`sync_status = 'pending'`) : le serveur fait le même renommage
///   de son côté, le renvoi converge sur les mêmes identifiants ;
/// - **valeurs d'origine réécrites** : un barème, une classe de poids ou une échéance restés
///   EXACTEMENT à leur valeur d'ouverture bovine prennent la valeur d'ouverture ovine ; une
///   valeur modifiée par l'animalier est conservée telle quelle (seul le nom de l'espèce change).
class MigrationBovinsVersOvins {
  const MigrationBovinsVersOvins(this._db);

  final AppDatabase _db;

  static const String ancien = 'bovins';
  static const String nouveau = 'ovins';

  /// Ancien intitulé du stade jeune (devenu « Agneau »).
  static const String _ancienStadeJeune = 'Veau';
  static const String _nouveauStadeJeune = 'Agneau';

  static const String _ancienneCategorie = 'Élevage bovin';
  static const String _nouvelleCategorie = 'Élevage ovin';

  /// Barèmes d'ouverture bovins : stade → ration (g/tête/j). Nouveau : stade → ration.
  static const Map<String, int> _anciensBaremes = {
    'Veau': 1500,
    'Embouche': 7000,
    'Reproducteur': 9000,
  };
  static const Map<String, int> _nouveauxBaremes = {
    'Veau': 300,
    'Embouche': 600,
    'Reproducteur': 800,
  };

  /// Classes d'ouverture bovines : (min, max, taux) → (min, max, taux) ovines.
  static const List<
    ({int minG, int? maxG, double taux, int nouvMinG, int? nouvMaxG, double nouvTaux})
  >
  _anciensTaux = [
    (minG: 0, maxG: 150000, taux: 3.5, nouvMinG: 0, nouvMaxG: 15000, nouvTaux: 4.0),
    (
      minG: 150000,
      maxG: 300000,
      taux: 3.0,
      nouvMinG: 15000,
      nouvMaxG: 30000,
      nouvTaux: 3.5,
    ),
    (minG: 300000, maxG: null, taux: 2.5, nouvMinG: 30000, nouvMaxG: null, nouvTaux: 3.0),
  ];

  /// Échéances d'ouverture bovines : jour → (traitement, produit).
  static const Map<int, (String, String)> _anciennesEcheances = {
    1: ('Déparasitage interne', 'Albendazole'),
    7: (
      'Détiquage (lutte contre les tiques)',
      'Deltaméthrine, bain ou pulvérisation',
    ),
    15: ('Vaccin péripneumonie contagieuse bovine (PPCB)', 'Vaccin T1/44'),
    30: ('Vaccin charbon bactéridien et symptomatique', 'Vaccin charbon'),
    45: ('Vaccin pasteurellose', 'Vaccin Pasteurella'),
    60: ('Déparasitage interne et externe', 'Ivermectine 1 %'),
    90: ('Détiquage (rappel)', 'Deltaméthrine, bain ou pulvérisation'),
    180: ('Déparasitage interne (rappel semestriel)', 'Albendazole'),
    365: ('Rappel annuel PPCB et charbon', 'Vaccin T1/44 et vaccin charbon'),
  };

  Future<void> executer() => _db.transaction(() async {
    await _modules();
    await _fichesJournee();
    await _ventesJour();
    await _baremes();
    await _taux();
    await _echeances();
    for (final table in const [
      'bandes',
      'soins_calendrier',
      'infirmerie',
      'lignes_vente',
    ]) {
      await _renommerSimplement(table);
    }
    await _produits();
    await _demandes();
  });

  // ------------------------------------------------------------- utilitaires

  Future<bool> _tableExiste(String table) async => (await _db.customSelect(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    variables: [Variable.withString(table)],
  ).get()).isNotEmpty;

  Future<bool> _colonneExiste(String table, String colonne) async =>
      (await _db.customSelect('PRAGMA table_info("$table")').get()).any(
        (l) => l.read<String>('name') == colonne,
      );

  /// Vrai si la table existe, a une colonne `id` TEXTE (UUID) et une colonne `espece`.
  /// Avant la v40 certaines tables ont encore une clé entière : la migration v40 les
  /// convertira, et ne verra alors plus que des lignes déjà au bon nom.
  Future<bool> _utilisable(String table) async {
    if (!await _tableExiste(table) || !await _colonneExiste(table, 'espece')) {
      return false;
    }
    return true;
  }

  Future<bool> _idTexte(String table) async {
    final colonnes = await _db.customSelect('PRAGMA table_info("$table")').get();
    final id = colonnes.where((l) => l.read<String>('name') == 'id');
    return id.isNotEmpty && id.first.read<String>('type').toUpperCase() == 'TEXT';
  }

  /// Remet une ligne à envoyer (faits synchronisés), si la table porte ces colonnes.
  Future<String> _marque(String table) async {
    if (await _colonneExiste(table, 'sync_status') &&
        await _colonneExiste(table, 'updated_at')) {
      return ", sync_status = 'pending', updated_at = '${instantSaisie()}'";
    }
    return '';
  }

  Future<bool> _existe(String table, String id) async => (await _db.customSelect(
    'SELECT 1 FROM "$table" WHERE id = ?',
    variables: [Variable.withString(id)],
  ).get()).isNotEmpty;

  Future<void> _supprimer(String table, String id) => _db.customStatement(
    'DELETE FROM "$table" WHERE id = ?',
    [id],
  );

  // ----------------------------------------------------------------- modules

  Future<void> _modules() async {
    if (!await _tableExiste('modules_actifs')) return;
    final dejaLa = await _db.customSelect(
      'SELECT 1 FROM modules_actifs WHERE module_id = ?',
      variables: [Variable.withString(nouveau)],
    ).get();
    if (dejaLa.isNotEmpty) {
      await _db.customStatement(
        'DELETE FROM modules_actifs WHERE module_id = ?',
        [ancien],
      );
      return;
    }
    await _db.customStatement(
      'UPDATE modules_actifs SET module_id = ?, espece = ? WHERE module_id = ?',
      [nouveau, nouveau, ancien],
    );
  }

  // ------------------------------------------------------- faits à identifiant

  Future<void> _fichesJournee() async {
    if (!await _utilisable('fiche_journee') || !await _idTexte('fiche_journee')) {
      return;
    }
    final marque = await _marque('fiche_journee');
    final lignes = await _db.customSelect(
      'SELECT id, date FROM fiche_journee WHERE espece = ?',
      variables: [Variable.withString(ancien)],
    ).get();
    for (final l in lignes) {
      final id = l.read<String>('id');
      final jour = DateTime.fromMillisecondsSinceEpoch(l.read<int>('date') * 1000);
      final nouvelId = identifiantFicheJournee(nouveau, jour);
      if (await _existe('fiche_journee', nouvelId)) {
        await _supprimer('fiche_journee', id);
      } else {
        await _db.customStatement(
          'UPDATE fiche_journee SET id = ?, espece = ?$marque WHERE id = ?',
          [nouvelId, nouveau, id],
        );
      }
    }
  }

  Future<void> _ventesJour() async {
    if (!await _utilisable('fiche_ventes_jour') ||
        !await _idTexte('fiche_ventes_jour')) {
      return;
    }
    final marque = await _marque('fiche_ventes_jour');
    final moi = await PreferencesPosteRepository(_db).identifiantPoste();
    final lignes = await _db.customSelect(
      'SELECT id, date, origine FROM fiche_ventes_jour WHERE espece = ?',
      variables: [Variable.withString(ancien)],
    ).get();
    for (final l in lignes) {
      final id = l.read<String>('id');
      final jour = DateTime.fromMillisecondsSinceEpoch(l.read<int>('date') * 1000);
      final poste = l.readNullable<String>('origine') ?? moi;
      final nouvelId = identifiantVentesJour(nouveau, jour, poste);
      if (await _existe('fiche_ventes_jour', nouvelId)) {
        await _supprimer('fiche_ventes_jour', id);
      } else {
        await _db.customStatement(
          'UPDATE fiche_ventes_jour SET id = ?, espece = ?$marque WHERE id = ?',
          [nouvelId, nouveau, id],
        );
      }
    }
  }

  // ------------------------------------------------------------ référentiels

  Future<void> _baremes() async {
    if (!await _utilisable('baremes_ration') || !await _idTexte('baremes_ration')) {
      return;
    }
    final lignes = await _db.customSelect(
      'SELECT id, stade, ration_grammes_par_jour AS ration, confirme '
      'FROM baremes_ration WHERE espece = ?',
      variables: [Variable.withString(ancien)],
    ).get();
    for (final l in lignes) {
      final id = l.read<String>('id');
      final stade = l.read<String>('stade');
      var ration = l.read<int>('ration');
      final origine =
          _anciensBaremes[stade] == ration && !(l.read<int>('confirme') == 1);
      var nouveauStade = stade;
      if (origine) {
        ration = _nouveauxBaremes[stade]!;
      }
      if (stade == _ancienStadeJeune) nouveauStade = _nouveauStadeJeune;
      final deterministe = id == IdentifiantsParametresElevage.bareme(ancien, stade);
      final nouvelId = deterministe
          ? IdentifiantsParametresElevage.bareme(nouveau, nouveauStade)
          : id;
      final dejaLa = await _db.customSelect(
        'SELECT id FROM baremes_ration WHERE espece = ? AND stade = ?',
        variables: [Variable.withString(nouveau), Variable.withString(nouveauStade)],
      ).get();
      if (dejaLa.isNotEmpty) {
        await _supprimer('baremes_ration', id);
        continue;
      }
      await _db.customStatement(
        'UPDATE baremes_ration SET id = ?, espece = ?, stade = ?, '
        'ration_grammes_par_jour = ? WHERE id = ?',
        [nouvelId, nouveau, nouveauStade, ration, id],
      );
    }
  }

  Future<void> _taux() async {
    if (!await _utilisable('taux_ration_poids') ||
        !await _idTexte('taux_ration_poids')) {
      return;
    }
    final lignes = await _db.customSelect(
      'SELECT id, poids_min_g, poids_max_g, taux_pourcent, confirme '
      'FROM taux_ration_poids WHERE espece = ? ORDER BY poids_min_g',
      variables: [Variable.withString(ancien)],
    ).get();
    // Les trois classes d'ouverture se réécrivent ensemble (ou pas du tout) : réécrire une
    // seule ferait se recouvrir les bornes.
    final inchangees =
        lignes.length == _anciensTaux.length &&
        [
          for (var i = 0; i < lignes.length; i++)
            lignes[i].read<int>('poids_min_g') == _anciensTaux[i].minG &&
                lignes[i].readNullable<int>('poids_max_g') == _anciensTaux[i].maxG &&
                lignes[i].read<double>('taux_pourcent') == _anciensTaux[i].taux &&
                lignes[i].read<int>('confirme') == 0,
        ].every((b) => b);
    for (var i = 0; i < lignes.length; i++) {
      final l = lignes[i];
      final id = l.read<String>('id');
      final min = l.read<int>('poids_min_g');
      var nouvMin = min;
      var nouvMax = l.readNullable<int>('poids_max_g');
      var nouvTaux = l.read<double>('taux_pourcent');
      if (inchangees) {
        nouvMin = _anciensTaux[i].nouvMinG;
        nouvMax = _anciensTaux[i].nouvMaxG;
        nouvTaux = _anciensTaux[i].nouvTaux;
      }
      final deterministe = id == IdentifiantsParametresElevage.taux(ancien, min);
      final nouvelId = deterministe
          ? IdentifiantsParametresElevage.taux(nouveau, nouvMin)
          : id;
      final dejaLa = await _db.customSelect(
        'SELECT id FROM taux_ration_poids WHERE espece = ? AND poids_min_g = ?',
        variables: [Variable.withString(nouveau), Variable.withInt(nouvMin)],
      ).get();
      if (dejaLa.isNotEmpty) {
        await _supprimer('taux_ration_poids', id);
        continue;
      }
      await _db.customStatement(
        'UPDATE taux_ration_poids SET id = ?, espece = ?, poids_min_g = ?, '
        'poids_max_g = ?, taux_pourcent = ? WHERE id = ?',
        [nouvelId, nouveau, nouvMin, nouvMax, nouvTaux, id],
      );
    }
  }

  Future<void> _echeances() async {
    if (!await _utilisable('calendrier_prophylaxie') ||
        !await _idTexte('calendrier_prophylaxie')) {
      return;
    }
    final nouvelles = {
      for (final e in ParametresElevageSeeder.echeancesNouvellesFilieres.where(
        (e) => e.espece == nouveau,
      ))
        e.jour: e,
    };
    final lignes = await _db.customSelect(
      'SELECT id, jour_cycle, traitement, produit FROM calendrier_prophylaxie '
      'WHERE espece = ?',
      variables: [Variable.withString(ancien)],
    ).get();
    final aSoins = await _colonneExiste(
      'soins_calendrier',
      'echeance_prophylaxie_id',
    );
    for (final l in lignes) {
      final id = l.read<String>('id');
      final jour = l.read<int>('jour_cycle');
      final traitement = l.read<String>('traitement');
      final produit = l.read<String>('produit');
      final deterministe =
          id ==
          IdentifiantsParametresElevage.echeance(ancien, jour, traitement, produit);
      final ouverture = _anciennesEcheances[jour];
      final seme = ouverture != null &&
          ouverture.$1 == traitement &&
          ouverture.$2 == produit;
      final cible = seme ? nouvelles[jour] : null;
      final nouvTraitement = cible?.traitement ?? traitement;
      final nouvProduit = cible?.produit ?? produit;
      final nouvelId = deterministe
          ? IdentifiantsParametresElevage.echeance(
              nouveau,
              jour,
              nouvTraitement,
              nouvProduit,
            )
          : id;
      if (nouvelId != id && await _existe('calendrier_prophylaxie', nouvelId)) {
        await _supprimer('calendrier_prophylaxie', id);
        if (aSoins) {
          await _db.customStatement(
            'UPDATE soins_calendrier SET echeance_prophylaxie_id = ? '
            'WHERE echeance_prophylaxie_id = ?',
            [nouvelId, id],
          );
        }
        continue;
      }
      await _db.customStatement(
        'UPDATE calendrier_prophylaxie SET id = ?, espece = ?, traitement = ?, '
        'produit = ?, dose = ?, remanence_jours = ? WHERE id = ?',
        [
          nouvelId,
          nouveau,
          nouvTraitement,
          nouvProduit,
          cible != null ? cible.dose : l.readNullable<String>('dose'),
          cible != null ? cible.remanence : l.read<int>('remanence_jours'),
          id,
        ],
      );
      if (nouvelId != id && aSoins) {
        await _db.customStatement(
          'UPDATE soins_calendrier SET echeance_prophylaxie_id = ? '
          'WHERE echeance_prophylaxie_id = ?',
          [nouvelId, id],
        );
      }
    }
  }

  // ------------------------------------------------------------ renommage simple

  Future<void> _renommerSimplement(String table) async {
    if (!await _utilisable(table)) return;
    final marque = await _marque(table);
    // `OR IGNORE` : une clé unique déjà prise par la ligne `ovins` laisse la ligne `bovins`
    // en place, retirée juste après (l'ovine l'emporte, jamais de doublon).
    await _db.customStatement(
      'UPDATE OR IGNORE "$table" SET espece = ?$marque WHERE espece = ?',
      [nouveau, ancien],
    );
    await _db.customStatement('DELETE FROM "$table" WHERE espece = ?', [ancien]);
  }

  Future<void> _produits() async {
    if (!await _tableExiste('produits_vendables')) return;
    await _db.customStatement(
      'UPDATE produits_vendables SET espece = ? WHERE espece = ?',
      [nouveau, ancien],
    );
    await _db.customStatement(
      'UPDATE produits_vendables SET cat = ? WHERE cat = ?',
      [_nouvelleCategorie, _ancienneCategorie],
    );
  }

  /// Demandes de modification EN ATTENTE d'un poste d'hier : leur module ou leur espèce
  /// passent aussi à `ovins` (le serveur accepte encore l'ancien nom, mais autant ne plus
  /// l'envoyer).
  Future<void> _demandes() async {
    if (!await _tableExiste('demandes_referentiel')) return;
    await _db.customStatement(
      "UPDATE demandes_referentiel SET "
      "cle = REPLACE(cle, '$ancien', '$nouveau'), "
      "donnees = REPLACE(REPLACE(donnees, '\"$ancien\"', '\"$nouveau\"'), "
      "'\"$_ancienStadeJeune\"', '\"$_nouveauStadeJeune\"') "
      "WHERE sync_status <> 'synced' AND (cle LIKE '%$ancien%' OR donnees LIKE '%\"$ancien\"%')",
    );
  }
}
