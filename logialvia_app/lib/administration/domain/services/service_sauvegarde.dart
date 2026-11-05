import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';

/// Une sauvegarde présente sur le disque.
class FichierSauvegarde {
  const FichierSauvegarde({
    required this.chemin,
    required this.nom,
    required this.date,
    required this.portee,
    required this.tailleOctets,
  });

  final String chemin;
  final String nom;
  final DateTime date;

  /// Colonne « Table » : le nom de la table exportée, ou « Base complète »
  /// pour une copie intégrale.
  final String portee;

  final int tailleOctets;

  bool get estBaseComplete => portee == ServiceSauvegarde.porteeBaseComplete;

  /// « 1,4 Mo », « 812 Ko ». Un poids affiché évite de croire qu'on a récupéré
  /// ses données en ouvrant un fichier vide.
  String get taille {
    if (tailleOctets >= 1024 * 1024) {
      final mo = tailleOctets / (1024 * 1024);
      return '${mo.toStringAsFixed(1).replaceAll('.', ',')} Mo';
    }
    if (tailleOctets >= 1024) return '${(tailleOctets / 1024).round()} Ko';
    return '$tailleOctets octets';
  }
}

/// Sauvegarde et export de la base — onglet « Sauvegardes » des Paramètres
/// Généraux.
///
/// ## Cet écran n'existe pas dans le prototype
///
/// Aucun des 31 fichiers HTML ne propose de sauvegarde. Il y a mieux — ou
/// pire : `parametres-generaux.html` l.75 affiche dans son panneau de
/// notifications « **Sauvegarde quotidienne effectuée — Aujourd'hui à 05:00** »
/// alors qu'aucun mécanisme de sauvegarde n'existe nulle part.
///
/// Sur une application **hors-ligne** dont toute la comptabilité tient dans un
/// seul fichier SQLite posé sur un ordinateur de Natitingou, affirmer qu'on
/// protège les données sans rien protéger est le message le plus dangereux du
/// prototype. Cet onglet le rend vrai.
class ServiceSauvegarde {
  const ServiceSauvegarde(this._db, this._dossierDocuments);

  final AppDatabase _db;

  /// Racine où déposer les sauvegardes — `getApplicationDocumentsDirectory()`
  /// en production, un dossier temporaire en test.
  final Directory _dossierDocuments;

  static const String porteeBaseComplete = 'Base complète';
  static const String sousDossier = 'LogiALVIA/Sauvegardes';

  /// Le dossier est dans **Documents**, pas dans le support applicatif.
  ///
  /// La base vit dans `getApplicationSupportDirectory()`, un chemin technique
  /// que la Gérante ne trouverait pas et que la désinstallation efface. Une
  /// sauvegarde qui disparaît avec l'application ne sauvegarde rien.
  Directory get dossier => dossierDepuis(_dossierDocuments);

  /// Le meme chemin, calculable sans instance : le demarrage a besoin de
  /// deposer la copie de securite d'une restauration avant que le service
  /// n'existe.
  static Directory dossierDepuis(Directory documents) =>
      Directory(p.join(documents.path, sousDossier));

  Future<Directory> _preparerDossier() async {
    final d = dossier;
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Horodatage du nom de fichier : triable, sans caractère interdit sous
  /// Windows, lisible sans outil.
  static String horodatage(DateTime date) =>
      '${date.year}-${_d(date.month)}-${_d(date.day)}'
      '-${_d(date.hour)}${_d(date.minute)}${_d(date.second)}';

  static String _d(int v) => v.toString().padLeft(2, '0');

  /// Copie intégrale de la base, cohérente même si l'application écrit au même
  /// moment.
  ///
  /// `VACUUM INTO` plutôt qu'une copie de fichier : SQLite garantit alors une
  /// image transactionnellement cohérente et compactée. Copier le `.sqlite` à
  /// la main pendant qu'une écriture est en cours produit une sauvegarde
  /// corrompue — **silencieusement**, ce qui est le pire des cas pour une
  /// sauvegarde : on ne s'en aperçoit que le jour où on en a besoin.
  Future<FichierSauvegarde> genererBaseComplete({DateTime? maintenant}) async {
    final d = await _preparerDossier();
    final date = maintenant ?? DateTime.now();
    final chemin = p.join(d.path, 'logialvia-${horodatage(date)}.sqlite');

    // `VACUUM INTO` refuse d'ecrire sur un fichier existant.
    final fichier = File(chemin);
    if (await fichier.exists()) await fichier.delete();

    await _db.customStatement('VACUUM INTO ?', [chemin]);

    return FichierSauvegarde(
      chemin: chemin,
      nom: p.basename(chemin),
      date: date,
      portee: porteeBaseComplete,
      tailleOctets: await fichier.length(),
    );
  }

  /// Tables exportables, par ordre alphabétique.
  List<String> get tablesExportables =>
      _db.allTables.map((t) => t.actualTableName).toList()..sort();

  /// Export CSV d'une table.
  ///
  /// Le CSV est lisible dans un tableur, contrairement au `.sqlite` : c'est ce
  /// qui permet de vérifier ce qu'on a sauvegardé, ou de transmettre un extrait
  /// au comptable sans lui remettre toute la base — y compris les comptes
  /// utilisateurs.
  Future<FichierSauvegarde> exporterTable(
    String table, {
    DateTime? maintenant,
  }) async {
    if (!tablesExportables.contains(table)) {
      // Le nom part dans une requete SQL : il doit venir du schema, jamais
      // d'une saisie.
      throw ArgumentError('Table inconnue : $table');
    }

    final d = await _preparerDossier();
    final date = maintenant ?? DateTime.now();
    final chemin = p.join(d.path, '$table-${horodatage(date)}.csv');

    final lignes = await _db.customSelect('SELECT * FROM $table').get();
    final tampon = StringBuffer();

    if (lignes.isEmpty) {
      // Une table vide produit quand meme son fichier, avec ses en-tetes : un
      // export absent se confondrait avec un export echoue.
      final colonnes = _db.allTables
          .firstWhere((t) => t.actualTableName == table)
          .$columns
          .map((c) => c.name);
      tampon.writeln(colonnes.map(_cellule).join(';'));
    } else {
      final colonnes = lignes.first.data.keys.toList();
      tampon.writeln(colonnes.map(_cellule).join(';'));
      for (final ligne in lignes) {
        tampon.writeln(colonnes.map((c) => _cellule(ligne.data[c])).join(';'));
      }
    }

    final fichier = File(chemin);
    // BOM UTF-8 : sans lui, Excel sous Windows affiche « Mais » au lieu de
    // « Maïs » et « Depenses » au lieu de « Dépenses ».
    await fichier.writeAsString('﻿$tampon');

    return FichierSauvegarde(
      chemin: chemin,
      nom: p.basename(chemin),
      date: date,
      portee: table,
      tailleOctets: await fichier.length(),
    );
  }

  /// Séparateur **point-virgule**, pas virgule : c'est ce qu'attend Excel en
  /// locale française, où la virgule est le séparateur décimal.
  static String _cellule(Object? valeur) {
    if (valeur == null) return '';
    final texte = valeur.toString();
    if (texte.contains(';') ||
        texte.contains('"') ||
        texte.contains('\n') ||
        texte.contains('\r')) {
      return '"${texte.replaceAll('"', '""')}"';
    }
    return texte;
  }

  /// Les sauvegardes présentes, la plus récente d'abord.
  Future<List<FichierSauvegarde>> lister() async {
    final d = dossier;
    if (!await d.exists()) return const [];

    final fichiers = <FichierSauvegarde>[];
    await for (final entree in d.list()) {
      if (entree is! File) continue;
      final nom = p.basename(entree.path);
      final extension = p.extension(nom).toLowerCase();
      if (extension != '.sqlite' && extension != '.csv') continue;

      fichiers.add(
        FichierSauvegarde(
          chemin: entree.path,
          nom: nom,
          // La date de modification du fichier, pas celle devinee depuis son
          // nom : un fichier renomme a la main ne doit pas mentir sur sa date.
          date: await entree.lastModified(),
          portee: _porteeDepuisNom(nom, extension),
          tailleOctets: await entree.length(),
        ),
      );
    }

    fichiers.sort((a, b) => b.date.compareTo(a.date));
    return fichiers;
  }

  static final RegExp _suffixeHorodate = RegExp(r'-\d{4}-\d{2}-\d{2}-\d{6}$');

  String _porteeDepuisNom(String nom, String extension) {
    if (extension == '.sqlite') return porteeBaseComplete;
    // « ventes-2026-08-18-143012.csv » -> « ventes »
    final base = p.basenameWithoutExtension(nom);
    return base.replaceFirst(_suffixeHorodate, '');
  }

  Future<void> supprimer(FichierSauvegarde sauvegarde) async {
    final fichier = File(sauvegarde.chemin);
    if (await fichier.exists()) await fichier.delete();
  }
}

/// Le dossier Documents de l'utilisateur, résolu **une fois** au démarrage.
///
/// `getApplicationDocumentsDirectory()` est asynchrone ; le fournir résolu à
/// l'arbre de widgets évite qu'un écran ait à l'attendre pour se construire.
class DossierDocuments {
  const DossierDocuments(this.dossier);

  final Directory dossier;
}
