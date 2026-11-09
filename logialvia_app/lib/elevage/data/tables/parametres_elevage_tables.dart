import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Barème de rationnement — `parametres-elevage.html` Onglet 1.
///
/// ⚠️ **Table absente de Doc D1.** L'écran Paramètres Élevage annonce pourtant
/// que ces valeurs sont « utilisées pour le calcul automatique dans les fiches
/// journalières » et que « cette page en est la CONFIGURATION, pas une seconde
/// source de données inventée séparément » (commentaire du script du
/// prototype). Sans persistance, l'écran serait décoratif : modifier une ration
/// n'aurait aucun effet sur le calcul de provende.
///
/// Le socle reprend les 12 barèmes réels du prototype ; le `libelle` de stade
/// correspond au `libelle` de [CategorieEspece], ce qui permet de relier une
/// ration modifiée à la catégorie qu'elle rationne.
@DataClassName('BaremeRationRow')
class BaremesRation extends Table {
  /// UUID (DV-19, `46c_`). Semes : UUID DETERMINISTE (meme identifiant sur tous les
  /// postes) ; saisis par l'utilisatrice : UUID aleatoire. Migration v40 pour l'existant.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  /// Identifiant d'espèce — même valeur que `FICHE_JOURNEE.espece`.
  TextColumn get espece => text()();

  /// Stade physiologique. Quand il correspond au libellé d'une catégorie de la
  /// fiche, la ration pilote réellement le calcul de provende de cette
  /// catégorie.
  TextColumn get stade => text()();

  IntColumn get rationGrammesParJour => integer()();

  /// « Confirmé (Référence Cuniculture) » contre « Générique (Aviculture, à
  /// confirmer) » — le prototype distingue les barèmes validés par la Gérante
  /// de ceux repris d'une référence générique.
  BoolColumn get confirme => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {espece, stade},
  ];
}

/// Calendrier de prophylaxie par espèce — `parametres-elevage.html` Onglet 2.
///
/// ⚠️ **Table absente de Doc D1** également. Le prototype la stocke dans
/// `PROPHYLAXIE_STORE`, un objet JavaScript remis à zéro à chaque rechargement
/// de page : ajouter une échéance n'y survit pas à un F5.
@DataClassName('EcheanceProphylaxieRow')
class CalendrierProphylaxie extends Table {
  /// UUID (DV-19, `46c_`). Semes : UUID DETERMINISTE (meme identifiant sur tous les
  /// postes) ; saisis par l'utilisatrice : UUID aleatoire. Migration v40 pour l'existant.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  TextColumn get espece => text()();

  /// Jour du cycle (J1, J5, J15…), tel que saisi dans la modale.
  IntColumn get jourCycle => integer()();

  TextColumn get traitement => text()();
  TextColumn get produit => text()();

  /// Rémanence en jours — délai avant lequel les produits (œufs, viande) ne
  /// doivent pas être commercialisés. 0 = aucune.
  IntColumn get remanenceJours => integer().withDefault(const Constant(0))();

  /// Dose du produit, texte libre (ex. « 7,5 mg par kg de poids vif, voie
  /// orale »). Reprise telle quelle sur le soin lors de l'injection du
  /// calendrier. NULL sur les echeances saisies avant la v27 : leur dose n'a
  /// jamais ete renseignee, et en inventer une serait pire que l'absence.
  ///
  /// La notice du produit utilise prevaut toujours sur cette valeur.
  TextColumn get dose => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Taux de ration par classe de poids vif — DV-17 (bovins), DV-01 (poissons).
///
/// Un ruminant se rationne en **pourcentage de son poids vif**, pas en grammes
/// fixes par tête : un veau de 100 kg et un bœuf de 350 kg n'ont pas le même
/// appétit, et `BAREMES_RATION` n'a qu'une valeur par stade. Cette table donne,
/// par classe de poids moyen, le taux de matière sèche journalier.
///
/// Les poids sont en **grammes**, comme la pesée de la fiche journalière
/// (`FICHE_JOURNEE.poidsGeneralG`) ; l'écran les affiche en kilos.
/// Une classe couvre `[poidsMinG, poidsMaxG[` : la borne basse est comprise, la
/// borne haute exclue, et `poidsMaxG` NULL ouvre la classe vers le haut.
@DataClassName('TauxRationPoidsRow')
class TauxRationPoids extends Table {
  /// UUID (DV-19, `46c_`). Semes : UUID DETERMINISTE (meme identifiant sur tous les
  /// postes) ; saisis par l'utilisatrice : UUID aleatoire. Migration v40 pour l'existant.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  /// Identifiant d'espèce — même valeur que `FICHE_JOURNEE.espece`.
  TextColumn get espece => text()();

  IntColumn get poidsMinG => integer()();
  IntColumn get poidsMaxG => integer().nullable()();

  /// Pourcentage du poids vif par jour, en matière sèche (ex. 3.5).
  RealColumn get tauxPourcent => real()();

  /// Faux tant que l'animalier n'a pas validé le repère.
  BoolColumn get confirme => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {espece, poidsMinG},
  ];
}
