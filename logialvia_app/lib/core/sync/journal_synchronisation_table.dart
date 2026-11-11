import 'package:drift/drift.dart';

/// Journal des tentatives de synchronisation **de ce poste** (une ligne par cycle).
///
/// Local au poste : jamais envoyé au serveur, jamais tiré (il décrit ce que CE
/// poste a vécu, et un chemin réseau n'a de sens que sur sa machine). On n'en
/// garde que les [DepotJournalSynchronisation.conservees] dernières.
///
/// Sert l'écran « Synchronisation » : les 10 dernières tentatives et
/// l'export du journal. Ne contient ni jeton, ni mot de passe, ni donnée
/// métier : des compteurs et le message affiché à l'utilisatrice.
@DataClassName('EntreeJournalSynchro')
class JournalSynchronisation extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Début du cycle (heure du poste).
  DateTimeColumn get debutLe => dateTime()();

  IntColumn get dureeMs => integer()();

  /// Ce qui a lancé le cycle : `ouverture`, `routine`, `saisie`, `manuel`,
  /// `demande`, `fermeture`, `appairage`.
  TextColumn get declencheur => text()();

  /// `IssueSynchronisation.name` : `terminee`, `horsLigne`, `revoque`, `refusee`…
  TextColumn get issue => text()();

  /// Message du rapport, tel qu'affiché.
  TextColumn get message => text()();

  IntColumn get recues => integer().withDefault(const Constant(0))();
  IntColumn get envoyees => integer().withDefault(const Constant(0))();
  IntColumn get acceptees => integer().withDefault(const Constant(0))();
  IntColumn get refusees => integer().withDefault(const Constant(0))();
  IntColumn get enAttenteDeDroit => integer().withDefault(const Constant(0))();
}
