import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logialvia_app/core/pdf/manuel/contenu_manuel.dart';
import 'package:logialvia_app/core/pdf/manuel/generateur_manuel.dart';

/// Produit le manuel d'utilisation en PDF.
///
///     dart run outils/generer_manuel.dart
///
/// Le programme est **pur Dart** : `package:pdf` ne dépend pas de Flutter, et
/// ni le contenu ni le modèle du manuel n'importent le framework. Il tourne
/// donc en quelques secondes, sans démarrer d'appareil.
///
/// Les captures viennent de `test/manuel/captures_test.dart`, qui les régénère
/// à partir d'un mois de données de démonstration. Le manuel se refait donc
/// entièrement à la commande, et ses copies d'écran ne peuvent pas dater.
Future<void> main(List<String> arguments) async {
  final racine = Directory.current.path;
  final dossierCaptures = Directory('$racine/../docs/manuel/captures');
  final sortie = arguments.isNotEmpty
      ? arguments.first
      : '$racine/../docs/manuel/LogiALVIA-Manuel-Utilisation.pdf';

  final captures = <String, Uint8List>{};
  if (dossierCaptures.existsSync()) {
    for (final f in dossierCaptures.listSync().whereType<File>()) {
      if (!f.path.endsWith('.png')) continue;
      final nom = f.uri.pathSegments.last.replaceAll('.png', '');
      captures[nom] = f.readAsBytesSync();
    }
  }

  // Une capture manquante ne doit pas passer inapercue : le manuel se
  // genererait sans elle, et personne ne s'en apercevrait avant l'impression.
  final attendues = ContenuManuel.manuel.chapitres
      .expand((c) => c.sections)
      .map((s) => s.capture)
      .whereType<String>()
      .toList();
  final manquantes = attendues.where((n) => !captures.containsKey(n)).toList();
  if (manquantes.isNotEmpty) {
    stderr.writeln(
      'ATTENTION — ${manquantes.length} capture(s) absente(s) sur '
      '${attendues.length} : ${manquantes.join(', ')}',
    );
    stderr.writeln('Relancez : flutter test test/manuel/captures_test.dart');
  }

  // Les rectangles des elements a annoter, releves pendant la capture.
  final reperes = <String, Map<String, CoordonneesRepere>>{};
  final dossierReperes = Directory('$racine/../docs/manuel/reperes');
  if (dossierReperes.existsSync()) {
    for (final f in dossierReperes.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final ecran = json['ecran'] as String;
      reperes[ecran] = {
        for (final r in (json['reperes'] as List).cast<Map<String, dynamic>>())
          r['nom'] as String: CoordonneesRepere(
            x: (r['x'] as num).toDouble(),
            y: (r['y'] as num).toDouble(),
            largeur: (r['largeur'] as num).toDouble(),
            hauteur: (r['hauteur'] as num).toDouble(),
          ),
      };
    }
  }

  final octets = await const GenerateurManuel().generer(
    manuel: ContenuManuel.manuel,
    roboto: _police('$racine/assets/fonts/Roboto-Regular.ttf'),
    robotoGras: _police('$racine/assets/fonts/Roboto-Bold.ttf'),
    captures: captures,
    reperes: reperes,
    edite: DateTime.now(),
  );

  final fichier = File(sortie);
  fichier.parent.createSync(recursive: true);
  fichier.writeAsBytesSync(octets);

  final ko = (octets.length / 1024).round();
  stdout.writeln('Manuel genere : ${fichier.absolute.path} ($ko Ko)');
  stdout.writeln(
    '${ContenuManuel.manuel.nombreEcrans} ecrans, '
    '${captures.length} captures integrees.',
  );
}

ByteData _police(String chemin) {
  final f = File(chemin);
  if (!f.existsSync()) {
    throw StateError('Police introuvable : $chemin');
  }
  return ByteData.sublistView(f.readAsBytesSync());
}
