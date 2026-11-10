import '../../domain/services/service_archivage.dart';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../domain/entities/compte_utilisateur.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../domain/services/hachage_mot_de_passe.dart';
import '../tables/messages_editeur_table.dart';

abstract class CompteRepository {
  Future<MetadonneesSession> metadonneesSession(int utilisateurId);

  Future<List<EntreeJournalPersonnel>> journalPersonnel(
    int utilisateurId, {
    int limite = 20,
  });

  /// Change le mot de passe **après vérification de l'ancien**.
  ///
  /// Lève [MotDePasseIncorrect] si l'ancien mot de passe ne correspond pas :
  /// la distinction doit remonter à l'écran, un message générique
  /// empêcherait l'utilisatrice de comprendre son erreur — contrairement à
  /// l'écran de connexion, où le message reste volontairement générique pour
  /// ne pas révéler l'existence d'un compte (Doc I3 §5).
  Future<void> changerMotDePasse({
    required int utilisateurId,
    required String ancienMotDePasse,
    required String nouveauMotDePasse,
  });

  Future<List<MessageEditeur>> chargerMessages();

  Future<void> enregistrerMessage({
    required String type,
    required String sujet,
    required String message,
    String? etapes,
    required String utilisateurId,
    String? auteurNom,
  });

  Future<void> marquerTransmis(String id);
  Future<void> supprimerMessage(
    String id, {
    String? utilisateurId,
    String? utilisateurNom,
  });
}

/// Levée quand l'ancien mot de passe saisi ne correspond pas.
class MotDePasseIncorrect implements Exception {
  const MotDePasseIncorrect();
}

class CompteRepositoryDrift implements CompteRepository {
  const CompteRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Future<MetadonneesSession> metadonneesSession(int utilisateurId) async {
    final connexions =
        await (_db.select(_db.auditLogs)
              ..where(
                (a) =>
                    a.utilisateurId.equals('$utilisateurId') &
                    a.action.equals('connexion') &
                    a.entiteConcernee.equals('Session'),
              )
              // `id` en second critere : deux evenements peuvent partager la
              // meme milliseconde (connexion puis deconnexion immediate), et
              // `horodatage` seul rendrait alors l'ordre indefini — donc la
              // « session en cours » potentiellement fausse.
              ..orderBy([
                (a) => OrderingTerm.desc(a.horodatage),
                (a) => OrderingTerm.desc(a.id),
              ]))
            .get();

    // On ne garde que les connexions, pas les deconnexions : les deux partagent
    // l'action `connexion` et se distinguent par le champ `details`
    // (contrainte de Doc D1, qui n'autorise que 5 valeurs d'action).
    final ouvertures = connexions
        .where((a) => (a.details ?? '').contains('"connexion"'))
        .toList();

    return MetadonneesSession(
      // La premiere de la liste est la session **en cours** : « la derniere
      // connexion » du point de vue de l'utilisatrice est la precedente.
      derniereConnexion: ouvertures.length >= 2
          ? ouvertures[1].horodatage
          : null,
      nombreConnexions: ouvertures.length,
    );
  }

  @override
  Future<List<EntreeJournalPersonnel>> journalPersonnel(
    int utilisateurId, {
    int limite = 20,
  }) async {
    final lignes =
        await (_db.select(_db.auditLogs)
              ..where((a) => a.utilisateurId.equals('$utilisateurId'))
              ..orderBy([
                (a) => OrderingTerm.desc(a.horodatage),
                (a) => OrderingTerm.desc(a.id),
              ])
              ..limit(limite))
            .get();

    return [
      for (final l in lignes)
        EntreeJournalPersonnel(
          horodatage: l.horodatage,
          action: _libelleAction(l),
          module: EntreeJournalPersonnel.modulePour(l.entiteConcernee),
        ),
    ];
  }

  /// Transforme une ligne d'audit technique en phrase lisible.
  static String _libelleAction(AuditLogRow ligne) {
    if (ligne.entiteConcernee == 'Session') {
      final estDeconnexion = (ligne.details ?? '').contains('"deconnexion"');
      return estDeconnexion ? 'Déconnexion' : 'Connexion réussie';
    }

    final verbe = switch (ligne.action) {
      'creation' => 'créé',
      'modification' => 'modifié',
      'suppression' => 'supprimé',
      'annulation' => 'annulé',
      'decloture' => 'déclôturé',
      _ => ligne.action,
    };
    return '${ligne.entiteConcernee} ${ligne.entiteId} $verbe';
  }

  @override
  Future<void> changerMotDePasse({
    required int utilisateurId,
    required String ancienMotDePasse,
    required String nouveauMotDePasse,
  }) async {
    await _db.transaction(() async {
      final utilisateur = await (_db.select(
        _db.utilisateurs,
      )..where((u) => u.id.equals(utilisateurId))).getSingleOrNull();
      if (utilisateur == null) throw const MotDePasseIncorrect();

      final correct = HachageMotDePasse.verifier(
        motDePasseSaisi: ancienMotDePasse,
        sel: utilisateur.sel,
        hashAttendu: utilisateur.motDePasseHash,
      );
      if (!correct) throw const MotDePasseIncorrect();

      // Un sel neuf a chaque changement : reutiliser l'ancien permettrait de
      // reconnaitre qu'un mot de passe deja utilise revient.
      final sel = HachageMotDePasse.genererSel();
      await (_db.update(
        _db.utilisateurs,
      )..where((u) => u.id.equals(utilisateurId))).write(
        UtilisateursCompanion(
          sel: Value(sel),
          motDePasseHash: Value(
            HachageMotDePasse.hacher(nouveauMotDePasse, sel),
          ),
        ),
      );

      // BR-ADM-003 : trace, **sans jamais journaliser le mot de passe**
      // (Doc I3 §3, Strict Avoid §13).
      await _db
          .into(_db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              horodatage: DateTime.now(),
              utilisateurId: '$utilisateurId',
              action: 'modification',
              entiteConcernee: 'Utilisateur',
              entiteId: utilisateur.identifiant,
              details: const Value('{"champ":"motDePasse"}'),
            ),
          );
    });
  }

  @override
  Future<List<MessageEditeur>> chargerMessages() async {
    final lignes =
        await (_db.select(_db.messagesEditeur)..orderBy([
              (m) => OrderingTerm.desc(m.horodatage),
              // Deux messages de la même seconde : l'instant de saisie (µs) les départage
              // (l'UUID, aléatoire, ne dit rien de l'ordre).
              (m) => OrderingTerm.desc(m.updatedAt),
              (m) => OrderingTerm.desc(m.id),
            ]))
            .get();

    return [
      for (final m in lignes)
        MessageEditeur(
          id: m.id,
          horodatage: m.horodatage,
          type: m.type,
          sujet: m.sujet,
          message: m.message,
          etapes: m.etapes,
          statut: m.statut,
          auteurNom: m.auteurNom,
        ),
    ];
  }

  @override
  Future<void> enregistrerMessage({
    required String type,
    required String sujet,
    required String message,
    String? etapes,
    required String utilisateurId,
    String? auteurNom,
  }) async {
    await _db
        .into(_db.messagesEditeur)
        .insert(
          MessagesEditeurCompanion.insert(
            horodatage: DateTime.now(),
            auteurNom: Value(auteurNom),
            type: type,
            sujet: sujet,
            message: message,
            etapes: Value(etapes),
            utilisateurId: utilisateurId,
          ),
        );
  }

  @override
  Future<void> marquerTransmis(String id) async {
    // Une modification : le message repart au serveur, daté de maintenant (doc 47u §4).
    await (_db.update(
      _db.messagesEditeur,
    )..where((m) => m.id.equals(id))).write(
      MessagesEditeurCompanion(
        statut: const Value(MessageEditeurStatut.transmis),
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
    );
  }

  @override
  Future<void> supprimerMessage(
    String id, {
    String? utilisateurId,
    String? utilisateurNom,
  }) async {
    await _db.transaction(() async {
      // La suppression est un fait daté : l'instantané de la corbeille porte l'instant de
      // saisie de la suppression, et repart au serveur en pierre tombale (doc 47u §4).
      await (_db.update(
        _db.messagesEditeur,
      )..where((m) => m.id.equals(id))).write(
        MessagesEditeurCompanion(
          syncStatus: const Value('pending'),
          syncMotif: const Value(null),
          updatedAt: Value(instantSaisie()),
        ),
      );
      final ligne = await (_db.select(
        _db.messagesEditeur,
      )..where((m) => m.id.equals(id))).getSingleOrNull();

      await ServiceArchivage(_db).archiver(
        type: TypeArchivable.messages,
        cle: id,
        designation:
            ligne?.sujet ??
            'Message ${id.substring(0, id.length < 8 ? id.length : 8)}',
        utilisateurId: utilisateurId,
        utilisateurNom: utilisateurNom,
      );
    });
  }
}

/// Décode le champ `details` d'une ligne d'audit, tolérant au JSON malformé.
Map<String, dynamic> detailsAudit(String? details) {
  if (details == null || details.isEmpty) return const {};
  try {
    final decode = jsonDecode(details);
    return decode is Map<String, dynamic> ? decode : const {};
  } on FormatException {
    return const {};
  }
}
