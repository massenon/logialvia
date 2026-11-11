/// Relève les libellés réellement affichés par chaque écran.
///
/// # Ne jamais écrire de mémoire
///
/// C'est la règle qui sépare un manuel fiable d'un manuel décoratif : chaque
/// libellé cité doit venir du logiciel, jamais d'une reconstitution. Un manuel
/// qui écrit « cliquez sur le bouton de validation » là où l'écran affiche
/// « Valider la Commande » envoie le lecteur chercher un bouton qui n'existe
/// pas.
///
/// Là où un produit web se relève en pilotant un navigateur, une application
/// Flutter se relève en **parcourant son arbre de widgets** pendant qu'elle est
/// montée. C'est plus fiable qu'un balayage de code source : ce qui est relevé
/// ici est ce qui s'affiche, y compris les libellés composés à l'exécution.
///
/// Sortie : `docs/manuel/libelles/<ecran>.json`, source de rédaction du manuel.
library;

import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:logialvia_app/core/tour/tour_guide.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ce qu'un écran donne à lire.
class InventaireEcran {
  InventaireEcran(this.fichier);

  final String fichier;

  final Set<String> titres = {};
  final Set<String> boutons = {};
  final Set<String> champs = {};
  final Set<String> colonnes = {};
  final Set<String> onglets = {};
  final Set<String> infobulles = {};
  final Set<String> textes = {};

  Map<String, dynamic> versJson() => {
    'ecran': fichier,
    'titres': titres.toList()..sort(),
    'onglets': onglets.toList()..sort(),
    'boutons': boutons.toList()..sort(),
    'champs': champs.toList()..sort(),
    'colonnes': colonnes.toList()..sort(),
    'infobulles': infobulles.toList()..sort(),
    'textes': textes.toList()..sort(),
  };
}

/// Parcourt l'arbre monté et classe chaque libellé selon le widget qui le
/// porte.
///
/// La classification n'est pas cosmétique : le manuel doit pouvoir écrire
/// « bouton **Émettre une Facture** » et « colonne **STOCK FINAL** » sans se
/// tromper de nature. Un libellé mal classé produit une phrase fausse.
InventaireEcran relever(WidgetTester tester, String fichier) {
  final inventaire = InventaireEcran(fichier);

  /// Le texte porté par un widget, quelle que soit sa forme.
  String? texteDe(Widget widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    return null;
  }

  /// Les textes contenus sous un élément — un bouton porte son libellé dans un
  /// `Text` descendant, pas dans ses propres champs.
  List<String> textesSous(Element element) {
    final trouves = <String>[];
    void descendre(Element e) {
      final t = texteDe(e.widget);
      if (t != null && t.trim().isNotEmpty) trouves.add(t.trim());
      e.visitChildren(descendre);
    }

    element.visitChildren(descendre);
    return trouves;
  }

  void visiter(Element element) {
    final widget = element.widget;

    if (widget is Tooltip) {
      final message = widget.message?.trim();
      if (message != null && message.isNotEmpty) {
        inventaire.infobulles.add(message);
      }
    } else if (widget is ButtonStyleButton ||
        widget is InkWell ||
        widget is MaterialButton) {
      // Un bouton peut envelopper plusieurs textes (icone + libelle) : on
      // retient le plus long, qui est le libelle.
      final textes = textesSous(element);
      if (textes.isNotEmpty) {
        textes.sort((a, b) => b.length.compareTo(a.length));
        inventaire.boutons.add(textes.first);
      }
    } else if (widget is TextField) {
      final decoration = widget.decoration;
      final etiquette = decoration?.labelText?.trim();
      final indice = decoration?.hintText?.trim();
      if (etiquette != null && etiquette.isNotEmpty) {
        inventaire.champs.add(etiquette);
      }
      if (indice != null && indice.isNotEmpty) {
        inventaire.champs.add('(indication) $indice');
      }
    } else if (widget is DropdownButtonFormField) {
      final etiquette = widget.decoration.labelText?.trim();
      if (etiquette != null && etiquette.isNotEmpty) {
        inventaire.champs.add(etiquette);
      }
    } else if (widget is Text) {
      final t = texteDe(widget)?.trim();
      if (t != null && t.isNotEmpty) {
        // Les en-tetes de colonnes sont ecrits en capitales dans toute
        // l'application : c'est le seul signe distinctif fiable, et il est
        // constant depuis le prototype.
        final estCapitales =
            t == t.toUpperCase() &&
            t.length > 2 &&
            RegExp(r'[A-ZÉÈÀÙÂÊÎÔÛÇ]').hasMatch(t);
        if (estCapitales) {
          inventaire.colonnes.add(t);
        } else {
          inventaire.textes.add(t);
        }
      }
    }

    element.visitChildren(visiter);
  }

  tester.binding.rootElement?.visitChildren(visiter);
  return inventaire;
}

/// Écrit l'inventaire d'un écran sur le disque.
void ecrireInventaire(InventaireEcran inventaire, String dossier) {
  Directory(dossier).createSync(recursive: true);
  File('$dossier/${inventaire.fichier}.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(inventaire.versJson()),
  );
}

/// Le rectangle d'un élément cible, en pourcentages de la capture.
///
/// # Pourquoi des pourcentages, et pourquoi les relever
///
/// Une flèche posée à l'œil se décale à la première recapture. Relevé pendant
/// que l'écran est monté, le rectangle réel de l'élément suit automatiquement
/// toute évolution de la mise en page — le repère reste sur sa cible sans que
/// personne n'y retouche.
///
/// Les ancres ne sont pas inventées non plus : ce sont les **cibles de la
/// visite guidée**, déjà posées dans l'application par `CibleTour`. Le manuel
/// et la visite montrent donc exactement les mêmes éléments.
class ReperCapture {
  const ReperCapture({
    required this.nom,
    required this.x,
    required this.y,
    required this.largeur,
    required this.hauteur,
  });

  final String nom;
  final double x;
  final double y;
  final double largeur;
  final double hauteur;

  Map<String, dynamic> versJson() => {
    'nom': nom,
    'x': double.parse(x.toStringAsFixed(2)),
    'y': double.parse(y.toStringAsFixed(2)),
    'largeur': double.parse(largeur.toStringAsFixed(2)),
    'hauteur': double.parse(hauteur.toStringAsFixed(2)),
  };
}

/// Relève le rectangle de chaque cible de visite guidée présente à l'écran.
List<ReperCapture> releverReperes(WidgetTester tester, Size surface) {
  final reperes = <ReperCapture>[];

  void visiter(Element element) {
    final widget = element.widget;
    if (widget is CibleTour) {
      final boite = element.renderObject;
      if (boite is RenderBox && boite.hasSize) {
        final origine = boite.localToGlobal(Offset.zero);
        // Hors champ : un element replie ou defile hors de la fenetre n'a rien
        // a annoter.
        final visible =
            origine.dx >= -1 &&
            origine.dy >= -1 &&
            origine.dx + boite.size.width <= surface.width + 1 &&
            origine.dy + boite.size.height <= surface.height + 1;
        if (visible && boite.size.width > 0 && boite.size.height > 0) {
          reperes.add(
            ReperCapture(
              nom: widget.nom,
              x: origine.dx / surface.width * 100,
              y: origine.dy / surface.height * 100,
              largeur: boite.size.width / surface.width * 100,
              hauteur: boite.size.height / surface.height * 100,
            ),
          );
        }
      }
    }
    element.visitChildren(visiter);
  }

  tester.binding.rootElement?.visitChildren(visiter);
  return reperes;
}

/// Écrit les repères d'un écran sur le disque.
void ecrireReperes(String fichier, List<ReperCapture> reperes, String dossier) {
  if (reperes.isEmpty) return;
  Directory(dossier).createSync(recursive: true);
  File('$dossier/$fichier.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'ecran': fichier,
      'reperes': [for (final r in reperes) r.versJson()],
    }),
  );
}
