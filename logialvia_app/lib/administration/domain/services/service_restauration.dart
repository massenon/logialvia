import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../../core/resultat/resultat.dart';

/// Ce qu'une restauration a réellement fait, une fois appliquée.
class RapportRestauration {
  const RapportRestauration({
    required this.fichierRestaure,
    required this.copieDeSecurite,
    required this.versionRestauree,
  });

  /// Nom du fichier de sauvegarde qui a été remis en place.
  final String fichierRestaure;

  /// Chemin de la base **précédente**, mise de côté avant remplacement.
  ///
  /// Une restauration est irréversible pour l'utilisateur si l'ancienne base
  /// disparaît. Elle ne disparaît pas.
  final String copieDeSecurite;

  final int versionRestauree;
}

/// Restauration d'une sauvegarde — la contrepartie qui manquait.
///
/// ## Le défaut que ce service comble
///
/// L'onglet Sauvegardes savait **générer**, **exporter**, **lister** et
/// **supprimer**. Il ne savait pas **restaurer**. L'application invitait donc
/// la Gérante à faire des sauvegardes et ne lui permettait jamais de s'en
/// servir — un bouton qui promet une sécurité qu'il ne donne pas, au seul
/// endroit où la promesse compte vraiment.
///
/// ## Pourquoi la restauration est différée au redémarrage
///
/// La base est ouverte en permanence par l'application : remplacer le fichier
/// sous une connexion vivante produit au mieux une erreur, au pire une base
/// à moitié écrite. Le fichier choisi est donc **mis en attente**, et c'est le
/// démarrage suivant qui l'applique, **avant** la première ouverture.
///
/// ## Les quatre contrôles, dans cet ordre
///
/// Ils s'exécutent **avant** que quoi que ce soit ne soit touché. Une
/// restauration qui échoue en cours de route est pire que pas de restauration :
/// elle laisse une exploitation sans base du tout.
///
/// 1. **Signature SQLite** — les 16 premiers octets. Un fichier renommé en
///    `.sqlite` n'est pas une base.
/// 2. **Intégrité** — `PRAGMA integrity_check`. Une sauvegarde corrompue se
///    découvre habituellement le jour où on en a besoin ; ici elle se découvre
///    avant de remplacer quoi que ce soit.
/// 3. **Signature LogiALVIA** — la base d'un autre logiciel s'ouvrirait très
///    bien et ne contiendrait rien d'utile.
/// 4. **Version** — une base produite par une version **plus récente** du
///    logiciel est refusée : on sait migrer en avant, jamais en arrière.
///
/// Le fichier est ouvert en **lecture seule** pour ces contrôles :
/// `AppDatabase.pourFichier` appliquerait ses migrations et modifierait donc la
/// sauvegarde qu'on est en train de vérifier.
class ServiceRestauration {
  const ServiceRestauration({
    required this.dossierBase,
    required this.dossierSauvegardes,
    required this.versionLogiciel,
  });

  /// Dossier de la base en service (`getApplicationSupportDirectory()`).
  final Directory dossierBase;

  /// Où déposer la copie de sécurité de la base remplacée.
  final Directory dossierSauvegardes;

  /// `AppDatabase.schemaVersion` — la version que ce logiciel sait lire.
  final int versionLogiciel;

  /// Nom du fichier de base, tel que `_ouvrirConnexion()` le crée.
  static const String nomBase = 'logialvia.db';

  /// Fichier mis en attente entre le choix et le redémarrage.
  static const String nomEnAttente = 'restauration-en-attente.sqlite';

  /// Tables qui signent une base LogiALVIA.
  static const List<String> tablesSignature = [
    'utilisateurs',
    'roles',
    'parametres_entreprise',
  ];

  File get _base => File(p.join(dossierBase.path, nomBase));
  File get _enAttente => File(p.join(dossierBase.path, nomEnAttente));

  bool get restaurationEnAttente => _enAttente.existsSync();

  // ------------------------------------------------------------- contrôles

  /// Contrôle un fichier **sans rien modifier**, ni lui ni la base en service.
  Resultat<int> verifier(File sauvegarde) {
    if (!sauvegarde.existsSync()) {
      return const Echec('Ce fichier de sauvegarde est introuvable.');
    }
    final octets = sauvegarde.lengthSync();
    if (octets == 0) {
      return const Echec('Ce fichier est vide : il ne contient aucune donnée.');
    }

    // 1. Signature SQLite — 'SQLite format 3' suivi d'un octet nul.
    //
    // Le descripteur est referme explicitement : sous Windows, un handle
    // laisse ouvert verrouille le fichier, et la sauvegarde deviendrait
    // impossible a supprimer ou a remplacer apres un simple controle.
    final lecteur = sauvegarde.openSync();
    final List<int> entete;
    try {
      entete = lecteur.readSync(16);
    } finally {
      lecteur.closeSync();
    }
    const attendue = 'SQLite format 3';
    final lue = String.fromCharCodes(entete.take(15));
    if (lue != attendue) {
      return const Echec(
        'Ce fichier n\'est pas une base de données SQLite. Vérifiez que vous '
        'avez bien choisi une sauvegarde LogiALVIA.',
      );
    }

    Database? base;
    try {
      // Lecture seule : on ne veut surtout pas migrer la sauvegarde controlee.
      base = sqlite3.open(sauvegarde.path, mode: OpenMode.readOnly);

      // 2. Integrite.
      final integrite = base.select('PRAGMA integrity_check');
      final verdict = integrite.isEmpty
          ? 'inconnu'
          : '${integrite.first.values.first}';
      if (verdict != 'ok') {
        return Echec(
          'Cette sauvegarde est endommagée et ne peut pas être restaurée '
          '(contrôle d\'intégrité : $verdict).',
        );
      }

      // 3. Signature LogiALVIA.
      final tables = base
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((l) => '${l['name']}')
          .toSet();
      final manquantes = tablesSignature
          .where((t) => !tables.contains(t))
          .toList();
      if (manquantes.isNotEmpty) {
        return Echec(
          'Ce fichier est une base SQLite, mais pas une base LogiALVIA : '
          'les tables ${manquantes.join(', ')} en sont absentes.',
        );
      }

      // 4. Version.
      final version = base.select('PRAGMA user_version').first.values.first;
      final numero = version is int ? version : int.tryParse('$version') ?? 0;
      if (numero > versionLogiciel) {
        return Echec(
          'Cette sauvegarde vient d\'une version plus récente du logiciel '
          '(schéma $numero, ce logiciel lit jusqu\'au $versionLogiciel). '
          'Mettez LogiALVIA à jour avant de la restaurer : une base ne se '
          'migre jamais en arrière.',
        );
      }

      return Succes(numero);
    } on SqliteException catch (e) {
      return Echec('Cette sauvegarde est illisible : ${e.message}');
    } finally {
      base?.close();
    }
  }

  // ------------------------------------------------------------ préparation

  /// Contrôle la sauvegarde puis la met en attente pour le prochain démarrage.
  Future<Resultat<void>> preparer(File sauvegarde) async {
    final controle = verifier(sauvegarde);
    if (controle case Echec<int>(:final message)) return Echec(message);

    try {
      if (await _enAttente.exists()) await _enAttente.delete();
      await sauvegarde.copy(_enAttente.path);
      return const Succes(null);
    } catch (e) {
      return Echec('Impossible de préparer la restauration : $e');
    }
  }

  /// Annule une restauration mise en attente et pas encore appliquée.
  Future<void> annuler() async {
    if (await _enAttente.exists()) await _enAttente.delete();
  }

  // ------------------------------------------------------------ application

  /// Applique la restauration en attente. **À appeler au démarrage, avant
  /// toute ouverture de la base.**
  ///
  /// Rend `null` s'il n'y a rien à restaurer — le cas de tous les démarrages
  /// ordinaires.
  Future<RapportRestauration?> appliquerSiDemandee({
    DateTime? maintenant,
  }) async {
    if (!await _enAttente.exists()) return null;

    // Re-controle avant d'agir : le fichier a pu etre remplace ou tronque
    // entre le choix et le redemarrage.
    final controle = verifier(_enAttente);
    if (controle case Echec<int>()) {
      await annuler();
      return null;
    }
    final version = (controle as Succes<int>).valeur;

    if (!await dossierSauvegardes.exists()) {
      await dossierSauvegardes.create(recursive: true);
    }

    final date = maintenant ?? DateTime.now();
    final copie = p.join(
      dossierSauvegardes.path,
      'logialvia-avant-restauration-${_horodatage(date)}.sqlite',
    );

    // La base precedente est mise de cote AVANT tout remplacement : une
    // restauration ne doit jamais etre un aller sans retour.
    if (await _base.exists()) {
      await _base.copy(copie);
    }

    await _enAttente.copy(_base.path);
    await _enAttente.delete();

    // Les journaux `-wal` et `-shm` decrivent l'ANCIENNE base : les laisser
    // ferait relire des pages qui n'ont plus rien a voir avec le fichier
    // restaure.
    for (final suffixe in const ['-wal', '-shm']) {
      final annexe = File('${_base.path}$suffixe');
      if (await annexe.exists()) await annexe.delete();
    }

    return RapportRestauration(
      fichierRestaure: p.basename(_enAttente.path),
      copieDeSecurite: copie,
      versionRestauree: version,
    );
  }

  static String _horodatage(DateTime d) =>
      '${d.year}-${_dd(d.month)}-${_dd(d.day)}'
      '-${_dd(d.hour)}${_dd(d.minute)}${_dd(d.second)}';

  static String _dd(int v) => v.toString().padLeft(2, '0');
}
