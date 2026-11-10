import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Table `BANDES` — **absente de Doc D1 et du prototype**, ajoutée en v25.
///
/// ## La donnée qui manquait
///
/// `parametres-elevage.html` annonce un « calendrier automatique injecté dans
/// Traitements & Prophylaxie des fiches journalières », et
/// `CALENDRIER_PROPHYLAXIE` indexe bien ses échéances sur le **jour du cycle**
/// (J1, J5, J8, J15…). Mais aucune table ne disait à quelle date un cycle
/// commence : sans elle, « J5 » ne se convertit en aucune date réelle, et
/// l'injection restait impossible — point ouvert le plus ancien du projet
/// (Doc INDEX 11-sexdecies).
///
/// Une bande, c'est cela et rien de plus : des sujets mis en place à une date,
/// sur une filière. C'est de cette date que se déduit le jour de cycle, donc
/// les dates réelles des traitements.
///
/// ## Ce que cette table n'est pas
///
/// Elle **ne redécoupe pas** `FICHE_JOURNEE`, qui reste tenue par filière et
/// par jour. Rattacher chaque journée à une bande supposerait de savoir
/// répartir un effectif entre bandes concomitantes — information que personne
/// n'a saisie, et que deviner fausserait tous les effectifs déjà enregistrés.
/// `effectifInitial` est donc **indicatif** : il documente la mise en place,
/// il n'alimente aucun calcul d'effectif.
@DataClassName('BandeRow')
class Bandes extends Table {
  TextColumn get id => text().clientDefault(nouvelUuid)();

  /// Identifiant de filière — même valeur que `FICHE_JOURNEE.espece`.
  TextColumn get espece => text()();

  /// Code terrain, formaté selon le préfixe de l'onglet « Numérotation Bandes
  /// & Sujets » des Paramètres Élevage (ex. « B12 »).
  TextColumn get code => text()();

  /// Date de mise en place — **J1 du cycle**.
  DateTimeColumn get dateMiseEnBande => dateTime()();

  /// Effectif mis en place, tel que déclaré. Indicatif : voir la note de
  /// classe.
  IntColumn get effectifInitial => integer().nullable()();

  /// Renseignée à la clôture de la bande (vendue, transférée, terminée).
  /// `null` = bande en cours.
  DateTimeColumn get dateCloture => dateTime().nullable()();

  TextColumn get observations => text().nullable()();

  // ------------------------------------------------------- Synchronisation
  //
  // Schema v38 (DV-19, `46a_`). `effectifInitial` voyage comme **declaration**
  // (indicative) ; l'effectif REEL n'est jamais stocke ni synchronise : il se
  // recalcule des fiches journalieres.

  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  TextColumn get syncMotif => text().nullable()();

  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {espece, code},
  ];
}
