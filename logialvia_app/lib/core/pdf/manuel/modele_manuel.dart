/// Le modèle du manuel d'utilisation.
///
/// # Trois principes, dont dépend tout le reste
///
/// **Exactitude.** Chaque libellé cité vient du logiciel réel, relevé par
/// `test/manuel/inventaire_libelles.dart` pendant que l'écran est monté. Rien
/// n'est reconstitué de mémoire : un manuel qui écrit « le bouton de
/// validation » là où l'écran affiche « Valider la Commande » envoie le lecteur
/// chercher ce qui n'existe pas.
///
/// **Lisibilité.** Un code couleur constant, des encadrés qui se comprennent
/// sans être lus, des captures annotées au pixel près, et de l'air.
///
/// **Reproductibilité.** Deux commandes reconstruisent le document entier,
/// captures comprises. C'est la seule condition pour qu'un manuel reste vrai
/// au-delà de sa première livraison.
library;

/// L'éditeur du logiciel, tel qu'il figure en couverture et en pied de page.
class EditeurManuel {
  const EditeurManuel({
    required this.nom,
    required this.qualification,
    required this.telephones,
    required this.emails,
    required this.societe,
    required this.roleSociete,
    required this.programme,
  });

  final String nom;
  final String qualification;
  final String telephones;
  final String emails;

  /// Le cabinet qui porte le logiciel.
  final String societe;

  /// Ce que fait ce cabinet, en une ligne.
  final String roleSociete;

  /// Le programme dans lequel s'inscrit le logiciel, sigle developpe.
  final String programme;
}

/// Niveau d'un encadré.
///
/// ⚠️ Les quatre pictogrammes usuels (ℹ️ ⚠️ 🛑 ✅) **n'existent dans aucune
/// police du projet** : vérification faite dans la table de caractères de
/// Roboto, aucun des codes U+2139, U+26A0, U+2705 ni les sélecteurs de
/// variation emoji n'y figurent. Les employer produirait des blancs — le pire
/// résultat possible pour un repère visuel.
///
/// Ils sont donc **dessinés en vectoriel** : une pastille de couleur et un
/// signe tracé. Le repère reste le même pour le lecteur — une couleur, une
/// forme, un mot — et il s'imprime.
///
/// **Discipline** : l'alerte rouge ne se galvaude pas. Si tout est rouge, plus
/// rien ne l'est. Elle est réservée à ce qui détruit des données ou engage la
/// responsabilité de l'entreprise.
enum NiveauEncadre {
  /// Bleu — une précision qui aide à comprendre. Non bloquante.
  information('Information'),

  /// Orange — l'erreur fréquente qu'on veut éviter.
  attention('Attention'),

  /// Rouge — perte de données ou action irréversible.
  alerte('Alerte'),

  /// Vert — un raccourci, une bonne pratique.
  astuce('Astuce');

  const NiveauEncadre(this.libelle);

  final String libelle;
}

/// Un encadré signalé, dans le corps d'une section.
class EncadreManuel {
  const EncadreManuel(this.niveau, this.texte);

  const EncadreManuel.information(this.texte)
    : niveau = NiveauEncadre.information;
  const EncadreManuel.attention(this.texte) : niveau = NiveauEncadre.attention;
  const EncadreManuel.alerte(this.texte) : niveau = NiveauEncadre.alerte;
  const EncadreManuel.astuce(this.texte) : niveau = NiveauEncadre.astuce;

  final NiveauEncadre niveau;
  final String texte;
}

/// Une étape numérotée d'une tâche.
class EtapeManuel {
  const EtapeManuel(this.titre, this.texte);

  final String titre;
  final String texte;
}

/// Un repère numéroté posé sur une capture.
///
/// Les coordonnées sont en **pourcentages** de la capture, relevées pendant
/// que l'écran était monté — jamais placées à l'œil. Une recapture après mise
/// à jour repositionne donc les repères toute seule.
class ReperManuel {
  const ReperManuel({
    required this.ancre,
    required this.legende,
    this.zone = false,
  });

  /// Nom de la cible de visite guidée (`CibleTour`) dont on reprend le
  /// rectangle. Le manuel et la visite montrent ainsi les mêmes éléments.
  final String ancre;

  /// Ce que le repère désigne, en clair.
  final String legende;

  /// `true` pour une région large — le cadre se trace en pointillés plutôt
  /// qu'en trait plein.
  final bool zone;
}

/// Une colonne de tableau, et ce qu'elle contient.
class ColonneManuel {
  const ColonneManuel(this.nom, this.contenu);

  /// L'en-tête exact, tel qu'il s'affiche.
  final String nom;

  /// Ce que la colonne dit, et d'où vient sa valeur.
  final String contenu;
}

/// Un tableau de référence — l'aide-mémoire des colonnes d'un écran.
class TableauManuel {
  const TableauManuel({required this.titre, required this.colonnes});

  final String titre;
  final List<ColonneManuel> colonnes;
}

/// Une fenêtre modale.
///
/// C'est elle qui porte la saisie. Un manuel qui montre l'écran sans montrer
/// sa modale ne montre pas le geste.
class ModaleManuel {
  const ModaleManuel({
    required this.nom,
    required this.declencheur,
    required this.aQuoiCaSert,
    this.capture,
    this.champs = const [],
    this.encadres = const [],
  });

  /// Titre exact de la modale.
  final String nom;

  /// Le bouton qui l'ouvre, nommé comme à l'écran.
  final String declencheur;

  final String aQuoiCaSert;
  final String? capture;

  /// Les champs de saisie et ce qu'ils attendent.
  final List<ColonneManuel> champs;

  final List<EncadreManuel> encadres;
}

/// Un onglet interne d'un écran.
class OngletManuel {
  const OngletManuel(this.nom, this.aQuoiCaSert, {this.capture});

  final String nom;
  final String aQuoiCaSert;
  final String? capture;
}

/// La section d'un écran.
class SectionManuel {
  const SectionManuel({
    required this.titre,
    required this.chemin,
    required this.role,
    required this.aQuoiCaSert,
    this.capture,
    this.reperes = const [],
    this.etapes = const [],
    this.encadres = const [],
    this.aRetenir = const [],
    this.onglets = const [],
    this.modales = const [],
    this.tableaux = const [],
  });

  /// Titre de l'écran, **exactement** tel qu'il s'affiche.
  final String titre;

  /// Chemin d'accès, en chevrons : « ÉLEVAGE & COUVEUSE › Cycle Couveuse ».
  final String chemin;

  /// Qui y a droit, en clair.
  final String role;

  /// Une à trois phrases : ce que l'écran sert à faire.
  final String aQuoiCaSert;

  /// Nom du fichier de capture, sans extension.
  final String? capture;

  /// Les repères numérotés posés dessus.
  final List<ReperManuel> reperes;

  /// Les gestes, dans l'ordre chronologique strict.
  final List<EtapeManuel> etapes;

  final List<EncadreManuel> encadres;

  /// Points sans ordre particulier — puces simples.
  final List<String> aRetenir;

  /// Les onglets internes, dans l'ordre d'affichage.
  final List<OngletManuel> onglets;

  /// Les fenêtres de saisie.
  final List<ModaleManuel> modales;

  /// Les tableaux de référence.
  final List<TableauManuel> tableaux;
}

/// Un chapitre : un groupe d'écrans.
class ChapitreManuel {
  const ChapitreManuel({
    required this.titre,
    required this.introduction,
    required this.sections,
  });

  final String titre;
  final String introduction;
  final List<SectionManuel> sections;
}

/// Une annexe.
class AnnexeManuel {
  const AnnexeManuel({
    required this.lettre,
    required this.titre,
    required this.introduction,
    this.paragraphes = const [],
    this.puces = const [],
    this.tableaux = const [],
    this.encadres = const [],
  });

  /// « A », « B »… La lettre sert de numérotation et de renvoi.
  final String lettre;

  final String titre;
  final String introduction;
  final List<String> paragraphes;
  final List<String> puces;
  final List<TableauManuel> tableaux;
  final List<EncadreManuel> encadres;
}

/// Le manuel complet.
class ManuelUtilisation {
  const ManuelUtilisation({
    required this.version,
    required this.editeur,
    required this.destinataire,
    required this.avantPropos,
    required this.chapitres,
    this.annexes = const [],
  });

  final String version;
  final EditeurManuel editeur;

  /// À qui le manuel est destiné — figure en en-tête courant.
  final String destinataire;

  final List<String> avantPropos;
  final List<ChapitreManuel> chapitres;
  final List<AnnexeManuel> annexes;

  int get nombreEcrans => chapitres.fold(0, (s, c) => s + c.sections.length);

  int get nombreModales => chapitres
      .expand((c) => c.sections)
      .fold(0, (s, section) => s + section.modales.length);

  int get nombreOnglets => chapitres
      .expand((c) => c.sections)
      .fold(0, (s, section) => s + section.onglets.length);
}
