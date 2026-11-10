import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../administration/data/repositories/preferences_poste_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../domain/entities/devis_emis.dart';
import '../../domain/services/numerotation_pieces.dart';

/// Devis de prestations : création, modification, changement de statut,
/// duplication, suppression (`47a2_`).
///
/// ## Règles
///
/// - Numéro **officiel**, préfixé par le poste (`DV-P2-2026-001`), jamais
///   renuméroté ; la séquence est le **maximum numérique** (suppressions comprises :
///   un numéro supprimé n'est jamais réutilisé).
/// - Seul un devis **émis** se modifie. Un devis **accepté** est figé et ne se
///   supprime pas ; accepté ou refusé, le statut peut encore être corrigé (le client
///   change d'avis, ou l'on s'est trompé de ligne).
/// - Supprimer = pierre tombale (`supprime_le`), pour que les autres postes et le web
///   l'apprennent ; la ligne reste, cachée.
/// - Chaque geste est une **saisie** : `updated_at` = maintenant, `sync_status` =
///   `pending`.
class DevisRepositoryDrift {
  DevisRepositoryDrift(this._db);

  final AppDatabase _db;

  static const String _msgIntrouvable = 'Ce devis n\'existe plus.';

  // ------------------------------------------------------------- lecture

  Future<List<DevisEmis>> tous() async {
    final lignes = await (_db.select(
      _db.devis,
    )..where((d) => d.supprimeLe.isNull())).get();
    lignes.sort((a, b) {
      final c = b.dateEmission.compareTo(a.dateEmission);
      return c != 0 ? c : b.reference.compareTo(a.reference);
    });
    return [for (final d in lignes) _versEntite(d)];
  }

  Future<DevisEmis?> parId(String id) async {
    final d = await (_db.select(
      _db.devis,
    )..where((x) => x.id.equals(id) & x.supprimeLe.isNull())).getSingleOrNull();
    return d == null ? null : _versEntite(d);
  }

  // ------------------------------------------------------------- écriture

  Future<Resultat<DevisEmis>> creer({
    required String client,
    required String objet,
    required double? montant,
    required int? validiteJours,
    DateTime? date,
  }) async {
    final invalide = _controler(client, objet, montant, validiteJours);
    if (invalide != null) return Echec(invalide);
    final validite = validiteJours ?? 15;

    try {
      final emission = date ?? DateTime.now();
      final reference = await _prochaineReference(emission.year);
      final id = nouvelUuid();
      await _db
          .into(_db.devis)
          .insert(
            DevisCompanion.insert(
              id: Value(id),
              reference: reference,
              client: client.trim(),
              objet: objet.trim(),
              montantEstime: montant!,
              validiteJours: Value(validite),
              dateEmission: emission,
              updatedAt: Value(instantSaisie()),
            ),
          );
      return Succes((await parId(id))!);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec generation devis: $e');
      return const Echec('Le devis n\'a pas pu être généré.');
    }
  }

  /// Modifie un devis **émis** : la référence et la date d'émission ne changent pas.
  Future<Resultat<DevisEmis>> modifier({
    required String id,
    required String client,
    required String objet,
    required double? montant,
    required int? validiteJours,
  }) async {
    final actuel = await _brut(id);
    if (actuel == null) return const Echec(_msgIntrouvable);
    if (StatutDevis.depuis(actuel.statut) != StatutDevis.emis) {
      return Echec(
        'Le devis ${actuel.reference} est ${StatutDevis.depuis(actuel.statut).libelle.toLowerCase()} : '
        'il ne se modifie plus. Établissez un nouveau devis.',
      );
    }
    final invalide = _controler(client, objet, montant, validiteJours);
    if (invalide != null) return Echec(invalide);

    await (_db.update(_db.devis)..where((d) => d.id.equals(id))).write(
      DevisCompanion(
        client: Value(client.trim()),
        objet: Value(objet.trim()),
        montantEstime: Value(montant!),
        validiteJours: Value(validiteJours ?? 15),
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
    );
    return Succes((await parId(id))!);
  }

  Future<Resultat<DevisEmis>> changerStatut(
    String id,
    StatutDevis statut,
  ) async {
    final actuel = await _brut(id);
    if (actuel == null) return const Echec(_msgIntrouvable);
    if (StatutDevis.depuis(actuel.statut) == statut) {
      return Succes((await parId(id))!);
    }
    await (_db.update(_db.devis)..where((d) => d.id.equals(id))).write(
      DevisCompanion(
        statut: Value(statut.code),
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
    );
    return Succes((await parId(id))!);
  }

  /// Un NOUVEAU devis (nouveau numéro, émis aujourd'hui) au contenu de celui-ci.
  Future<Resultat<DevisEmis>> dupliquer(String id) async {
    final d = await _brut(id);
    if (d == null) return const Echec(_msgIntrouvable);
    return creer(
      client: d.client,
      objet: d.objet,
      montant: d.montantEstime,
      validiteJours: d.validiteJours,
    );
  }

  /// Pierre tombale. Un devis accepté ne se supprime pas.
  Future<Resultat<void>> supprimer(String id) async {
    final d = await _brut(id);
    if (d == null) return const Echec(_msgIntrouvable);
    if (StatutDevis.depuis(d.statut) == StatutDevis.accepte) {
      return Echec(
        'Le devis ${d.reference} est accepté : il engage l\'entreprise et ne se '
        'supprime pas.',
      );
    }
    final instant = instantSaisie();
    await (_db.update(_db.devis)..where((x) => x.id.equals(id))).write(
      DevisCompanion(
        supprimeLe: Value(instant),
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instant),
      ),
    );
    return const Succes(null);
  }

  // ------------------------------------------------------------- interne

  Future<DevisRow?> _brut(String id) => (_db.select(
    _db.devis,
  )..where((d) => d.id.equals(id) & d.supprimeLe.isNull())).getSingleOrNull();

  static String? _controler(
    String client,
    String objet,
    double? montant,
    int? validiteJours,
  ) {
    if (client.trim().isEmpty) return 'Le client est obligatoire.';
    if (objet.trim().isEmpty) return 'L\'objet est obligatoire.';
    if (montant == null || montant <= 0) {
      return 'Le montant doit être supérieur à 0.';
    }
    if ((validiteJours ?? 15) < 1) {
      return 'La validité doit être d\'au moins 1 jour.';
    }
    return null;
  }

  /// `DV-P2-2026-001` (poste appairé) ou `DV-2026-001` : maximum NUMÉRIQUE des
  /// références du poste pour l'année, **supprimées comprises**.
  Future<String> _prochaineReference(int annee) async {
    final code = await PreferencesPosteRepository(_db).codeAttribue();
    final prefixe = NumerotationPieces.prefixeDevis(annee, code);
    final existants = await (_db.select(
      _db.devis,
    )..where((d) => d.reference.like('$prefixe%'))).get();
    var maximum = 0;
    for (final d in existants) {
      final numero = NumerotationPieces.sequence(d.reference, prefixe);
      if (numero != null && numero > maximum) maximum = numero;
    }
    return NumerotationPieces.composer(prefixe, maximum + 1);
  }

  DevisEmis _versEntite(DevisRow d) => DevisEmis(
    id: d.id,
    reference: d.reference,
    client: d.client,
    objet: d.objet,
    montant: d.montantEstime,
    validiteJours: d.validiteJours,
    dateEmission: d.dateEmission,
    statut: StatutDevis.depuis(d.statut),
  );
}
