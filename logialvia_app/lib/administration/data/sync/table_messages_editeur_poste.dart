import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../tables/messages_editeur_table.dart';

/// `messages_editeur` — les messages adressés à l'éditeur : un FAIT saisi au poste (ou au
/// web), **dernier écrivain gagne** par UUID (`46_` §2.3, doc 47u §4).
///
/// ## Aucun effet de bord
///
/// Absorber le message d'un autre poste (ou du web) ne fait rien d'autre que l'inscrire au
/// registre : **aucun e-mail n'est envoyé**, ni ici ni au serveur. Le message reste
/// « En attente » tant qu'un humain ne l'a pas transmis lui-même.
///
/// ## Suppression
///
/// Supprimer un message le range en corbeille. La suppression voyage comme une **pierre
/// tombale** : l'instantané de la corbeille (qui porte l'instant de la suppression) repart
/// au serveur avec `supprime_le`. Restaurer le message lève la pierre tombale (il repart,
/// daté de maintenant). Une corbeille vidée avant l'envoi perd la pierre tombale (limite
/// documentée, comme pour les lots de couveuse).
class TableMessagesEditeurPoste implements TablePoste {
  const TableMessagesEditeurPoste(this._db);

  final AppDatabase _db;

  static const String _tableArchivee = 'messages_editeur';

  static const List<String> _types = ['question', 'bug'];

  static const List<String> _statuts = [
    MessageEditeurStatut.enAttente,
    MessageEditeurStatut.transmis,
  ];

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  String get nom => 'messages_editeur';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([_db.messagesEditeur, _db.corbeille]),
      )
      .map((_) {});

  // ------------------------------------------------------------- Absorption

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        final id = l['id'];
        final type = l['type'];
        final sujet = l['sujet'];
        final texte = l['message'];
        final statut = l['statut'];
        final etapes = l['etapes'];
        final auteur = l['auteur'];
        final horodatage = l['horodatage'] is String
            ? DateTime.tryParse(l['horodatage'] as String)
            : null;
        final instant = l['updated_at'] is String
            ? DateTime.tryParse(l['updated_at'] as String)
            : null;
        // Strict : une ligne incohérente est refusée, jamais lissée.
        if (id is! String ||
            !_uuid.hasMatch(id) ||
            type is! String ||
            !_types.contains(type) ||
            sujet is! String ||
            sujet.trim().isEmpty ||
            texte is! String ||
            texte.trim().isEmpty ||
            statut is! String ||
            !_statuts.contains(statut) ||
            (etapes != null && etapes is! String) ||
            (auteur != null && auteur is! String) ||
            horodatage == null ||
            instant == null) {
          refusees++;
          continue;
        }

        final locale = await (_db.select(
          _db.messagesEditeur,
        )..where((m) => m.id.equals(id))).getSingleOrNull();
        var supplantee = false;
        if (locale != null && locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++; // la saisie locale est plus récente : elle gagnera
            continue;
          }
          supplantee =
              true; // le serveur a une version strictement plus récente
        }

        // Pierre tombale : le serveur a supprimé ce message.
        if (l['supprime_le'] != null) {
          if (supplantee) supplantees++;
          if (locale != null) {
            await (_db.delete(
              _db.messagesEditeur,
            )..where((m) => m.id.equals(id))).go();
            absorbees++;
          }
          continue;
        }

        // Un message SUPPRIMÉ ici (corbeille) n'est pas ressuscité par l'écho du serveur :
        // son propre envoi lui revient au tirage suivant, avant que la pierre tombale soit
        // partie. Seule une version STRICTEMENT plus récente le fait revenir.
        if (locale == null) {
          final archive = await _archiveDe(id);
          if (archive != null) {
            final saisieArchive = archive.donnees['updated_at'] is String
                ? DateTime.tryParse(archive.donnees['updated_at'] as String)
                : null;
            if (saisieArchive != null && !instant.isAfter(saisieArchive)) {
              conservees++;
              continue;
            }
            if (archive.donnees['sync_status'] != 'synced') supplantees++;
            await _marquerArchive(id, null, 'synced', null);
          }
        }

        if (supplantee) supplantees++;
        await _db
            .into(_db.messagesEditeur)
            .insertOnConflictUpdate(
              MessagesEditeurCompanion(
                id: Value(id),
                horodatage: Value(horodatage.toLocal()),
                type: Value(type),
                sujet: Value(sujet.trim()),
                message: Value(texte.trim()),
                etapes: Value(
                  etapes is String && etapes.trim().isNotEmpty
                      ? etapes.trim()
                      : null,
                ),
                // L'identifiant d'utilisatrice est LOCAL : un message reçu n'en a pas ici.
                utilisateurId: Value(locale?.utilisateurId ?? ''),
                statut: Value(statut),
                auteurNom: Value(auteur as String?),
                syncStatus: const Value('synced'),
                syncMotif: const Value(null),
                updatedAt: Value(instant.toUtc().toIso8601String()),
              ),
            );
        absorbees++;
      }
      return ResultatAbsorption(
        absorbees: absorbees,
        refusees: refusees,
        conservees: conservees,
        supplantees: supplantees,
      );
    });
  }

  // ------------------------------------------------------------------ Envoi

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final lignes = await (_db.select(
      _db.messagesEditeur,
    )..where((m) => m.syncStatus.equals('pending'))).get();

    final envois = <LigneAEnvoyer>[
      for (final m in lignes)
        LigneAEnvoyer(
          id: m.id,
          instantSaisie: m.updatedAt,
          corps: {
            'id': m.id,
            'horodatage': m.horodatage.toUtc().toIso8601String(),
            'type': m.type,
            'sujet': m.sujet,
            'message': m.message,
            'etapes': m.etapes,
            'auteur': m.auteurNom,
            'statut': m.statut,
            'supprime_le': null,
            'updated_at': m.updatedAt,
          },
        ),
    ];

    // Pierres tombales : les messages supprimés dont la suppression n'est pas partie.
    for (final archive in await _archives()) {
      final donnees = archive.donnees;
      if (donnees['sync_status'] != 'pending') continue;
      final id = donnees['id'];
      final saisie = donnees['updated_at'];
      final horodatage = donnees['horodatage'];
      if (id is! String ||
          saisie is! String ||
          horodatage is! int ||
          !_uuid.hasMatch(id)) {
        continue;
      }
      envois.add(
        LigneAEnvoyer(
          id: id,
          instantSaisie: saisie,
          corps: {
            'id': id,
            'horodatage': DateTime.fromMillisecondsSinceEpoch(
              horodatage * 1000,
            ).toUtc().toIso8601String(),
            'type': donnees['type'],
            'sujet': donnees['sujet'],
            'message': donnees['message'],
            'etapes': donnees['etapes'],
            'auteur': donnees['auteur_nom'],
            'statut': donnees['statut'],
            'supprime_le': saisie,
            'updated_at': saisie,
          },
        ),
      );
    }

    envois.sort((a, b) {
      final c = DateTime.parse(
        a.instantSaisie,
      ).compareTo(DateTime.parse(b.instantSaisie));
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return envois;
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    final ecrites =
        await (_db.update(_db.messagesEditeur)..where(
              (m) => m.id.equals(id) & m.updatedAt.equals(instantEnvoye),
            ))
            .write(
              const MessagesEditeurCompanion(
                syncStatus: Value('synced'),
                syncMotif: Value(null),
              ),
            );
    if (ecrites == 0) {
      await _marquerArchive(id, instantEnvoye, 'synced', null);
    }
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    final ecrites =
        await (_db.update(
          _db.messagesEditeur,
        )..where((m) => m.id.equals(id))).write(
          MessagesEditeurCompanion(
            syncStatus: const Value('conflict'),
            syncMotif: Value(motif),
          ),
        );
    if (ecrites == 0) {
      await _marquerArchive(id, null, 'conflict', motif);
    }
  }

  /// Remise à zéro du serveur : vide les messages. La corbeille n'est pas touchée (elle
  /// appartient à l'utilisatrice) ; les saisies non envoyées sont comptées.
  @override
  Future<int> purger() async {
    final nonEnvoyes = await (_db.select(
      _db.messagesEditeur,
    )..where((m) => m.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.messagesEditeur).go();
    return nonEnvoyes.length;
  }

  // ------------------------------------------------------------------ Outils

  Future<List<_Archive>> _archives() async {
    final lignes = await (_db.select(
      _db.corbeille,
    )..where((c) => c.nomTable.equals(_tableArchivee))).get();
    final archives = <_Archive>[];
    for (final ligne in lignes) {
      try {
        final donnees = jsonDecode(ligne.donneesJson);
        if (donnees is Map<String, Object?>) {
          archives.add(_Archive(ligne.id, donnees));
        }
      } on FormatException {
        // Instantané illisible : il ne part pas, il ne bloque rien.
      }
    }
    return archives;
  }

  /// L'instantané de corbeille le plus récent de ce message, s'il en existe un.
  Future<_Archive?> _archiveDe(String id) async {
    _Archive? plusRecente;
    for (final archive in await _archives()) {
      if (archive.donnees['id'] != id) continue;
      if (plusRecente == null ||
          archive.idCorbeille > plusRecente.idCorbeille) {
        plusRecente = archive;
      }
    }
    return plusRecente;
  }

  /// Marque l'instantané d'un message supprimé (accusé de sa pierre tombale, ou refus).
  /// [instant] non nul : ne touche que si l'instantané n'a pas changé depuis l'envoi.
  Future<void> _marquerArchive(
    String id,
    String? instant,
    String statut,
    String? motif,
  ) async {
    for (final archive in await _archives()) {
      if (archive.donnees['id'] != id) continue;
      if (instant != null && archive.donnees['updated_at'] != instant) continue;
      final donnees = {
        ...archive.donnees,
        'sync_status': statut,
        'sync_motif': motif,
      };
      await (_db.update(_db.corbeille)
            ..where((c) => c.id.equals(archive.idCorbeille)))
          .write(CorbeilleCompanion(donneesJson: Value(jsonEncode(donnees))));
    }
  }
}

class _Archive {
  const _Archive(this.idCorbeille, this.donnees);

  final int idCorbeille;
  final Map<String, Object?> donnees;
}
