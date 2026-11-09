import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../domain/entities/soin.dart';
import '../../domain/repositories/soins_repository.dart';

class SoinsRepositoryDrift implements SoinsRepository {
  const SoinsRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Future<List<Soin>> chargerSoins() async {
    final lignes =
        await (_db.select(_db.soinsCalendrier)
              ..orderBy([(s) => OrderingTerm.desc(s.datePrevue)]))
            .get();
    return lignes.map(_soinVersDomaine).toList();
  }

  @override
  Future<Soin> enregistrerSoin({
    required String espece,
    required DateTime date,
    required String typeSoin,
    required String statut,
    String? produit,
    String? dose,
    int remanenceJours = 0,
    String? veterinaire,
    String? symptomes,
    int coutFcfa = 0,
    String? bandeId,
    int? echeanceProphylaxieId,
  }) async {
    final jour = DateTime(date.year, date.month, date.day);
    final id = await _db
        .into(_db.soinsCalendrier)
        .insert(
          SoinsCalendrierCompanion.insert(
            espece: espece,
            datePrevue: jour,
            typeSoin: typeSoin,
            statut: statut,
            produit: Value(produit),
            dose: Value(dose),
            remanenceJours: Value(remanenceJours),
            veterinaire: Value(veterinaire),
            symptomes: Value(symptomes),
            coutFcfa: Value(coutFcfa),
            bandeId: Value(bandeId),
            echeanceProphylaxieId: Value(echeanceProphylaxieId),
          ),
        );

    return Soin(
      id: id,
      espece: espece,
      datePrevue: jour,
      typeSoin: typeSoin,
      statut: statut,
      produit: produit,
      dose: dose,
      remanenceJours: remanenceJours,
      veterinaire: veterinaire,
      symptomes: symptomes,
      coutFcfa: coutFcfa,
      bandeId: bandeId,
      echeanceProphylaxieId: echeanceProphylaxieId,
    );
  }

  @override
  Future<void> confirmerAdministration(int soinId) async {
    await (_db.update(_db.soinsCalendrier)..where((s) => s.id.equals(soinId)))
        .write(const SoinsCalendrierCompanion(statut: Value(StatutSoin.effectue)));
  }

  @override
  Future<List<EntreeInfirmerie>> chargerInfirmerie() async {
    final lignes =
        await (_db.select(_db.infirmerie)
              ..orderBy([(i) => OrderingTerm.desc(i.dateEntree)]))
            .get();
    return lignes.map(_entreeVersDomaine).toList();
  }

  @override
  Future<EntreeInfirmerie> enregistrerEntreeInfirmerie({
    required String sujet,
    required String motif,
    required String niveauIsolement,
    required DateTime dateEntree,
    String? espece,
  }) async {
    final jour = DateTime(dateEntree.year, dateEntree.month, dateEntree.day);
    final id = await _db
        .into(_db.infirmerie)
        .insert(
          InfirmerieCompanion.insert(
            dateEntree: jour,
            sujet: sujet,
            motif: motif,
            niveauIsolement: niveauIsolement,
            statut: StatutInfirmerie.enCours,
            espece: Value(espece),
          ),
        );

    return EntreeInfirmerie(
      id: id,
      dateEntree: jour,
      sujet: sujet,
      motif: motif,
      niveauIsolement: niveauIsolement,
      statut: StatutInfirmerie.enCours,
      espece: espece,
    );
  }

  @override
  Future<void> cloturerEntree({
    required int entreeId,
    required String statut,
    required DateTime dateSortie,
  }) async {
    await (_db.update(_db.infirmerie)..where((i) => i.id.equals(entreeId)))
        .write(
          InfirmerieCompanion(
            statut: Value(statut),
            dateSortie: Value(
              DateTime(dateSortie.year, dateSortie.month, dateSortie.day),
            ),
          ),
        );
  }

  Soin _soinVersDomaine(SoinCalendrierRow ligne) => Soin(
    id: ligne.id,
    espece: ligne.espece,
    datePrevue: ligne.datePrevue,
    typeSoin: ligne.typeSoin,
    statut: ligne.statut,
    produit: ligne.produit,
    dose: ligne.dose,
    remanenceJours: ligne.remanenceJours,
    veterinaire: ligne.veterinaire,
    symptomes: ligne.symptomes,
    coutFcfa: ligne.coutFcfa,
    observations: ligne.observations,
    bandeId: ligne.bandeId,
    echeanceProphylaxieId: ligne.echeanceProphylaxieId,
  );

  @override
  Future<void> marquerDecesReporte({
    required int entreeId,
    required int categorieMortalite,
  }) async {
    await (_db.update(_db.infirmerie)..where((i) => i.id.equals(entreeId)))
        .write(
          InfirmerieCompanion(categorieMortalite: Value(categorieMortalite)),
        );
  }

  EntreeInfirmerie _entreeVersDomaine(InfirmerieRow ligne) => EntreeInfirmerie(
    id: ligne.id,
    dateEntree: ligne.dateEntree,
    sujet: ligne.sujet,
    motif: ligne.motif,
    niveauIsolement: ligne.niveauIsolement,
    statut: ligne.statut,
    dateSortie: ligne.dateSortie,
    espece: ligne.espece,
    categorieMortalite: ligne.categorieMortalite,
  );
}
