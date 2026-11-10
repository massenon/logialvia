import 'package:drift/drift.dart';

import '../../../administration/data/sync/depot_demandes_referentiel.dart';
import '../../../administration/data/sync/regle_referentiel.dart';
import '../../../administration/domain/services/service_archivage.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';

/// Base commune des **référentiels d'élevage** (`46_` §2.2, `46c_`) : barèmes de
/// ration, taux par classe de poids vif, calendrier de prophylaxie.
///
/// - Le **serveur gagne** ; le poste ne les envoie jamais, il les **propose**
///   (`DepotDemandesReferentiel`, une demande par ligne, type propre à chaque table).
/// - **Absorbeur strict** : une ligne incohérente est REFUSÉE et comptée.
/// - **Règle du plus récent** : une demande locale en attente n'est supplantée que
///   par une décision du serveur POSTÉRIEURE à la saisie (`saisi_le`).
/// - **Pierre tombale** : une ligne supprimée sur un autre poste (`archive_le`) est
///   archivée dans la corbeille d'ICI (restaurable). Un poste neuf ne crée jamais une
///   ligne archivée.
/// - **Clé naturelle** : si le serveur sert une ligne dont la clé unique (espèce +
///   stade, espèce + poids minimal) est déjà portée ici par un AUTRE identifiant, la
///   ligne locale non modifiée cède la place (le serveur gagne) ; si elle a une
///   demande en attente, elle est conservée et partira.
/// - Une remise à zéro préserve les référentiels (blueprint §6).
abstract class _TableParametresElevagePoste implements TablePoste {
  const _TableParametresElevagePoste(this._db);

  final AppDatabase _db;

  DepotDemandesReferentiel get _depot => DepotDemandesReferentiel(_db);

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Type de demande de cette table.
  String get typeDemande;

  /// Valide une ligne tirée ; `null` si elle est incohérente.
  Map<String, Object?>? valider(Map<String, dynamic> ligne);

  /// Écrit (ou remplace) la ligne ; renvoie vrai si la base a changé. [id] est
  /// l'identifiant du serveur, [v] le résultat de [valider].
  Future<bool> ecrire(String id, Map<String, Object?> v);

  /// Archive ici la ligne supprimée ailleurs ; faux si elle n'existe pas.
  Future<bool> archiver(String id);

  /// Identifiant d'une AUTRE ligne locale portant la même clé naturelle, ou `null`.
  Future<String?> autreIdentifiantMemeCle(String id, Map<String, Object?> v);

  /// Supprime la ligne locale de cet identifiant (cède la place au serveur).
  Future<void> supprimerLocale(String id);

  static String? texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  @override
  bool get referentiel => true;

  @override
  Stream<void> get modifications => const Stream<void>.empty();

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        final id = l['id'];
        final v = id is String && _uuid.hasMatch(id) ? valider(l) : null;
        if (v == null) {
          refusees++;
          continue;
        }
        final identifiant = id as String;

        final demande = await _depot.enAttente(typeDemande, identifiant);
        if (demande != null) {
          final serveur = DateTime.tryParse('${l['saisi_le']}');
          if (serveur == null ||
              !serveur.isAfter(DateTime.parse(demande.saisiLe))) {
            conservees++; // la saisie locale est plus récente : elle partira
            continue;
          }
        }

        // Pierre tombale : la ligne a été supprimée sur un autre poste.
        final archive = l['archive_le'];
        if (archive is String && archive.isNotEmpty) {
          if (await archiver(identifiant)) absorbees++;
          if (demande != null) await _depot.abandonner(demande.id);
          continue;
        }

        // Même clé naturelle sous un autre identifiant : le serveur gagne, sauf si la
        // ligne locale attend d'être proposée.
        final autre = await autreIdentifiantMemeCle(identifiant, v);
        if (autre != null) {
          if (await _depot.enAttente(typeDemande, autre) != null) {
            conservees++;
            continue;
          }
          await supprimerLocale(autre);
        }

        if (await ecrire(identifiant, v)) {
          absorbees++;
          if (demande != null) supplantees++;
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

  // Un référentiel ne s'envoie pas : il se propose.
  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async => const [];

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {}

  @override
  Future<void> marquerConflit(String id, String motif) async {}

  @override
  Future<int> purger() async => 0;
}

/// `baremes_ration` — clé unique (espèce, stade).
class TableBaremesRationPoste extends _TableParametresElevagePoste {
  const TableBaremesRationPoste(super.db);

  @override
  String get nom => 'baremes_ration';

  @override
  String get typeDemande => DepotDemandesReferentiel.typeBareme;

  @override
  Map<String, Object?>? valider(Map<String, dynamic> l) {
    final espece = _TableParametresElevagePoste.texte(l['espece']);
    final stade = _TableParametresElevagePoste.texte(l['stade']);
    final ration = l['ration_grammes_par_jour'];
    final confirme = lireBool(l['confirme']);
    if (espece == null ||
        stade == null ||
        ration is! int ||
        ration < 1 ||
        ration > 20000 ||
        confirme == null) {
      return null;
    }
    return {
      'espece': espece,
      'stade': stade,
      'ration': ration,
      'confirme': confirme,
    };
  }

  @override
  Future<String?> autreIdentifiantMemeCle(
    String id,
    Map<String, Object?> v,
  ) async {
    final autre =
        await (_db.select(_db.baremesRation)..where(
              (b) =>
                  b.espece.equals(v['espece']! as String) &
                  b.stade.equals(v['stade']! as String) &
                  b.id.isNotValue(id),
            ))
            .getSingleOrNull();
    return autre?.id;
  }

  @override
  Future<void> supprimerLocale(String id) =>
      (_db.delete(_db.baremesRation)..where((b) => b.id.equals(id))).go();

  @override
  Future<bool> ecrire(String id, Map<String, Object?> v) async {
    final locale = await (_db.select(
      _db.baremesRation,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
    if (locale == null) {
      await _db
          .into(_db.baremesRation)
          .insert(
            BaremesRationCompanion.insert(
              id: Value(id),
              espece: v['espece']! as String,
              stade: v['stade']! as String,
              rationGrammesParJour: v['ration']! as int,
              confirme: Value(v['confirme']! as bool),
            ),
          );
      return true;
    }
    final nouveau = locale.copyWith(
      espece: v['espece']! as String,
      stade: v['stade']! as String,
      rationGrammesParJour: v['ration']! as int,
      confirme: v['confirme']! as bool,
    );
    if (nouveau == locale) return false;
    await _db.update(_db.baremesRation).replace(nouveau);
    return true;
  }

  @override
  Future<bool> archiver(String id) async {
    final ligne = await (_db.select(
      _db.baremesRation,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
    if (ligne == null) return false;
    await ServiceArchivage(_db).archiver(
      type: TypeArchivable.baremes,
      cle: id,
      designation: '${ligne.espece} — ${ligne.stade}',
    );
    return true;
  }
}

/// `taux_ration_poids` — clé unique (espèce, poids minimal).
class TableTauxRationPoidsPoste extends _TableParametresElevagePoste {
  const TableTauxRationPoidsPoste(super.db);

  @override
  String get nom => 'taux_ration_poids';

  @override
  String get typeDemande => DepotDemandesReferentiel.typeTauxPoids;

  @override
  Map<String, Object?>? valider(Map<String, dynamic> l) {
    final espece = _TableParametresElevagePoste.texte(l['espece']);
    final min = l['poids_min_g'];
    final max = l['poids_max_g'];
    final taux = l['taux_pourcent'];
    final confirme = lireBool(l['confirme']);
    if (espece == null ||
        min is! int ||
        min < 0 ||
        (max != null && (max is! int || max <= min)) ||
        taux is! num ||
        taux <= 0 ||
        taux > 25 ||
        confirme == null) {
      return null;
    }
    return {
      'espece': espece,
      'min': min,
      'max': max,
      'taux': taux.toDouble(),
      'confirme': confirme,
    };
  }

  @override
  Future<String?> autreIdentifiantMemeCle(
    String id,
    Map<String, Object?> v,
  ) async {
    final autre =
        await (_db.select(_db.tauxRationPoids)..where(
              (t) =>
                  t.espece.equals(v['espece']! as String) &
                  t.poidsMinG.equals(v['min']! as int) &
                  t.id.isNotValue(id),
            ))
            .getSingleOrNull();
    return autre?.id;
  }

  @override
  Future<void> supprimerLocale(String id) =>
      (_db.delete(_db.tauxRationPoids)..where((t) => t.id.equals(id))).go();

  @override
  Future<bool> ecrire(String id, Map<String, Object?> v) async {
    final locale = await (_db.select(
      _db.tauxRationPoids,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (locale == null) {
      await _db
          .into(_db.tauxRationPoids)
          .insert(
            TauxRationPoidsCompanion.insert(
              id: Value(id),
              espece: v['espece']! as String,
              poidsMinG: v['min']! as int,
              poidsMaxG: Value(v['max'] as int?),
              tauxPourcent: v['taux']! as double,
              confirme: Value(v['confirme']! as bool),
            ),
          );
      return true;
    }
    final nouveau = locale.copyWith(
      espece: v['espece']! as String,
      poidsMinG: v['min']! as int,
      poidsMaxG: Value(v['max'] as int?),
      tauxPourcent: v['taux']! as double,
      confirme: v['confirme']! as bool,
    );
    if (nouveau == locale) return false;
    await _db.update(_db.tauxRationPoids).replace(nouveau);
    return true;
  }

  @override
  Future<bool> archiver(String id) async {
    final ligne = await (_db.select(
      _db.tauxRationPoids,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (ligne == null) return false;
    await ServiceArchivage(_db).archiver(
      type: TypeArchivable.tauxPoids,
      cle: id,
      designation:
          '${ligne.espece} — ${ligne.poidsMinG} g (${ligne.tauxPourcent} %)',
    );
    return true;
  }
}

/// `calendrier_prophylaxie` — pas de clé naturelle unique : seul l'UUID identifie.
class TableCalendrierProphylaxiePoste extends _TableParametresElevagePoste {
  const TableCalendrierProphylaxiePoste(super.db);

  @override
  String get nom => 'calendrier_prophylaxie';

  @override
  String get typeDemande => DepotDemandesReferentiel.typeEcheance;

  @override
  Map<String, Object?>? valider(Map<String, dynamic> l) {
    final espece = _TableParametresElevagePoste.texte(l['espece']);
    final jour = l['jour_cycle'];
    final traitement = _TableParametresElevagePoste.texte(l['traitement']);
    final produit = _TableParametresElevagePoste.texte(l['produit']);
    final remanence = l['remanence_jours'];
    if (espece == null ||
        jour is! int ||
        jour < 1 ||
        jour > 365 ||
        traitement == null ||
        produit == null ||
        remanence is! int ||
        remanence < 0 ||
        (l['dose'] != null && l['dose'] is! String)) {
      return null;
    }
    return {
      'espece': espece,
      'jour': jour,
      'traitement': traitement,
      'produit': produit,
      'remanence': remanence,
      'dose': _TableParametresElevagePoste.texte(l['dose']),
    };
  }

  @override
  Future<String?> autreIdentifiantMemeCle(
    String id,
    Map<String, Object?> v,
  ) async => null;

  @override
  Future<void> supprimerLocale(String id) async {}

  @override
  Future<bool> ecrire(String id, Map<String, Object?> v) async {
    final locale = await (_db.select(
      _db.calendrierProphylaxie,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (locale == null) {
      await _db
          .into(_db.calendrierProphylaxie)
          .insert(
            CalendrierProphylaxieCompanion.insert(
              id: Value(id),
              espece: v['espece']! as String,
              jourCycle: v['jour']! as int,
              traitement: v['traitement']! as String,
              produit: v['produit']! as String,
              remanenceJours: Value(v['remanence']! as int),
              dose: Value(v['dose'] as String?),
            ),
          );
      return true;
    }
    final nouveau = locale.copyWith(
      espece: v['espece']! as String,
      jourCycle: v['jour']! as int,
      traitement: v['traitement']! as String,
      produit: v['produit']! as String,
      remanenceJours: v['remanence']! as int,
      dose: Value(v['dose'] as String?),
    );
    if (nouveau == locale) return false;
    await _db.update(_db.calendrierProphylaxie).replace(nouveau);
    return true;
  }

  @override
  Future<bool> archiver(String id) async {
    final ligne = await (_db.select(
      _db.calendrierProphylaxie,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (ligne == null) return false;
    await ServiceArchivage(_db).archiver(
      type: TypeArchivable.prophylaxie,
      cle: id,
      designation: '${ligne.espece} — J+${ligne.jourCycle} ${ligne.traitement}',
    );
    return true;
  }
}
