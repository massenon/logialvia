import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/domain/services/service_images_entreprise.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';

/// Logo et favicon de l'entreprise : validation et copie (Doc I3 §2).
void main() {
  late Directory racine;
  late Directory destination;
  late ServiceImagesEntreprise service;

  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4];

  File ecrire(String nom, List<int> octets) =>
      File('${racine.path}${Platform.pathSeparator}$nom')
        ..writeAsBytesSync(octets);

  setUp(() {
    racine = Directory.systemTemp.createTempSync('logialvia-images-');
    destination = Directory('${racine.path}${Platform.pathSeparator}poste');
    service = ServiceImagesEntreprise(() async => destination);
  });

  tearDown(() => racine.deleteSync(recursive: true));

  test(
    'un PNG valide est copie sous un nom regenere dans le dossier du poste',
    () async {
      final source = ecrire('Mon Logo.png', png);

      final r = await service.importer(TypeImageEntreprise.logo, source.path);

      expect(r, isA<Succes<String>>());
      final chemin = (r as Succes<String>).valeur;
      expect(chemin, startsWith(destination.path));
      expect(
        chemin.split(Platform.pathSeparator).last,
        matches(r'^logo-\d+\.png$'),
      );
      expect(File(chemin).readAsBytesSync(), png);
      expect(
        source.existsSync(),
        isTrue,
        reason: 'l\'original n\'est pas touche',
      );
    },
  );

  test(
    'les guillemets de « Copier en tant que chemin d\'acces » sont retires',
    () async {
      final source = ecrire('a.png', png);

      final r = await service.importer(
        TypeImageEntreprise.logo,
        '  "${source.path}"  ',
      );

      expect(r, isA<Succes<String>>());
    },
  );

  test('chemin vide, fichier introuvable, fichier vide', () async {
    expect(
      (await service.importer(TypeImageEntreprise.logo, '  ')),
      isA<Echec<String>>(),
    );
    final introuvable = await service.importer(
      TypeImageEntreprise.logo,
      '${racine.path}/nulle-part.png',
    );
    expect((introuvable as Echec<String>).message, contains('introuvable'));
    final vide = ecrire('vide.png', const []);
    expect(
      (await service.importer(TypeImageEntreprise.logo, vide.path))
          as Echec<String>,
      isA<Echec<String>>(),
    );
  });

  test(
    'une extension non permise est refusee ; .ico seulement pour le favicon',
    () async {
      final ico = ecrire('i.ico', const [0, 0, 1, 0, 1, 0, 16, 16]);
      final texte = ecrire('note.txt', const [65, 66, 67]);

      expect(
        await service.importer(TypeImageEntreprise.logo, texte.path),
        isA<Echec<String>>(),
      );
      expect(
        await service.importer(TypeImageEntreprise.logo, ico.path),
        isA<Echec<String>>(),
      );
      expect(
        await service.importer(TypeImageEntreprise.favicon, ico.path),
        isA<Succes<String>>(),
      );
    },
  );

  test(
    'un fichier renomme en .png dont le contenu n\'est pas un PNG est refuse',
    () async {
      final faux = ecrire('virus.png', const [
        0x4D,
        0x5A,
        0x90,
        0x00,
        1,
        2,
        3,
        4,
      ]);

      final r = await service.importer(TypeImageEntreprise.logo, faux.path);

      expect((r as Echec<String>).message, contains('ne correspond pas'));
      expect(
        destination.existsSync() ? destination.listSync() : const [],
        isEmpty,
      );
    },
  );

  test('un JPEG et un WebP valides sont acceptes', () async {
    final jpg = ecrire('p.jpg', const [0xFF, 0xD8, 0xFF, 0xE0, 0, 16]);
    final webp = ecrire('p.webp', const [
      0x52,
      0x49,
      0x46,
      0x46,
      0,
      0,
      0,
      0,
      0x57,
      0x45,
      0x42,
      0x50,
    ]);

    expect(
      await service.importer(TypeImageEntreprise.logo, jpg.path),
      isA<Succes<String>>(),
    );
    expect(
      await service.importer(TypeImageEntreprise.logo, webp.path),
      isA<Succes<String>>(),
    );
  });

  test('un fichier trop lourd est refuse (favicon : 512 Ko)', () async {
    final gros = ecrire('gros.png', [...png, ...List.filled(512 * 1024, 0)]);

    final r = await service.importer(TypeImageEntreprise.favicon, gros.path);

    expect((r as Echec<String>).message, contains('trop lourd'));
    expect(
      await service.importer(TypeImageEntreprise.logo, gros.path),
      isA<Succes<String>>(),
    );
  });

  test('supprimer ne retire qu\'un fichier du dossier du poste', () async {
    final source = ecrire('a.png', png);
    final copie =
        (await service.importer(TypeImageEntreprise.logo, source.path)
                as Succes<String>)
            .valeur;

    await service.supprimer(source.path);
    expect(
      source.existsSync(),
      isTrue,
      reason: 'jamais un fichier de l\'utilisateur',
    );
    await service.supprimer(copie);
    expect(File(copie).existsSync(), isFalse);
    await service.supprimer(null);
  });
}
