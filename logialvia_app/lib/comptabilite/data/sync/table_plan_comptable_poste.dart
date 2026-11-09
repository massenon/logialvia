import 'package:drift/drift.dart';

import '../../../administration/data/sync/depot_demandes_referentiel.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';

/// `plan_comptable` — **référentiel** : le serveur gagne, le poste PROPOSE (`46d_` §2).
///
/// - **Clé naturelle** : le numéro de compte, la même sur tous les postes ; le plan est
///   semé à l'identique partout (`PlanComptableSeeder`), donc rien n'est converti en UUID.
/// - Le poste ne l'envoie jamais ; un compte créé, renommé ou archivé ici part comme
///   **demande** (`compte_comptable`) ; le serveur décide et le résultat redescend.
/// - **Valeur de semis ≠ décision** : un compte que le serveur n'a jamais décidé
///   (`updated_at == created_at`) n'écrase pas le poste.
/// - Règle du plus récent contre une demande locale en attente ; ligne incohérente
///   **refusée et comptée**, jamais lissée ; le plan n'est jamais purgé (référentiel).
class TablePlanComptablePoste implements TablePoste {
  const TablePlanComptablePoste(this._db);

  final AppDatabase _db;

  DepotDemandesReferentiel get _depot => DepotDemandesReferentiel(_db);

  static final RegExp _numero = RegExp(r'^[1-7]\d{0,19}$');

  @override
  String get nom => 'plan_comptable';

  @override
  bool get referentiel => true;

  @override
  Stream<void> get modifications => const Stream<void>.empty();

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        final numero = _texte(l['numero_compte']);
        final libelle = _texte(l['libelle']);
        final classe = _texte(l['classe']);
        final archive = l['archive'];
        // Strict : une ligne incohérente est refusée, jamais lissée.
        if (numero == null ||
            !_numero.hasMatch(numero) ||
            libelle == null ||
            classe == null ||
            !numero.startsWith(classe) ||
            classe.length != 1 ||
            archive is! bool) {
          refusees++;
          continue;
        }

        final creation = DateTime.tryParse('${l['created_at']}');
        final decision = DateTime.tryParse('${l['updated_at']}');
        final decide =
            creation != null && decision != null && decision.isAfter(creation);

        final demande = await _depot.enAttente(
          DepotDemandesReferentiel.typeCompte,
          numero,
        );
        if (demande != null && decide) {
          final serveur = DateTime.tryParse('${l['saisi_le']}');
          if (serveur == null ||
              !serveur.isAfter(DateTime.parse(demande.saisiLe))) {
            conservees++; // la saisie locale est plus récente : elle partira
            continue;
          }
        }

        final locale = await (_db.select(
          _db.planComptable,
        )..where((c) => c.numeroCompte.equals(numero))).getSingleOrNull();

        if (locale == null) {
          await _db
              .into(_db.planComptable)
              .insert(
                PlanComptableCompanion.insert(
                  numeroCompte: numero,
                  libelle: libelle,
                  classe: classe,
                  archive: Value(archive),
                ),
              );
          absorbees++;
        } else if (decide) {
          if (locale.classe != classe) {
            // Un compte mouvementé ne change pas de classe : cela déplacerait
            // rétroactivement ses écritures d'un poste du bilan à un autre.
            final n = _db.ecritureComptable.id.count();
            final mouvements =
                await (_db.selectOnly(_db.ecritureComptable)
                      ..addColumns([n])
                      ..where(
                        _db.ecritureComptable.numeroCompte.equals(numero),
                      ))
                    .map((r) => r.read(n) ?? 0)
                    .getSingle();
            if (mouvements > 0) {
              refusees++;
              continue;
            }
          }
          if (locale.libelle != libelle ||
              locale.classe != classe ||
              locale.archive != archive) {
            await (_db.update(
              _db.planComptable,
            )..where((c) => c.numeroCompte.equals(numero))).write(
              PlanComptableCompanion(
                libelle: Value(libelle),
                classe: Value(classe),
                archive: Value(archive),
              ),
            );
            absorbees++;
            if (demande != null) supplantees++;
          }
        } else {
          continue; // valeur de semis : le poste garde la sienne
        }
        if (demande != null) await _depot.abandonner(demande.id);
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
  Future<List<LigneAEnvoyer>> aEnvoyer() async => const [];

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {}

  @override
  Future<void> marquerConflit(String id, String motif) async {}

  @override
  Future<int> purger() async => 0;
}
