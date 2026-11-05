import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Peuplement du plan comptable et de l'exercice courant.
///
/// ## ⚠️ Source réellement utilisée, et celle volontairement écartée
///
/// Le dossier `prototype_html` contient un fichier `m10-comptabilite-data.js`
/// avec un plan comptable complet. **Il n'a PAS été utilisé** : il décrit une
/// activité d'hôtellerie-restauration — « Prestations d'hébergement »,
/// « Ventes bar », « Prestations touristiques (circuits) », « Caisse —
/// Restaurant », « Frais plateforme de gestion (hébergement cPanel) » — et son
/// en-tête référence `SEEDER_TEST_LARAVEL.md` et `SPEC_ECRAN_M10_*.md`,
/// documents absents de ce projet. Les fichiers `m10-*.html` ne sont d'ailleurs
/// référencés par aucune entrée de `sidebar.js`.
///
/// C'est un plan comptable **d'un autre projet**, déposé dans le même dossier.
/// L'utiliser aurait donné à une exploitation avicole de Natitingou des comptes
/// de bar et de location de véhicules.
///
/// La source retenue est `plan-comptable.html` (l.179-192), le seul écran
/// réellement relié à la navigation LogiALVIA : **12 comptes**, tous cohérents
/// avec l'activité (Intrants Provende, Frais Vétérinaires, Ventes de Produits
/// Avicoles, Commerce Annexe).
class PlanComptableSeeder {
  const PlanComptableSeeder(this._db);

  final AppDatabase _db;

  /// Les 12 comptes réels de `plan-comptable.html`.
  static const List<({String numero, String libelle, String classe})>
  comptesReels = [
    (numero: '31', libelle: 'Stocks de Marchandises (Commerce Annexe)', classe: '3'),
    (numero: '32', libelle: 'Stocks de Matières (Intrants Provende)', classe: '3'),
    (numero: '401', libelle: 'Fournisseurs', classe: '4'),
    (numero: '411', libelle: 'Clients', classe: '4'),
    (numero: '419', libelle: 'Clients — Avances Reçues', classe: '4'),
    (numero: '512', libelle: 'Banques — Mobile Money', classe: '5'),
    (numero: '531', libelle: 'Caisse', classe: '5'),
    (numero: '601', libelle: 'Achats de Matières (Intrants Provende)', classe: '6'),
    (numero: '602', libelle: 'Achats de Marchandises (Commerce Annexe)', classe: '6'),
    (numero: '622', libelle: 'Frais Vétérinaires', classe: '6'),
    (numero: '701', libelle: 'Ventes de Produits Avicoles', classe: '7'),
    (numero: '707', libelle: 'Ventes de Marchandises (Commerce Annexe)', classe: '7'),
  ];

  /// ⚠️ COMPLÉMENT NÉCESSAIRE, signalé.
  ///
  /// Le plan réel ne contient **aucun compte de classe 1** (capitaux). Or le
  /// Bilan SYSCOHADA exigé par Doc F6 §4 comporte obligatoirement un Capital,
  /// un Report à Nouveau (alimenté par BR-CPT-002 à la clôture annuelle) et un
  /// Résultat de l'exercice. Sans ces 3 comptes, le passif du bilan est
  /// structurellement vide et l'équilibre Actif = Passif est impossible.
  ///
  /// Ces 3 comptes sont donc ajoutés au minimum réglementaire. Ce sont les
  /// numéros standard SYSCOHADA, pas une invention — mais leur absence du
  /// prototype est un manque réel à signaler à la Gérante.
  static const List<({String numero, String libelle, String classe})>
  comptesCapitauxAjoutes = [
    (numero: '101', libelle: 'Capital Social', classe: '1'),
    (numero: '121', libelle: 'Report à Nouveau', classe: '1'),
    (numero: '131', libelle: 'Résultat de l\'Exercice', classe: '1'),
  ];

  /// ⚠️ INCOHÉRENCE RÉELLE DU PROTOTYPE, signalée.
  ///
  /// `saisie-depenses.html` (l.44-49) propose 4 catégories de charges —
  /// **613 Locations, 616 Assurances, 624 Transports, 628 Charges Diverses de
  /// Gestion** — qui ne figurent dans **aucune** ligne de `plan-comptable.html`.
  /// L'écran de saisie des dépenses du prototype impute donc sur des comptes que
  /// l'écran du plan comptable déclare inexistants : sur le web les deux pages
  /// ont chacune leur tableau JavaScript, l'incohérence ne se voit pas.
  ///
  /// Ici les deux écrans lisent la **même** table `PLAN_COMPTABLE` : ces 4
  /// comptes doivent y être, sinon la clé étrangère de `ECRITURE_COMPTABLE`
  /// rejette toute dépense. Les libellés sont ceux de `saisie-depenses.html`,
  /// mot pour mot.
  static const List<({String numero, String libelle, String classe})>
  comptesDepensesAjoutes = [
    (numero: '613', libelle: 'Locations', classe: '6'),
    (numero: '616', libelle: 'Assurances', classe: '6'),
    (numero: '624', libelle: 'Transports', classe: '6'),
    (numero: '628', libelle: 'Charges Diverses de Gestion', classe: '6'),
  ];

  /// Charges considérées comme **fixes** par `saisie-depenses.html` (l.30 du
  /// script : `613` et `616` alimentent le KPI « Charges Fixes », tout le reste
  /// les « Charges Variables »).
  static const Set<String> comptesChargesFixes = {'613', '616'};

  static List<({String numero, String libelle, String classe})> get tous => [
    ...comptesReels,
    ...comptesCapitauxAjoutes,
    ...comptesDepensesAjoutes,
  ];

  /// Retourne `true` si le plan vient d'être peuplé pour la première fois.
  Future<bool> executer() async {
    final premier = await (_db.select(
      _db.planComptable,
    )..limit(1)).getSingleOrNull();
    final planVierge = premier == null;

    await completerComptesManquants();

    // Ouvre l'exercice courant : sans exercice ouvert, aucune écriture ne peut
    // être enregistrée (contrainte de clé étrangère).
    await _ouvrirExerciceSiNecessaire(DateTime.now().year);
    return planVierge;
  }

  /// Insère les comptes du socle absents de la base — **jamais** de mise à jour
  /// ni de suppression.
  ///
  /// Un simple « si la table est vide, la remplir » ne suffit pas : une base
  /// créée avant l'ajout des comptes de dépenses a déjà un plan non vide, et
  /// resterait indéfiniment sans les comptes 613/616/624/628 que l'écran de
  /// saisie des dépenses exige. Un compte renommé ou archivé par la Gérante
  /// n'est pas touché — seuls les numéros absents sont ajoutés.
  Future<void> completerComptesManquants() async {
    final existants = (await _db.select(_db.planComptable).get())
        .map((c) => c.numeroCompte)
        .toSet();

    final manquants = tous
        .where((c) => !existants.contains(c.numero))
        .toList();
    if (manquants.isEmpty) return;

    await _db.batch((batch) {
      batch.insertAll(
        _db.planComptable,
        manquants.map(
          (c) => PlanComptableCompanion.insert(
            numeroCompte: c.numero,
            libelle: c.libelle,
            classe: c.classe,
          ),
        ),
      );
    });
  }

  /// Idempotent — utilisé aussi au changement d'année civile.
  Future<void> _ouvrirExerciceSiNecessaire(int annee) async {
    final existant = await (_db.select(
      _db.exerciceComptable,
    )..where((e) => e.annee.equals(annee))).getSingleOrNull();
    if (existant != null) return;

    await _db
        .into(_db.exerciceComptable)
        // `annee` est un INTEGER PRIMARY KEY, donc alias de rowid cote SQLite :
        // Drift l'expose en `Value<int>` optionnel, il faut l'envelopper.
        .insert(ExerciceComptableCompanion.insert(annee: Value(annee)));
  }

  /// Appelé au démarrage : garantit qu'un exercice existe pour l'année en
  /// cours, même si l'application n'a pas été lancée depuis le 31 décembre.
  Future<void> garantirExerciceCourant() =>
      _ouvrirExerciceSiNecessaire(DateTime.now().year);
}
