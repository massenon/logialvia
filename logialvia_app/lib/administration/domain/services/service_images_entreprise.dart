import 'dart:io';

import '../../../core/resultat/resultat.dart';

/// Les deux images de l'entreprise que le poste sait recevoir.
enum TypeImageEntreprise {
  /// Logo : sert aux documents imprimés (Doc E9).
  logo(
    prefixe: 'logo',
    libelle: 'logo',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
    tailleMax: 2 * 1024 * 1024,
  ),

  /// Favicon : l'icône de l'entreprise (carrée, petite).
  favicon(
    prefixe: 'favicon',
    libelle: 'favicon',
    extensions: ['png', 'ico', 'jpg', 'jpeg', 'webp'],
    tailleMax: 512 * 1024,
  );

  const TypeImageEntreprise({
    required this.prefixe,
    required this.libelle,
    required this.extensions,
    required this.tailleMax,
  });

  final String prefixe;
  final String libelle;
  final List<String> extensions;
  final int tailleMax;
}

/// Reçoit le logo ou le favicon choisi par l'utilisateur — Doc I3 §2.
///
/// Le chemin saisi n'est **jamais** conservé tel quel : un fichier pointé sur
/// une clé USB ou un dossier réseau disparaîtrait avec lui, et un chemin n'a
/// de sens que sur cette machine (`TableParametresEntreprisePoste`). Après
/// validation, le fichier est **copié** dans le dossier de données du poste
/// sous un **nom régénéré** ; c'est ce nouveau chemin qui est enregistré.
///
/// Validation, dans l'ordre : le fichier existe, son extension est permise,
/// sa taille est sous la limite, et son **contenu** (signature des premiers
/// octets) est bien celui de l'extension annoncée — renommer un exécutable en
/// `.png` ne passe pas.
class ServiceImagesEntreprise {
  ServiceImagesEntreprise(this._dossier);

  final Future<Directory> Function() _dossier;

  Future<Resultat<String>> importer(
    TypeImageEntreprise type,
    String cheminSaisi,
  ) async {
    final chemin = _nettoyer(cheminSaisi);
    if (chemin.isEmpty) {
      return Echec('Indiquez le chemin du fichier ${type.libelle}.');
    }
    final source = File(chemin);
    if (!source.existsSync()) {
      return Echec('Fichier introuvable : $chemin');
    }
    final extension = _extension(chemin);
    if (!type.extensions.contains(extension)) {
      return Echec(
        'Format non accepté pour le ${type.libelle} : choisissez un fichier '
        '${type.extensions.map((e) => e.toUpperCase()).join(', ')}.',
      );
    }
    final taille = source.lengthSync();
    if (taille == 0) return const Echec('Le fichier est vide.');
    if (taille > type.tailleMax) {
      return Echec(
        'Le fichier est trop lourd (${_ko(taille)}) : '
        '${_ko(type.tailleMax)} au maximum pour le ${type.libelle}.',
      );
    }
    final octets = await source.openRead(0, 16).expand((b) => b).toList();
    if (!_signatureCorrespond(extension, octets)) {
      return Echec(
        'Le contenu du fichier ne correspond pas à une image '
        '${extension.toUpperCase()}.',
      );
    }

    final destination = await _dossier();
    await destination.create(recursive: true);
    final horodatage = DateTime.now().millisecondsSinceEpoch;
    final copie = File(
      '${destination.path}${Platform.pathSeparator}'
      '${type.prefixe}-$horodatage.$extension',
    );
    await source.copy(copie.path);

    return Succes(copie.path);
  }

  /// Retire une image reçue, si elle est bien dans le dossier du poste (jamais
  /// un fichier de l'utilisateur).
  Future<void> supprimer(String? chemin) async {
    if (chemin == null || chemin.isEmpty) return;
    final dossier = (await _dossier()).absolute.path;
    final fichier = File(chemin);
    if (fichier.absolute.path.startsWith(dossier) && fichier.existsSync()) {
      await fichier.delete();
    }
  }

  /// Retire les guillemets que l'Explorateur Windows ajoute à « Copier en tant
  /// que chemin d'accès ».
  static String _nettoyer(String saisie) {
    var s = saisie.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1).trim();
    }
    return s;
  }

  static String _extension(String chemin) {
    final point = chemin.lastIndexOf('.');
    return point < 0 ? '' : chemin.substring(point + 1).toLowerCase();
  }

  static String _ko(int octets) => '${(octets / 1024).ceil()} Ko';

  static bool _signatureCorrespond(String extension, List<int> o) {
    bool commence(List<int> motif) =>
        o.length >= motif.length &&
        [
          for (var i = 0; i < motif.length; i++) o[i] == motif[i],
        ].every((b) => b);

    switch (extension) {
      case 'png':
        return commence([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      case 'jpg':
      case 'jpeg':
        return commence([0xFF, 0xD8, 0xFF]);
      case 'ico':
        return commence([0x00, 0x00, 0x01, 0x00]);
      case 'webp':
        // « RIFF » .... « WEBP »
        return commence([0x52, 0x49, 0x46, 0x46]) &&
            o.length >= 12 &&
            o[8] == 0x57 &&
            o[9] == 0x45 &&
            o[10] == 0x42 &&
            o[11] == 0x50;
    }
    return false;
  }
}
