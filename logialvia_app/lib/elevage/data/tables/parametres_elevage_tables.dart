import 'package:drift/drift.dart';

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
  IntColumn get id => integer().autoIncrement()();

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
  IntColumn get id => integer().autoIncrement()();

  TextColumn get espece => text()();

  /// Jour du cycle (J1, J5, J15…), tel que saisi dans la modale.
  IntColumn get jourCycle => integer()();

  TextColumn get traitement => text()();
  TextColumn get produit => text()();

  /// Rémanence en jours — délai avant lequel les produits (œufs, viande) ne
  /// doivent pas être commercialisés. 0 = aucune.
  IntColumn get remanenceJours => integer().withDefault(const Constant(0))();
}
