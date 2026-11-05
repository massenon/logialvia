import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../formatage/formats.dart';
import 'document_pdf.dart';

/// Générateur PDF **unique** — Doc E9 §5, Doc J2 §3.
///
/// ## Ce qui a été suivi, et ce qui a été corrigé
///
/// Doc E9 §2 décrit une facture **A5** avec sa propre mise en page. Vérification
/// faite dans le prototype : `downloadInvoice()` de `ventes.html` appelle en
/// réalité `generateOfficialPDF()`, comme les 23 autres boutons d'export. Il
/// n'existe qu'**un seul** document type — A4, en-tête officiel, bandeau de
/// titre, corps, signatures — et la facture n'en est qu'un cas particulier
/// (`signatures: false`). C'est cette mise en page réelle qui est reproduite,
/// pas celle du croquis.
///
/// Toutes les couleurs et tailles proviennent du bloc `<style>` de
/// `generateOfficialPDF` (`assets/js/common.js` l.424-452).
///
/// ## Police : Roboto embarqué, jamais téléchargé
///
/// Doc E9 §3 propose `PdfGoogleFonts.robotoRegular()`. Cet appel **télécharge
/// la police depuis Internet** : sur une exploitation de Natitingou sans
/// connexion garantie, l'export échouerait au moment précis où on en a besoin.
/// La police est donc lue dans les **assets** du logiciel.
///
/// ⚠️ **Ce que cela corrige.** Les documents étaient composés en Helvetica,
/// police de base PDF qui ne couvre que Latin-1. Constat obtenu à
/// l'exécution : le tiret cadratin, œ, ≥, l'apostrophe typographique, €, №,
/// les points de suspension et la puce laissaient un **blanc** dans le
/// document — sur des états officiels signés. Roboto contient ces huit
/// caractères : ils s'impriment désormais tels qu'ils s'affichent.
///
/// ⚠️ **Ce que cela ne corrige pas.** Roboto ne contient ni les flèches
/// → ←, ni les exposants ᵉ ʳ ᵐ, ni l'espace fine insécable, ni ✓ —
/// vérifié dans sa table de caractères, pas supposé. Or
/// « Goliathau (0 → 4 mois) » existe bel et bien dans l'interface.
/// [normaliserPourRoboto] ne substitue donc **que** ce qui manque réellement,
/// en interrogeant la table embarquée (`TtfParser.charToGlyphIndexMap`)
/// plutôt qu'une liste écrite à la main : le jour où la police change, la
/// substitution suit toute seule.
///
/// La série **statique** est employée ici, là où l'interface utilise la fonte
/// variable : le paquet `pdf` embarque les contours tels quels et ne tirerait
/// d'une variable que son instance par défaut (400) — le gras des titres
/// deviendrait identique au corps de texte. Voir `assets/fonts/README.md`.
class GenerateurPdf {
  const GenerateurPdf();

  // Palette exacte du prototype.
  static final PdfColor _navy = PdfColor.fromHex('#1F3864');
  static final PdfColor _or = PdfColor.fromHex('#B58B2A');
  static final PdfColor _gris = PdfColor.fromHex('#6f7973');
  static final PdfColor _filet = PdfColor.fromHex('#bec9c2');
  static final PdfColor _zebre = PdfColor.fromHex('#F2F2F2');
  static final PdfColor _encre = PdfColor.fromHex('#191c1d');
  static final PdfColor _vert = PdfColor.fromHex('#15803D');
  static final PdfColor _rouge = PdfColor.fromHex('#DC2626');

  /// Substitutions de repli — voir la note de classe.
  ///
  /// ⚠️ Elles ne s'appliquent **qu'aux caractères absents de la
  /// police embarquée**. Depuis que Roboto a remplacé Helvetica, la
  /// plupart ne servent plus : le tiret cadratin, œ, ≥ et € s'impriment
  /// tels quels. Elles sont conservées parce qu'elles décrivent le
  /// **repli correct** si la police venait à changer — les supprimer
  /// reviendrait à parier sur la police du jour.
  ///
  /// Tout caractère absent de la police **et** de cette table devient
  /// « ? » : visible, donc signalé, plutôt que supprimé en silence.
  static const Map<String, String> _substitutions = {
    '—': '-', // — tiret cadratin
    '–': '-', // – tiret demi-cadratin
    '−': '-', // − signe moins
    '‘': "'", // ' apostrophe ouvrante
    '’': "'", // ' apostrophe typographique
    '“': '"', // " guillemet anglais ouvrant
    '”': '"', // " guillemet anglais fermant
    '…': '...', // … points de suspension
    '•': '-', // • puce
    'Œ': 'OE', // Œ
    'œ': 'oe', // œ
    '→': '->', // →
    '←': '<-', // ←
    '≥': '>=', // ≥
    '≤': '<=', // ≤
    '≠': '!=', // ≠
    ' ': ' ', // espace insecable
    ' ': ' ', // espace fine insecable
    '№': 'No', // №
    'ᵉ': 'e', // ᵉ (1ᵉʳ, 2ᵉ)
    'ʳ': 'r', // ʳ
    'ᵐ': 'm', // ᵐ
    '€': 'EUR', // €
    '✓': 'v', // ✓ coche
    '✗': 'x', // ✗ croix
  };

  /// Caractères réellement présents dans la police embarquée.
  ///
  /// `null` tant que la police n'a pas été chargée ; la normalisation retombe
  /// alors sur la table seule — correct, simplement plus prudent.
  static Set<int>? _runesDeLaPolice;

  static (pw.Font, pw.Font)? _cachePolices;

  /// Rend un texte imprimable sans perte silencieuse.
  ///
  /// Un caractère que la police contient est **laissé intact** : c'est tout
  /// l'intérêt d'avoir embarqué Roboto. Seuls les absents sont remplacés, par
  /// leur équivalent de [_substitutions] ou, à défaut, par un point
  /// d'interrogation.
  static String normaliserPourRoboto(String texte) {
    final disponibles = _runesDeLaPolice;
    final tampon = StringBuffer();

    for (final unite in texte.runes) {
      final caractere = String.fromCharCode(unite);

      if (disponibles != null && disponibles.contains(unite)) {
        tampon.write(caractere);
        continue;
      }

      final substitution = _substitutions[caractere];
      if (substitution != null) {
        tampon.write(substitution);
      } else if (disponibles == null && unite <= 0xFF) {
        // Police pas encore chargee : on ne peut rien affirmer au-dela de
        // Latin-1, socle commun a toutes les polices PDF.
        tampon.write(caractere);
      } else {
        tampon.write('?');
      }
    }
    return tampon.toString();
  }

  /// Charge Roboto une seule fois pour toute la durée du processus.
  ///
  /// Relire 340 Ko à chaque export n'aurait rien de visible, mais chaque
  /// document en porterait le coût — et ces états s'impriment en série.
  static Future<(pw.Font, pw.Font)> chargerPolices() async {
    final cache = _cachePolices;
    if (cache != null) return cache;

    final normal = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final gras = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');

    // On ne retient que les caracteres presents dans les DEUX graisses : un
    // glyphe qui n'existerait qu'en romain laisserait un trou dans un titre.
    _runesDeLaPolice = TtfParser(normal).charToGlyphIndexMap.keys
        .toSet()
        .intersection(TtfParser(gras).charToGlyphIndexMap.keys.toSet());

    final polices = (pw.Font.ttf(normal), pw.Font.ttf(gras));
    _cachePolices = polices;
    return polices;
  }

  /// Vide le cache — pour les tests, qui doivent pouvoir observer le
  /// comportement **avant** chargement comme après.
  static void oublierPolices() {
    _cachePolices = null;
    _runesDeLaPolice = null;
  }

  /// Rend le document. `maintenant` est injectable pour rendre la sortie
  /// reproductible en test — sans quoi la date d'édition changerait à chaque
  /// exécution.
  Future<Uint8List> generer(
    DocumentPdf document, {
    required EnteteOfficielle entete,
    DateTime? maintenant,
  }) async {
    final date = maintenant ?? DateTime.now();
    final (normal, gras) = await chargerPolices();

    final doc = pw.Document(
      title: 'LogiALVIA - ${document.titre}',
      author: entete.raisonSociale,
    );

    doc.addPage(
      pw.MultiPage(
        // `@page { size: A4 <orientation>; margin: 14mm; }`
        pageFormat: document.orientation == OrientationPdf.paysage
            ? PdfPageFormat.a4.landscape
            : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(14 * PdfPageFormat.mm),
        theme: pw.ThemeData.withFont(base: normal, bold: gras),
        header: (context) => context.pageNumber == 1
            ? _entete(document, entete, date)
            : pw.SizedBox(height: 0),
        footer: (context) => _pied(context),
        // `build` est appele une seule fois pour produire le flux de widgets :
        // `context.pageNumber` n'y est pas encore defini (il l'est dans
        // `header`/`footer`, appeles page par page). Le bandeau de titre ouvre
        // donc simplement le flux — il n'apparait qu'une fois, en tete du
        // document, ce qui est le comportement voulu.
        build: (context) => [
          _bandeauTitre(document.titre),
          if (document.indicateurs.isNotEmpty)
            _indicateurs(document.indicateurs),
          for (final paragraphe in document.paragraphes)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: _texte(
                paragraphe.texte,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: paragraphe.gras
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                  lineSpacing: 3,
                ),
              ),
            ),
          if (document.estVide)
            _etatVide(document.messageSiVide)
          else
            for (final tableau in document.tableaux)
              if (!tableau.estVide) ..._tableau(tableau),
          if (document.signatures) _signatures(),
        ],
      ),
    );

    return doc.save();
  }

  /// Tout texte du document passe par ici : c'est le point unique ou la
  /// normalisation s'applique, impossible a contourner par oubli.
  pw.Widget _texte(
    String texte, {
    pw.TextStyle? style,
    pw.TextAlign? textAlign,
  }) => pw.Text(
    normaliserPourRoboto(texte),
    style: style,
    textAlign: textAlign,
  );

  pw.Widget _entete(
    DocumentPdf document,
    EnteteOfficielle entete,
    DateTime date,
  ) {
    final mentions = <String>[
      if (entete.ifu != null && entete.ifu!.isNotEmpty) 'IFU : ${entete.ifu}',
      if (entete.rccm != null && entete.rccm!.isNotEmpty)
        'RCCM : ${entete.rccm}',
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      margin: const pw.EdgeInsets.only(bottom: 16),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 2)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _texte(
                  entete.raisonSociale,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: _navy,
                  ),
                ),
                if (entete.promoteur != null && entete.promoteur!.isNotEmpty)
                  _texte(
                    'Gérante : ${entete.promoteur}',
                    style: pw.TextStyle(fontSize: 10, color: _gris),
                  ),
                if (entete.adresse != null && entete.adresse!.isNotEmpty)
                  _texte(
                    entete.adresse!,
                    style: pw.TextStyle(fontSize: 10, color: _gris),
                  ),
                if (mentions.isNotEmpty)
                  _texte(
                    mentions.join('  ·  '),
                    style: pw.TextStyle(fontSize: 10, color: _gris),
                  ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _texte(
                'Édité le : ${Formats.date(date)}',
                style: pw.TextStyle(fontSize: 10, color: _gris),
              ),
              if (document.periode.isNotEmpty)
                _texte(
                  'Période : ${document.periode}',
                  style: pw.TextStyle(fontSize: 10, color: _gris),
                ),
              _texte(
                'Généré par : ${entete.generePar}',
                style: pw.TextStyle(fontSize: 10, color: _gris),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// `.title-band` — fond navy, filet or à gauche, capitales blanches.
  pw.Widget _bandeauTitre(String titre) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _navy,
        border: pw.Border(left: pw.BorderSide(color: _or, width: 4)),
      ),
      child: _texte(
        titre.toUpperCase(),
        style: const pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _indicateurs(List<IndicateurPdf> indicateurs) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      child: pw.Row(
        children: [
          for (final indicateur in indicateurs) ...[
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _or),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _texte(
                      indicateur.libelle.toUpperCase(),
                      style: pw.TextStyle(fontSize: 8, color: _gris),
                    ),
                    pw.SizedBox(height: 2),
                    _texte(
                      indicateur.valeur,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: _navy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (indicateur != indicateurs.last) pw.SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  /// Rend **une liste de widgets**, jamais une `Column` qui les envelopperait.
  ///
  /// `MultiPage` ne sait découper que les widgets de premier niveau de son
  /// `build`. Un `pw.Table` enveloppé dans une `Column` devient indivisible :
  /// au-delà d'une page, la pagination boucle et le paquet lève
  /// `PdfTooBigPageException`. Un journal comptable de 200 lignes est un cas
  /// tout à fait ordinaire — le tableau doit donc rester à plat.
  List<pw.Widget> _tableau(TableauPdf tableau) {
    final largeurs = <int, pw.TableColumnWidth>{
      for (var i = 0; i < tableau.colonnes.length; i++)
        i: pw.FlexColumnWidth(tableau.colonnes[i].largeur.toDouble()),
    };

    return [
        if (tableau.titre != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
            child: _texte(
              tableau.titre!,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _navy,
              ),
            ),
          ),
        pw.Table(
          columnWidths: largeurs,
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _navy),
              repeat: true,
              children: [
                for (final colonne in tableau.colonnes)
                  _cellule(
                    CellulePdf(colonne.titre.toUpperCase()),
                    colonne.alignement,
                    taille: 9,
                    couleur: PdfColors.white,
                    gras: true,
                  ),
              ],
            ),
            for (var i = 0; i < tableau.lignes.length; i++)
              pw.TableRow(
                // `tbody tr:nth-child(even)` — la 1re ligne de donnees est
                // impaire cote CSS, donc blanche.
                decoration: pw.BoxDecoration(
                  color: i.isOdd ? _zebre : null,
                  border: pw.Border(bottom: pw.BorderSide(color: _filet)),
                ),
                children: [
                  for (var c = 0; c < tableau.colonnes.length; c++)
                    _cellule(
                      c < tableau.lignes[i].length
                          ? tableau.lignes[i][c]
                          : const CellulePdf(''),
                      tableau.colonnes[c].alignement,
                    ),
                ],
              ),
            if (tableau.pied != null)
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _zebre),
                children: [
                  for (var c = 0; c < tableau.colonnes.length; c++)
                    _cellule(
                      c < tableau.pied!.length
                          ? tableau.pied![c]
                          : const CellulePdf(''),
                      tableau.colonnes[c].alignement,
                      gras: true,
                    ),
                ],
              ),
          ],
        ),
        if (tableau.note != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 10),
            child: _texte(
              tableau.note!,
              style: pw.TextStyle(fontSize: 8, color: _gris, lineSpacing: 2),
            ),
          )
        else
          pw.SizedBox(height: 10),
    ];
  }

  pw.Widget _cellule(
    CellulePdf cellule,
    AlignementPdf alignement, {
    double taille = 10,
    PdfColor? couleur,
    bool gras = false,
  }) {
    final (couleurTeinte, grasTeinte) = switch (cellule.teinte) {
      TeintePdf.positive => (_vert, true),
      TeintePdf.negative => (_rouge, true),
      TeintePdf.attenuee => (_gris, false),
      TeintePdf.normale => (couleur ?? _encre, false),
    };

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: _texte(
        cellule.texte,
        textAlign: switch (alignement) {
          AlignementPdf.gauche => pw.TextAlign.left,
          AlignementPdf.centre => pw.TextAlign.center,
          AlignementPdf.droite => pw.TextAlign.right,
        },
        style: pw.TextStyle(
          fontSize: taille,
          color: couleur ?? couleurTeinte,
          fontWeight: gras || grasTeinte || cellule.gras
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// Master Prompt §2.2 — un état sans ligne dit pourquoi, il ne reste pas blanc.
  pw.Widget _etatVide(String? message) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _filet)),
      child: _texte(
        message ?? 'Aucune donnée sur la période sélectionnée.',
        style: pw.TextStyle(fontSize: 10, color: _gris, lineSpacing: 3),
      ),
    );
  }

  pw.Widget _signatures() {
    pw.Widget bloc(String libelle) => pw.SizedBox(
      width: 200,
      child: pw.Column(
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 30, bottom: 4),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _encre)),
            ),
          ),
          _texte(libelle, style: pw.TextStyle(fontSize: 9, color: _gris)),
        ],
      ),
    );

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 40),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          bloc('Signature de l\'Animalier / Agent'),
          bloc('Signature de la Gérante / Direction'),
        ],
      ),
    );
  }

  /// Pied de page. Le prototype n'a pas de pagination — il imprime une page
  /// unique. Un état de plusieurs pages sans numéro est inexploitable, la
  /// pagination est donc ajoutée.
  pw.Widget _pied(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _filet)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _texte(
            'LogiALVIA v1.0.0 — ALLMANY ET COMPAGNIE — Natitingou, Bénin',
            style: pw.TextStyle(fontSize: 8, color: _gris),
          ),
          _texte(
            'Page ${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _gris),
          ),
        ],
      ),
    );
  }
}
