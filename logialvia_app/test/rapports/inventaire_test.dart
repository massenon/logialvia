import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/rapports/data/repositories/inventaire_repository_drift.dart';
import 'package:logialvia_app/rapports/domain/entities/inventaire.dart';
import 'package:logialvia_app/rapports/presentation/screens/documents_inventaire.dart';
import 'package:logialvia_app/rapports/presentation/viewmodels/inventaire_view_model.dart';

/// L'inventaire est **daté** — c'est ce qui le distingue du Rapport de Stocks.
///
/// ## Le piège que ces tests ferment
///
/// `INTRANTS.stock` donne l'état **d'aujourd'hui**, pas celui d'une date
/// passée. Prendre cette colonne telle quelle pour un inventaire au 5 août
/// produirait un inventaire d'aujourd'hui portant la date du 5 — une erreur
/// qu'aucun contrôle ne rattrape, parce que le document a l'air juste.
///
/// Le stock à une date se reconstitue donc à rebours, en défalquant les
/// mouvements postérieurs.
void main() {
  late AppDatabase db;
  late InventaireRepositoryDrift depot;

  setUp(() async {
    db = AppDatabase.enMemoire();
    depot = InventaireRepositoryDrift(db);
  });

  tearDown(() => db.close());

  Future<void> creerIntrant({
    String code = 'INT-001',
    String nom = 'Provende Ponte',
    int stock = 100,
    int pmp = 350,
  }) => db
      .into(db.intrants)
      .insert(
        IntrantsCompanion.insert(
          code: code,
          name: nom,
          cat: 'Provende',
          stock: stock,
          unit: 'sac',
          threshold: 10,
          pmp: pmp,
        ),
      );

  Future<void> mouvement({
    String code = 'INT-001',
    required DateTime quand,
    required double quantite,
  }) => db
      .into(db.mouvementsIntrant)
      .insert(
        MouvementsIntrantCompanion.insert(
          horodatage: quand,
          intrantCode: code,
          article: 'Provende Ponte',
          type: quantite > 0 ? 'Entrée' : 'Sortie',
          motif: quantite > 0 ? 'Réception' : 'Distribution',
          quantite: quantite,
        ),
      );

  group('Reconstitution du stock à une date', () {
    test('les mouvements postérieurs sont défalqués', () async {
      await creerIntrant(stock: 100);
      // Apres la cloture : 40 sacs recus le 10.
      await mouvement(quand: DateTime(2026, 8, 10, 9), quantite: 40);

      final inv = await depot.construire(
        debut: DateTime(2026, 8, 5),
        fin: DateTime(2026, 8, 5),
      );

      expect(
        inv.intrants.single.stockFinal,
        60,
        reason:
            'Au 5 août il y avait 60 sacs : les 40 reçus le 10 ne peuvent pas '
            'figurer dans un inventaire arrêté avant.',
      );
    });

    test('la borne haute inclut toute la journée de clôture', () async {
      await creerIntrant(stock: 100);
      await mouvement(quand: DateTime(2026, 8, 5, 16), quantite: 20);

      final inv = await depot.construire(
        debut: DateTime(2026, 8, 5),
        fin: DateTime(2026, 8, 5),
      );

      // La reception de 16 h appartient au 5 : le stock final la comprend.
      expect(inv.intrants.single.stockFinal, 100);
      expect(inv.intrants.single.entrees, 20);
    });

    test('entrées et sorties de la période sont séparées', () async {
      await creerIntrant(stock: 100);
      await mouvement(quand: DateTime(2026, 8, 3), quantite: 50);
      await mouvement(quand: DateTime(2026, 8, 4), quantite: -30);

      final inv = await depot.construire(
        debut: DateTime(2026, 8, 1),
        fin: DateTime(2026, 8, 31),
      );

      final l = inv.intrants.single;
      expect(l.entrees, 50);
      expect(
        l.sorties,
        30,
        reason:
            'Les sorties s\'affichent en positif : le signe est porté par la '
            'colonne, pas par le nombre.',
      );
      expect(l.stockInitial, 80); // 100 - 50 + 30
    });

    test(
      'l\'égalité initial + entrées − sorties = final est vérifiée',
      () async {
        await creerIntrant(stock: 100);
        await mouvement(quand: DateTime(2026, 8, 3), quantite: 50);
        await mouvement(quand: DateTime(2026, 8, 4), quantite: -30);

        final inv = await depot.construire(
          debut: DateTime(2026, 8, 1),
          fin: DateTime(2026, 8, 31),
        );

        expect(inv.intrants.single.equilibre, isTrue);
        expect(inv.intrantsDesequilibres, isEmpty);
      },
    );
  });

  group('Valorisation', () {
    test(
      'les intrants sont valorisés au PMP, pas à un prix de vente',
      () async {
        await creerIntrant(stock: 20, pmp: 350);

        final inv = await depot.construire(
          debut: DateTime(2026, 8, 1),
          fin: DateTime(2026, 8, 31),
        );

        expect(inv.intrants.single.valeur, 7000);
        expect(inv.valeurIntrants, 7000);
      },
    );

    test('un produit sans coût de revient n\'entre dans aucun total', () async {
      await db
          .into(db.produitsVendables)
          .insert(
            ProduitsVendablesCompanion.insert(
              name: 'Goliath mature',
              cat: 'Avicole',
              price: 6000,
              unit: 'tête',
              icon: 'pets',
              stock: 10,
              threshold: 2,
              // Cout de revient absent : c'est le cas par defaut au portage.
            ),
          );

      final inv = await depot.construire(
        debut: DateTime(2026, 8, 1),
        fin: DateTime(2026, 8, 31),
      );

      final l = inv.produits.single;
      expect(l.estValorise, isFalse);
      expect(l.valeur, isNull);
      expect(
        inv.valeurProduits,
        0,
        reason:
            'Le valoriser à son prix de vente gonflerait l\'actif d\'une marge '
            'non réalisée (Doc D1 v18).',
      );
      expect(
        inv.produitsNonValorises,
        1,
        reason: 'Un total qui tait ses exclusions se lit comme complet.',
      );
    });

    test('un produit avec coût de revient est valorisé au coût', () async {
      await db
          .into(db.produitsVendables)
          .insert(
            ProduitsVendablesCompanion.insert(
              name: 'Goliath mature',
              cat: 'Avicole',
              price: 6000,
              unit: 'tête',
              icon: 'pets',
              stock: 10,
              threshold: 2,
              coutRevient: const Value(4200),
            ),
          );

      final inv = await depot.construire(
        debut: DateTime(2026, 8, 1),
        fin: DateTime(2026, 8, 31),
      );

      expect(inv.produits.single.valeur, 42000);
      expect(inv.produitsNonValorises, 0);
    });
  });

  group('Périodes du ViewModel', () {
    test('le jour arrête début et fin sur la même date', () async {
      final vm = InventaireViewModel(
        depot,
        maintenant: DateTime(2026, 8, 12, 15),
      );
      await vm.charger();

      expect(vm.debut, DateTime(2026, 8, 12));
      expect(vm.fin, DateTime(2026, 8, 12));
      expect(vm.libellePeriode, 'Situation au 12/08/2026');
    });

    test('la semaine part du lundi', () async {
      // Le 12 aout 2026 est un mercredi.
      final vm = InventaireViewModel(depot, maintenant: DateTime(2026, 8, 12));
      await vm.changerPeriode(PeriodeInventaire.semaine);

      expect(vm.debut, DateTime(2026, 8, 10));
      expect(vm.fin, DateTime(2026, 8, 12));
    });

    test('le mois part du premier', () async {
      final vm = InventaireViewModel(depot, maintenant: DateTime(2026, 8, 12));
      await vm.changerPeriode(PeriodeInventaire.mois);

      expect(vm.debut, DateTime(2026, 8, 1));
      expect(vm.libellePeriode, 'Du 01/08/2026 au 12/08/2026');
    });

    test("la dernière borne choisie fait foi et entraîne l’autre", () async {
      final vm = InventaireViewModel(depot, maintenant: DateTime(2026, 8, 12));

      // « Du 20 » alors que la fin est au 12 : l'utilisatrice dit qu'elle
      // commence le 20, pas qu'elle finit le 20. La fin suit.
      await vm.definirPlage(debut: DateTime(2026, 8, 20));
      expect(vm.debut, DateTime(2026, 8, 20));
      expect(vm.fin, DateTime(2026, 8, 20));

      // Puis « au 5 » : cette fois c'est le debut qui suit.
      await vm.definirPlage(fin: DateTime(2026, 8, 5));
      expect(vm.debut, DateTime(2026, 8, 5));
      expect(vm.fin, DateTime(2026, 8, 5));

      expect(vm.periode, PeriodeInventaire.plage);
    });

    test('la recherche filtre les deux tableaux', () async {
      await creerIntrant(nom: 'Provende Ponte');
      await creerIntrant(code: 'INT-002', nom: 'Maïs concassé');

      final vm = InventaireViewModel(depot, maintenant: DateTime(2026, 8, 12));
      await vm.charger();
      expect(vm.intrants, hasLength(2));

      vm.definirRecherche('maïs');
      expect(vm.intrants, hasLength(1));
      expect(vm.intrants.single.article, 'Maïs concassé');
    });
  });

  group('Base vierge — aucun chiffre inventé', () {
    test('un inventaire sans stock est un constat, pas une erreur', () async {
      await SeedInitial(db).executer();

      final inv = await depot.construire(
        debut: DateTime(2026, 8, 1),
        fin: DateTime(2026, 8, 31),
      );

      // Le socle peuple le catalogue et les intrants : l'inventaire les voit,
      // et n'invente aucun mouvement pour autant.
      for (final l in inv.intrants) {
        expect(l.entrees, 0);
        expect(l.sorties, 0);
      }
      for (final l in inv.effectifs) {
        expect(l.effectif, 0);
        expect(
          l.dateSaisie,
          isNull,
          reason:
              '« Jamais saisie » et « effectif nul » ne disent pas la même '
              'chose.',
        );
      }
      expect(inv.oeufsEnIncubation, 0);
    });
  });

  group('L\'état imprimé dit la même chose que l\'écran', () {
    /// Le défaut visé : l'écran affiche quatre indicateurs, le PDF en
    /// affichait cinq. Qui compare les deux se demande lequel ment — et
    /// cesse de faire confiance aux deux.
    test('le PDF porte les mêmes quatre indicateurs que l\'écran', () async {
      await SeedInitial(db).executer();
      final vm = InventaireViewModel(depot, maintenant: DateTime(2026, 8, 20));
      await vm.charger();

      final document = DocumentsInventaire.etat(vm);

      expect(
        document.indicateurs.map((i) => i.libelle).toList(),
        [
          'Valeur totale du stock',
          'Dont intrants',
          'Dont produits finis',
          'Animaux sur pied',
        ],
        reason:
            'Les quatre libellés, dans l\'ordre du bandeau de l\'écran. Un '
            'cinquième indicateur ici ferait douter de l\'écran.',
      );
      vm.dispose();
    });

    test('les œufs en incubation restent dits, ailleurs', () async {
      await SeedInitial(db).executer();
      final vm = InventaireViewModel(depot, maintenant: DateTime(2026, 8, 20));
      await vm.charger();

      final document = DocumentsInventaire.etat(vm);
      final texte = document.paragraphes.map((p) => p.texte).join(' ');

      expect(
        texte,
        contains('œufs en incubation'),
        reason:
            'Sortir le chiffre du bandeau ne veut pas dire le perdre : un '
            'œuf en couveuse n\'est ni un intrant ni un produit fini, c\'est '
            'un en-cours, et il appartient au paragraphe de ce qui est compté '
            'sans être valorisé.',
      );
      expect(texte, contains('non valorisés'));
      vm.dispose();
    });
  });
}
