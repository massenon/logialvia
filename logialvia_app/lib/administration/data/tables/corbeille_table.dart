import 'package:drift/drift.dart';

/// Corbeille — tout ce qui a ete « supprime » dans l'application.
@DataClassName('ElementArchiveRow')
class Corbeille extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Nom technique de la table d'origine. Vient toujours d'une liste blanche,
  /// jamais d'une saisie : il part dans une requete SQL a la restauration.
  TextColumn get nomTable => text()();

  /// Module d'ou vient l'element — « Elevage », « Commercial »...
  TextColumn get module => text()();

  /// Ce que c'est, en francais : « Barème de rationnement », « Produit ».
  TextColumn get typeElement => text()();

  /// Comment la Gerante le reconnait : « Goliaths — Démarrage ».
  TextColumn get designation => text()();

  /// La ligne entiere, serialisee en JSON. C'est elle qui permet de restaurer
  /// a l'identique, colonnes inconnues comprises.
  TextColumn get donneesJson => text()();

  DateTimeColumn get archiveLe => dateTime()();

  /// Qui a archive. Nullable : les archivages faits hors session (tests,
  /// migrations) n'ont pas d'auteur, et inventer « admin » serait faux.
  TextColumn get archiveParId => text().nullable()();
  TextColumn get archiveParNom => text().nullable()();
}
