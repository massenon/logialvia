import '../../../administration/domain/services/service_archivage.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../domain/entities/parametres_elevage.dart';

abstract class ParametresElevageRepository {
  Future<List<BaremeRation>> chargerBaremes();
  Future<List<EcheanceProphylaxie>> chargerProphylaxie();
  Future<List<TauxRationPoids>> chargerTauxPoids();
  Future<FormatsNumerotation> chargerFormatsNumerotation();
  Future<List<TypeProvende>> chargerTypesProvende();

  Future<void> creerBareme({
    required String espece,
    required String stade,
    required int rationGrammesParJour,
  });
  Future<void> modifierRation({
    required int id,
    required int rationGrammesParJour,
    bool? confirme,
  });
  Future<void> supprimerBareme(
    int id, {
    String? utilisateurId,
    String? utilisateurNom,
  });

  Future<void> enregistrerTauxPoids({
    int? id,
    required String espece,
    required int poidsMinG,
    required int? poidsMaxG,
    required double tauxPourcent,
    bool? confirme,
  });
  Future<void> supprimerTauxPoids(
    int id, {
    String? utilisateurId,
    String? utilisateurNom,
  });

  Future<void> enregistrerEcheance({
    int? id,
    required String espece,
    required int jourCycle,
    required String traitement,
    required String produit,
    required int remanenceJours,
    String? dose,
  });
  Future<void> supprimerEcheance(
    int id, {
    String? utilisateurId,
    String? utilisateurNom,
  });

  Future<void> enregistrerFormatsNumerotation(FormatsNumerotation formats);
}

class ParametresElevageRepositoryDrift implements ParametresElevageRepository {
  const ParametresElevageRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Future<List<BaremeRation>> chargerBaremes() async {
    final lignes =
        await (_db.select(_db.baremesRation)..orderBy([
              (b) => OrderingTerm.asc(b.espece),
              (b) => OrderingTerm.asc(b.id),
            ]))
            .get();
    return [
      for (final b in lignes)
        BaremeRation(
          id: b.id,
          espece: b.espece,
          stade: b.stade,
          rationGrammesParJour: b.rationGrammesParJour,
          confirme: b.confirme,
        ),
    ];
  }

  @override
  Future<List<TauxRationPoids>> chargerTauxPoids() async {
    final lignes =
        await (_db.select(_db.tauxRationPoids)..orderBy([
              (t) => OrderingTerm.asc(t.espece),
              (t) => OrderingTerm.asc(t.poidsMinG),
            ]))
            .get();
    return [
      for (final t in lignes)
        TauxRationPoids(
          id: t.id,
          espece: t.espece,
          poidsMinG: t.poidsMinG,
          poidsMaxG: t.poidsMaxG,
          tauxPourcent: t.tauxPourcent,
          confirme: t.confirme,
        ),
    ];
  }

  @override
  Future<void> enregistrerTauxPoids({
    int? id,
    required String espece,
    required int poidsMinG,
    required int? poidsMaxG,
    required double tauxPourcent,
    bool? confirme,
  }) async {
    if (id != null) {
      // [confirme] `null` laisse le statut tel quel ; c'est le ViewModel qui
      // decide s'il tombe (valeur modifiee) ou passe a « valide ».
      await (_db.update(
        _db.tauxRationPoids,
      )..where((t) => t.id.equals(id))).write(
        TauxRationPoidsCompanion(
          poidsMinG: Value(poidsMinG),
          poidsMaxG: Value(poidsMaxG),
          tauxPourcent: Value(tauxPourcent),
          confirme: confirme == null ? const Value.absent() : Value(confirme),
        ),
      );
      return;
    }
    await _db
        .into(_db.tauxRationPoids)
        .insert(
          TauxRationPoidsCompanion.insert(
            espece: espece,
            poidsMinG: poidsMinG,
            poidsMaxG: Value(poidsMaxG),
            tauxPourcent: tauxPourcent,
          ),
        );
  }

  @override
  Future<void> supprimerTauxPoids(
    int id, {
    String? utilisateurId,
    String? utilisateurNom,
  }) async {
    final ligne = await (_db.select(
      _db.tauxRationPoids,
    )..where((t) => t.id.equals(id))).getSingleOrNull();

    await ServiceArchivage(_db).archiver(
      type: TypeArchivable.tauxPoids,
      cle: id,
      designation: ligne == null
          ? 'Taux de ration #$id'
          : '${ligne.espece} — ${TauxRationPoids(id: ligne.id, espece: ligne.espece, poidsMinG: ligne.poidsMinG, poidsMaxG: ligne.poidsMaxG, tauxPourcent: ligne.tauxPourcent, confirme: ligne.confirme).libelleClasse} '
                '(${ligne.tauxPourcent} %)',
      utilisateurId: utilisateurId,
      utilisateurNom: utilisateurNom,
    );
  }

  @override
  Future<List<EcheanceProphylaxie>> chargerProphylaxie() async {
    final lignes =
        await (_db.select(_db.calendrierProphylaxie)..orderBy([
              (c) => OrderingTerm.asc(c.espece),
              (c) => OrderingTerm.asc(c.jourCycle),
            ]))
            .get();
    return [
      for (final c in lignes)
        EcheanceProphylaxie(
          id: c.id,
          espece: c.espece,
          jourCycle: c.jourCycle,
          traitement: c.traitement,
          produit: c.produit,
          remanenceJours: c.remanenceJours,
          dose: c.dose,
        ),
    ];
  }

  @override
  Future<FormatsNumerotation> chargerFormatsNumerotation() async {
    final ligne = await (_db.select(
      _db.parametresEntreprise,
    )..where((p) => p.id.equals(1))).getSingleOrNull();
    if (ligne == null) return const FormatsNumerotation();
    return FormatsNumerotation(
      enclos: ligne.prefixeEnclos,
      cage: ligne.prefixeCage,
      bande: ligne.prefixeBande,
      bassin: ligne.prefixeBassin,
      bac: ligne.prefixeBac,
      parc: ligne.prefixeParc,
    );
  }

  /// Onglet 3 — lecture seule, alimentée par la **vraie** table `INTRANTS`.
  ///
  /// Le prototype code les 5 lignes en dur dans son HTML ; elles sont ici lues
  /// depuis Gestion Stocks, comme la page l'annonce elle-même. Le prix indicatif
  /// est le **PMP** réellement calculé par le module Approvisionnement, pas une
  /// seconde valeur saisie à part.
  @override
  Future<List<TypeProvende>> chargerTypesProvende() async {
    final lignes =
        await (_db.select(_db.intrants)
              ..where((i) => i.cat.equals('Intrants Provende'))
              ..orderBy([(i) => OrderingTerm.asc(i.code)]))
            .get();
    return [
      for (final i in lignes)
        TypeProvende(
          code: i.code,
          nom: i.name,
          stock: i.stock.toDouble(),
          unite: i.unit,
          prixIndicatif: i.pmp.toDouble(),
          seuil: i.threshold.toDouble(),
        ),
    ];
  }

  @override
  Future<void> creerBareme({
    required String espece,
    required String stade,
    required int rationGrammesParJour,
  }) async {
    final companion = BaremesRationCompanion.insert(
      espece: espece,
      stade: stade,
      rationGrammesParJour: rationGrammesParJour,
    );

    // `UNIQUE(espece, stade)` — cible explicite, jamais la cle primaire
    // auto-incrementee (Doc K3 §6-TER). Ajouter deux fois le meme stade met la
    // ration a jour au lieu d'echouer silencieusement.
    await _db
        .into(_db.baremesRation)
        .insert(
          companion,
          onConflict: DoUpdate(
            (_) => BaremesRationCompanion(
              rationGrammesParJour: Value(rationGrammesParJour),
            ),
            target: [_db.baremesRation.espece, _db.baremesRation.stade],
          ),
        );
  }

  @override
  Future<void> modifierRation({
    required int id,
    required int rationGrammesParJour,
    bool? confirme,
  }) async {
    await (_db.update(_db.baremesRation)..where((b) => b.id.equals(id))).write(
      BaremesRationCompanion(
        rationGrammesParJour: Value(rationGrammesParJour),
        confirme: confirme == null ? const Value.absent() : Value(confirme),
      ),
    );
  }

  @override
  Future<void> supprimerBareme(
    int id, {
    String? utilisateurId,
    String? utilisateurNom,
  }) async {
    // Archive au lieu de supprimer : la Gerante peut restaurer le bareme
    // depuis Parametres > Corbeille. Voir `ServiceArchivage`.
    final ligne = await (_db.select(
      _db.baremesRation,
    )..where((b) => b.id.equals(id))).getSingleOrNull();

    await ServiceArchivage(_db).archiver(
      type: TypeArchivable.baremes,
      cle: id,
      designation: ligne == null
          ? 'Barème #$id'
          : '${ligne.espece} — ${ligne.stade}',
      utilisateurId: utilisateurId,
      utilisateurNom: utilisateurNom,
    );
  }

  @override
  Future<void> enregistrerEcheance({
    int? id,
    required String espece,
    required int jourCycle,
    required String traitement,
    required String produit,
    required int remanenceJours,
    String? dose,
  }) async {
    if (id != null) {
      await (_db.update(
        _db.calendrierProphylaxie,
      )..where((c) => c.id.equals(id))).write(
        CalendrierProphylaxieCompanion(
          jourCycle: Value(jourCycle),
          traitement: Value(traitement),
          produit: Value(produit),
          remanenceJours: Value(remanenceJours),
          dose: Value(dose),
        ),
      );
      return;
    }

    await _db
        .into(_db.calendrierProphylaxie)
        .insert(
          CalendrierProphylaxieCompanion.insert(
            espece: espece,
            jourCycle: jourCycle,
            traitement: traitement,
            produit: produit,
            remanenceJours: Value(remanenceJours),
            dose: Value(dose),
          ),
        );
  }

  @override
  Future<void> supprimerEcheance(
    int id, {
    String? utilisateurId,
    String? utilisateurNom,
  }) async {
    final ligne = await (_db.select(
      _db.calendrierProphylaxie,
    )..where((c) => c.id.equals(id))).getSingleOrNull();

    await ServiceArchivage(_db).archiver(
      type: TypeArchivable.prophylaxie,
      cle: id,
      designation: ligne == null
          ? 'Échéance #$id'
          : '${ligne.espece} — J+${ligne.jourCycle} ${ligne.traitement}',
      utilisateurId: utilisateurId,
      utilisateurNom: utilisateurNom,
    );
  }

  @override
  Future<void> enregistrerFormatsNumerotation(
    FormatsNumerotation formats,
  ) async {
    // Table a ligne unique : `id` vaut toujours 1.
    await _db
        .into(_db.parametresEntreprise)
        .insertOnConflictUpdate(
          ParametresEntrepriseCompanion(
            id: const Value(1),
            prefixeEnclos: Value(formats.enclos),
            prefixeCage: Value(formats.cage),
            prefixeBande: Value(formats.bande),
            prefixeBassin: Value(formats.bassin),
            prefixeBac: Value(formats.bac),
            prefixeParc: Value(formats.parc),
          ),
        );
  }
}
