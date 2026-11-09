import '../../../core/formatage/formats.dart';
import '../../../core/pdf/document_pdf.dart';
import '../viewmodels/approvisionnement_view_model.dart';

/// Documents imprimables du module Approvisionnement — Doc F5.
class DocumentsAppro {
  DocumentsAppro._();

  /// État des stocks d'intrants — `gestion-stocks.html`.
  static DocumentPdf stocks(ApprovisionnementViewModel vm) {
    final intrants = vm.intrants;

    return DocumentPdf(
      titre: 'État des Stocks d\'Intrants',
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf(
          'Valeur Totale du Stock',
          Formats.montant(vm.valeurTotaleStock),
        ),
        IndicateurPdf('Articles Suivis', '${vm.articlesSuivis}'),
        IndicateurPdf('Sous le Seuil', '${vm.intrantsSousSeuil}'),
        IndicateurPdf('Mouvements (7 j)', '${vm.mouvements7Jours}'),
      ],
      messageSiVide: 'Aucun intrant ne correspond aux filtres retenus.',
      tableaux: [
        TableauPdf(
          titre: 'Intrants',
          colonnes: const [
            ColonnePdf('Code', largeur: 2),
            ColonnePdf('Désignation', largeur: 5),
            ColonnePdf('Catégorie', largeur: 3),
            ColonnePdf('Stock', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Unité', largeur: 2),
            ColonnePdf(
              'Seuil Alerte',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('PMP', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Valeur', alignement: AlignementPdf.droite, largeur: 3),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 2),
          ],
          lignes: [
            for (final i in intrants)
              [
                CellulePdf(i.code),
                CellulePdf(i.nom, gras: true),
                CellulePdf(i.categorie),
                CellulePdf(
                  '${i.stock}',
                  teinte: i.estCritique
                      ? TeintePdf.negative
                      : TeintePdf.normale,
                ),
                CellulePdf(i.unite),
                CellulePdf('${i.seuil}'),
                CellulePdf(Formats.nombre(i.pmp)),
                CellulePdf.montant(Formats.nombre(i.valeur)),
                CellulePdf(i.estCritique ? 'Critique' : 'OK'),
              ],
          ],
          pied: [
            CellulePdf('TOTAL (${intrants.length})'),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf(
              Formats.nombre(intrants.fold<double>(0, (s, i) => s + i.valeur)),
            ),
            const CellulePdf(''),
          ],
          note:
              'Le PMP (Prix Moyen Pondéré) est recalculé à chaque réception de '
              'commande. La valeur affichée est stock × PMP.',
        ),
        TableauPdf(
          titre: 'Journal des mouvements',
          colonnes: const [
            ColonnePdf('Date / Heure', largeur: 3),
            ColonnePdf('Référence', largeur: 3),
            ColonnePdf('Article', largeur: 4),
            ColonnePdf('Type', largeur: 2),
            ColonnePdf('Motif', largeur: 5),
            ColonnePdf(
              'Quantité',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
          ],
          lignes: [
            for (final m in vm.mouvements)
              [
                CellulePdf(
                  '${Formats.date(m.horodatage)} '
                  '${Formats.heure(m.horodatage)}',
                ),
                CellulePdf(m.reference ?? '—'),
                CellulePdf(m.article),
                CellulePdf(m.type),
                CellulePdf(m.motif),
                CellulePdf.montant(
                  Formats.nombre(m.quantite),
                  teinte: m.quantite < 0
                      ? TeintePdf.negative
                      : TeintePdf.positive,
                ),
              ],
          ],
          note:
              'La quantité est signée : positive en entrée, négative en sortie.',
        ),
      ],
    );
  }

  /// Achats et commandes — `achats-commandes.html`.
  static DocumentPdf achats(ApprovisionnementViewModel vm) {
    final achats = vm.achats;
    // Les commandes annulées (au web) restent listées mais ne comptent dans aucun total.
    final actifs = achats.where((a) => !a.estAnnule).toList();

    return DocumentPdf(
      titre: 'Achats & Commandes',
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Commandes en Cours', '${vm.commandesEnCours}'),
        IndicateurPdf(
          'Montant Total Engagé',
          Formats.montant(vm.montantTotalEngage),
        ),
        IndicateurPdf(
          'Achats Cumulés (Mois)',
          Formats.montant(vm.achatsCumulesMois),
        ),
      ],
      messageSiVide: 'Aucune commande ne correspond aux filtres retenus.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Référence', largeur: 3),
            ColonnePdf('Fournisseur', largeur: 4),
            ColonnePdf('Date', largeur: 2),
            ColonnePdf('Mode', largeur: 2),
            ColonnePdf('Total', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Réglé', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Reste Dû',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 3),
          ],
          lignes: [
            for (final a in achats)
              [
                CellulePdf(a.reference),
                CellulePdf(a.fournisseurNom),
                CellulePdf(Formats.date(a.date)),
                CellulePdf(a.mode ?? '—'),
                CellulePdf(Formats.nombre(a.total)),
                CellulePdf(Formats.nombre(a.paye)),
                a.soldeDu > 0.01
                    ? CellulePdf.montant(
                        Formats.nombre(a.soldeDu),
                        teinte: TeintePdf.negative,
                      )
                    : const CellulePdf('—', teinte: TeintePdf.attenuee),
                CellulePdf(a.statut),
              ],
          ],
          pied: [
            CellulePdf('TOTAUX (${achats.length})'),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf(
              Formats.nombre(actifs.fold<double>(0, (s, a) => s + a.total)),
            ),
            CellulePdf(
              Formats.nombre(actifs.fold<double>(0, (s, a) => s + a.paye)),
            ),
            CellulePdf(
              Formats.nombre(actifs.fold<double>(0, (s, a) => s + a.soldeDu)),
            ),
            const CellulePdf(''),
          ],
        ),
      ],
    );
  }

  /// Fournisseurs et dettes — `fournisseurs.html`.
  static DocumentPdf fournisseurs(ApprovisionnementViewModel vm) {
    final fournisseurs = vm.fournisseurs;

    return DocumentPdf(
      titre: 'Fournisseurs & Dettes',
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Fournisseurs Actifs', '${vm.fournisseursActifs}'),
        IndicateurPdf('Dette Totale', Formats.montant(vm.detteTotale)),
        IndicateurPdf('Dettes Soldées (Mois)', '${vm.dettesSoldeesMois}'),
      ],
      messageSiVide: 'Aucun fournisseur enregistré.',
      tableaux: [
        TableauPdf(
          titre: 'Fournisseurs',
          colonnes: const [
            ColonnePdf('Nom', largeur: 5),
            ColonnePdf('Téléphone', largeur: 3),
            ColonnePdf('Adresse', largeur: 4),
            ColonnePdf('Fournit', largeur: 4),
            ColonnePdf(
              'Solde Dû',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
          ],
          lignes: [
            for (final f in fournisseurs)
              [
                CellulePdf(f.nom, gras: true),
                CellulePdf(f.telephone ?? '—'),
                CellulePdf(f.adresse ?? '—'),
                CellulePdf(f.fournit ?? '—'),
                f.soldeDu > 0.01
                    ? CellulePdf.montant(
                        Formats.nombre(f.soldeDu),
                        teinte: TeintePdf.negative,
                      )
                    : const CellulePdf('—', teinte: TeintePdf.attenuee),
              ],
          ],
          pied: [
            CellulePdf('TOTAL (${fournisseurs.length})'),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf(Formats.nombre(vm.detteTotale)),
          ],
        ),
        TableauPdf(
          titre: 'Dettes en cours',
          colonnes: const [
            ColonnePdf('Référence', largeur: 3),
            ColonnePdf('Fournisseur', largeur: 4),
            ColonnePdf('Date', largeur: 2),
            ColonnePdf('Total', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Réglé', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Reste Dû',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
          ],
          lignes: [
            for (final d in vm.dettes)
              [
                CellulePdf(d.reference),
                CellulePdf(d.fournisseurNom),
                CellulePdf(Formats.date(d.date)),
                CellulePdf(Formats.nombre(d.total)),
                CellulePdf(Formats.nombre(d.paye)),
                CellulePdf.montant(
                  Formats.nombre(d.total - d.paye),
                  teinte: TeintePdf.negative,
                ),
              ],
          ],
        ),
      ],
    );
  }
}
