import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:logialvia_app/core/widgets/barre_titre_fenetre.dart';

Widget _habiller({
  bool maximisee = true,
  VoidCallback? onReduire,
  VoidCallback? onBasculer,
  VoidCallback? onFermer,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          BarreTitreVue(
            maximisee: maximisee,
            onReduire: onReduire ?? () {},
            onBasculer: onBasculer ?? () {},
            onFermer: onFermer ?? () {},
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('affiche le titre et les trois boutons', (tester) async {
    await tester.pumpWidget(_habiller());
    expect(find.text('LogiALVIA — ALLMANY ET COMPAGNIE'), findsOneWidget);
    expect(find.byKey(const Key('fenetre-reduire')), findsOneWidget);
    expect(find.byKey(const Key('fenetre-agrandir')), findsOneWidget);
    expect(find.byKey(const Key('fenetre-fermer')), findsOneWidget);
  });

  testWidgets('chaque bouton appelle son action', (tester) async {
    final appels = <String>[];
    await tester.pumpWidget(
      _habiller(
        onReduire: () => appels.add('reduire'),
        onBasculer: () => appels.add('basculer'),
        onFermer: () => appels.add('fermer'),
      ),
    );
    await tester.tap(find.byKey(const Key('fenetre-reduire')));
    await tester.tap(find.byKey(const Key('fenetre-agrandir')));
    await tester.tap(find.byKey(const Key('fenetre-fermer')));
    expect(appels, ['reduire', 'basculer', 'fermer']);
  });

  testWidgets('double clic sur la barre : agrandir/restaurer', (tester) async {
    var bascules = 0;
    await tester.pumpWidget(_habiller(onBasculer: () => bascules++));
    final titre = find.byKey(const Key('titre-fenetre'));
    await tester.tap(titre);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(titre);
    await tester.pump(const Duration(milliseconds: 400));
    expect(bascules, 1);
  });

  testWidgets('l icone d agrandissement change selon l etat', (tester) async {
    await tester.pumpWidget(_habiller(maximisee: true));
    expect(find.byIcon(Icons.filter_none), findsOneWidget);
    await tester.pumpWidget(_habiller(maximisee: false));
    expect(find.byIcon(Icons.crop_square), findsOneWidget);
  });
}
