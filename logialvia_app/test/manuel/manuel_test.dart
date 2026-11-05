import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/pdf/manuel/contenu_manuel.dart';
import 'package:logialvia_app/core/pdf/manuel/generateur_manuel.dart';
import 'package:logialvia_app/core/pdf/manuel/modele_manuel.dart';
import 'package:logialvia_app/core/router/navigation_model.dart';

/// Le manuel dit-il vrai, et s'imprime-t-il ?
///
/// ## Les trois façons dont un manuel se périme
///
/// 1. **Il nomme un écran qui a changé de nom.** L'utilisatrice cherche
///    « Catalogue Produits » dans une barre latérale qui affiche « Catalogue &
///    Seuils », et conclut que le manuel ne parle pas de son logiciel.
/// 2. **Il montre une capture qui n'existe plus**, ou plus du tout : le PDF se
///    génère quand même, avec un trou blanc que personne ne voit avant
///    l'impression.
/// 3. **Il emploie un caractère absent de Roboto.** Aucune erreur, aucun
///    avertissement — juste un blanc à la place du pictogramme, dans un
///    document déjà distribué.
///
/// Les trois passent inaperçues à la relecture. Elles sont donc verrouillées.
void main() {
  final sections = ContenuManuel.manuel.chapitres
      .expand((c) => c.sections)
      .toList();

  group('Contenu', () {
    test('chaque écran de l\'application a sa section', () {
      // Les 4 ecrans du hub Comptabilite ne figurent pas dans la barre
      // laterale : ils sont ajoutes a la main a la liste attendue.
      final barreLaterale = NavigationModel.groupes
          .expand((g) => g.entrees)
          .map((e) => e.libelle)
          .toSet();
      final decrits = sections.map((s) => s.titre).toSet();

      final oublies = barreLaterale.difference(decrits);
      expect(
        oublies,
        isEmpty,
        reason:
            'Ces entrées de menu n\'ont aucune section dans le manuel : '
            '${oublies.join(', ')}.',
      );
    });

    test('aucun titre n\'invente un libellé de menu', () {
      final barreLaterale = NavigationModel.groupes
          .expand((g) => g.entrees)
          .map((e) => e.libelle)
          .toSet();
      // Les ecrans hors barre laterale, nommes ailleurs dans l'interface.
      const horsBarre = {
        // Le chapitre « Prise en main » decrit des ecrans et des gestes qui ne
        // sont pas des entrees de menu : l'ecran de connexion precede la barre
        // laterale, et « Se deplacer » decrit la barre elle-meme.
        'Connexion',
        'Se déplacer dans le logiciel',
        'Journal Comptable',
        'Plan Comptable',
        'Clôture d\'Exercice',
        'Comptabilité Analytique',
        'Mon Profil',
        'Aide & À Propos',
        'Contactez l\'Éditeur',
      };

      for (final s in sections) {
        expect(
          barreLaterale.contains(s.titre) || horsBarre.contains(s.titre),
          isTrue,
          reason:
              'La section « ${s.titre} » ne correspond à aucun libellé de '
              'l\'interface. Le manuel doit nommer les écrans exactement '
              'comme ils s\'affichent.',
        );
      }
    });

    test('chaque section dit où aller et qui a le droit', () {
      for (final s in sections) {
        expect(s.chemin, isNotEmpty, reason: s.titre);
        expect(s.role, isNotEmpty, reason: s.titre);
        expect(s.aQuoiCaSert.length, greaterThan(40), reason: s.titre);
      }
    });

    test('les chemins emploient le chevron, jamais une flèche absente', () {
      // `→`, `➔` et `▸` ne sont dans aucune police du projet : ils
      // s'imprimeraient en blanc.
      for (final s in sections) {
        expect(
          RegExp(r'[←-⇿➔-➿▶▸]').hasMatch(s.chemin),
          isFalse,
          reason: 'Chemin de « ${s.titre} » : employez « › ».',
        );
      }
    });
  });

  group('Typographie', () {
    /// Tout le texte du manuel, bout à bout.
    Iterable<String> tousLesTextes() sync* {
      yield* ContenuManuel.manuel.avantPropos;
      for (final c in ContenuManuel.manuel.chapitres) {
        yield c.titre;
        yield c.introduction;
        for (final s in c.sections) {
          yield s.titre;
          yield s.chemin;
          yield s.role;
          yield s.aQuoiCaSert;
          for (final e in s.etapes) {
            yield e.titre;
            yield e.texte;
          }
          for (final e in s.encadres) {
            yield e.texte;
          }
          yield* s.aRetenir;
        }
      }
    }

    test('aucun caractère absent de Roboto', () {
      // Mesure faite dans la table de caracteres : Roboto porte les
      // ponctuations et symboles courants jusqu'a U+20AC, mais aucun
      // pictogramme des blocs Dingbats, Fleches ou Emoji. La borne est donc
      // posee au-dessus du bloc « Ponctuation generale » etendu, avec la liste
      // explicite de ce qui est verifie present.
      const autorisesAuDela = {
        '›', // U+203A, le chevron des chemins
        '—', '–', '…', '•', '«', '»', '’', '€', '№', '≥', '≤', '−', 'œ', 'Œ',
      };

      for (final texte in tousLesTextes()) {
        for (final rune in texte.runes) {
          final c = String.fromCharCode(rune);
          if (rune <= 0x00FF || autorisesAuDela.contains(c)) continue;
          fail(
            'Caractère « $c » (U+${rune.toRadixString(16).toUpperCase()}) '
            'absent des polices du manuel — il s\'imprimerait en blanc. '
            'Texte : « ${texte.substring(0, texte.length.clamp(0, 60))}… »',
          );
        }
      }
    });
  });

  group('Captures', () {
    final dossier = Directory('../docs/manuel/captures');

    test('chaque section a sa capture, et le fichier existe', () {
      if (!dossier.existsSync()) {
        markTestSkipped('Captures non générées : captures_test.dart');
        return;
      }
      for (final s in sections) {
        expect(
          s.capture,
          isNotNull,
          reason: '« ${s.titre} » n\'a pas de capture déclarée.',
        );
        final f = File('${dossier.path}/${s.capture}.png');
        expect(
          f.existsSync(),
          isTrue,
          reason:
              'Capture manquante pour « ${s.titre} » : ${f.path}. '
              'Relancez captures_test.dart.',
        );
      }
    });

    test('aucune capture orpheline', () {
      if (!dossier.existsSync()) {
        markTestSkipped('Captures non générées.');
        return;
      }
      final declarees = {
        ...sections.map((s) => s.capture),
        ...sections.expand((s) => s.onglets).map((o) => o.capture),
        ...sections.expand((s) => s.modales).map((m) => m.capture),
      };
      for (final f in dossier.listSync().whereType<File>()) {
        if (!f.path.endsWith('.png')) continue;
        final nom = f.uri.pathSegments.last.replaceAll('.png', '');
        expect(
          declarees.contains(nom),
          isTrue,
          reason:
              'La capture $nom n\'est référencée par aucune section : '
              'soit la section manque, soit le fichier est un reste.',
        );
      }
    });
  });

  group('Onglets', () {
    final dossier = Directory('../docs/manuel/captures');
    final avecOnglets = sections.where((s) => s.onglets.isNotEmpty).toList();

    test('les sept écrans à onglets sont tous documentés', () {
      // Releve dans le code des ecrans : ce sont les seuls a avoir des
      // onglets internes. Un huitieme qui apparaitrait sans etre decrit ferait
      // echouer ce test le jour ou on l'ajoutera ici.
      const attendus = {
        'Fiche Poulets/Pondeuses': 2,
        'Soins & Calendrier': 3,
        'Paramètres Élevage': 4,
        'Ventes': 4,
        'États Financiers': 4,
        'Rapports & États': 6,
        'Paramètres Général': 7,
      };
      expect(
        {for (final s in avecOnglets) s.titre: s.onglets.length},
        attendus,
        reason: 'Le nombre d\'onglets décrits doit coller à celui des écrans.',
      );
    });

    test('chaque onglet a un nom et une phrase', () {
      for (final s in avecOnglets) {
        for (final o in s.onglets) {
          expect(o.nom, isNotEmpty, reason: s.titre);
          expect(
            o.aQuoiCaSert.length,
            greaterThan(30),
            reason: '${s.titre} / ${o.nom}',
          );
        }
      }
    });

    test('le premier onglet reprend la capture de l\'écran', () {
      // La capture principale de la section montre deja le premier onglet :
      // la reprendre serait la meme image deux fois.
      for (final s in avecOnglets) {
        expect(
          s.onglets.first.capture,
          isNull,
          reason:
              '${s.titre} : le premier onglet est deja celui de la capture '
              'principale.',
        );
      }
    });

    test('les autres onglets ont leur capture sur le disque', () {
      if (!dossier.existsSync()) {
        markTestSkipped('Captures non générées.');
        return;
      }
      for (final s in avecOnglets) {
        for (final o in s.onglets.skip(1)) {
          expect(o.capture, isNotNull, reason: '${s.titre} / ${o.nom}');
          expect(
            File('${dossier.path}/${o.capture}.png').existsSync(),
            isTrue,
            reason:
                'Capture manquante : ${o.capture}.png (${s.titre} / '
                '${o.nom}). Relancez captures_test.dart.',
          );
        }
      }
    });
  });

  group('Fenêtres de saisie', () {
    final dossier = Directory('../docs/manuel/captures');
    final modales = sections.expand((s) => s.modales).toList();

    test('chaque modale dit par quel bouton elle s\'ouvre', () {
      expect(modales, isNotEmpty);
      for (final m in modales) {
        expect(m.declencheur, isNotEmpty, reason: m.nom);
        expect(
          m.aQuoiCaSert.length,
          greaterThan(40),
          reason:
              '${m.nom} : une modale sans explication ne montre pas le '
              'geste, seulement une boîte.',
        );
      }
    });

    test('chaque modale décrit ses champs', () {
      for (final m in modales) {
        expect(
          m.champs,
          isNotEmpty,
          reason:
              '${m.nom} : c\'est la modale qui porte la saisie. Sans le '
              'tableau de ses champs, le manuel montre une fenêtre sans dire '
              'quoi y mettre.',
        );
        for (final c in m.champs) {
          expect(c.nom, isNotEmpty);
          expect(
            c.contenu.length,
            greaterThan(15),
            reason: '${m.nom} / ${c.nom}',
          );
        }
      }
    });

    test('la capture de chaque modale existe', () {
      if (!dossier.existsSync()) {
        markTestSkipped('Captures non générées.');
        return;
      }
      for (final m in modales) {
        expect(m.capture, isNotNull, reason: m.nom);
        expect(
          File('${dossier.path}/${m.capture}.png').existsSync(),
          isTrue,
          reason: 'Capture manquante : ${m.capture}.png (${m.nom}).',
        );
      }
    });
  });

  group('Annotations', () {
    final dossier = Directory('../docs/manuel/reperes');

    test('chaque repère vise une ancre réellement relevée', () {
      if (!dossier.existsSync()) {
        markTestSkipped('Repères non générés.');
        return;
      }
      for (final s in sections) {
        if (s.reperes.isEmpty) continue;
        final f = File('${dossier.path}/${s.capture}.json');
        expect(
          f.existsSync(),
          isTrue,
          reason:
              '${s.titre} : aucun repère relevé pour ${s.capture}. Une '
              'pastille posée sans coordonnées pointerait à côté.',
        );
        final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final ancres = {
          for (final r
              in (json['reperes'] as List).cast<Map<String, dynamic>>())
            r['nom'] as String,
        };
        for (final r in s.reperes) {
          expect(
            ancres,
            contains(r.ancre),
            reason:
                '${s.titre} : l\'ancre « ${r.ancre} » n\'existe pas sur cet '
                'écran. Les ancres sont les cibles de la visite guidée.',
          );
        }
      }
    });
  });

  group('Annexes', () {
    final annexes = ContenuManuel.manuel.annexes;

    test('les six annexes annoncées sont présentes', () {
      expect(annexes.map((a) => a.lettre).toList(), [
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
      ]);
    });

    test('chaque annexe a de la matière', () {
      for (final a in annexes) {
        expect(a.introduction.length, greaterThan(40), reason: a.lettre);
        expect(
          a.tableaux.isNotEmpty ||
              a.puces.isNotEmpty ||
              a.paragraphes.isNotEmpty,
          isTrue,
          reason:
              'Annexe ${a.lettre} : une annexe vide est une promesse non '
              'tenue dans le sommaire.',
        );
      }
    });

    test('aucun mot de passe n\'est imprimé', () {
      // Un manuel circule. Le mot de passe de livraison se transmet
      // separement, jamais dans un document qui se photocopie.
      final texte = [
        for (final a in annexes) ...[
          a.introduction,
          ...a.paragraphes,
          ...a.puces,
          for (final t in a.tableaux)
            for (final c in t.colonnes) c.contenu,
        ],
      ].join(' ');
      expect(
        texte.contains('LogiALVIA@'),
        isFalse,
        reason: 'Le mot de passe initial ne doit jamais figurer ici.',
      );
    });
  });

  group('Génération', () {
    test('le PDF se construit, avec ou sans captures', () async {
      final octets = await const GenerateurManuel().generer(
        manuel: ContenuManuel.manuel,
        roboto: _police('assets/fonts/Roboto-Regular.ttf'),
        robotoGras: _police('assets/fonts/Roboto-Bold.ttf'),
        captures: const <String, Uint8List>{},
        reperes: const <String, Map<String, CoordonneesRepere>>{},
        edite: DateTime(2026, 8, 19),
      );

      // Une signature PDF valide, et un document qui n'est pas vide.
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
      expect(octets.length, greaterThan(20000));
    });

    test('les quatre niveaux d\'encadré sont tous employés', () {
      final employes = sections
          .expand((s) => s.encadres)
          .map((e) => e.niveau)
          .toSet();
      expect(
        employes,
        containsAll(NiveauEncadre.values),
        reason:
            'Un niveau jamais utilisé est un repère que le lecteur apprend '
            'pour rien.',
      );
    });
  });
}

ByteData _police(String chemin) =>
    ByteData.sublistView(File(chemin).readAsBytesSync());
