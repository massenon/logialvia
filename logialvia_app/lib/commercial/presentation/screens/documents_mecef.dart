import '../../../core/formatage/formats.dart';
import '../../../core/pdf/document_pdf.dart';
import '../../domain/entities/facture_mecef.dart';

/// La facture normalisée MeCeF, imprimable.
///
/// ## Ce que le document dit de lui-même
///
/// Une facture normalisée porte le code rendu par la DGI, le NIM de la machine
/// et un lien de vérification. Tant que ces éléments n'existent pas, le
/// document **le dit en toutes lettres** au lieu de laisser croire qu'il est
/// en règle. C'est le point le plus important de ce fichier : une facture qui
/// se présente comme normalisée alors qu'elle ne l'est pas expose l'entreprise
/// bien plus qu'une facture qui annonce son propre état.
///
/// Aucun QR n'est dessiné. Un QR se fabrique en deux lignes, mais celui d'une
/// facture normalisée encode le lien de vérification de la DGI : en produire
/// un localement, sans ce lien, donnerait un carré qui ne vérifie rien.
class DocumentsMecef {
  DocumentsMecef._();

  static DocumentPdf facture(FactureMecef f) {
    final estAvoir = f.type == TypeFacture.avoir;
    final signe = estAvoir ? -1 : 1;

    return DocumentPdf(
      titre: '${f.type.libelle} — ${f.reference}',
      periode: Formats.date(f.date),
      // Une facture ne se contresigne pas.
      signatures: false,
      indicateurs: [
        IndicateurPdf('Référence', f.reference),
        IndicateurPdf('Type', '${f.type.code} — ${f.type.libelle}'),
        IndicateurPdf('Total TTC', Formats.montant(signe * f.totalTtc)),
        IndicateurPdf('Statut', f.statut.libelle),
      ],
      paragraphes: [
        ParagraphePdf('Client : ${f.client}'),
        if (f.clientIfu != null)
          ParagraphePdf('IFU du client : ${f.clientIfu}'),
        if (f.clientAdresse != null)
          ParagraphePdf('Adresse : ${f.clientAdresse}'),
        if (estAvoir && f.origineRef != null)
          ParagraphePdf(
            'Avoir sur la facture ${f.origineRef} — '
            '${f.motif ?? "motif non précisé"}.',
            gras: true,
          ),
        if (f.venteRef != null)
          ParagraphePdf('Vente d\'origine : ${f.venteRef}'),
        ..._mentionNormalisation(f),
      ],
      messageSiVide: 'Cette facture ne comporte aucune ligne.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Désignation', largeur: 6),
            ColonnePdf('Qté', alignement: AlignementPdf.centre, largeur: 1),
            ColonnePdf('P.U. HT', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Gr.', alignement: AlignementPdf.centre, largeur: 1),
            ColonnePdf(
              'Montant HT',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
          ],
          lignes: [
            for (final l in f.lignes)
              [
                CellulePdf(l.designation),
                CellulePdf(Formats.nombre(l.quantite)),
                CellulePdf(Formats.montant(l.prixUnitaireHt)),
                CellulePdf(l.groupeTaxe),
                CellulePdf(Formats.montant(signe * l.montantHt)),
              ],
          ],
        ),
        // Le recapitulatif par groupe : c'est lui qui justifie le montant de
        // taxe, ligne par ligne d'un controle fiscal.
        TableauPdf(
          colonnes: const [
            ColonnePdf('Groupe de taxe', largeur: 6),
            ColonnePdf('Taux', alignement: AlignementPdf.centre, largeur: 2),
            ColonnePdf('Base HT', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Taxe', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: [
            for (final t in f.totauxParGroupe)
              [
                CellulePdf(t.groupe),
                CellulePdf(
                  t.taux == 0 ? 'Exonéré' : '${Formats.nombre(t.taux)} %',
                ),
                CellulePdf(Formats.montant(signe * t.baseHt)),
                CellulePdf(Formats.montant(signe * t.taxe)),
              ],
            [
              const CellulePdf('TOTAL', gras: true),
              const CellulePdf(''),
              CellulePdf(Formats.montant(signe * f.totalHt), gras: true),
              CellulePdf(Formats.montant(signe * f.totalTaxe), gras: true),
            ],
            [
              const CellulePdf('NET À PAYER TTC', gras: true),
              const CellulePdf(''),
              const CellulePdf(''),
              CellulePdf(Formats.montant(signe * f.totalTtc), gras: true),
            ],
          ],
        ),
      ],
    );
  }

  /// Le bloc de normalisation — ou son absence, dite franchement.
  static List<ParagraphePdf> _mentionNormalisation(FactureMecef f) {
    if (f.estNormalisee) {
      return [
        ParagraphePdf('Code MeCeF/DGI : ${f.codeMecef}', gras: true),
        ParagraphePdf(
          'NIM : ${f.nim}'
          '${f.compteur != null ? "   ·   Compteur : ${f.compteur}" : ""}'
          '${f.dateNormalisation != null ? "   ·   Normalisée le ${Formats.date(f.dateNormalisation!)}" : ""}',
        ),
        if (f.lienVerification != null)
          ParagraphePdf('Vérification : ${f.lienVerification}'),
      ];
    }

    return [
      const ParagraphePdf(
        'FACTURE NON NORMALISÉE — en attente de transmission e-MECeF. '
        'Ce document ne vaut pas facture normalisée au sens de la '
        'réglementation fiscale.',
        gras: true,
      ),
      if (f.erreurTransmission != null)
        ParagraphePdf('Dernier refus : ${f.erreurTransmission}'),
    ];
  }
}
