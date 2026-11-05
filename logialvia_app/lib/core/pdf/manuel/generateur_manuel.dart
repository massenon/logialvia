/// Compose le manuel d'utilisation en PDF.
///
/// # Parti pris de mise en page
///
/// Le manuel n'est pas un état comptable : il se lit, il ne se contrôle pas.
/// Il ne réutilise donc pas `GenerateurPdf`, dont l'en-tête officielle, les
/// signatures et les tableaux zébrés servent un tout autre usage.
///
/// - **Une police, deux graisses** — Roboto, comme à l'écran. Un manuel qui ne
///   ressemble pas au logiciel oblige le lecteur à traduire.
/// - **La palette du produit** — marine et or de LogiALVIA. Le manuel et
///   l'application doivent se reconnaître comme appartenant au même produit.
/// - **Beaucoup de blanc** — marges larges, interligne 1,6. Le manuel se lit
///   souvent debout, à côté d'un poste.
/// - **Chaque chapitre commence sur une page neuve.** Le blanc de fin de
///   chapitre est voulu.
/// - **Chevrons `›` pour les chemins** — `Élevage › Cycle Couveuse`. La flèche
///   `→` et le `➔` n'existent pas dans Roboto : les employer laisserait un
///   blanc. Vérifié dans la table de caractères, pas supposé.
/// - **Chiffres pour les gestes, puces pour les listes** — l'ordre
///   chronologique se numérote, une énumération sans ordre ne se numérote pas.
///
/// # Les pictogrammes sont dessinés
///
/// ℹ️ ⚠️ 🛑 ✅ n'existent dans aucune police du projet. Chaque encadré porte
/// donc une **pastille vectorielle** — un disque coloré et un signe tracé —
/// plus son mot en toutes lettres. Le repère visuel est conservé, et il
/// s'imprime.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'modele_manuel.dart';

/// Le rectangle d'un repère sur une capture, en pourcentages.
class CoordonneesRepere {
  const CoordonneesRepere({
    required this.x,
    required this.y,
    required this.largeur,
    required this.hauteur,
  });

  final double x;
  final double y;
  final double largeur;
  final double hauteur;
}

class GenerateurManuel {
  const GenerateurManuel();

  // Palette du produit (tailwind-config.js), plus les quatre couleurs
  // sémantiques réservées aux encadrés.
  static final PdfColor _navy = PdfColor.fromHex('#1F3864');
  static final PdfColor _or = PdfColor.fromHex('#B58B2A');
  static final PdfColor _encre = PdfColor.fromHex('#1A1D23');
  static final PdfColor _gris = PdfColor.fromHex('#6B7280');
  static final PdfColor _filet = PdfColor.fromHex('#D8DCE3');
  static final PdfColor _zebre = PdfColor.fromHex('#F7F7F8');
  static final PdfColor _rougeRepere = PdfColor.fromHex('#D12E2E');

  static final Map<NiveauEncadre, PdfColor> _couleurs = {
    NiveauEncadre.information: PdfColor.fromHex('#2563EB'),
    NiveauEncadre.attention: PdfColor.fromHex('#B58B2A'),
    NiveauEncadre.alerte: PdfColor.fromHex('#B33A3A'),
    NiveauEncadre.astuce: PdfColor.fromHex('#3A7D44'),
  };

  static final Map<NiveauEncadre, PdfColor> _fonds = {
    NiveauEncadre.information: PdfColor.fromHex('#EAF1FE'),
    NiveauEncadre.attention: PdfColor.fromHex('#FBF3E0'),
    NiveauEncadre.alerte: PdfColor.fromHex('#FBE3E3'),
    NiveauEncadre.astuce: PdfColor.fromHex('#E1F0E3'),
  };

  static const double _corps = 11;
  static const double _interligne = 3.6; // 11 pt × 1,6 ≈ 17,6 pt de hauteur

  Future<Uint8List> generer({
    required ManuelUtilisation manuel,
    required ByteData roboto,
    required ByteData robotoGras,
    required Map<String, Uint8List> captures,
    required Map<String, Map<String, CoordonneesRepere>> reperes,
    required DateTime edite,
  }) async {
    final normal = pw.Font.ttf(roboto);
    final gras = pw.Font.ttf(robotoGras);

    final doc = pw.Document(
      title: 'LogiALVIA — Manuel d\'utilisation',
      author: '${manuel.editeur.nom} — ${manuel.editeur.qualification}',
      subject:
          'Manuel d\'utilisation de LogiALVIA, application de gestion et de '
          'suivi avicole intégré',
      keywords:
          'LogiALVIA, manuel, élevage, couveuse, ventes, stocks, '
          'comptabilité SYSCOHADA, MeCeF, ALLMANY ET COMPAGNIE',
      creator: 'LogiALVIA — outils/generer_manuel.dart',
    );

    final theme = pw.ThemeData.withFont(base: normal, bold: gras).copyWith(
      defaultTextStyle: pw.TextStyle(
        font: normal,
        fontSize: _corps,
        color: _encre,
        lineSpacing: _interligne,
      ),
    );

    doc.addPage(_couverture(manuel, normal, gras, edite));
    doc.addPage(_commentLire(manuel, theme));
    doc.addPage(_sommaire(manuel, theme));

    for (var c = 0; c < manuel.chapitres.length; c++) {
      doc.addPage(
        _chapitre(manuel, manuel.chapitres[c], c + 1, theme, captures, reperes),
      );
    }
    for (final annexe in manuel.annexes) {
      doc.addPage(_annexe(manuel, annexe, theme));
    }

    return doc.save();
  }

  // ------------------------------------------------------------ couverture

  pw.Page _couverture(
    ManuelUtilisation manuel,
    pw.Font normal,
    pw.Font gras,
    DateTime edite,
  ) {
    final e = manuel.editeur;
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      // Sans cette marge nulle, le bloc marine s'arrêterait à 1 cm du bord et
      // la couverture aurait l'air d'une page ratée.
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Container(
        color: _navy,
        child: pw.Padding(
          padding: const pw.EdgeInsets.all(48),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(width: 64, height: 4, color: _or),
              pw.SizedBox(height: 28),
              pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: 'Logi',
                      style: pw.TextStyle(
                        font: gras,
                        fontSize: 40,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.TextSpan(
                      text: 'ALVIA',
                      style: pw.TextStyle(font: gras, fontSize: 40, color: _or),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Manuel d\'utilisation',
                style: pw.TextStyle(
                  font: normal,
                  fontSize: 22,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${manuel.nombreEcrans} écrans · ${manuel.nombreOnglets} '
                'onglets · ${manuel.nombreModales} fenêtres de saisie',
                style: pw.TextStyle(font: normal, fontSize: 13, color: _or),
              ),
              pw.Spacer(),
              pw.Container(height: 1, color: const PdfColor(1, 1, 1, 0.25)),
              pw.SizedBox(height: 16),
              pw.Text(
                'Destinataire',
                style: pw.TextStyle(
                  font: normal,
                  fontSize: 9,
                  color: const PdfColor(1, 1, 1, 0.55),
                ),
              ),
              pw.Text(
                manuel.destinataire,
                style: pw.TextStyle(
                  font: gras,
                  fontSize: 14,
                  color: PdfColors.white,
                ),
              ),
              pw.Text(
                'Ferme avicole, cunicole et piscicole — Natitingou, Bénin',
                style: pw.TextStyle(
                  font: normal,
                  fontSize: 11,
                  color: const PdfColor(1, 1, 1, 0.7),
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Text(
                'Éditeur',
                style: pw.TextStyle(
                  font: normal,
                  fontSize: 9,
                  color: const PdfColor(1, 1, 1, 0.55),
                ),
              ),
              pw.Text(
                e.nom,
                style: pw.TextStyle(
                  font: gras,
                  fontSize: 13,
                  color: PdfColors.white,
                ),
              ),
              pw.Text(
                e.qualification,
                style: pw.TextStyle(
                  font: normal,
                  fontSize: 11,
                  color: const PdfColor(1, 1, 1, 0.7),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${e.telephones}   ·   ${e.emails}',
                style: pw.TextStyle(
                  font: normal,
                  fontSize: 10,
                  color: const PdfColor(1, 1, 1, 0.7),
                ),
              ),
              pw.SizedBox(height: 14),
              // Le cabinet et le programme : ce logiciel n'est pas né tout
              // seul, et la Gérante doit savoir à quel accompagnement il se
              // rattache.
              pw.Container(width: 40, height: 2, color: _or),
              pw.SizedBox(height: 8),
              pw.Text(
                e.societe,
                style: pw.TextStyle(
                  font: gras,
                  fontSize: 12,
                  color: PdfColors.white,
                ),
              ),
              pw.Text(
                e.roleSociete,
                style: pw.TextStyle(
                  font: normal,
                  fontSize: 10,
                  color: const PdfColor(1, 1, 1, 0.7),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                e.programme,
                style: pw.TextStyle(font: normal, fontSize: 10, color: _or),
              ),
              pw.SizedBox(height: 14),
              pw.Text(
                'Version ${manuel.version}  ·  Édité le ${_date(edite)}',
                style: pw.TextStyle(
                  font: normal,
                  fontSize: 10,
                  color: const PdfColor(1, 1, 1, 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------- comment lire ce manuel

  pw.Page _commentLire(ManuelUtilisation manuel, pw.ThemeData theme) {
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.fromLTRB(48, 52, 48, 48),
      header: (c) => _enTete(manuel, c),
      footer: (c) => _pied(manuel, c),
      build: (context) => [
        _titreNiveau1('Comment lire ce manuel'),
        pw.SizedBox(height: 12),
        _paragraphe(
          'Ce manuel emploie trois conventions, toujours les mêmes du début à '
          'la fin. Les connaître fait gagner du temps sur chaque page.',
        ),
        pw.SizedBox(height: 18),
        _sousTitre('1.  Les chemins d\'accès'),
        pw.SizedBox(height: 6),
        _paragraphe(
          'Une suite d\'écrans à traverser s\'écrit avec des chevrons : '
          '**PARAMÈTRES › Paramètres Général › Sauvegardes**. Le premier nom '
          'est celui du groupe dans la barre latérale, à gauche de l\'écran.',
        ),
        pw.SizedBox(height: 16),
        _sousTitre('2.  Les éléments de l\'interface'),
        pw.SizedBox(height: 8),
        pw.Wrap(
          spacing: 14,
          runSpacing: 8,
          crossAxisAlignment: pw.WrapCrossAlignment.center,
          children: [
            _marqueurBouton('Valider la Vente'),
            _paragraphe('un bouton sur lequel cliquer', taille: 10.5),
            _marqueurChamp('Montant reçu'),
            _paragraphe('un champ à remplir', taille: 10.5),
            _marqueurEcran('Historique des Ventes'),
            _paragraphe('un écran ou un onglet', taille: 10.5),
          ],
        ),
        pw.SizedBox(height: 8),
        _paragraphe(
          'Chaque nom est écrit **exactement** comme à l\'écran, avec sa '
          'casse et sa ponctuation. Si le manuel dit « Émettre une Facture », '
          'c\'est ce que porte le bouton.',
        ),
        pw.SizedBox(height: 16),
        _sousTitre('3.  Les listes'),
        pw.SizedBox(height: 6),
        _paragraphe(
          'Les **chiffres** marquent un ordre à respecter : 1, puis 2, puis 3. '
          'Les **puces rondes** marquent une énumération sans ordre — des '
          'variantes, des prérequis, des points à connaître.',
        ),
        pw.SizedBox(height: 16),
        _sousTitre('4.  Les captures annotées'),
        pw.SizedBox(height: 6),
        _paragraphe(
          'Les pastilles rouges numérotées désignent un élément précis de '
          'l\'écran ; la légende sous l\'image dit ce que chacune montre. Un '
          'cadre en trait plein entoure un élément, un cadre en pointillés '
          'une zone entière.',
        ),
        pw.SizedBox(height: 20),
        _titreNiveau1('Les quatre repères'),
        pw.SizedBox(height: 10),
        _paragraphe(
          'Le code couleur se comprend sans lire le texte. L\'alerte rouge ne '
          'se galvaude pas : elle est réservée à ce qui détruit des données ou '
          'engage la responsabilité de l\'entreprise.',
        ),
        pw.SizedBox(height: 12),
        _legendeEncadres(),
      ],
    );
  }

  /// La légende des quatre repères.
  pw.Widget _legendeEncadres() {
    const explications = {
      NiveauEncadre.information: 'une précision qui aide à comprendre',
      NiveauEncadre.attention:
          'une erreur fréquente, rencontrée sur le terrain',
      NiveauEncadre.alerte: 'une perte de données ou une action irréversible',
      NiveauEncadre.astuce: 'un raccourci, une bonne pratique',
    };

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _zebre,
        border: pw.Border.all(color: _filet),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final entree in explications.entries)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 7),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  _pastille(entree.key),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    entree.key.libelle,
                    style: pw.TextStyle(
                      fontSize: 10.5,
                      color: _couleurs[entree.key],
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '  ${entree.value}',
                    style: const pw.TextStyle(fontSize: 10.5),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- sommaire

  pw.Page _sommaire(ManuelUtilisation manuel, pw.ThemeData theme) {
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.fromLTRB(48, 52, 48, 48),
      header: (c) => _enTete(manuel, c),
      footer: (c) => _pied(manuel, c),
      build: (context) => [
        _titreNiveau1('Avant de commencer'),
        pw.SizedBox(height: 10),
        for (final p in manuel.avantPropos) ...[
          _paragraphe(p),
          pw.SizedBox(height: 8),
        ],
        pw.SizedBox(height: 18),
        _titreNiveau1('Sommaire'),
        pw.SizedBox(height: 12),
        for (var c = 0; c < manuel.chapitres.length; c++) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
            child: pw.Text(
              '${c + 1}.  ${manuel.chapitres[c].titre}',
              style: pw.TextStyle(fontSize: 13, color: _navy),
            ),
          ),
          for (final s in manuel.chapitres[c].sections) _ligneSommaire(s),
        ],
        if (manuel.annexes.isNotEmpty) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
            child: pw.Text(
              'Annexes',
              style: pw.TextStyle(fontSize: 13, color: _navy),
            ),
          ),
          for (final a in manuel.annexes)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 22, bottom: 2),
              child: pw.Text(
                'Annexe ${a.lettre} — ${a.titre}',
                style: const pw.TextStyle(fontSize: 10.5),
              ),
            ),
        ],
      ],
    );
  }

  pw.Widget _ligneSommaire(SectionManuel s) => pw.Padding(
    padding: const pw.EdgeInsets.only(left: 22, bottom: 2),
    child: pw.Row(
      children: [
        pw.Container(
          width: 3,
          height: 3,
          margin: const pw.EdgeInsets.only(right: 8, top: 1),
          decoration: pw.BoxDecoration(color: _or, shape: pw.BoxShape.circle),
        ),
        pw.Expanded(
          child: pw.Text(s.titre, style: const pw.TextStyle(fontSize: 10.5)),
        ),
        pw.Text(s.chemin, style: pw.TextStyle(fontSize: 9, color: _gris)),
      ],
    ),
  );

  // --------------------------------------------------------------- chapitre

  pw.Page _chapitre(
    ManuelUtilisation manuel,
    ChapitreManuel chapitre,
    int numero,
    pw.ThemeData theme,
    Map<String, Uint8List> captures,
    Map<String, Map<String, CoordonneesRepere>> reperes,
  ) {
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.fromLTRB(48, 52, 48, 48),
      header: (c) => _enTete(manuel, c),
      footer: (c) => _pied(manuel, c),
      build: (context) => [
        pw.Outline(
          name: 'chapitre-$numero',
          title: '$numero. ${chapitre.titre}',
          child: _titreNiveau1('$numero.  ${chapitre.titre}'),
        ),
        pw.SizedBox(height: 8),
        _paragraphe(chapitre.introduction, couleur: _gris),
        pw.SizedBox(height: 6),
        for (var i = 0; i < chapitre.sections.length; i++)
          ..._section(
            chapitre.sections[i],
            '$numero.${i + 1}',
            captures,
            reperes,
          ),
      ],
    );
  }

  List<pw.Widget> _section(
    SectionManuel section,
    String numero,
    Map<String, Uint8List> captures,
    Map<String, Map<String, CoordonneesRepere>> reperes,
  ) {
    final capture = section.capture == null ? null : captures[section.capture!];

    return [
      pw.SizedBox(height: 20),
      // Le titre, le rappel « OÙ ? / QUI ? » et la phrase de présentation
      // voyagent ensemble : un titre seul en pied de page n'annonce rien.
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Outline(
              name: 'section-$numero',
              title: '$numero ${section.titre}',
              level: 1,
              child: _titreSection(numero, section.titre),
            ),
            pw.SizedBox(height: 8),
            _ligneReperes(section),
            pw.SizedBox(height: 10),
            _paragraphe(section.aQuoiCaSert),
          ],
        ),
      ),
      if (capture != null)
        ..._blocCapture(
          capture,
          legende: 'Écran ${section.titre}',
          reperes: section.reperes,
          coordonnees: reperes[section.capture] ?? const {},
        ),
      if (section.etapes.isNotEmpty) ..._blocEtapes(section.etapes),
      if (section.onglets.isNotEmpty)
        ..._blocOnglets(section.onglets, captures),
      if (section.modales.isNotEmpty)
        ..._blocModales(section.modales, captures),
      if (section.tableaux.isNotEmpty)
        for (final t in section.tableaux) ..._blocTableau(t),
      if (section.aRetenir.isNotEmpty) ..._blocARetenir(section.aRetenir),
      for (final e in section.encadres) ...[
        pw.SizedBox(height: 10),
        _encadre(e),
      ],
    ];
  }

  // ------------------------------------------------------------- les blocs

  /// La capture, ses repères numérotés et sa légende — insécables.
  List<pw.Widget> _blocCapture(
    Uint8List image, {
    required String legende,
    required List<ReperManuel> reperes,
    required Map<String, CoordonneesRepere> coordonnees,
  }) {
    // Seuls les repères dont l'ancre a réellement été relevée sont dessinés :
    // une pastille posée au jugé pointerait à côté.
    final poses = <(int, ReperManuel, CoordonneesRepere)>[];
    for (var i = 0; i < reperes.length; i++) {
      final c = coordonnees[reperes[i].ancre];
      if (c != null) poses.add((poses.length + 1, reperes[i], c));
    }

    return [
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 12),
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _filet),
                borderRadius: pw.BorderRadius.circular(4),
                boxShadow: [
                  const pw.BoxShadow(
                    color: PdfColor(0, 0, 0, 0.10),
                    offset: PdfPoint(0, -1),
                    blurRadius: 2,
                  ),
                ],
              ),
              child: pw.Stack(
                children: [
                  pw.Image(pw.MemoryImage(image), fit: pw.BoxFit.contain),
                  for (final (numero, repere, c) in poses)
                    pw.Positioned.fill(
                      child: pw.LayoutBuilder(
                        builder: (context, constraints) =>
                            _repereSurCapture(numero, repere, c, constraints!),
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              poses.isEmpty
                  ? '$legende, avec des données de démonstration.'
                  : '$legende, avec des données de démonstration. '
                        '${poses.map((p) => '${p.$1} ${p.$2.legende}').join('  ·  ')}',
              style: pw.TextStyle(fontSize: 8.5, color: _gris),
            ),
          ],
        ),
      ),
    ];
  }

  /// Un cadre et sa pastille numérotée, placés aux coordonnées relevées.
  pw.Widget _repereSurCapture(
    int numero,
    ReperManuel repere,
    CoordonneesRepere c,
    pw.BoxConstraints contraintes,
  ) {
    final l = contraintes.maxWidth;
    final h = contraintes.maxHeight;
    final gauche = c.x / 100 * l;
    final haut = c.y / 100 * h;
    final largeur = c.largeur / 100 * l;
    final hauteur = c.hauteur / 100 * h;

    return pw.Stack(
      children: [
        pw.Positioned(
          left: gauche,
          top: haut,
          child: pw.Container(
            width: largeur,
            height: hauteur,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                color: repere.zone
                    ? PdfColor(
                        _rougeRepere.red,
                        _rougeRepere.green,
                        _rougeRepere.blue,
                        0.55,
                      )
                    : _rougeRepere,
                width: repere.zone ? 0.8 : 1.2,
              ),
              borderRadius: pw.BorderRadius.circular(3),
            ),
          ),
        ),
        // La pastille au coin haut-gauche du rectangle, legerement debordante
        // pour ne pas masquer le contenu qu'elle designe.
        pw.Positioned(
          left: gauche - 7,
          top: haut - 7,
          child: pw.Container(
            width: 14,
            height: 14,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: _rougeRepere,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              '$numero',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<pw.Widget> _blocEtapes(List<EtapeManuel> etapes) => [
    pw.Inseparable(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 14),
          _surtitre('Pas à pas'),
          pw.SizedBox(height: 6),
          _etape(1, etapes.first),
        ],
      ),
    ),
    for (var i = 1; i < etapes.length; i++) _etape(i + 1, etapes[i]),
  ];

  List<pw.Widget> _blocOnglets(
    List<OngletManuel> onglets,
    Map<String, Uint8List> captures,
  ) => [
    pw.Inseparable(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 14),
          _surtitre('Les ${onglets.length} onglets de cet écran'),
          pw.SizedBox(height: 6),
          _ligneOnglet(onglets.first),
        ],
      ),
    ),
    for (final o in onglets.skip(1)) _ligneOnglet(o),
    for (final o in onglets)
      if (o.capture != null && captures[o.capture] != null)
        ..._blocCapture(
          captures[o.capture]!,
          legende: 'Onglet ${o.nom}',
          reperes: const [],
          coordonnees: const {},
        ),
  ];

  List<pw.Widget> _blocModales(
    List<ModaleManuel> modales,
    Map<String, Uint8List> captures,
  ) => [
    for (final m in modales) ...[
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 14),
            _surtitre('Fenêtre « ${m.nom} »'),
            pw.SizedBox(height: 6),
            pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: _corps),
                children: [
                  const pw.TextSpan(text: 'S\'ouvre par '),
                  pw.WidgetSpan(child: _marqueurBouton(m.declencheur)),
                  const pw.TextSpan(text: '.  '),
                  pw.TextSpan(text: m.aQuoiCaSert),
                ],
              ),
            ),
          ],
        ),
      ),
      if (m.capture != null && captures[m.capture] != null)
        ..._blocCapture(
          captures[m.capture]!,
          legende: 'Fenêtre ${m.nom}',
          reperes: const [],
          coordonnees: const {},
        ),
      if (m.champs.isNotEmpty)
        ..._blocTableau(
          TableauManuel(titre: 'Les champs de ${m.nom}', colonnes: m.champs),
          intitule: 'Champ',
        ),
      for (final e in m.encadres) ...[pw.SizedBox(height: 10), _encadre(e)],
    ],
  ];

  /// Un tableau de référence. L'en-tête se répète quand il se coupe.
  List<pw.Widget> _blocTableau(
    TableauManuel tableau, {
    String intitule = 'Colonne',
  }) => [
    pw.SizedBox(height: 14),
    _surtitre(tableau.titre),
    pw.SizedBox(height: 6),
    pw.TableHelper.fromTextArray(
      headers: [intitule, 'Ce qu\'elle contient'],
      data: [
        for (final c in tableau.colonnes) [c.nom, c.contenu],
      ],
      border: pw.TableBorder.symmetric(
        inside: pw.BorderSide(color: _filet, width: 0.5),
        outside: pw.BorderSide(color: _filet, width: 0.5),
      ),
      headerStyle: const pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        letterSpacing: 0.5,
      ),
      headerDecoration: pw.BoxDecoration(color: _navy),
      headerAlignment: pw.Alignment.centerLeft,
      cellStyle: const pw.TextStyle(fontSize: 9.8),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      oddRowDecoration: pw.BoxDecoration(color: _zebre),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(7),
      },
    ),
  ];

  List<pw.Widget> _blocARetenir(List<String> points) => [
    pw.Inseparable(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 12),
          _surtitre('À retenir'),
          pw.SizedBox(height: 6),
          _puce(points.first),
        ],
      ),
    ),
    for (final p in points.skip(1)) _puce(p),
  ];

  // ---------------------------------------------------------------- annexes

  pw.Page _annexe(
    ManuelUtilisation manuel,
    AnnexeManuel annexe,
    pw.ThemeData theme,
  ) {
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.fromLTRB(48, 52, 48, 48),
      header: (c) => _enTete(manuel, c),
      footer: (c) => _pied(manuel, c),
      build: (context) => [
        pw.Outline(
          name: 'annexe-${annexe.lettre}',
          title: 'Annexe ${annexe.lettre} — ${annexe.titre}',
          child: _titreNiveau1('Annexe ${annexe.lettre}  —  ${annexe.titre}'),
        ),
        pw.SizedBox(height: 8),
        _paragraphe(annexe.introduction, couleur: _gris),
        for (final p in annexe.paragraphes) ...[
          pw.SizedBox(height: 10),
          _paragraphe(p),
        ],
        if (annexe.puces.isNotEmpty) pw.SizedBox(height: 8),
        for (final p in annexe.puces) _puce(p),
        for (final t in annexe.tableaux)
          ..._blocTableau(t, intitule: 'Élément'),
        for (final e in annexe.encadres) ...[
          pw.SizedBox(height: 10),
          _encadre(e),
        ],
      ],
    );
  }

  // ----------------------------------------------------------- les briques

  pw.Widget _titreSection(String numero, String titre) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.only(bottom: 5),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _or, width: 1.5)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text('$numero  ', style: pw.TextStyle(fontSize: 15, color: _or)),
        pw.Expanded(
          child: pw.Text(
            titre,
            style: pw.TextStyle(fontSize: 15, color: _navy),
          ),
        ),
      ],
    ),
  );

  /// Chemin d'accès et rôle autorisé, sur une ligne.
  pw.Widget _ligneReperes(SectionManuel section) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: pw.BoxDecoration(
      color: _zebre,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Row(
      children: [
        pw.Text('OÙ ?  ', style: pw.TextStyle(fontSize: 8.5, color: _gris)),
        pw.Expanded(
          child: pw.Text(
            section.chemin,
            style: pw.TextStyle(fontSize: 10, color: _navy),
          ),
        ),
        pw.Text('QUI ?  ', style: pw.TextStyle(fontSize: 8.5, color: _gris)),
        pw.Text(section.role, style: const pw.TextStyle(fontSize: 10)),
      ],
    ),
  );

  pw.Widget _etape(int numero, EtapeManuel etape) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 9),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 19,
          height: 19,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(color: _navy, shape: pw.BoxShape.circle),
          child: pw.Text(
            '$numero',
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                etape.titre,
                style: pw.TextStyle(
                  fontSize: _corps,
                  color: _navy,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 1),
              _paragraphe(etape.texte),
            ],
          ),
        ),
      ],
    ),
  );

  pw.Widget _ligneOnglet(OngletManuel onglet) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 5,
          height: 5,
          margin: const pw.EdgeInsets.only(top: 5.5, right: 8, left: 2),
          decoration: pw.BoxDecoration(color: _navy, shape: pw.BoxShape.circle),
        ),
        pw.Expanded(
          child: pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 10.5),
              children: [
                pw.TextSpan(
                  text: '${onglet.nom} — ',
                  style: pw.TextStyle(
                    color: _navy,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.TextSpan(text: onglet.aQuoiCaSert),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  pw.Widget _puce(String texte) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 4,
          height: 4,
          margin: const pw.EdgeInsets.only(top: 6, right: 9, left: 4),
          decoration: pw.BoxDecoration(color: _or, shape: pw.BoxShape.circle),
        ),
        pw.Expanded(child: _paragraphe(texte)),
      ],
    ),
  );

  pw.Widget _encadre(EncadreManuel encadre) {
    final couleur = _couleurs[encadre.niveau]!;
    // Le filet de couleur est un **fond**, pas une bordure : `Border(left: …)`
    // avec un `borderRadius` lève une assertion du paquet.
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: couleur,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Container(
        margin: const pw.EdgeInsets.only(left: 3),
        padding: const pw.EdgeInsets.all(11),
        decoration: pw.BoxDecoration(
          color: _fonds[encadre.niveau],
          borderRadius: const pw.BorderRadius.horizontal(
            right: pw.Radius.circular(4),
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _pastille(encadre.niveau),
            pw.SizedBox(width: 9),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    encadre.niveau.libelle.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      color: couleur,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  _paragraphe(encadre.texte, taille: 10.5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Le pictogramme, **dessiné** : aucune police du projet n'a d'emoji.
  pw.Widget _pastille(NiveauEncadre niveau) {
    final couleur = _couleurs[niveau]!;
    final carre = niveau == NiveauEncadre.alerte;

    return pw.Container(
      width: 16,
      height: 16,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: couleur,
        shape: carre ? pw.BoxShape.rectangle : pw.BoxShape.circle,
        borderRadius: carre ? pw.BorderRadius.circular(3) : null,
      ),
      child: niveau == NiveauEncadre.astuce
          ? pw.CustomPaint(size: const PdfPoint(16, 16), painter: _coche)
          : pw.Text(
              niveau == NiveauEncadre.information ? 'i' : '!',
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
    );
  }

  /// Une coche blanche, en deux segments. L'origine du PDF part du **bas**.
  static void _coche(PdfGraphics canvas, PdfPoint taille) {
    canvas
      ..setStrokeColor(PdfColors.white)
      ..setLineWidth(1.5)
      ..setLineCap(PdfLineCap.round)
      ..setLineJoin(PdfLineJoin.round)
      ..moveTo(4.5, 8.4)
      ..lineTo(6.9, 5.6)
      ..lineTo(11.6, 10.8)
      ..strokePath();
  }

  // ------------------------------------------------- marquages signalétiques

  /// Un bouton cité : fond plein, texte blanc.
  pw.Widget _marqueurBouton(String texte) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
    decoration: pw.BoxDecoration(
      color: _navy,
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: pw.Text(
      texte,
      style: const pw.TextStyle(
        fontSize: 9.5,
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );

  /// Un champ à remplir : fond blanc, bordure d'accent.
  pw.Widget _marqueurChamp(String texte) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      border: pw.Border.all(color: _or, width: 0.8),
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: pw.Text(texte, style: pw.TextStyle(fontSize: 9.5, color: _encre)),
  );

  /// Un écran ou un onglet : fond gris très clair.
  pw.Widget _marqueurEcran(String texte) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
    decoration: pw.BoxDecoration(
      color: _zebre,
      border: pw.Border.all(color: _filet, width: 0.8),
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: pw.Text(texte, style: pw.TextStyle(fontSize: 9.5, color: _navy)),
  );

  // ------------------------------------------------------------------ texte

  /// Rend un paragraphe en respectant les passages entre `**`.
  ///
  /// Le manuel met en gras le mot qui porte la règle — « le stock **final** de
  /// la veille ». Sans ce rendu, les étoiles s'imprimaient telles quelles.
  pw.Widget _paragraphe(
    String texte, {
    double taille = _corps,
    PdfColor? couleur,
  }) {
    final morceaux = texte.split('**');
    if (morceaux.length == 1) {
      return pw.Text(
        texte,
        style: pw.TextStyle(fontSize: taille, color: couleur),
      );
    }
    return pw.RichText(
      text: pw.TextSpan(
        style: pw.TextStyle(fontSize: taille, color: couleur),
        children: [
          for (var i = 0; i < morceaux.length; i++)
            pw.TextSpan(
              text: morceaux[i],
              // Un indice impair est un passage encadré par deux `**`.
              style: i.isOdd
                  ? const pw.TextStyle(fontWeight: pw.FontWeight.bold)
                  : null,
            ),
        ],
      ),
    );
  }

  pw.Widget _titreNiveau1(String texte) =>
      pw.Text(texte, style: pw.TextStyle(fontSize: 21, color: _navy));

  pw.Widget _sousTitre(String texte) =>
      pw.Text(texte, style: pw.TextStyle(fontSize: 13.5, color: _navy));

  pw.Widget _surtitre(String texte) => pw.Text(
    texte.toUpperCase(),
    style: pw.TextStyle(fontSize: 9, color: _gris, letterSpacing: 0.7),
  );

  // ----------------------------------------------------- en-tête et pied

  pw.Widget _enTete(ManuelUtilisation manuel, pw.Context context) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        padding: const pw.EdgeInsets.only(bottom: 5),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _filet, width: 0.6)),
        ),
        child: pw.Row(
          children: [
            pw.Text(
              'LogiALVIA — Manuel d\'utilisation',
              style: pw.TextStyle(fontSize: 8.5, color: _navy),
            ),
            pw.Spacer(),
            pw.Text(
              manuel.destinataire,
              style: pw.TextStyle(fontSize: 8.5, color: _gris),
            ),
          ],
        ),
      );

  pw.Widget _pied(ManuelUtilisation manuel, pw.Context context) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 12),
    child: pw.Row(
      children: [
        pw.Text(
          '${manuel.editeur.societe}  ·  ${manuel.editeur.nom}  ·  '
          'version ${manuel.version}',
          style: pw.TextStyle(fontSize: 8.5, color: _gris),
        ),
        pw.Spacer(),
        pw.Text(
          'page ${context.pageNumber} / ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 9, color: _navy),
        ),
      ],
    ),
  );

  static String _date(DateTime d) => '${_dd(d.day)}/${_dd(d.month)}/${d.year}';

  static String _dd(int v) => v.toString().padLeft(2, '0');
}
