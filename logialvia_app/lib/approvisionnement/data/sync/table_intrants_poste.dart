import 'package:drift/drift.dart';

import '../../../administration/data/sync/depot_demandes_referentiel.dart';
import '../../../administration/domain/services/service_archivage.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';

/// `intrants` — **référentiel** : le serveur gagne (`46_` §2.2).
///
/// Décision du client : **stock propre à chaque poste + journal partagé**.
/// - Le poste ne l'envoie jamais ; il le **propose** (`DepotDemandesReferentiel`).
/// - **Le stock et le PMP ne sont JAMAIS absorbés** : un intrant créé par un autre
///   poste arrive avec un stock et un PMP de 0 ; un intrant connu garde les siens.
/// - La clé est le **code** (partagée par tous les postes).
/// - Règle du plus récent contre une demande locale en attente ; ligne incohérente
///   refusée ; une remise à zéro préserve les intrants.
class TableIntrantsPoste implements TablePoste {
  const TableIntrantsPoste(this._db);

  final AppDatabase _db;

  DepotDemandesReferentiel get _depot => DepotDemandesReferentiel(_db);

  @override
  String get nom => 'intrants';

  @override
  bool get referentiel => true;

  @override
  Stream<void> get modifications => const Stream<void>.empty();

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        final code = _texte(l['code']);
        final nomIntrant = _texte(l['name']);
        final cat = _texte(l['cat']);
        final unite = _texte(l['unit']);
        final seuil = l['threshold'];
        // Strict : une ligne incohérente est refusée, jamais lissée.
        if (code == null ||
            code.length > 40 ||
            nomIntrant == null ||
            cat == null ||
            unite == null ||
            (seuil != null && (seuil is! num || seuil < 0))) {
          refusees++;
          continue;
        }

        final demande = await _depot.enAttente(
          DepotDemandesReferentiel.typeIntrant,
          code,
        );
        if (demande != null) {
          final serveur = DateTime.tryParse('${l['saisi_le']}');
          if (serveur == null ||
              !serveur.isAfter(DateTime.parse(demande.saisiLe))) {
            conservees++; // la saisie locale est plus récente : elle partira
            continue;
          }
        }

        final locale = await (_db.select(
          _db.intrants,
        )..where((i) => i.code.equals(code))).getSingleOrNull();

        // Pierre tombale : l'intrant a été supprimé sur un autre poste (`47h_` D4).
        final archive = l['archive_le'];
        if (archive is String && archive.isNotEmpty) {
          if (locale != null && await _archiver(locale)) absorbees++;
          if (demande != null) await _depot.abandonner(demande.id);
          continue;
        }

        if (locale == null) {
          await _db
              .into(_db.intrants)
              .insert(
                IntrantsCompanion.insert(
                  code: code,
                  name: nomIntrant,
                  cat: cat,
                  stock: 0, // propre à chaque poste : jamais absorbé
                  unit: unite,
                  threshold: (seuil as num?)?.toInt() ?? 0,
                  pmp: 0, // idem
                ),
              );
          absorbees++;
        } else {
          final nouveau = locale.copyWith(
            name: nomIntrant,
            cat: cat,
            unit: unite,
            threshold: (seuil as num?)?.toInt() ?? locale.threshold,
            // `stock` et `pmp` : volontairement absents.
          );
          if (nouveau != locale) {
            await _db.update(_db.intrants).replace(nouveau);
            absorbees++;
            if (demande != null) supplantees++;
          }
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

  /// Archive ici l'intrant supprimé ailleurs (corbeille de CE poste, restaurable). Un
  /// intrant déjà cité par un achat ou un mouvement d'ICI reste : son historique l'exige
  /// (clé étrangère) et le supprimer à la main échouerait de la même façon.
  /// Faux = conservé.
  Future<bool> _archiver(IntrantRow intrant) async {
    final cite = await _db
        .customSelect(
          'SELECT 1 FROM lignes_achat WHERE intrant_code = ? '
          'UNION SELECT 1 FROM mouvements_intrant WHERE intrant_code = ? LIMIT 1',
          variables: [
            Variable.withString(intrant.code),
            Variable.withString(intrant.code),
          ],
        )
        .getSingleOrNull();
    if (cite != null) return false;
    await ServiceArchivage(_db).archiver(
      type: TypeArchivable.intrants,
      cle: intrant.code,
      designation: '${intrant.code} — ${intrant.name}',
    );
    return true;
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
