import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/pilotage/data/repositories/tableau_bord_repository_drift.dart';
import 'package:logialvia_app/pilotage/presentation/screens/widgets/modale_stock_critique.dart';
import 'package:logialvia_app/pilotage/presentation/viewmodels/alertes_view_model.dart';

/// Popup « Alertes Critiques de Stock ».
///
/// ## Ce que ces tests protègent
///
/// Une rupture de provende ne se rattrape pas : les animaux mangent tous les
/// jours. La cloche et le panneau du tableau de bord affichent déjà l'alerte,
/// mais tous deux attendent qu'on les regarde. La popup, elle, va chercher la
/// Gérante — à condition qu'elle s'ouvre quand il faut, et **seulement** quand
/// il faut : une popup qui surgit sans raison finit par se fermer sans se lire.
void main() {
  late AppDatabase db;
  late AlertesViewModel vm;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    vm = AlertesViewModel(TableauBordRepositoryDrift(db));
    AlertesStockCritique.reinitialiserReport();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  /// Remet tous les intrants au-dessus de leur seuil.
  Future<void> stockConfortable() async {
    await db.customStatement('UPDATE intrants SET stock = threshold + 100');
    await db.customStatement(
      'UPDATE produits_vendables SET stock = threshold + 100',
    );
  }

  /// Fait passer un intrant sous son seuil.
  Future<String> unIntrantEnAlerte() async {
    final intrant = (await db.select(db.intrants).get()).first;
    await (db.update(db.intrants)..where((i) => i.code.equals(intrant.code)))
        .write(IntrantsCompanion(stock: Value(intrant.threshold - 5)));
    return intrant.name;
  }

  group('Détection', () {
    test('sans article sous seuil, la liste est vide', () async {
      await stockConfortable();
      await vm.rafraichir();
      expect(vm.articlesSousSeuil, isEmpty);
    });

    test('un intrant sous son seuil apparaît avec ses quantités', () async {
      await stockConfortable();
      final nom = await unIntrantEnAlerte();
      await vm.rafraichir();

      final article = vm.articlesSousSeuil.firstWhere((a) => a.libelle == nom);
      expect(article.estIntrant, isTrue);
      expect(
        article.stock,
        lessThan(article.seuil),
        reason:
            'Un article listé en alerte doit réellement être sous le seuil.',
      );
      expect(
        article.unite,
        isNotEmpty,
        reason:
            'Sans unité, « manque 5 » ne dit pas si ce sont 5 kg ou 5 sacs.',
      );
    });

    test('la même alerte alimente la cloche et la popup', () async {
      await stockConfortable();
      await unIntrantEnAlerte();
      await vm.rafraichir();

      expect(vm.articlesSousSeuil, isNotEmpty);
      expect(
        vm.alertes.any((a) => a.message.contains('sous le seuil critique')),
        isTrue,
        reason:
            'Deux sources séparées finiraient par diverger — c\'est le défaut '
            'du prototype que ce ViewModel corrige.',
      );
    });
  });

  group('Ouverture', () {
    testWidgets('rien ne s\'ouvre quand aucun stock n\'est critique', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () =>
                  AlertesStockCritique.ouvrirSiNecessaire(ctx, const []),
              child: const Text('déclencher'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('déclencher'));
      await tester.pumpAndSettle();

      expect(find.text('Alertes Critiques de Stock'), findsNothing);
    });

    testWidgets('la popup s\'ouvre et annonce ce qui manque', (tester) async {
      await stockConfortable();
      await unIntrantEnAlerte();
      await vm.rafraichir();
      final articles = vm.articlesSousSeuil;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () =>
                  AlertesStockCritique.ouvrirSiNecessaire(ctx, articles),
              child: const Text('déclencher'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('déclencher'));
      await tester.pumpAndSettle();

      expect(find.text('Alertes Critiques de Stock'), findsOneWidget);
      expect(find.textContaining('sous le seuil'), findsWidgets);
      expect(
        find.textContaining('manque'),
        findsWidgets,
        reason: 'Le manque est la seule information qui dise quoi commander.',
      );
      expect(find.text('Ouvrir la Gestion des Stocks'), findsOneWidget);
    });

    testWidgets('« Plus tard » vaut pour la session, pas au-delà', (
      tester,
    ) async {
      await stockConfortable();
      await unIntrantEnAlerte();
      await vm.rafraichir();
      final articles = vm.articlesSousSeuil;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () =>
                  AlertesStockCritique.ouvrirSiNecessaire(ctx, articles),
              child: const Text('déclencher'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('déclencher'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      expect(find.text('Alertes Critiques de Stock'), findsNothing);

      // Deuxieme passage sur le tableau de bord : elle ne doit pas resurgir.
      await tester.tap(find.text('déclencher'));
      await tester.pumpAndSettle();
      expect(
        find.text('Alertes Critiques de Stock'),
        findsNothing,
        reason:
            'Un rappel qu\'on ne peut pas écarter n\'est plus un rappel, '
            'c\'est un obstacle.',
      );

      // Au redemarrage suivant, en revanche, elle revient.
      AlertesStockCritique.reinitialiserReport();
      await tester.tap(find.text('déclencher'));
      await tester.pumpAndSettle();
      expect(find.text('Alertes Critiques de Stock'), findsOneWidget);
    });
  });
}
