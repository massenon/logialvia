import 'dart:io';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'moteur_synchronisation.dart';

/// Écrit et relit le journal des tentatives de synchronisation du poste.
class DepotJournalSynchronisation {
  DepotJournalSynchronisation(this._db);

  final AppDatabase _db;

  /// Nombre de cycles gardés ; les plus anciens sont supprimés à chaque écriture.
  static const int conservees = 200;

  /// Enregistre un cycle. Un poste hors ligne ne remplit pas le journal : deux
  /// « hors ligne » de suite ne font qu'une ligne.
  Future<void> enregistrer({
    required DateTime debut,
    required Duration duree,
    required String declencheur,
    required RapportSynchronisation rapport,
  }) async {
    if (rapport.issue == IssueSynchronisation.nonAppairee) return;
    if (rapport.issue == IssueSynchronisation.horsLigne) {
      final derniere = await dernieres(1);
      if (derniere.isNotEmpty &&
          derniere.first.issue == IssueSynchronisation.horsLigne.name) {
        return;
      }
    }

    await _db
        .into(_db.journalSynchronisation)
        .insert(
          JournalSynchronisationCompanion.insert(
            debutLe: debut,
            dureeMs: duree.inMilliseconds,
            declencheur: declencheur,
            issue: rapport.issue.name,
            message: rapport.message,
            recues: Value(rapport.recues),
            envoyees: Value(rapport.envoyees),
            acceptees: Value(rapport.acceptees),
            refusees: Value(rapport.refusees),
            enAttenteDeDroit: Value(rapport.enAttenteDeDroit),
          ),
        );
    await _purger();
  }

  Future<void> _purger() async {
    await _db.customStatement(
      'DELETE FROM journal_synchronisation WHERE id NOT IN '
      '(SELECT id FROM journal_synchronisation ORDER BY id DESC LIMIT $conservees)',
    );
  }

  /// Les [n] derniers cycles, du plus récent au plus ancien.
  Future<List<EntreeJournalSynchro>> dernieres([int n = 10]) =>
      (_db.select(_db.journalSynchronisation)
            ..orderBy([(j) => OrderingTerm.desc(j.id)])
            ..limit(n))
          .get();

  /// Journal complet au format CSV (séparateur `;`, ouvrable dans Excel).
  Future<String> exporterCsv() async {
    final lignes = await (_db.select(
      _db.journalSynchronisation,
    )..orderBy([(j) => OrderingTerm.desc(j.id)])).get();
    String champ(Object? v) {
      final t = '$v'.replaceAll('"', '""');
      return t.contains(RegExp(r'[;"\n\r]')) ? '"$t"' : t;
    }

    final sortie = StringBuffer(
      '\u{FEFF}date;duree_ms;declencheur;issue;recues;envoyees;acceptees;'
      'refusees;en_attente_de_droit;message\r\n',
    );
    for (final j in lignes) {
      sortie.write(
        [
          j.debutLe.toIso8601String(),
          j.dureeMs,
          j.declencheur,
          j.issue,
          j.recues,
          j.envoyees,
          j.acceptees,
          j.refusees,
          j.enAttenteDeDroit,
          j.message,
        ].map(champ).join(';'),
      );
      sortie.write('\r\n');
    }
    return sortie.toString();
  }

  /// Écrit le CSV dans [dossier] (créé au besoin) et renvoie le fichier.
  Future<File> exporterVers(Directory dossier) async {
    await dossier.create(recursive: true);
    final maintenant = DateTime.now();
    String d2(int n) => n.toString().padLeft(2, '0');
    final nom =
        'Journal-synchronisation-${maintenant.year}${d2(maintenant.month)}'
        '${d2(maintenant.day)}-${d2(maintenant.hour)}${d2(maintenant.minute)}.csv';
    final fichier = File('${dossier.path}${Platform.pathSeparator}$nom');
    await fichier.writeAsString(await exporterCsv());
    return fichier;
  }
}
