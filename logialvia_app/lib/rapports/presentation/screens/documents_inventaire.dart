import '../../../core/formatage/formats.dart';
import '../../../core/pdf/document_pdf.dart';
import '../viewmodels/inventaire_view_model.dart';

/// Le document imprimable de l'Inventaire.
///
/// ## Ce qu'un inventaire signé doit porter
///
/// Un état d'inventaire sert à être contresigné : il doit donc dire **à quelle
/// date** il arrête les comptes, **sur quelle base** les stocks sont valorisés,
/// et **ce qu'il exclut**. Un total qui tait ses exclusions se lit comme un
/// total complet — et c'est ce total-là qui part au dossier.
class DocumentsInventaire {
  DocumentsInventaire._();

  static DocumentPdf etat(InventaireViewModel vm) {
    final inv = vm.inventaire;

    if (inv == null || inv.estVide) {
      return DocumentPdf(
        titre: 'Inventaire',
        periode: vm.libellePeriode,
        messageSiVide:
            'Aucun stock enregistré à cette date. Un inventaire vide est un '
            'constat, pas une erreur.',
      );
    }

    return DocumentPdf(
      titre: 'Inventaire',
      periode: vm.libellePeriode,
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf(
          'Valeur totale du stock',
          Formats.montant(inv.valeurTotale),
        ),
        IndicateurPdf('Dont intrants', Formats.montant(inv.valeurIntrants)),
        IndicateurPdf(
          'Dont produits finis',
          Formats.montant(inv.valeurProduits),
        ),
        IndicateurPdf('Animaux sur pied', '${inv.effectifTotal} sujets'),
        // Les oeufs en incubation ne figurent plus ici : l'ecran n'affiche que
        // quatre indicateurs depuis l'arbitrage de la Gerante, et un etat qui
        // en montre cinq fait douter de celui qui en montre quatre. Le chiffre
        // n'est pas perdu pour autant -- il descend dans le paragraphe qui
        // explique ce qui est compte sans etre valorise, ou il a davantage sa
        // place : un oeuf en couveuse n'est ni un intrant ni un produit fini,
        // c'est un en-cours.
      ],
      paragraphes: [
        const ParagraphePdf(
          'Les intrants sont valorisés au prix moyen pondéré, les produits '
          'finis à leur coût de revient. Aucun stock n\'est valorisé à son '
          'prix de vente : un animal encore en enclos n\'a rien rapporté.',
        ),
        if (inv.produitsNonValorises > 0)
          ParagraphePdf(
            '${inv.produitsNonValorises} produit(s) sont exclus du total, '
            'faute de coût de revient renseigné.',
            gras: true,
          ),
        ParagraphePdf(
          'Comptés mais non valorisés : ${inv.effectifTotal} animaux sur pied '
          'et ${inv.oeufsEnIncubation} œufs en incubation. Leur coût dépend '
          'de la provende consommée depuis la mise en bande, que le logiciel '
          'ne cumule pas par lot.',
        ),
        if (inv.intrantsDesequilibres.isNotEmpty)
          ParagraphePdf(
            'ATTENTION — ${inv.intrantsDesequilibres.length} article(s) dont '
            'les mouvements n\'expliquent pas le stock : '
            '${inv.intrantsDesequilibres.map((l) => l.article).join(', ')}.',
            gras: true,
          ),
      ],
      tableaux: [
        TableauPdf(
          titre: 'Intrants — valorisés au PMP',
          colonnes: const [
            ColonnePdf('Article', largeur: 3),
            ColonnePdf('Catégorie', largeur: 2),
            ColonnePdf('Stock initial', alignement: AlignementPdf.droite),
            ColonnePdf('Entrées', alignement: AlignementPdf.droite),
            ColonnePdf('Sorties', alignement: AlignementPdf.droite),
            ColonnePdf('Stock final', alignement: AlignementPdf.droite),
            ColonnePdf('PMP', alignement: AlignementPdf.droite),
            ColonnePdf('Valeur', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: [
            for (final l in vm.intrants)
              [
                CellulePdf('${l.article} (${l.code})'),
                CellulePdf(l.categorie),
                CellulePdf(Formats.nombre(l.stockInitial)),
                CellulePdf(l.entrees == 0 ? '—' : Formats.nombre(l.entrees)),
                CellulePdf(l.sorties == 0 ? '—' : Formats.nombre(l.sorties)),
                CellulePdf(
                  '${Formats.nombre(l.stockFinal)} ${l.unite}',
                  gras: true,
                ),
                CellulePdf(Formats.montant(l.pmp)),
                CellulePdf.montant(Formats.montant(l.valeur)),
              ],
          ],
          pied: [
            const CellulePdf('TOTAL INTRANTS', gras: true),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf.montant(Formats.montant(inv.valeurIntrants)),
          ],
        ),
        TableauPdf(
          titre: 'Produits finis — valorisés au coût de revient',
          colonnes: const [
            ColonnePdf('Produit', largeur: 3),
            ColonnePdf('Catégorie', largeur: 2),
            ColonnePdf('Stock initial', alignement: AlignementPdf.droite),
            ColonnePdf('Sorties (ventes)', alignement: AlignementPdf.droite),
            ColonnePdf('Stock final', alignement: AlignementPdf.droite),
            ColonnePdf('Coût de revient', alignement: AlignementPdf.droite),
            ColonnePdf('Valeur', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: [
            for (final l in vm.produits)
              [
                CellulePdf('${l.produit} (${l.sku})'),
                CellulePdf(l.categorie),
                CellulePdf('${l.stockInitial}'),
                CellulePdf(l.sorties == 0 ? '—' : Formats.nombre(l.sorties)),
                CellulePdf('${l.stockFinal} ${l.unite}', gras: true),
                CellulePdf(
                  l.estValorise
                      ? Formats.montant(l.coutRevient!)
                      : 'Non renseigné',
                  teinte: l.estValorise
                      ? TeintePdf.normale
                      : TeintePdf.attenuee,
                ),
                l.estValorise
                    ? CellulePdf.montant(Formats.montant(l.valeur!))
                    : const CellulePdf(
                        'Non valorisé',
                        teinte: TeintePdf.attenuee,
                      ),
              ],
          ],
          pied: [
            const CellulePdf('TOTAL PRODUITS FINIS', gras: true),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf.montant(Formats.montant(inv.valeurProduits)),
          ],
        ),
        TableauPdf(
          titre: 'Animaux sur pied — comptés, non valorisés',
          colonnes: const [
            ColonnePdf('Filière', largeur: 3),
            ColonnePdf('Effectif', alignement: AlignementPdf.droite),
            ColonnePdf('Dernière saisie', alignement: AlignementPdf.droite),
          ],
          lignes: [
            for (final l in inv.effectifs)
              [
                CellulePdf(l.libelle),
                CellulePdf('${l.effectif}', gras: true),
                CellulePdf(
                  l.dateSaisie == null
                      ? 'Jamais saisie'
                      : Formats.date(l.dateSaisie!),
                  teinte: l.dateSaisie == null
                      ? TeintePdf.attenuee
                      : TeintePdf.normale,
                ),
              ],
          ],
          pied: [
            const CellulePdf('TOTAL', gras: true),
            CellulePdf('${inv.effectifTotal}', gras: true),
            const CellulePdf(''),
          ],
        ),
      ],
    );
  }
}
