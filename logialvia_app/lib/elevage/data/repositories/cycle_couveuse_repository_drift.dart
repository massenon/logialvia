import '../../../administration/data/repositories/preferences_poste_repository.dart';
import '../../../administration/domain/services/service_archivage.dart';
import 'package:drift/drift.dart';

import '../../../commercial/domain/services/numerotation_pieces.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../domain/entities/cycle_incubation.dart';
import '../../domain/repositories/cycle_couveuse_repository.dart';

class CycleCouveuseRepositoryDrift implements CycleCouveuseRepository {
  const CycleCouveuseRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Future<List<CycleIncubation>> chargerTous() async {
    final lignes =
        await (_db.select(_db.cycleCouveuse)
              ..orderBy([(c) => OrderingTerm.desc(c.dateIncubation)]))
            .get();

    // Machines et codes parents resolus en une passe : une requete par ligne
    // ferait N+1 appels sur un couvoir qui accumule les lots.
    final machines = {
      for (final m in await _db.select(_db.machinesIncubateur).get())
        m.id: m.code,
    };
    final codes = {for (final l in lignes) l.id: l.codeIncubation};

    return [
      for (final ligne in lignes)
        _versDomaine(
          ligne,
          machineCode: ligne.machineId == null
              ? null
              : machines[ligne.machineId],
          lotParentCode: ligne.lotParentId == null
              ? null
              : codes[ligne.lotParentId],
        ),
    ];
  }

  @override
  Future<List<MachineIncubateur>> chargerMachines() async {
    final lignes =
        await (_db.select(_db.machinesIncubateur)
              ..orderBy([(m) => OrderingTerm.asc(m.code)]))
            .get();
    return [
      for (final m in lignes)
        MachineIncubateur(
          id: m.id,
          code: m.code,
          libelle: m.libelle,
          capaciteOeufs: m.capaciteOeufs,
          active: m.active,
        ),
    ];
  }

  @override
  Future<MachineIncubateur> creerMachine({
    required String code,
    required String libelle,
    int? capaciteOeufs,
  }) async {
    // Identite = code : deux postes qui declarent « INC-01 » designent le meme
    // incubateur (`46b_`, decision a valider).
    final id = uuidDeterministe('machine:${code.trim().toLowerCase()}');
    await _db
        .into(_db.machinesIncubateur)
        .insert(
          MachinesIncubateurCompanion.insert(
            id: Value(id),
            code: code,
            libelle: libelle,
            capaciteOeufs: Value(capaciteOeufs),
          ),
        );
    return MachineIncubateur(
      id: id,
      code: code,
      libelle: libelle,
      capaciteOeufs: capaciteOeufs,
    );
  }

  @override
  Future<CycleIncubation> creer({
    required EspeceCouvable espece,
    required DateTime dateChargement,
    required int oeufsCharges,
    String? machineId,
    String? lotParentId,
  }) async {
    final annee = dateChargement.year;
    final numero = await prochainNumero(annee);
    final code = NumerotationPieces.composer(await _prefixe(annee), numero);
    final jour = _minuit(dateChargement);

    final id = nouvelUuid();
    await _db
        .into(_db.cycleCouveuse)
        .insert(
          CycleCouveuseCompanion.insert(
            id: Value(id),
            codeIncubation: code,
            espece: Value(espece.identifiant),
            dateIncubation: jour,
            oeufsCouves: oeufsCharges,
            statut: StatutCycle.enIncubation,
            machineId: Value(machineId),
            lotParentId: Value(lotParentId),
          ),
        );

    return CycleIncubation(
      id: id,
      code: code,
      espece: espece,
      dateChargement: jour,
      oeufsCharges: oeufsCharges,
      statut: StatutCycle.enIncubation,
      machineId: machineId,
      lotParentId: lotParentId,
    );
  }

  @override
  Future<void> enregistrerMirage({
    required String cycleId,
    required int jour,
    required int oeufsRetires,
  }) async {
    final companion = switch (jour) {
      EspeceCouvable.jourMirage1 => CycleCouveuseCompanion(
        oeufsBlancsJ7: Value(oeufsRetires),
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
      EspeceCouvable.jourMirage2 => CycleCouveuseCompanion(
        oeufsGatesJ14: Value(oeufsRetires),
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
      _ => throw ArgumentError('Mirage inconnu au jour $jour.'),
    };

    await (_db.update(
      _db.cycleCouveuse,
    )..where((c) => c.id.equals(cycleId))).write(companion);
  }

  @override
  Future<ResultatEclosion> enregistrerEclosion({
    required String cycleId,
    required int poussinsEclos,
    required int oeufsPerdus,
    int? oeufsRemplacement,
    EspeceCouvable? especeRemplacement,
    DateTime? dateRemplacement,
  }) async {
    // Cloture et remplacement dans UNE transaction : si la creation du
    // sous-lot echoue, le lot d'origine ne doit pas rester marque
    // « Remplacé » alors que sa place est restee vide.
    return _db.transaction(() async {
      final ligne = await (_db.select(
        _db.cycleCouveuse,
      )..where((c) => c.id.equals(cycleId))).getSingle();

      final remplace = oeufsRemplacement != null && oeufsRemplacement > 0;

      await (_db.update(_db.cycleCouveuse)..where((c) => c.id.equals(cycleId)))
          .write(
            CycleCouveuseCompanion(
              poussinsNes: Value(poussinsEclos),
              oeufsPerdus: Value(oeufsPerdus),
              statut: Value(
                remplace
                    ? StatutCycle.remplace
                    : StatutCycle.eclosionEffectuee,
              ),
              syncStatus: const Value('pending'),
              syncMotif: const Value(null),
              updatedAt: Value(instantSaisie()),
            ),
          );

      CycleIncubation? sousLot;
      if (remplace) {
        sousLot = await creer(
          // A defaut de precision, la place reprend la meme espece : c'est le
          // cas courant, et l'ecran permet d'en changer.
          espece:
              especeRemplacement ??
              EspeceCouvable.depuisIdentifiant(ligne.espece) ??
              EspeceCouvable.goliath,
          dateChargement: dateRemplacement ?? DateTime.now(),
          oeufsCharges: oeufsRemplacement,
          machineId: ligne.machineId,
          lotParentId: cycleId,
        );
      }

      final apres = await (_db.select(
        _db.cycleCouveuse,
      )..where((c) => c.id.equals(cycleId))).getSingle();

      return ResultatEclosion(lot: _versDomaine(apres), sousLot: sousLot);
    });
  }

  @override
  Future<void> modifier({
    required String cycleId,
    required EspeceCouvable espece,
    required DateTime dateChargement,
    required int oeufsCharges,
    String? machineId,
  }) async {
    await (_db.update(
      _db.cycleCouveuse,
    )..where((c) => c.id.equals(cycleId))).write(
      CycleCouveuseCompanion(
        espece: Value(espece.identifiant),
        dateIncubation: Value(_minuit(dateChargement)),
        oeufsCouves: Value(oeufsCharges),
        machineId: Value(machineId),
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
    );
  }

  @override
  Future<void> supprimer(
    String cycleId, {
    String? utilisateurId,
    String? utilisateurNom,
  }) async {
    // Les sous-lots deviennent des lots racines plutot que de disparaitre :
    // ils sont physiquement dans la machine, et leur suppression en cascade
    // ferait s'evaporer des oeufs bien reels.
    await _db.transaction(() async {
      // Les sous-lots sont MODIFIES : ils repartent au serveur avec leur nouvel etat.
      await (_db.update(
        _db.cycleCouveuse,
      )..where((c) => c.lotParentId.equals(cycleId))).write(
        CycleCouveuseCompanion(
          lotParentId: const Value(null),
          syncStatus: const Value('pending'),
          syncMotif: const Value(null),
          updatedAt: Value(instantSaisie()),
        ),
      );
      // La suppression est un fait daté : l'instantané de la corbeille porte l'instant
      // de saisie de la suppression (pierre tombale envoyée au serveur, `46b_`).
      await (_db.update(
        _db.cycleCouveuse,
      )..where((c) => c.id.equals(cycleId))).write(
        CycleCouveuseCompanion(
          syncStatus: const Value('pending'),
          syncMotif: const Value(null),
          updatedAt: Value(instantSaisie()),
        ),
      );
      final ligne = await (_db.select(
        _db.cycleCouveuse,
      )..where((c) => c.id.equals(cycleId))).getSingleOrNull();

      await ServiceArchivage(_db).archiver(
        type: TypeArchivable.lots,
        cle: cycleId,
        designation: ligne == null
            ? 'Lot $cycleId'
            : '${ligne.codeIncubation} — ${ligne.oeufsCouves} œufs',
        utilisateurId: utilisateurId,
        utilisateurNom: utilisateurNom,
      );
    });
  }

  @override
  Future<int> prochainNumero(int annee) async {
    final prefixe = await _prefixe(annee);
    final lignes = await _db.select(_db.cycleCouveuse).get();
    var maximum = 0;
    for (final ligne in lignes) {
      final numero = NumerotationPieces.sequence(ligne.codeIncubation, prefixe);
      if (numero != null && numero > maximum) maximum = numero;
    }
    return maximum + 1;
  }

  /// `C-P2-2026-` pour un poste appairé (DV-21 étendu aux lots, `46b_`), `C-2026-`
  /// sinon. Le code de poste fait l'unicité entre postes sans passer par le serveur.
  Future<String> _prefixe(int annee) async {
    final code = await PreferencesPosteRepository(_db).codeAttribue();
    return NumerotationPieces.prefixeLot(annee, code);
  }

  CycleIncubation _versDomaine(
    CycleCouveuseRow ligne, {
    String? machineCode,
    String? lotParentCode,
  }) {
    return CycleIncubation(
      id: ligne.id,
      code: ligne.codeIncubation,
      espece:
          EspeceCouvable.depuisIdentifiant(ligne.espece) ??
          EspeceCouvable.goliath,
      dateChargement: ligne.dateIncubation,
      oeufsCharges: ligne.oeufsCouves,
      statut: ligne.statut,
      poussinsEclos: ligne.poussinsNes,
      oeufsPerdus: ligne.oeufsPerdus,
      machineId: ligne.machineId,
      machineCode: machineCode,
      oeufsBlancsJ7: ligne.oeufsBlancsJ7,
      oeufsGatesJ14: ligne.oeufsGatesJ14,
      lotParentId: ligne.lotParentId,
      lotParentCode: lotParentCode,
    );
  }

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);
}
