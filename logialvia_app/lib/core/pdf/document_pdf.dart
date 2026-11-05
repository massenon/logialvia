/// Modèle de contenu d'un document imprimable — Doc E9, Doc J2 §3.
///
/// Ce fichier ne connaît **rien** du paquet `pdf` : c'est une description de ce
/// qu'il faut imprimer, pas une mise en page. Chaque écran construit un
/// [DocumentPdf] à partir de ses propres données, et [GenerateurPdf] le rend.
/// Une classe de génération par type de document est explicitement interdite
/// (Doc E9 §5, Strict Avoid §12).
library;

/// Orientation de la page — `@page { size: A4 portrait|landscape }`.
enum OrientationPdf { portrait, paysage }

/// Alignement d'une colonne, repris des `style="text-align:…"` du prototype.
enum AlignementPdf { gauche, centre, droite }

/// Teinte d'une cellule de montant.
enum TeintePdf {
  /// Noir standard.
  normale,

  /// `.positive` du prototype — vert, gras.
  positive,

  /// `.negative` du prototype — rouge, gras.
  negative,

  /// Gris, pour un « — » ou une mention secondaire.
  attenuee,
}

/// Une colonne de tableau.
class ColonnePdf {
  const ColonnePdf(
    this.titre, {
    this.alignement = AlignementPdf.gauche,
    this.largeur = 1,
  });

  final String titre;
  final AlignementPdf alignement;

  /// Largeur relative — l'équivalent du `flex` des tableaux à l'écran.
  final int largeur;
}

/// Une cellule.
class CellulePdf {
  const CellulePdf(
    this.texte, {
    this.teinte = TeintePdf.normale,
    this.gras = false,
  });

  const CellulePdf.montant(this.texte, {this.teinte = TeintePdf.normale})
    : gras = true;

  final String texte;
  final TeintePdf teinte;
  final bool gras;
}

/// Un encadré d'indicateur — `.kpi-box` du prototype (bordure or, libellé en
/// petites capitales grises, valeur en navy).
class IndicateurPdf {
  const IndicateurPdf(this.libelle, this.valeur);

  final String libelle;
  final String valeur;
}

/// Un tableau, éventuellement précédé d'un titre et suivi d'une ligne de
/// totaux.
class TableauPdf {
  const TableauPdf({
    this.titre,
    required this.colonnes,
    required this.lignes,
    this.pied,
    this.note,
  });

  final String? titre;
  final List<ColonnePdf> colonnes;
  final List<List<CellulePdf>> lignes;

  /// Ligne de totaux, sur fond gris — `<tfoot>` du prototype.
  final List<CellulePdf>? pied;

  /// Mention en petits caractères sous le tableau : sert à porter sur le papier
  /// les limites déjà énoncées à l'écran (échéances non saisies, CMUP au prix
  /// de vente…). Un état imprimé qui tait ce que l'écran signale induirait son
  /// lecteur en erreur.
  final String? note;

  bool get estVide => lignes.isEmpty;
}

/// Un bloc de texte libre — utilisé par la lettre de relance, qui n'a pas de
/// tableau.
class ParagraphePdf {
  const ParagraphePdf(this.texte, {this.gras = false});

  final String texte;
  final bool gras;
}

/// Le document complet.
class DocumentPdf {
  const DocumentPdf({
    required this.titre,
    this.periode = '',
    this.orientation = OrientationPdf.portrait,
    this.signatures = true,
    this.indicateurs = const [],
    this.paragraphes = const [],
    this.tableaux = const [],
    this.messageSiVide,
  });

  /// Bandeau navy à filet or, en capitales.
  final String titre;

  /// « Exercice 2026 », « 01/08/2026 au 08/08/2026 »… Vide si sans objet.
  final String periode;

  final OrientationPdf orientation;

  /// Bloc de 2 signatures en pied de page. `false` sur une facture, un plan
  /// comptable ou une lettre — le prototype le règle appel par appel.
  final bool signatures;

  final List<IndicateurPdf> indicateurs;
  final List<ParagraphePdf> paragraphes;
  final List<TableauPdf> tableaux;

  /// Affiché à la place des tableaux quand ils sont tous vides. Un état imprimé
  /// sans aucune ligne doit dire **pourquoi**, jamais rester blanc
  /// (Master Prompt §2.2).
  final String? messageSiVide;

  bool get estVide =>
      paragraphes.isEmpty && tableaux.every((t) => t.estVide);

  /// Nom de fichier proposé à l'enregistrement — accents et ponctuation retirés
  /// pour rester valide sur tous les systèmes de fichiers.
  String get nomFichier {
    const accents = 'àâäçéèêëîïôöùûüÿÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸ';
    const sansAccents = 'aaaceeeeiioouuuyAAACEEEEIIOOUUUY';

    final tampon = StringBuffer();
    for (final caractere in titre.characters) {
      final index = accents.indexOf(caractere);
      final normalise = index >= 0 ? sansAccents[index] : caractere;
      tampon.write(
        RegExp(r'[A-Za-z0-9]').hasMatch(normalise) ? normalise : '_',
      );
    }

    final nettoye = tampon
        .toString()
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'LogiALVIA_$nettoye.pdf';
  }
}

/// En-tête officiel : ce que le document dit de son émetteur et de son auteur.
///
/// Le prototype code « Gérante : SIDI ALI Raïmatou », « Natitingou, Atakora,
/// Bénin » et « Généré par : Administratrice » **en dur** dans son générateur.
/// Ces trois lignes viennent ici de `PARAMETRES_ENTREPRISE` et de la session
/// réellement ouverte : un document officiel signé du nom d'une autre personne
/// que celle qui l'a produit n'a aucune valeur probante.
class EnteteOfficielle {
  const EnteteOfficielle({
    required this.raisonSociale,
    this.promoteur,
    this.adresse,
    required this.generePar,
    this.ifu,
    this.rccm,
  });

  final String raisonSociale;
  final String? promoteur;
  final String? adresse;

  /// Nom et rôle de l'utilisatrice connectée.
  final String generePar;

  /// Mentions légales, imprimées quand elles sont renseignées (Doc F8).
  final String? ifu;
  final String? rccm;

  static const EnteteOfficielle parDefaut = EnteteOfficielle(
    raisonSociale: 'ALLMANY ET COMPAGNIE',
    generePar: '—',
  );
}

extension on String {
  Iterable<String> get characters sync* {
    for (var i = 0; i < length; i++) {
      yield this[i];
    }
  }
}
