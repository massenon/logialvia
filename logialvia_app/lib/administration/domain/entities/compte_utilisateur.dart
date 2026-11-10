/// Entités de l'écran Mon Profil et de Contactez l'Éditeur — Doc F9.
library;

/// Une entrée du journal d'audit personnel — `mon-profil.html`.
class EntreeJournalPersonnel {
  const EntreeJournalPersonnel({
    required this.horodatage,
    required this.action,
    required this.module,
  });

  final DateTime horodatage;

  /// Libellé lisible : « Connexion réussie », « Vente V-2026-142 enregistrée »…
  final String action;

  /// Module d'origine, déduit de l'entité concernée par l'action.
  final String module;

  /// Traduction `entiteConcernee` → module affiché.
  ///
  /// `AUDIT_LOGS` (Doc D1) stocke l'entité technique, pas un nom de module :
  /// la correspondance est faite ici plutôt que dupliquée à chaque écriture de
  /// journal, qui aurait pu diverger d'un module à l'autre.
  static String modulePour(String entiteConcernee) {
    return switch (entiteConcernee) {
      'Session' || 'Utilisateur' => 'Authentification',
      'Vente' || 'Devis' || 'Client' => 'Point de Vente',
      'Achat' || 'Fournisseur' => 'Achats & Fournisseurs',
      'Intrant' ||
      'ProduitVendable' ||
      'MouvementIntrant' => 'Stocks & Catalogue',
      'Soin' || 'Infirmerie' => 'Doses & Vaccins',
      'FicheJournee' || 'CycleCouveuse' => 'Élevage & Couveuse',
      'Ecriture' ||
      'CloturePeriodique' ||
      'ExerciceComptable' => 'Comptabilité',
      'ParametresEntreprise' || 'ModuleActif' => 'Paramètres',
      _ => entiteConcernee,
    };
  }
}

/// Métadonnées de session affichées sur la carte de profil.
class MetadonneesSession {
  const MetadonneesSession({
    required this.derniereConnexion,
    required this.nombreConnexions,
  });

  /// Avant-dernière connexion réussie — c'est bien « la dernière fois » du
  /// point de vue de l'utilisatrice, la connexion courante étant en cours.
  final DateTime? derniereConnexion;

  final int nombreConnexions;
}

/// Une question de la Foire Aux Questions — `aide-a-propos.html`.
class QuestionAide {
  const QuestionAide({
    required this.question,
    required this.reponse,
    required this.motsCles,
  });

  final String question;
  final String reponse;

  /// Le prototype filtre sur un attribut `data-question` normalisé (sans
  /// accents ni ponctuation) et non sur le libellé affiché. La recherche porte
  /// donc ici sur ces mots-clés **et** sur le texte visible.
  final String motsCles;

  bool correspond(String terme) {
    if (terme.isEmpty) return true;
    final t = terme.toLowerCase();
    return motsCles.contains(t) ||
        question.toLowerCase().contains(t) ||
        reponse.toLowerCase().contains(t);
  }
}

/// Un message adressé à l'éditeur.
class MessageEditeur {
  const MessageEditeur({
    required this.id,
    required this.horodatage,
    required this.type,
    required this.sujet,
    required this.message,
    required this.etapes,
    required this.statut,
    this.auteurNom,
  });

  final String id;
  final DateTime horodatage;
  final String type;
  final String sujet;
  final String message;
  final String? etapes;
  final String statut;

  /// « Nom (identifiant) — Rôle » de la rédactrice (`null` avant la v45).
  final String? auteurNom;

  bool get estBug => type == 'bug';

  /// Texte prêt à être collé dans WhatsApp ou un e-mail.
  String texteAEnvoyer({required String expediteur, required String version}) {
    final entete = estBug
        ? 'LogiALVIA $version — Signalement de problème'
        : 'LogiALVIA $version — Question';
    final tampon = StringBuffer()
      ..writeln(entete)
      ..writeln('De : $expediteur')
      ..writeln(estBug ? 'Module concerné : $sujet' : 'Objet : $sujet')
      ..writeln()
      ..writeln(message);
    if (etapes != null && etapes!.trim().isNotEmpty) {
      tampon
        ..writeln()
        ..writeln('Étapes pour reproduire :')
        ..writeln(etapes);
    }
    return tampon.toString();
  }
}

/// Coordonnées de l'éditeur — reprises telles quelles de `contact-editeur.html`
/// et du `<meta name="author">` présent sur les 31 pages du prototype.
class Editeur {
  Editeur._();

  static const String societe = 'FAGUEZ SARL';

  /// Ce que fait le cabinet, en une ligne.
  static const String roleSociete =
      'Cabinet d\'accompagnement des PME dans le cadre du PAEB';

  /// Le programme dans lequel s'inscrit le logiciel, developpe comme
  /// `index.html` et `login.html` l'ecrivent — sigle developpe a sa premiere
  /// apparition, puis repris seul.
  static const String programme =
      'Projet d\'Appui à l\'Entrepreneuriat au Bénin (PAEB)';
  static const String contact = 'Dr MASSENON Rhodes';

  /// Qualification, telle que l'éditeur la donne.
  static const String qualification =
      'Docteur en Génie Logiciel et Intelligence Artificielle';

  static const String role = 'Ingénierie logicielle';

  /// Ligne principale.
  static const String telephone = '+229 01 51 33 50 40';

  /// Seconde ligne.
  static const String telephoneSecondaire = '+229 01 97 31 24 37';

  /// Adresse personnelle de l'éditeur.
  static const String email = 'rarhodes06@gmail.com';

  /// Adresse professionnelle — celle à privilégier pour un signalement.
  static const String emailProfessionnel = 'contact@massenonrhodes.com';

  /// Les deux lignes et les deux adresses, prêtes à afficher.
  static const String telephones = '$telephone / $telephoneSecondaire';
  static const String emails = '$emailProfessionnel / $email';

  static const String mentionProjet =
      'Développé dans le cadre du PAEB par FAGUEZ SARL — '
      'Dr Rhodes MASSENON (ingénierie logicielle)';

  static const String descriptionApplication =
      'LogiALVIA — Application de Gestion et de Suivi Avicole d\'ALLMANY';
}
