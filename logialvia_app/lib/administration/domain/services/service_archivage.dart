import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../data/sync/depot_demandes_referentiel.dart';

/// Un élément archivé, tel que l'onglet Corbeille l'affiche.
class ElementArchive {
  const ElementArchive({
    required this.id,
    required this.nomTable,
    required this.module,
    required this.typeElement,
    required this.designation,
    required this.archiveLe,
    this.archiveParNom,
  });

  final int id;
  final String nomTable;
  final String module;
  final String typeElement;
  final String designation;
  final DateTime archiveLe;
  final String? archiveParNom;
}

/// Ce qu'on peut archiver, et sous quel nom l'afficher.
///
/// **Liste blanche stricte.** Le nom de table part dans une requête SQL à la
/// restauration : il ne doit jamais venir d'ailleurs que d'ici.
class TypeArchivable {
  const TypeArchivable({
    required this.nomTable,
    required this.clePrimaire,
    required this.module,
    required this.libelle,
    required this.reserveALAdmin,
  });

  final String nomTable;
  final String clePrimaire;
  final String module;
  final String libelle;

  /// Vrai quand seul un administrateur peut **restaurer** cet élément.
  ///
  /// L'archivage, lui, reste ouvert à qui a le droit de gérer l'écran — un
  /// Agent de Vente retire un produit du catalogue, c'est son métier. Mais le
  /// **remettre** est une décision d'administration : ressusciter un compte
  /// utilisateur ou une écriture comptable ne se fait pas depuis un poste de
  /// caisse.
  final bool reserveALAdmin;

  static const utilisateurs = TypeArchivable(
    nomTable: 'utilisateurs',
    clePrimaire: 'id',
    module: 'Administration',
    libelle: 'Utilisateur',
    reserveALAdmin: true,
  );
  static const ecritures = TypeArchivable(
    nomTable: 'ecriture_comptable',
    clePrimaire: 'id',
    module: 'Comptabilité',
    libelle: 'Écriture comptable',
    reserveALAdmin: true,
  );
  static const produits = TypeArchivable(
    nomTable: 'produits_vendables',
    clePrimaire: 'id',
    module: 'Commercial',
    libelle: 'Produit du catalogue',
    reserveALAdmin: false,
  );
  static const intrants = TypeArchivable(
    nomTable: 'intrants',
    clePrimaire: 'code',
    module: 'Approvisionnement',
    libelle: 'Intrant',
    reserveALAdmin: false,
  );
  static const baremes = TypeArchivable(
    nomTable: 'baremes_ration',
    clePrimaire: 'id',
    module: 'Élevage',
    libelle: 'Barème de rationnement',
    reserveALAdmin: false,
  );
  static const tauxPoids = TypeArchivable(
    nomTable: 'taux_ration_poids',
    clePrimaire: 'id',
    module: 'Élevage',
    libelle: 'Taux de ration par classe de poids',
    reserveALAdmin: false,
  );
  static const prophylaxie = TypeArchivable(
    nomTable: 'calendrier_prophylaxie',
    clePrimaire: 'id',
    module: 'Élevage',
    libelle: 'Échéance de prophylaxie',
    reserveALAdmin: false,
  );
  static const lots = TypeArchivable(
    nomTable: 'cycle_couveuse',
    clePrimaire: 'id',
    module: 'Élevage',
    libelle: 'Lot d\'incubation',
    reserveALAdmin: false,
  );
  static const messages = TypeArchivable(
    nomTable: 'messages_editeur',
    clePrimaire: 'id',
    module: 'Compte',
    libelle: 'Message à l\'éditeur',
    reserveALAdmin: false,
  );

  static const List<TypeArchivable> tous = [
    utilisateurs,
    ecritures,
    produits,
    intrants,
    baremes,
    tauxPoids,
    prophylaxie,
    lots,
    messages,
  ];

  static TypeArchivable? parTable(String nomTable) {
    for (final t in tous) {
      if (t.nomTable == nomTable) return t;
    }
    return null;
  }
}

/// Levée quand une restauration ne peut pas aboutir.
class EchecRestauration implements Exception {
  const EchecRestauration(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Archivage et restauration — « supprimer » ne détruit plus rien.
///
/// ## Pourquoi une corbeille plutôt qu'un drapeau `archive` par table
///
/// Marquer chaque table d'un booléen aurait imposé de filtrer **toutes** les
/// requêtes de l'application : une seule oubliée, et un intrant supprimé
/// réapparaît dans une fabrication de provende. La corbeille sort la ligne de
/// sa table et en garde une copie JSON complète — aucune requête existante ne
/// change, et la restauration réécrit la ligne à l'identique, y compris les
/// colonnes ajoutées par une migration ultérieure.
///
/// Ce que ça ne fait pas : ressusciter les enfants d'une ligne supprimée en
/// cascade. C'est sans effet ici, parce que les seules suppressions ouvertes à
/// l'utilisateur portent sur des lignes sans enfants, ou protégées par une clé
/// étrangère qui refuse la suppression tant qu'elles en ont.
class ServiceArchivage {
  const ServiceArchivage(this._db);

  final AppDatabase _db;

  /// Archive une ligne : copie JSON en corbeille, puis retrait de sa table.
  ///
  /// Les deux dans **une transaction** : une copie sans retrait laisserait un
  /// doublon, un retrait sans copie serait la suppression définitive qu'on
  /// cherche justement à éviter.
  Future<void> archiver({
    required TypeArchivable type,
    required Object cle,
    required String designation,
    String? utilisateurId,
    String? utilisateurNom,
    DateTime? maintenant,
  }) async {
    await _db.transaction(() async {
      final ligne = await _db
          .customSelect(
            'SELECT * FROM ${type.nomTable} WHERE ${type.clePrimaire} = ?',
            variables: [_variable(cle)],
          )
          .getSingleOrNull();

      if (ligne == null) return;

      await _db
          .into(_db.corbeille)
          .insert(
            CorbeilleCompanion.insert(
              nomTable: type.nomTable,
              module: type.module,
              typeElement: type.libelle,
              designation: designation,
              donneesJson: jsonEncode(_encoder(ligne.data)),
              archiveLe: maintenant ?? DateTime.now(),
              archiveParId: Value(utilisateurId),
              archiveParNom: Value(utilisateurNom),
            ),
          );

      await _db.customStatement(
        'DELETE FROM ${type.nomTable} WHERE ${type.clePrimaire} = ?',
        [cle],
      );
    });
  }

  /// Les éléments archivés, le plus récent d'abord.
  Future<List<ElementArchive>> lister() async {
    final lignes = await (_db.select(
      _db.corbeille,
    )..orderBy([(c) => OrderingTerm.desc(c.archiveLe)])).get();
    return [
      for (final l in lignes)
        ElementArchive(
          id: l.id,
          nomTable: l.nomTable,
          module: l.module,
          typeElement: l.typeElement,
          designation: l.designation,
          archiveLe: l.archiveLe,
          archiveParNom: l.archiveParNom,
        ),
    ];
  }

  /// Remet une ligne dans sa table et la retire de la corbeille.
  ///
  /// [estAdmin] conditionne les types réservés — voir
  /// [TypeArchivable.reserveALAdmin].
  Future<void> restaurer(int idArchive, {required bool estAdmin}) async {
    await _db.transaction(() async {
      final archive = await (_db.select(
        _db.corbeille,
      )..where((c) => c.id.equals(idArchive))).getSingleOrNull();

      if (archive == null) {
        throw const EchecRestauration('Cet élément n\'est plus en corbeille.');
      }

      final type = TypeArchivable.parTable(archive.nomTable);
      if (type == null) {
        // Impossible en pratique : l'archivage passe par la liste blanche.
        // Le refus est explicite plutot que d'executer un nom de table
        // arbitraire venu de la base.
        throw EchecRestauration(
          'Type d\'élément inconnu : ${archive.nomTable}.',
        );
      }

      if (type.reserveALAdmin && !estAdmin) {
        throw EchecRestauration(
          'Seule une administratrice peut restaurer un élément de type '
          '« ${type.libelle} ».',
        );
      }

      final donnees = (jsonDecode(archive.donneesJson) as Map<String, Object?>);
      if (type.nomTable == TypeArchivable.lots.nomTable) {
        // Un lot restauré lève la pierre tombale envoyée au serveur : il repart,
        // daté de maintenant (`46b_`). Un instantané ancien n'a pas ces colonnes.
        donnees['sync_status'] = 'pending';
        donnees['sync_motif'] = null;
        donnees['updated_at'] = instantSaisie();
      }
      final colonnes = donnees.keys.toList();

      final existe = await _db
          .customSelect(
            'SELECT 1 FROM ${type.nomTable} WHERE ${type.clePrimaire} = ?',
            variables: [_variable(donnees[type.clePrimaire])],
          )
          .getSingleOrNull();
      if (existe != null) {
        // Un element recree entre-temps sous la meme cle : ecraser
        // remplacerait des donnees a jour par des donnees perimees.
        throw const EchecRestauration(
          'Un élément portant la même référence existe déjà. Renommez-le ou '
          'supprimez-le avant de restaurer celui-ci.',
        );
      }

      await _db.customStatement(
        'INSERT INTO ${type.nomTable} '
        '(${colonnes.join(', ')}) '
        'VALUES (${List.filled(colonnes.length, '?').join(', ')})',
        [for (final c in colonnes) _decoder(donnees[c])],
      );

      await (_db.delete(
        _db.corbeille,
      )..where((c) => c.id.equals(idArchive))).go();

      // Un produit restauré lève la pierre tombale posée au serveur à sa suppression.
      if (type.nomTable == TypeArchivable.produits.nomTable) {
        await DepotDemandesReferentiel(
          _db,
        ).proposerProduit('${donnees[type.clePrimaire]}');
      }

      // Barème, taux ou échéance restaurés : la demande lève la pierre tombale posée
      // au serveur à leur suppression (P7c).
      final idRestaure = '${donnees[type.clePrimaire]}';
      if (type.nomTable == TypeArchivable.baremes.nomTable) {
        await DepotDemandesReferentiel(_db).proposerBareme(idRestaure);
      } else if (type.nomTable == TypeArchivable.tauxPoids.nomTable) {
        await DepotDemandesReferentiel(_db).proposerTauxPoids(idRestaure);
      } else if (type.nomTable == TypeArchivable.prophylaxie.nomTable) {
        await DepotDemandesReferentiel(_db).proposerEcheance(idRestaure);
      }
    });
  }

  /// Supprime **définitivement** un élément archivé.
  ///
  /// Réservé à l'administratrice, sans exception : c'est la seule opération de
  /// toute l'application qui détruit vraiment quelque chose.
  Future<void> purger(int idArchive, {required bool estAdmin}) async {
    if (!estAdmin) {
      throw const EchecRestauration(
        'Seule une administratrice peut vider la corbeille.',
      );
    }
    await (_db.delete(
      _db.corbeille,
    )..where((c) => c.id.equals(idArchive))).go();
  }

  Future<void> purgerTout({required bool estAdmin}) async {
    if (!estAdmin) {
      throw const EchecRestauration(
        'Seule une administratrice peut vider la corbeille.',
      );
    }
    await _db.delete(_db.corbeille).go();
  }

  static Variable<Object> _variable(Object? valeur) => switch (valeur) {
    final int v => Variable.withInt(v),
    final String v => Variable.withString(v),
    _ => Variable.withString('${valeur ?? ''}'),
  };

  /// Les `DateTime` et les `bool` de Drift transitent en entiers : JSON les
  /// rendrait tels quels, mais on les repasse à SQLite sans conversion.
  static Map<String, Object?> _encoder(Map<String, Object?> data) => {
    for (final entree in data.entries)
      entree.key: switch (entree.value) {
        final DateTime v => v.millisecondsSinceEpoch ~/ 1000,
        final Uint8List v => base64Encode(v),
        final value => value,
      },
  };

  static Object? _decoder(Object? valeur) => valeur;
}

/// Qui a archivé — porté du bouton « Supprimer » jusqu'à la corbeille.
///
/// Un objet plutôt que deux `String?` traversant six couches : deux paramètres
/// nullables côte à côte finissent toujours par être inversés quelque part, et
/// la corbeille attribuerait alors la suppression à la mauvaise personne.
///
/// `null` reste légitime — un archivage déclenché hors session (test,
/// migration) n'a pas d'auteur, et inventer « admin » serait faux.
class AuteurArchivage {
  const AuteurArchivage({required this.id, required this.nom});

  final String id;
  final String nom;
}
