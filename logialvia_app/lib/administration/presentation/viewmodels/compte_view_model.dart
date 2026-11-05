import '../../domain/services/service_archivage.dart';
import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../data/repositories/compte_repository_drift.dart';
import '../../domain/entities/compte_utilisateur.dart';
import '../../domain/entities/session_utilisateur.dart';

/// Compte Utilisateur — Doc F9, 3 écrans (`/profil`, `/aide`, `/contact`).
///
/// Un seul ViewModel : les 3 écrans dépendent de la même session ouverte, et
/// le formulaire de contact a besoin de l'identité de l'expéditrice.
class CompteViewModel extends ChangeNotifier {
  CompteViewModel(this._repository, this.session);

  final CompteRepository _repository;

  /// Session courante. `null` ne devrait pas arriver — les 3 routes sont
  /// derrière le garde d'authentification — mais l'écran doit rester lisible.
  final SessionUtilisateur? session;

  /// Version affichée sur Aide & À Propos. Alignée sur `pubspec.yaml`.
  static const String version = 'v1.0.0';

  bool _chargement = true;
  bool get chargement => _chargement;

  MetadonneesSession _metadonnees = const MetadonneesSession(
    derniereConnexion: null,
    nombreConnexions: 0,
  );
  MetadonneesSession get metadonnees => _metadonnees;

  List<EntreeJournalPersonnel> _journal = const [];
  List<EntreeJournalPersonnel> get journal => _journal;

  List<MessageEditeur> _messages = const [];
  List<MessageEditeur> get messages => _messages;

  // ----------------------------------------------------------- identité

  String get nomAffiche => session?.utilisateur.nom ?? '—';
  String get identifiant => session?.utilisateur.identifiant ?? '—';
  String get libelleRole => session?.role.libelle ?? '—';

  /// Initiales du pastille de profil — « SR » pour SIDI ALI Raïmatou.
  String get initiales {
    final mots = nomAffiche
        .split(RegExp(r'\s+'))
        .where((m) => m.isNotEmpty)
        .toList();
    if (mots.isEmpty) return '?';
    if (mots.length == 1) return mots.first.characters.take(2);
    return '${mots.first.characters.take(1)}${mots.last.characters.take(1)}';
  }

  // --------------------------------------------------------- chargement

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    await _rafraichir();
    _chargement = false;
    notifyListeners();
  }

  Future<void> _rafraichir() async {
    final id = session?.utilisateur.id;
    if (id != null) {
      _metadonnees = await _repository.metadonneesSession(id);
      _journal = await _repository.journalPersonnel(id);
    }
    _messages = await _repository.chargerMessages();
  }

  // ------------------------------------------------- Mot de passe (F9 §1)

  /// Règles de complexité affichées par le prototype :
  /// « Min. 8 caractères, 1 majuscule, 1 chiffre ».
  ///
  /// Le script du prototype ne vérifie en réalité que la longueur ≥ 8 — les
  /// deux autres règles sont annoncées et jamais appliquées. Elles le sont ici :
  /// un texte d'aide qui ment est pire que pas de texte du tout.
  static String? erreurComplexite(String motDePasse) {
    if (motDePasse.length < 8) {
      return 'Le mot de passe doit compter au moins 8 caractères.';
    }
    if (!motDePasse.contains(RegExp('[A-ZÀ-Þ]'))) {
      return 'Le mot de passe doit contenir au moins une majuscule.';
    }
    if (!motDePasse.contains(RegExp(r'\d'))) {
      return 'Le mot de passe doit contenir au moins un chiffre.';
    }
    return null;
  }

  Future<Resultat<void>> changerMotDePasse({
    required String ancien,
    required String nouveau,
    required String confirmation,
  }) async {
    final id = session?.utilisateur.id;
    if (id == null) return const Echec('Aucune session ouverte.');

    if (ancien.trim().isEmpty) {
      return const Echec('L\'ancien mot de passe est obligatoire.');
    }
    final erreur = erreurComplexite(nouveau);
    if (erreur != null) return Echec(erreur);
    if (nouveau != confirmation) {
      return const Echec('Les mots de passe ne correspondent pas.');
    }
    if (nouveau == ancien) {
      return const Echec(
        'Le nouveau mot de passe doit être différent de l\'ancien.',
      );
    }

    try {
      await _repository.changerMotDePasse(
        utilisateurId: id,
        ancienMotDePasse: ancien,
        nouveauMotDePasse: nouveau,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } on MotDePasseIncorrect {
      return const Echec('L\'ancien mot de passe est incorrect.');
    } catch (e) {
      if (kDebugMode) debugPrint('Echec changement mot de passe: $e');
      return const Echec('Le mot de passe n\'a pas pu être modifié.');
    }
  }

  // ------------------------------------------------------ Aide (F9 §2)

  String _rechercheFaq = '';
  String get rechercheFaq => _rechercheFaq;

  void definirRechercheFaq(String valeur) {
    _rechercheFaq = valeur;
    notifyListeners();
  }

  /// Les 5 questions de `aide-a-propos.html`, mot pour mot.
  static const List<QuestionAide> faq = [
    QuestionAide(
      question: 'Comment enregistrer une nouvelle vente ?',
      reponse:
          'Rendez-vous dans Ventes & Clients > Point de Vente, ajoutez les '
          'produits au panier, choisissez un client (ou Client Comptant), puis '
          'validez le mode de règlement.',
      motsCles: 'comment enregistrer une nouvelle vente ?',
    ),
    QuestionAide(
      question: 'Comment activer ou désactiver une filière (ex. Lapins) ?',
      reponse:
          'Rendez-vous dans Paramètres Généraux > Modules Actifs. L\'effet est '
          'immédiat sur le menu latéral et le Dashboard Élevage.',
      motsCles: 'comment activer ou desactiver un module ?',
    ),
    QuestionAide(
      question: 'Comment fonctionne l\'alerte de stock critique ?',
      reponse:
          'Chaque produit a un seuil d\'alerte (réglable dans Catalogue '
          'Produits > Seuils d\'Alerte). Un badge rouge s\'affiche '
          'automatiquement dès que le stock repasse sous ce seuil.',
      motsCles: 'comment fonctionne l\'alerte de stock ?',
    ),
    QuestionAide(
      question: 'Comment administrer une dose et décrémenter le stock ?',
      reponse:
          'Dans Soins & Calendrier > Administrer une Dose, sélectionnez le lot '
          'et le produit — le stock vétérinaire est décrémenté automatiquement, '
          'ou l\'action est bloquée si le stock est épuisé.',
      motsCles: 'comment administrer une dose de vaccin ?',
    ),
    QuestionAide(
      question: 'Comment relancer un client avec un solde impayé ?',
      reponse:
          'Depuis Clients et Relances > Suivi des Soldes, utilisez le bouton de '
          'relance sur la ligne du client concerné.',
      motsCles: 'comment relancer un client avec un solde impaye ?',
    ),
  ];

  List<QuestionAide> get faqFiltree {
    final terme = _rechercheFaq.trim().toLowerCase();
    return faq.where((q) => q.correspond(terme)).toList();
  }

  // --------------------------------------------------- Contact (F9 §3)

  Future<Resultat<MessageEditeur>> enregistrerMessage({
    required String type,
    required String sujet,
    required String message,
    String? etapes,
  }) async {
    if (sujet.trim().isEmpty) {
      return Echec(
        type == 'bug'
            ? 'Le module concerné est obligatoire.'
            : 'L\'objet est obligatoire.',
      );
    }
    if (message.trim().isEmpty) {
      return const Echec('Le message est obligatoire.');
    }

    try {
      await _repository.enregistrerMessage(
        type: type,
        sujet: sujet.trim(),
        message: message.trim(),
        etapes: etapes?.trim().isEmpty ?? true ? null : etapes!.trim(),
        utilisateurId: '${session?.utilisateur.id ?? 0}',
      );
      await _rafraichir();
      notifyListeners();
      // Le message tout juste enregistre est le plus recent.
      return Succes(_messages.first);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec enregistrement message: $e');
      return const Echec('Le message n\'a pas pu être enregistré.');
    }
  }

  /// Texte prêt à coller, construit avec l'identité réelle de l'expéditrice.
  String texteAEnvoyer(MessageEditeur message) => message.texteAEnvoyer(
    expediteur: '$nomAffiche ($identifiant) — $libelleRole',
    version: version,
  );

  Future<Resultat<void>> marquerTransmis(MessageEditeur message) async {
    try {
      await _repository.marquerTransmis(message.id);
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec marquage transmis: $e');
      return const Echec('Ce message n\'a pas pu être marqué comme transmis.');
    }
  }

  Future<Resultat<void>> supprimerMessage(
    MessageEditeur message, {
    AuteurArchivage? auteur,
  }) async {
    try {
      await _repository.supprimerMessage(
        message.id,
        utilisateurId: auteur?.id,
        utilisateurNom: auteur?.nom,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec suppression message: $e');
      return const Echec('Ce message n\'a pas pu être supprimé.');
    }
  }
}

/// Petit utilitaire de découpe sûre pour les initiales — `substring` casserait
/// sur un prénom composé d'un seul caractère.
extension on String {
  _Caracteres get characters => _Caracteres(this);
}

class _Caracteres {
  const _Caracteres(this.valeur);

  final String valeur;

  String take(int n) => valeur.length <= n
      ? valeur.toUpperCase()
      : valeur.substring(0, n).toUpperCase();
}
