import 'package:drift/drift.dart';

import '../../../core/sync/identifiant_poste.dart';

/// Messages adressés à l'éditeur — `contact-editeur.html`.
///
/// ## ⚠️ Pourquoi cette table existe
///
/// Le prototype affiche `showToast('Message envoyé à l'éditeur.')` **sans rien
/// envoyer ni rien conserver** : c'est exactement l'anti-patron que le Master
/// Prompt §2.3 interdit (le même que `validateSale()`). L'application est
/// hors-ligne, aucun transport e-mail n'est configuré — un mot de passe SMTP
/// n'est d'ailleurs volontairement pas stocké (Doc I3 §3).
///
/// Deux issues honnêtes étaient possibles : retirer les formulaires, ou leur
/// donner un effet réel. La seconde a été retenue — un message rédigé par la
/// Gérante ne doit pas disparaître dans un toast. Il est **conservé ici** et
/// copié dans le presse-papiers pour envoi par WhatsApp au numéro de l'éditeur,
/// et l'écran dit exactement cela.
@DataClassName('MessageEditeurRow')
class MessagesEditeur extends Table {
  /// UUID généré au poste (DV-19, doc 47u §4) : un message est un fait synchronisé,
  /// lisible et gérable depuis le web et les autres postes. Les messages existants
  /// reçoivent le leur à la migration v45.
  TextColumn get id => text().clientDefault(nouvelUuid)();

  DateTimeColumn get horodatage => dateTime()();

  /// `question` ou `bug` — les 2 onglets du formulaire.
  TextColumn get type => text()();

  /// Objet (onglet Question) ou module concerné (onglet Problème).
  TextColumn get sujet => text()();

  TextColumn get message => text()();

  /// « Étapes pour Reproduire », uniquement sur l'onglet Problème.
  TextColumn get etapes => text().nullable()();

  /// Identifiant de l'utilisatrice qui a rédigé le message (traçabilité).
  TextColumn get utilisateurId => text()();

  /// Aucun envoi automatique n'existe : le message reste `enAttente` tant que
  /// la Gérante ne l'a pas transmis elle-même, puis elle le marque `transmis`.
  TextColumn get statut =>
      text().withDefault(const Constant(MessageEditeurStatut.enAttente))();

  /// « Nom (identifiant) — Rôle » de la rédactrice : `utilisateur_id` est un entier
  /// LOCAL qui n'a pas de sens sur le serveur ni sur un autre poste. `null` pour les
  /// messages d'avant la v45.
  TextColumn get auteurNom => text().nullable()();

  // --- Synchronisation (`46_` §1) ---

  /// `pending` (à envoyer) · `synced` · `conflict` (refusé, voir `syncMotif`).
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  /// Motif du refus du serveur, en français ; `null` hors conflit.
  TextColumn get syncMotif => text().nullable()();

  /// Instant de SAISIE (UTC, ISO 8601, microsecondes).
  TextColumn get updatedAt => text().clientDefault(instantSaisie)();

  @override
  Set<Column> get primaryKey => {id};
}

class MessageEditeurStatut {
  MessageEditeurStatut._();

  static const String enAttente = 'En attente';
  static const String transmis = 'Transmis';
}
