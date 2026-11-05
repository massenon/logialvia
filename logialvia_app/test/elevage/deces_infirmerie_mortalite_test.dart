import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/fiche_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/soins_repository_drift.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/entities/journee_elevage.dart';
import 'package:logialvia_app/elevage/domain/entities/soin.dart';
import 'package:logialvia_app/elevage/domain/services/calcul_fiche_journaliere.dart';
import 'package:logialvia_app/elevage/domain/usecases/enregistrer_journee_usecase.dart';
import 'package:logialvia_app/elevage/domain/usecases/reporter_deces_infirmerie_usecase.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/soins_view_model.dart';

/// Un décès déclaré à l'infirmerie doit compter dans la mortalité de la fiche.
///
/// ## Ce que ces tests protègent
///
/// `soins-calendrier.html` l.326 promet que le décès « sera reflété dans le
/// décompte de mortalité de la fiche d'élevage correspondante ». Rien, dans le
/// prototype, ne le fait. Tant que ce n'était pas implémenté, un animal isolé
/// puis mort disparaissait de l'effectif sans jamais entrer dans le taux de
/// mortalité : le chiffre était **faux**, silencieusement.
///
/// Le report ne se contente pas d'incrémenter `mortCatN` : il repasse par
/// [EnregistrerJourneeUseCase], donc par le recalcul des effectifs et la
/// cascade des jours suivants (Doc 05 §5). Un `UPDATE` direct laisserait
/// `effectif` faux — le bug cardinal du projet.
void main() {
  late AppDatabase db;

  const goliaths = ConfigurationsEspeces.goliaths;
  const pondeuses = ConfigurationsEspeces.pondeuses;

  late ReporterDecesInfirmerieUseCase reporter;

  setUp(() {
    db = AppDatabase.enMemoire();
    reporter = ReporterDecesInfirmerieUseCase(fabriqueFicheElevage(db));
  });
  tearDown(() async => db.close());

  FicheElevageRepositoryDrift depot(ConfigurationEspece config) =>
      FicheElevageRepositoryDrift(db, config);

  Future<JourneeElevage?> lire(ConfigurationEspece config, DateTime date) =>
      depot(config).chargerJour(espece: config.identifiant, date: date);

  /// Saisit une journée réelle, par le chemin normal de l'application.
  Future<void> saisir(
    ConfigurationEspece config,
    DateTime date,
    MouvementsJour mouvements, {
    int? poidsGeneralG,
  }) async {
    final resultat = await EnregistrerJourneeUseCase(depot(config), config)
        .executer(
          date: date,
          mouvements: mouvements,
          poidsGeneralG: poidsGeneralG,
        );
    expect(resultat, isA<Succes<JourneeElevage>>());
  }

  group('Report du décès sur la fiche', () {
    test("incrémente la catégorie choisie, et elle seule", () async {
      await saisir(
        goliaths,
        DateTime(2026, 8, 1),
        const MouvementsJour(achat: 90),
      );
      // Trois catégories peuplées, pour que le cloisonnement soit visible.
      await saisir(
        goliaths,
        DateTime(2026, 8, 2),
        const MouvementsJour(mortsParCategorie: [0, 0, 0]),
      );

      final avant = await lire(goliaths, DateTime(2026, 8, 2));
      expect(avant!.effectif, 90);

      final resultat = await reporter.executer(
        espece: 'goliaths',
        indexCategorie: 0,
        date: DateTime(2026, 8, 2),
      );
      expect(resultat, isA<Succes<void>>());

      final apres = await lire(goliaths, DateTime(2026, 8, 2));
      expect(apres!.mortsParCategorie[0], 1);
      expect(apres.mortsParCategorie[1], 0);
      expect(apres.mortsParCategorie[2], 0);
      // L'effectif suit : c'est ce qu'un UPDATE direct de mortCat1 ne ferait
      // pas, et c'est précisément le bug cardinal du projet.
      expect(apres.effectif, 89);
      expect(apres.effectifsParCategorie[0], 89);
    });

    test("s'ajoute aux mouvements du jour sans les écraser", () async {
      await saisir(
        goliaths,
        DateTime(2026, 8, 1),
        const MouvementsJour(achat: 100),
      );
      await saisir(
        goliaths,
        DateTime(2026, 8, 2),
        const MouvementsJour(
          achat: 5,
          ne: 3,
          mortsParCategorie: [2, 0, 0],
          donsParCategorie: [1, 0, 0],
        ),
        poidsGeneralG: 45000,
      );

      await reporter.executer(
        espece: 'goliaths',
        indexCategorie: 0,
        date: DateTime(2026, 8, 2),
      );

      final apres = await lire(goliaths, DateTime(2026, 8, 2));
      expect(apres!.achat, 5);
      expect(apres.ne, 3);
      expect(apres.donsParCategorie[0], 1);
      expect(apres.poidsGeneralG, 45000);
      // 2 morts saisies + 1 décès d'infirmerie.
      expect(apres.mortsParCategorie[0], 3);
      expect(apres.effectif, 100 + 5 + 3 - 3 - 1);
    });

    test("crée la journée quand elle n'a pas encore été saisie", () async {
      await saisir(
        goliaths,
        DateTime(2026, 8, 1),
        const MouvementsJour(achat: 40),
      );

      expect(await lire(goliaths, DateTime(2026, 8, 3)), isNull);

      await reporter.executer(
        espece: 'goliaths',
        indexCategorie: 0,
        date: DateTime(2026, 8, 3),
      );

      final creee = await lire(goliaths, DateTime(2026, 8, 3));
      expect(creee, isNotNull);
      expect(creee!.mortsParCategorie[0], 1);
      expect(creee.effectif, 39);
      // Marquée saisie : sinon la cascade s'arrêterait sur elle et les jours
      // suivants garderaient un effectif faux.
      expect(creee.isRecorded, isTrue);
    });

    test("reprend la vente du POS sur une journée pas encore saisie", () async {
      await saisir(
        goliaths,
        DateTime(2026, 8, 1),
        const MouvementsJour(achat: 60),
      );

      // Le POS a vendu 4 sujets le 3, sans qu'aucune fiche n'ait été saisie.
      await db
          .into(db.ficheVentesJour)
          .insert(
            FicheVentesJourCompanion.insert(
              espece: 'goliaths',
              date: DateTime(2026, 8, 3),
              qte: const Value(4),
            ),
          );

      await reporter.executer(
        espece: 'goliaths',
        indexCategorie: 2,
        date: DateTime(2026, 8, 3),
      );

      final creee = await lire(goliaths, DateTime(2026, 8, 3));
      // Sans cette relecture, le report remettrait la vente à zéro et
      // regonflerait l'effectif de 4 sujets déjà vendus.
      expect(creee!.vente, 4);
      expect(creee.effectif, 60 - 4 - 1);
    });

    test(
      "recalcule les jours suivants déjà saisis (cascade Doc 05 §5)",
      () async {
        await saisir(
          goliaths,
          DateTime(2026, 8, 1),
          const MouvementsJour(achat: 50),
        );
        await saisir(
          goliaths,
          DateTime(2026, 8, 2),
          const MouvementsJour(achat: 10),
        );
        await saisir(
          goliaths,
          DateTime(2026, 8, 3),
          const MouvementsJour(achat: 5),
        );
        expect((await lire(goliaths, DateTime(2026, 8, 3)))!.effectif, 65);

        await reporter.executer(
          espece: 'goliaths',
          indexCategorie: 0,
          date: DateTime(2026, 8, 1),
        );

        expect((await lire(goliaths, DateTime(2026, 8, 1)))!.effectif, 49);
        expect((await lire(goliaths, DateTime(2026, 8, 2)))!.effectif, 59);
        expect((await lire(goliaths, DateTime(2026, 8, 3)))!.effectif, 64);
      },
    );

    test("accepte la 4e catégorie des Pondeuses", () async {
      await saisir(
        pondeuses,
        DateTime(2026, 8, 1),
        const MouvementsJour(achat: 200),
      );

      final resultat = await reporter.executer(
        espece: 'pondeuses',
        indexCategorie: 3,
        date: DateTime(2026, 8, 2),
      );
      expect(resultat, isA<Succes<void>>());

      final jour = await lire(pondeuses, DateTime(2026, 8, 2));
      expect(jour!.mortsParCategorie[3], 1);
      expect(jour.effectif, 199);
    });

    test("refuse une filière inconnue plutôt que de deviner", () async {
      final resultat = await reporter.executer(
        espece: 'autruches',
        indexCategorie: 0,
        date: DateTime(2026, 8, 2),
      );
      expect(resultat, isA<Echec<void>>());
    });

    test("refuse une catégorie hors bornes", () async {
      // Les Goliaths n'ont que 3 catégories : l'index 3 est celui des
      // Pondeuses. L'accepter écrirait dans `mortCat4`, colonne nullable
      // réservée à une autre filière.
      final resultat = await reporter.executer(
        espece: 'goliaths',
        indexCategorie: 3,
        date: DateTime(2026, 8, 2),
      );
      expect(resultat, isA<Echec<void>>());
      expect(await lire(goliaths, DateTime(2026, 8, 2)), isNull);
    });
  });

  group("Clôture d'une entrée d'infirmerie pour décès", () {
    late SoinsRepositoryDrift depotSoins;
    late SoinsViewModel vm;

    final aujourdHui = DateTime.now();
    final jourJ = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day);
    final veille = jourJ.subtract(const Duration(days: 1));

    setUp(() async {
      depotSoins = SoinsRepositoryDrift(db);
      vm = SoinsViewModel(depotSoins, reporter);
      await vm.charger();
      // Un effectif de départ, sans quoi il n'y a rien à décrémenter.
      await saisir(goliaths, veille, const MouvementsJour(achat: 80));
    });

    tearDown(() => vm.dispose());

    Future<EntreeInfirmerie> isoler({String? espece = 'goliaths'}) =>
        depotSoins.enregistrerEntreeInfirmerie(
          sujet: 'Goliath #G-014',
          motif: 'Suspicion Newcastle',
          niveauIsolement: NiveauIsolement.quarantaineStricte,
          dateEntree: jourJ,
          espece: espece,
        );

    test("porte la perte sur la fiche et le mémorise", () async {
      final entree = await isoler();

      final resultat = await vm.cloturerEntree(
        entree: entree,
        statut: StatutInfirmerie.decede,
        categorieMortalite: 1,
      );
      expect(resultat, isA<Succes<void>>());

      final fiche = await lire(goliaths, jourJ);
      expect(fiche!.mortsParCategorie[1], 1);
      expect(fiche.effectif, 79);

      // Relecture en base : la marque doit être persistée, pas seulement
      // affichée. C'est elle qui empêchera un double comptage.
      final relue = vm.infirmerie.firstWhere((e) => e.id == entree.id);
      expect(relue.statut, StatutInfirmerie.decede);
      expect(relue.categorieMortalite, 1);
      expect(relue.reporteEnFiche, isTrue);
    });

    test("« déjà saisie » ne touche pas la fiche", () async {
      final entree = await isoler();

      final resultat = await vm.cloturerEntree(
        entree: entree,
        statut: StatutInfirmerie.decede,
      );
      expect(resultat, isA<Succes<void>>());

      // Aucune journée créée pour aujourd'hui : l'animalier a déjà compté la
      // perte lui-même, l'ajouter la compterait deux fois.
      expect(await lire(goliaths, jourJ), isNull);

      final relue = vm.infirmerie.firstWhere((e) => e.id == entree.id);
      expect(relue.categorieMortalite, isNull);
      expect(relue.reporteEnFiche, isFalse);
    });

    test(
      "une entrée déjà clôturée ne peut pas l'être une seconde fois",
      () async {
        final entree = await isoler();
        await vm.cloturerEntree(
          entree: entree,
          statut: StatutInfirmerie.decede,
          categorieMortalite: 0,
        );
        final close = vm.infirmerie.firstWhere((e) => e.id == entree.id);

        final rejeu = await vm.cloturerEntree(
          entree: close,
          statut: StatutInfirmerie.decede,
          categorieMortalite: 0,
        );
        expect(rejeu, isA<Echec<void>>());

        // La mortalité reste à 1 : c'est tout l'enjeu.
        final fiche = await lire(goliaths, jourJ);
        expect(fiche!.mortsParCategorie[0], 1);
        expect(fiche.effectif, 79);
      },
    );

    test("refuse une catégorie sans filière rattachée", () async {
      final entree = await isoler(espece: null);

      final resultat = await vm.cloturerEntree(
        entree: entree,
        statut: StatutInfirmerie.decede,
        categorieMortalite: 0,
      );
      expect(resultat, isA<Echec<void>>());

      // Rien n'a été clôturé : l'entrée reste disponible. Le refus intervient
      // AVANT toute écriture, la liste n'a donc pas été rechargée.
      await vm.charger();
      final relue = vm.infirmerie.firstWhere((e) => e.id == entree.id);
      expect(relue.estEnCours, isTrue);
    });

    test("refuse une catégorie sur une réintégration", () async {
      final entree = await isoler();

      final resultat = await vm.cloturerEntree(
        entree: entree,
        statut: StatutInfirmerie.reintegre,
        categorieMortalite: 0,
      );
      expect(resultat, isA<Echec<void>>());
      expect(await lire(goliaths, jourJ), isNull);
    });

    test("une réintégration ne touche jamais la mortalité", () async {
      final entree = await isoler();

      final resultat = await vm.cloturerEntree(
        entree: entree,
        statut: StatutInfirmerie.reintegre,
      );
      expect(resultat, isA<Succes<void>>());
      expect(await lire(goliaths, jourJ), isNull);
    });
  });
}
