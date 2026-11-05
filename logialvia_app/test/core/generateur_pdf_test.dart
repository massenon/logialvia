import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/core/pdf/document_pdf.dart';
import 'package:logialvia_app/core/pdf/generateur_pdf.dart';

/// Le générateur est pur : il rend des octets. C'est ce qui le rend testable —
/// l'envoi à l'imprimante, lui, touche la plateforme et vit dans
/// `ServiceImpression`.
void main() {
  // La police est desormais lue dans les assets : le binding doit exister.
  TestWidgetsFlutterBinding.ensureInitialized();

  // `Formats` s'appuie sur la locale `fr_FR`, initialisee au demarrage de
  // l'application (`main.dart`) mais pas dans un test isole.
  setUpAll(() => initializeDateFormatting('fr_FR'));

  const generateur = GenerateurPdf();
  final edition = DateTime(2026, 8, 20);

  const entete = EnteteOfficielle(
    raisonSociale: 'ALLMANY ET COMPAGNIE',
    promoteur: 'SIDI ALI Raïmatou',
    adresse: 'Natitingou, Atakora, Bénin',
    generePar: 'SIDI ALI Raïmatou (admin) — Administratrice',
    ifu: '0123456789',
  );

  DocumentPdf documentSimple({
    int lignes = 3,
    bool signatures = true,
    OrientationPdf orientation = OrientationPdf.portrait,
  }) => DocumentPdf(
    titre: 'Balance Générale',
    periode: 'Exercice 2026',
    orientation: orientation,
    signatures: signatures,
    indicateurs: const [
      IndicateurPdf('Total Débits', '142 000 FCFA'),
      IndicateurPdf('Total Crédits', '142 000 FCFA'),
    ],
    tableaux: [
      TableauPdf(
        colonnes: const [
          ColonnePdf('N° Compte', largeur: 2),
          ColonnePdf('Libellé', largeur: 5),
          ColonnePdf('Débit', alignement: AlignementPdf.droite, largeur: 2),
          ColonnePdf('Crédit', alignement: AlignementPdf.droite, largeur: 2),
        ],
        lignes: [
          for (var i = 0; i < lignes; i++)
            [
              CellulePdf('${531 + i}'),
              CellulePdf('Compte de démonstration $i'),
              CellulePdf.montant(
                '${(i + 1) * 1000}',
                teinte: TeintePdf.positive,
              ),
              const CellulePdf('—', teinte: TeintePdf.attenuee),
            ],
        ],
        pied: const [
          CellulePdf('TOTAUX'),
          CellulePdf(''),
          CellulePdf('142 000'),
          CellulePdf('142 000'),
        ],
        note: 'Les montants sont exprimés en FCFA, sans décimale.',
      ),
    ],
  );

  Future<List<int>> rendre(DocumentPdf document) =>
      generateur.generer(document, entete: entete, maintenant: edition);

  group('Rendu de base', () {
    test('produit un PDF valide, en-tête et EOF compris', () async {
      final octets = await rendre(documentSimple());

      expect(octets.length, greaterThan(1000));
      expect(
        String.fromCharCodes(octets.take(5)),
        '%PDF-',
        reason: 'Tout PDF commence par cette signature.',
      );
      expect(
        String.fromCharCodes(octets.skip(octets.length - 8)),
        contains('%%EOF'),
      );
    });

    test('le paysage produit une page plus large que le portrait', () async {
      final portrait = await rendre(documentSimple());
      final paysage = await rendre(
        documentSimple(orientation: OrientationPdf.paysage),
      );
      // Les deux documents different reellement : meme contenu, mise en page
      // differente, donc taille d'octets differente.
      expect(paysage.length, isNot(portrait.length));
    });

    test(
      'le bloc de signatures peut être retiré — cas de la facture',
      () async {
        final avec = await rendre(documentSimple());
        final sans = await rendre(documentSimple(signatures: false));
        expect(
          sans.length,
          lessThan(avec.length),
          reason:
              'Le prototype passe `signatures: false` sur la facture et la '
              'lettre de relance.',
        );
      },
    );
  });

  group('Robustesse du texte français', () {
    test(
      'les accents, ligatures et guillemets ne font pas échouer le rendu',
      () async {
        final document = const DocumentPdf(
          titre: 'État Financier — Exercice Clôturé',
          periode: 'Août 2026',
          paragraphes: [
            ParagraphePdf(
              'Madame, Monsieur, sauf erreur ou omission de notre part, la '
              'facture reste impayée à ce jour. Cœur, œuf, æquo, «citation», '
              '№ 12 — 100 % à régler.',
            ),
          ],
          tableaux: [
            TableauPdf(
              colonnes: [ColonnePdf('Désignation'), ColonnePdf('Détail')],
              lignes: [
                [
                  CellulePdf('Œufs fertiles pintade'),
                  CellulePdf('Coquille d\'huître — 22 kg'),
                ],
                [
                  CellulePdf('Goliathau (0 → 4 mois)'),
                  CellulePdf('Éligible à la Vente ; ≥ 2,8 kg'),
                ],
              ],
            ),
          ],
        );

        // Le paquet `pdf` leve si un caractere manque a la police : ce test
        // est le garde-fou de la normalisation, et du choix d'une police
        // embarquee plutot que telechargee.
        final octets = await rendre(document);
        expect(octets.length, greaterThan(1000));
      },
    );

    test(
      'le nom de fichier est débarrassé des accents et de la ponctuation',
      () {
        expect(
          const DocumentPdf(titre: 'État Financier — Bilan').nomFichier,
          'LogiALVIA_Etat_Financier_Bilan.pdf',
        );
        expect(
          const DocumentPdf(titre: 'Facture de Vente — V-2026-142').nomFichier,
          'LogiALVIA_Facture_de_Vente_V_2026_142.pdf',
        );
        expect(
          const DocumentPdf(titre: 'Clôture d\'Exercice').nomFichier,
          'LogiALVIA_Cloture_d_Exercice.pdf',
        );
      },
    );
  });

  group('États vides — Master Prompt §2.2', () {
    test('un document sans aucune ligne est signalé comme vide', () {
      const document = DocumentPdf(
        titre: 'Journal Comptable',
        tableaux: [
          TableauPdf(colonnes: [ColonnePdf('Date')], lignes: []),
        ],
      );
      expect(document.estVide, isTrue);
    });

    test(
      'il porte le message explicatif plutôt qu\'une page blanche',
      () async {
        const document = DocumentPdf(
          titre: 'Journal Comptable',
          messageSiVide:
              'Aucune écriture sur l\'exercice. Les ventes et achats '
              'enregistrés apparaissent ici automatiquement.',
          tableaux: [
            TableauPdf(colonnes: [ColonnePdf('Date')], lignes: []),
          ],
        );
        final octets = await rendre(document);
        expect(octets.length, greaterThan(1000));
      },
    );

    test('un document avec un paragraphe n\'est pas vide', () {
      const document = DocumentPdf(
        titre: 'Lettre de Relance',
        paragraphes: [ParagraphePdf('Madame, Monsieur,')],
      );
      expect(document.estVide, isFalse);
    });
  });

  group('Documents longs', () {
    test(
      'un tableau de 200 lignes se répartit sur plusieurs pages sans erreur',
      () async {
        final octets = await rendre(documentSimple(lignes: 200));
        expect(octets.length, greaterThan(5000));
      },
    );

    test(
      'une ligne plus courte que l\'en-tête ne fait pas échouer le rendu',
      () async {
        // Cas reel : une ligne de totaux qui ne remplit que 2 des 4 colonnes.
        const document = DocumentPdf(
          titre: 'Test',
          tableaux: [
            TableauPdf(
              colonnes: [
                ColonnePdf('A'),
                ColonnePdf('B'),
                ColonnePdf('C'),
                ColonnePdf('D'),
              ],
              lignes: [
                [CellulePdf('1')],
              ],
              pied: [CellulePdf('Total')],
            ),
          ],
        );
        final octets = await rendre(document);
        expect(octets.length, greaterThan(1000));
      },
    );
  });

  group('En-tête officielle', () {
    test(
      'l\'IFU et le RCCM ne s\'impriment que s\'ils sont renseignés',
      () async {
        const sansMentions = EnteteOfficielle(
          raisonSociale: 'ALLMANY ET COMPAGNIE',
          generePar: 'admin',
        );
        final avec = await generateur.generer(
          documentSimple(),
          entete: entete,
          maintenant: edition,
        );
        final sans = await generateur.generer(
          documentSimple(),
          entete: sansMentions,
          maintenant: edition,
        );
        expect(sans.length, lessThan(avec.length));
      },
    );

    test('la date d\'édition est injectable — sans quoi la sortie changerait à '
        'chaque exécution', () async {
      final premier = await rendre(documentSimple());
      final second = await rendre(documentSimple());
      expect(
        premier.length,
        second.length,
        reason: 'Deux rendus identiques doivent produire la même taille.',
      );
    });
  });
}
