import '../../../core/formatage/formats.dart';
import '../../../core/pdf/document_pdf.dart';
import '../../domain/entities/vente.dart';
import '../viewmodels/catalogue_view_model.dart';
import '../viewmodels/clients_view_model.dart';
import '../viewmodels/ventes_view_model.dart';

/// Documents imprimables du module Commercial — Doc F4, Doc H1, Doc E9.
class DocumentsCommercial {
  DocumentsCommercial._();

  /// Facture d'une vente — `downloadInvoice()` de `ventes.html`.
  ///
  /// ⚠️ **Correction à Doc E9 §2** : le document décrit une facture **A5** avec
  /// sa propre mise en page. Le prototype, lui, fait passer la facture par
  /// `generateOfficialPDF()` comme les 23 autres exports — même en-tête A4,
  /// même bandeau de titre, `signatures: false`. C'est ce comportement réel qui
  /// est reproduit.
  static DocumentPdf facture(Vente vente) {
    return DocumentPdf(
      titre: 'Facture de Vente — ${vente.reference}',
      periode: Formats.date(vente.date),
      // Une facture n'est pas contresignee par l'animalier.
      signatures: false,
      indicateurs: [
        IndicateurPdf('Référence', vente.reference),
        IndicateurPdf('Mode de Règlement', vente.mode),
        IndicateurPdf('Total', Formats.montant(vente.total)),
      ],
      paragraphes: [
        ParagraphePdf('Client : ${vente.client}'),
        if (vente.estAnnulee)
          ParagraphePdf(
            'VENTE ANNULÉE — ${vente.motifAnnulation ?? "motif non précisé"}. '
            'Ce document ne vaut pas justificatif de vente.',
            gras: true,
          ),
      ],
      messageSiVide: 'Cette vente ne comporte aucune ligne.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Article', largeur: 6),
            ColonnePdf(
              'Quantité',
              alignement: AlignementPdf.centre,
              largeur: 2,
            ),
            ColonnePdf(
              'Prix Unitaire',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Montant', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: [
            for (final l in vente.lignes)
              [
                CellulePdf(l.nom),
                CellulePdf(
                  '${Formats.nombre(l.quantite)} ${l.unite ?? ""}'.trim(),
                ),
                CellulePdf(Formats.nombre(l.prixUnitaire)),
                CellulePdf.montant(Formats.nombre(l.total)),
              ],
          ],
          pied: [
            const CellulePdf('TOTAL'),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf('${Formats.nombre(vente.total)} FCFA'),
          ],
          note: vente.resteDu > 0
              ? 'Réglé : ${Formats.montant(vente.paye)} — '
                    'Reste dû : ${Formats.montant(vente.resteDu)}.'
              : 'Vente intégralement réglée.',
        ),
      ],
    );
  }

  /// Historique des ventes filtré — Doc E9 §5.
  static DocumentPdf historiqueVentes(VentesViewModel vm) {
    final ventes = vm.ventes;
    final encaisse = ventes
        .where((v) => !v.estAnnulee)
        .fold<double>(0, (s, v) => s + v.paye);
    final chiffreAffaires = ventes
        .where((v) => !v.estAnnulee)
        .fold<double>(0, (s, v) => s + v.total);

    return DocumentPdf(
      titre: 'Historique des Ventes',
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Ventes', '${ventes.length}'),
        IndicateurPdf('Chiffre d\'Affaires', Formats.montant(chiffreAffaires)),
        IndicateurPdf('Encaissé', Formats.montant(encaisse)),
        IndicateurPdf('Reste Dû', Formats.montant(chiffreAffaires - encaisse)),
      ],
      messageSiVide:
          'Aucune vente enregistrée. L\'historique se remplit depuis le Point '
          'de Vente.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Référence', largeur: 3),
            ColonnePdf('Date', largeur: 2),
            ColonnePdf('Client', largeur: 4),
            ColonnePdf('Mode', largeur: 2),
            ColonnePdf('Total', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Payé', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Reste Dû',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 2),
          ],
          lignes: [
            for (final v in ventes)
              [
                CellulePdf(v.reference),
                CellulePdf(Formats.date(v.date)),
                CellulePdf(v.client),
                CellulePdf(v.mode),
                CellulePdf(Formats.nombre(v.total)),
                CellulePdf(Formats.nombre(v.paye)),
                v.resteDu > 0
                    ? CellulePdf.montant(
                        Formats.nombre(v.resteDu),
                        teinte: TeintePdf.negative,
                      )
                    : const CellulePdf('—', teinte: TeintePdf.attenuee),
                CellulePdf(
                  v.statut,
                  teinte: v.estAnnulee ? TeintePdf.attenuee : TeintePdf.normale,
                ),
              ],
          ],
          pied: [
            CellulePdf('TOTAUX (${ventes.length})'),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf(Formats.nombre(chiffreAffaires)),
            CellulePdf(Formats.nombre(encaisse)),
            CellulePdf(Formats.nombre(chiffreAffaires - encaisse)),
            const CellulePdf(''),
          ],
          note:
              'Les ventes annulées figurent dans l\'historique mais sont '
              'exclues des totaux : leur écriture a été contrepassée '
              '(BR-CPT-003).',
        ),
      ],
    );
  }

  /// Suivi des soldes clients — `relances-clients.html`.
  static DocumentPdf creancesClients(
    ClientsViewModel vm, {
    DateTime? maintenant,
  }) {
    final creances = vm.creances;
    final date = maintenant ?? DateTime.now();

    return DocumentPdf(
      titre: 'Suivi des Soldes Clients',
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Clients Enregistrés', '${vm.clientsEnregistres}'),
        IndicateurPdf(
          'Solde Total Restant Dû',
          Formats.montant(vm.soldeTotalRestantDu),
        ),
        IndicateurPdf('Soldes Anciens', '${vm.soldesAnciens}'),
      ],
      messageSiVide:
          'Aucune créance en cours : toutes les ventes sont intégralement '
          'réglées.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Client', largeur: 4),
            ColonnePdf('Référence', largeur: 3),
            ColonnePdf('Date', largeur: 2),
            ColonnePdf('Total', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Payé', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Reste Dû',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf(
              'Ancienneté',
              alignement: AlignementPdf.centre,
              largeur: 2,
            ),
          ],
          lignes: [
            for (final c in creances)
              [
                CellulePdf(c.client),
                CellulePdf(c.referenceVente),
                CellulePdf(Formats.date(c.dateVente)),
                CellulePdf(Formats.nombre(c.montantTotal)),
                CellulePdf(Formats.nombre(c.dejaRegle)),
                CellulePdf.montant(
                  Formats.nombre(c.soldeRestantDu),
                  teinte: TeintePdf.negative,
                ),
                CellulePdf(
                  '${c.ancienneteJours(date)} j',
                  teinte: c.estAncienne(date)
                      ? TeintePdf.negative
                      : TeintePdf.normale,
                ),
              ],
          ],
          pied: [
            CellulePdf('TOTAL (${creances.length})'),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf(Formats.nombre(vm.soldeTotalRestantDu)),
            const CellulePdf(''),
          ],
        ),
      ],
    );
  }

  /// Lettre de relance individuelle — `exportLettreRelance()` de
  /// `rapports-exports.html`, reprise mot pour mot.
  /// L'échéance conditionne la phrase d'attaque : sans elle, on ne peut pas
  /// écrire « reste impayée » — rien ne dit que le paiement était dû.
  static DocumentPdf lettreRelance({
    required String client,
    required String reference,
    required double solde,
    DateTime? echeance,
  }) {
    return DocumentPdf(
      titre: echeance == null
          ? 'Rappel de Solde — $client'
          : 'Lettre de Relance — $client',
      // Une lettre se signe : le prototype passe `signatures: true` ici.
      paragraphes: [
        ParagraphePdf('Madame, Monsieur $client,'),
        if (echeance == null)
          // Aucun delai n'a ete convenu sur cette vente : le solde est du,
          // mais il n'est pas EN RETARD. Le prototype ne fait pas la
          // difference et reclame dans tous les cas.
          ParagraphePdf(
            'Sauf erreur ou omission de notre part, la facture $reference '
            'présente un solde de ${Formats.montant(solde)} restant à régler.',
          )
        else
          ParagraphePdf(
            'Sauf erreur ou omission de notre part, nous constatons que la '
            'facture $reference, payable le ${Formats.date(echeance)}, reste '
            'impayée à ce jour pour un montant de ${Formats.montant(solde)}.',
          ),
        const ParagraphePdf(
          'Nous vous remercions de bien vouloir procéder au règlement de ce '
          'solde dans les meilleurs délais, ou de nous contacter si un '
          'arrangement est nécessaire.',
        ),
        const ParagraphePdf(
          'Dans l\'attente de votre règlement, nous vous prions d\'agréer, '
          'Madame, Monsieur, l\'expression de nos salutations distinguées.',
        ),
      ],
    );
  }

  /// Catalogue et seuils d'alerte — `catalogue-produits.html`.
  static DocumentPdf catalogue(CatalogueViewModel vm) {
    final produits = vm.produits;

    return DocumentPdf(
      titre: 'Catalogue Produits & Seuils d\'Alerte',
      orientation: OrientationPdf.paysage,
      signatures: false,
      indicateurs: [
        IndicateurPdf('Produits Actifs', '${vm.produitsActifs}'),
        IndicateurPdf(
          'Valeur du Catalogue',
          Formats.montant(vm.valeurCatalogue),
        ),
        IndicateurPdf('Produits Critiques', '${vm.produitsCritiques}'),
      ],
      messageSiVide: 'Aucun produit ne correspond aux filtres retenus.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('SKU', largeur: 2),
            ColonnePdf('Désignation', largeur: 5),
            ColonnePdf('Catégorie', largeur: 3),
            ColonnePdf('Prix', alignement: AlignementPdf.droite, largeur: 3),
            ColonnePdf('Unité', largeur: 2),
            ColonnePdf('Stock', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Seuil', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 2),
          ],
          lignes: [
            for (final p in produits)
              [
                CellulePdf(p.sku ?? '—'),
                CellulePdf(p.nom, gras: true),
                CellulePdf(p.categorie),
                CellulePdf(
                  p.prixMax == null
                      ? Formats.nombre(p.prix)
                      : '${Formats.nombre(p.prix)} – '
                            '${Formats.nombre(p.prixMax!)}',
                ),
                CellulePdf(p.unite),
                CellulePdf(
                  '${p.stock}',
                  teinte: p.estCritique
                      ? TeintePdf.negative
                      : TeintePdf.normale,
                ),
                CellulePdf('${p.seuil}'),
                CellulePdf(p.estCritique ? 'Critique' : 'OK'),
              ],
          ],
        ),
      ],
    );
  }
}
