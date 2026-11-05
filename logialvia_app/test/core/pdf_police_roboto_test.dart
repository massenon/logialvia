import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/pdf/generateur_pdf.dart';

/// Les documents officiels ne sont plus troués.
///
/// ## Ce que ces tests protègent
///
/// L'export utilisait Helvetica — police de base PDF, embarquée dans tout
/// lecteur, mais qui ne couvre que Latin-1. Constat obtenu à l'exécution :
/// « — », « œ », « ≥ », « ’ », « € », « № », « … » et « • » laissaient un
/// **blanc** dans le document. Une normalisation les remplaçait donc au rendu :
/// « — » devenait « - », « œ » devenait « oe ». Sur des états signés portés à
/// la banque ou à l'administration, la typographie ne correspondait pas à
/// l'écran.
///
/// Roboto est désormais embarqué dans les assets — jamais téléchargé : une
/// exploitation de Natitingou sans connexion doit pouvoir imprimer. Ces
/// caractères passent maintenant tels quels.
///
/// ⚠️ **Roboto n'a pas tout.** Les flèches, les exposants et l'espace fine
/// insécable en sont absents — vérifié dans sa table de caractères. La
/// substitution subsiste pour eux, et pour eux seuls : elle interroge la police
/// réellement embarquée plutôt qu'une liste écrite à la main.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(GenerateurPdf.oublierPolices);
  tearDownAll(GenerateurPdf.oublierPolices);

  group('Avant chargement de la police — repli prudent', () {
    test('la substitution Latin-1 s\'applique encore', () {
      // Rien ne garantit alors ce que la police contient : on s'en tient au
      // socle commun a toutes les polices PDF.
      expect(
        GenerateurPdf.normaliserPourRoboto('Œufs — 12 €'),
        'OEufs - 12 EUR',
      );
    });
  });

  group('Après chargement — Roboto imprime ce que l\'écran affiche', () {
    setUp(() => GenerateurPdf.chargerPolices());

    test('les huit caractères qui laissaient un blanc passent intacts', () {
      const cas = {
        'Poussins — Éligible à la Vente': 'tiret cadratin',
        'Œufs fertiles, cœur': 'ligature oe',
        '≥ 2,8 kg': 'supérieur ou égal',
        'l’exercice clôturé': 'apostrophe typographique',
        '1 200 €': 'euro',
        '№ 12': 'numéro',
        'et plus…': 'points de suspension',
        '• premier point': 'puce',
      };

      for (final entree in cas.entries) {
        expect(
          GenerateurPdf.normaliserPourRoboto(entree.key),
          entree.key,
          reason:
              'Le ${entree.value} devrait s\'imprimer tel quel : Roboto le '
              'contient.',
        );
      }
    });

    test('les accents et guillemets français passent, comme avant', () {
      const texte = 'Été à Natitingou « Élevage » — çà et là, où ?';
      expect(GenerateurPdf.normaliserPourRoboto(texte), texte);
    });

    test('ce que Roboto n\'a pas est encore remplacé — et pas effacé', () {
      // Verifie dans la table de caracteres de la police, pas suppose.
      expect(
        GenerateurPdf.normaliserPourRoboto('Goliathau (0 → 4 mois)'),
        'Goliathau (0 -> 4 mois)',
      );
      expect(
        GenerateurPdf.normaliserPourRoboto('1ᵉʳ trimestre'),
        '1er trimestre',
      );
      expect(GenerateurPdf.normaliserPourRoboto('✓ fait'), 'v fait');
    });

    test('un caractère inconnu de la police devient « ? », jamais un vide', () {
      // Un ideogramme : absent de Roboto, absent de la table de repli. Le
      // laisser passer produirait un blanc silencieux dans un document signe.
      final rendu = GenerateurPdf.normaliserPourRoboto('lot 中 numéro 4');
      expect(rendu, 'lot ? numéro 4');
    });

    test('la police n\'est lue qu\'une fois', () async {
      final premier = await GenerateurPdf.chargerPolices();
      final second = await GenerateurPdf.chargerPolices();
      expect(identical(premier.$1, second.$1), isTrue);
      expect(identical(premier.$2, second.$2), isTrue);
    });
  });
}
