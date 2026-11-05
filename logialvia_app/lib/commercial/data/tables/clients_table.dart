import 'package:drift/drift.dart';

/// Table `CLIENTS` — Doc D1 §2.
@DataClassName('ClientRow')
class Clients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nom => text()();
  TextColumn get telephone => text().nullable()();

  /// Somme des ventes en statut 'Avance' non soldees.
  ///
  /// NOTE : cette colonne est conservee pour rester conforme a Doc D1, mais le
  /// solde affiche est **recalcule depuis `VENTES`** a chaque lecture. Stocker
  /// un cumul dérivé, c'est accepter qu'il diverge de sa source — le genre
  /// d'incoherence silencieuse que ce projet a deja connue.
  RealColumn get soldeCreance => real().withDefault(const Constant(0))();

  /// ⚠️ AJOUTEE — colonne « Date de Naissance » du tableau et du formulaire
  /// client (`relances-clients.html` l.144 et l.329), absente de Doc D1.
  /// C'est la source des « Événements CRM (7j) » et de l'alerte
  /// « Anniversaire client demain » du tableau de bord.
  DateTimeColumn get dateNaissance => dateTime().nullable()();

  /// ⚠️ AJOUTEE — colonne « Dernier Contact » du tableau CRM (l.251).
  DateTimeColumn get dernierContact => dateTime().nullable()();
}
