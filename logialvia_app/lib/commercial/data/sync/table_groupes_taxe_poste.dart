import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../../core/sync/table_poste.dart';

/// `groupes_taxe` — **référentiel** : le serveur gagne (`46_` §2.2, `46e_` §1).
///
/// ## Clé déterministe
///
/// La clé d'un groupe est sa **lettre** (`A`, `B`…), la même sur tous les postes
/// et au serveur ; son UUID sur le fil est déterministe
/// (`uuidDeterministe('groupe_taxe:A')`), pour que deux installations du même
/// programme donnent la même ligne et non un doublon. Le poste ne le stocke pas :
/// il le **recalcule** pour vérifier la ligne reçue.
///
/// ## Ce que cette table ne fait PAS
///
/// - **Pas d'envoi.** Le poste n'a aucun écran pour modifier la grille ; la
///   seule voie est la base elle-même. Aucune demande n'existe pour ce
///   référentiel (limite déclarée, `46e_` §6).
/// - **Valeur de semis ≠ décision** (même règle que `parametres_entreprise`,
///   `45_` §6e) : une ligne que le serveur n'a jamais modifiée
///   (`updated_at == created_at`) n'écrase JAMAIS une valeur locale, car la
///   grille du poste a pu être corrigée à la main à partir de la documentation de
///   la DGI. Une ligne absente du poste est toujours créée.
/// - **Aucune suppression** : un groupe absent du serveur reste ici (des lignes de
///   facture le citent).
/// - Les lignes de facture sont **figées** (lettre et taux copiés à l'émission) :
///   changer un taux ne réécrit jamais une facture déjà émise.
class TableGroupesTaxePoste implements TablePoste {
  const TableGroupesTaxePoste(this._db);

  final AppDatabase _db;

  static final RegExp _lettre = RegExp(r'^[A-Z]$');

  @override
  String get nom => 'groupes_taxe';

  @override
  bool get referentiel => true;

  @override
  Stream<void> get modifications => const Stream<void>.empty();

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;

      for (final l in lignes) {
        final code = l['code'];
        final libelle = l['libelle'];
        final taux = l['taux'];
        final ordre = l['ordre'];
        final id = l['id'];
        final cree = l['created_at'] is String
            ? DateTime.tryParse(l['created_at'] as String)
            : null;
        final modifie = l['updated_at'] is String
            ? DateTime.tryParse(l['updated_at'] as String)
            : null;
        // Strict : une ligne incohérente est refusée, jamais lissée.
        if (code is! String ||
            !_lettre.hasMatch(code) ||
            libelle is! String ||
            libelle.trim().isEmpty ||
            taux is! num ||
            taux < 0 ||
            taux > 100 ||
            (ordre != null && (ordre is! num || ordre < 0)) ||
            (id != null && id != uuidDeterministe('groupe_taxe:$code')) ||
            cree == null ||
            modifie == null) {
          refusees++;
          continue;
        }

        final locale = await (_db.select(
          _db.groupesTaxe,
        )..where((g) => g.code.equals(code))).getSingleOrNull();

        if (locale == null) {
          await _db
              .into(_db.groupesTaxe)
              .insert(
                GroupesTaxeCompanion.insert(
                  code: code,
                  libelle: libelle.trim(),
                  taux: taux.toDouble(),
                  ordre: Value((ordre as num?)?.toInt() ?? 0),
                ),
              );
          absorbees++;
          continue;
        }

        // Valeur de semis : le serveur n'a jamais décidé, il n'écrase rien.
        if (modifie.toUtc() == cree.toUtc()) continue;

        final nouveau = locale.copyWith(
          libelle: libelle.trim(),
          taux: taux.toDouble(),
          ordre: (ordre as num?)?.toInt() ?? locale.ordre,
        );
        if (nouveau != locale) {
          await _db.update(_db.groupesTaxe).replace(nouveau);
          absorbees++;
        }
      }
      return ResultatAbsorption(absorbees: absorbees, refusees: refusees);
    });
  }

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async => const [];

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {}

  @override
  Future<void> marquerConflit(String id, String motif) async {}

  /// Une remise à zéro préserve les référentiels (blueprint §6).
  @override
  Future<int> purger() async => 0;
}
