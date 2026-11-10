import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../domain/entities/bande.dart';
import '../../../administration/data/repositories/preferences_poste_repository.dart';
import '../../domain/repositories/bandes_repository.dart';

class BandesRepositoryDrift implements BandesRepository {
  const BandesRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Future<List<Bande>> chargerBandes(String espece) async {
    final lignes =
        await (_db.select(_db.bandes)
              ..where((b) => b.espece.equals(espece))
              ..orderBy([
                (b) => OrderingTerm.desc(b.dateMiseEnBande),
                (b) => OrderingTerm.desc(b.id),
              ]))
            .get();
    return lignes.map(_versDomaine).toList();
  }

  /// Toutes les bandes, toutes especes confondues.
  ///
  /// Le rappel de prophylaxie du tableau de bord ne connait pas d'espece a
  /// l'avance : il doit balayer les filieres actives. Boucler sur
  /// `chargerBandes` espece par espece ferait six requetes la ou une suffit.
  Future<List<Bande>> chargerToutes() async {
    final lignes =
        await (_db.select(_db.bandes)..orderBy([
              (b) => OrderingTerm.desc(b.dateMiseEnBande),
              (b) => OrderingTerm.desc(b.id),
            ]))
            .get();
    return lignes.map(_versDomaine).toList();
  }

  @override
  Future<Bande?> bandeCouvrant({
    required String espece,
    required DateTime date,
  }) async {
    final jour = _minuit(date);

    // La plus recente des bandes ouvertes a cette date. Deux bandes peuvent se
    // chevaucher (un couvoir en rotation en met une en place avant d'avoir
    // vendu la precedente) : on retient celle qui a demarre le plus tard,
    // c'est elle dont le cycle est en cours sur le terrain.
    final ligne =
        await (_db.select(_db.bandes)
              ..where(
                (b) =>
                    b.espece.equals(espece) &
                    b.dateMiseEnBande.isSmallerOrEqualValue(jour) &
                    (b.dateCloture.isNull() |
                        b.dateCloture.isBiggerOrEqualValue(jour)),
              )
              ..orderBy([
                (b) => OrderingTerm.desc(b.dateMiseEnBande),
                (b) => OrderingTerm.desc(b.id),
              ])
              ..limit(1))
            .getSingleOrNull();

    return ligne == null ? null : _versDomaine(ligne);
  }

  @override
  Future<Bande> creerBande({
    required String espece,
    required String code,
    required DateTime dateMiseEnBande,
    int? effectifInitial,
    String? observations,
  }) async {
    final jour = _minuit(dateMiseEnBande);
    // UUID aleatoire (DV-19) : une bande est une saisie de l'utilisatrice. Le code
    // reste unique par filiere (`UNIQUE(espece, code)`) : deux postes qui declarent
    // « B2 » ne se confondent pas, le second recoit un refus visible (`46a_`).
    final id = nouvelUuid();
    await _db
        .into(_db.bandes)
        .insert(
          BandesCompanion.insert(
            id: Value(id),
            espece: espece,
            code: code,
            dateMiseEnBande: jour,
            effectifInitial: Value(effectifInitial),
            observations: Value(observations),
            syncStatus: const Value('pending'),
            updatedAt: Value(instantSaisie()),
          ),
        );

    return Bande(
      id: id,
      espece: espece,
      code: code,
      dateMiseEnBande: jour,
      effectifInitial: effectifInitial,
      observations: observations,
    );
  }

  @override
  Future<void> cloturerBande({
    required String id,
    required DateTime dateCloture,
  }) async {
    await (_db.update(_db.bandes)..where((b) => b.id.equals(id))).write(
      BandesCompanion(
        dateCloture: Value(_minuit(dateCloture)),
        // Toute modification locale remet la bande a envoyer (`46_` §1).
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
    );
  }

  @override
  Future<void> recoderBande({
    required String id,
    required String nouveauCode,
  }) async {
    final code = nouveauCode.trim();
    if (code.isEmpty) {
      throw ArgumentError('Le code de la bande est obligatoire.');
    }
    final ligne = await (_db.select(_db.bandes)..where((b) => b.id.equals(id)))
        .getSingle();
    final pris = await (_db.select(_db.bandes)..where(
          (b) =>
              b.espece.equals(ligne.espece) &
              b.code.equals(code) &
              b.id.equals(id).not(),
        ))
        .getSingleOrNull();
    if (pris != null) {
      throw StateError('Ce code de bande est déjà utilisé pour cette filière.');
    }
    final jour = DateTime.now();
    final trace =
        'Recodée de ${ligne.code} en $code le '
        '${jour.year.toString().padLeft(4, '0')}-'
        '${jour.month.toString().padLeft(2, '0')}-'
        '${jour.day.toString().padLeft(2, '0')} (code déjà utilisé sur un autre poste).';
    await (_db.update(_db.bandes)..where((b) => b.id.equals(id))).write(
      BandesCompanion(
        code: Value(code),
        observations: Value(
          ligne.observations == null || ligne.observations!.isEmpty
              ? trace
              : '${ligne.observations} · $trace',
        ),
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
    );
    // La bande de l'autre poste a ete refusee ici tant que ce code etait pris, et le
    // curseur de tirage est deja passe : un tirage complet la ramene.
    await PreferencesPosteRepository(_db).definirCurseurTirage(null);
  }

  @override
  Future<String?> codePoste() => PreferencesPosteRepository(_db).codeAttribue();

  Bande _versDomaine(BandeRow ligne) => Bande(
    id: ligne.id,
    espece: ligne.espece,
    code: ligne.code,
    dateMiseEnBande: ligne.dateMiseEnBande,
    effectifInitial: ligne.effectifInitial,
    dateCloture: ligne.dateCloture,
    observations: ligne.observations,
    motifConflit: ligne.syncStatus == 'conflict' ? ligne.syncMotif : null,
  );

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);
}
