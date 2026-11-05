import '../../../core/formatage/formats.dart';
import '../../../core/pdf/document_pdf.dart';
import '../../domain/entities/rapports.dart';
import '../viewmodels/rapports_view_model.dart';

/// Construction des 6 états imprimables — Doc F7, Doc J2.
///
/// Le prototype clone le panneau DOM de l'onglet **actif** et le passe au
/// générateur unique (Doc F7 §Structure Commune). Le principe est repris : un
/// seul bouton, qui exporte l'onglet affiché avec ses filtres en vigueur.
class DocumentsRapports {
  DocumentsRapports._();

  static String _periode(RapportsViewModel vm) =>
      'du ${Formats.date(vm.debut)} au ${Formats.date(vm.fin)}';

  static CellulePdf _montant(double valeur, {TeintePdf? teinte}) =>
      valeur.abs() < 0.01
      ? const CellulePdf('—', teinte: TeintePdf.attenuee)
      : CellulePdf.montant(
          Formats.nombre(valeur),
          teinte: teinte ?? TeintePdf.normale,
        );

  /// Sélectionne le document de l'onglet actif.
  static DocumentPdf pourOnglet(int onglet, RapportsViewModel vm) =>
      switch (onglet) {
        0 => recettesDepenses(vm),
        1 => tresorerie(vm),
        2 => creances(vm),
        3 => dettes(vm),
        4 => elevage(vm),
        _ => stocks(vm),
      };

  // ------------------------------------------------------------ Onglet 1

  static DocumentPdf recettesDepenses(RapportsViewModel vm) {
    final lignes = vm.recettesDepensesFiltrees;
    final cumuls = vm.soldesCumules;

    return DocumentPdf(
      titre: 'Recettes et Dépenses',
      periode: _periode(vm),
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Total Recettes', Formats.montant(vm.totalRecettes)),
        IndicateurPdf('Total Dépenses', Formats.montant(vm.totalDepenses)),
        IndicateurPdf('Résultat Net', Formats.montant(vm.resultatNet)),
        IndicateurPdf(
          'Taux de Marge Brute',
          vm.tauxMargeBrute == null
              ? '—'
              : Formats.pourcentage(vm.tauxMargeBrute!),
        ),
      ],
      messageSiVide:
          'Aucune écriture de gestion sur la période. Les ventes et les '
          'dépenses enregistrées apparaissent ici automatiquement.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Période', largeur: 3),
            ColonnePdf('N° Pièce', largeur: 3),
            ColonnePdf('Catégorie SYSCOHADA', largeur: 7),
            ColonnePdf('Centre de Profit', largeur: 3),
            ColonnePdf(
              'Encaissement',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf(
              'Décaissement',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf(
              'Solde Cumulé',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
          ],
          lignes: [
            for (var i = 0; i < lignes.length; i++)
              [
                CellulePdf(lignes[i].periode),
                CellulePdf(lignes[i].numeroPiece),
                CellulePdf(lignes[i].categorie),
                CellulePdf(lignes[i].centre),
                _montant(lignes[i].encaissement, teinte: TeintePdf.positive),
                _montant(lignes[i].decaissement, teinte: TeintePdf.negative),
                CellulePdf.montant(Formats.nombre(cumuls[i])),
              ],
          ],
          note:
              'Seules les classes 6 et 7 sont comptées. Les contreparties de '
              'trésorerie et de tiers ne sont ni une recette ni une dépense : '
              'les additionner doublerait les totaux.',
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Onglet 2

  static DocumentPdf tresorerie(RapportsViewModel vm) {
    final mouvements = vm.mouvementsFiltres;
    final soldes = vm.soldesProgressifsTresorerie;

    return DocumentPdf(
      titre: 'État de Trésorerie',
      periode: _periode(vm),
      orientation: OrientationPdf.paysage,
      indicateurs: [
        for (final libelle in vm.libellesComptesTresorerie)
          IndicateurPdf(libelle, Formats.montant(vm.soldeCloture(libelle))),
        IndicateurPdf(
          'Trésorerie Nette',
          Formats.montant(vm.tresorerieNetteGlobale),
        ),
      ],
      messageSiVide:
          'Aucun mouvement de trésorerie sur la période. Les encaissements de '
          'vente et les décaissements d\'achat apparaissent ici '
          'automatiquement.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Date', largeur: 2),
            ColonnePdf('Compte', largeur: 2),
            ColonnePdf('Type d\'Opération', largeur: 3),
            ColonnePdf('Libellé', largeur: 6),
            ColonnePdf('Entrée', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Sortie', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Solde Progressif',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
          ],
          lignes: [
            // Soldes d'ouverture, comme a l'ecran : sans eux, la premiere
            // valeur du solde progressif sortirait de nulle part.
            for (final compte in vm.comptesAffiches)
              [
                CellulePdf(Formats.date(vm.debut)),
                CellulePdf(CompteTresorerie.libelleCourt(compte.numero)),
                const CellulePdf(
                  'Solde d\'Ouverture',
                  teinte: TeintePdf.attenuee,
                ),
                const CellulePdf('', teinte: TeintePdf.attenuee),
                const CellulePdf(''),
                const CellulePdf(''),
                CellulePdf.montant(
                  Formats.nombre(
                    vm.soldeOuverture(
                      CompteTresorerie.libelleCourt(compte.numero),
                    ),
                  ),
                ),
              ],
            for (var i = 0; i < mouvements.length; i++)
              [
                CellulePdf(Formats.date(mouvements[i].date)),
                CellulePdf(mouvements[i].compte),
                CellulePdf(mouvements[i].typeOperation),
                CellulePdf(mouvements[i].libelle),
                _montant(mouvements[i].entree, teinte: TeintePdf.positive),
                _montant(mouvements[i].sortie, teinte: TeintePdf.negative),
                CellulePdf.montant(Formats.nombre(soldes[i])),
              ],
          ],
          note:
              'Le solde progressif est tenu par compte : une ligne Mobile '
              'Money n\'affiche jamais un cumul mêlant la Caisse.',
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Onglet 3

  static DocumentPdf creances(RapportsViewModel vm) {
    final creances = vm.creancesFiltrees;

    return DocumentPdf(
      titre: 'Créances Clients',
      periode: _periode(vm),
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Créances En Cours', Formats.montant(vm.creancesEnCours)),
        IndicateurPdf(
          'Créances en Retard',
          Formats.montant(vm.creancesEnRetard),
        ),
        IndicateurPdf('Clients Débiteurs', '${vm.clientsDebiteurs}'),
        IndicateurPdf(
          'Taux de Recouvrement',
          vm.tauxRecouvrement == null
              ? '—'
              : Formats.pourcentage(vm.tauxRecouvrement!),
        ),
      ],
      messageSiVide:
          'Aucune créance en cours : toutes les ventes sont intégralement '
          'réglées.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Code', largeur: 2),
            ColonnePdf('Client', largeur: 4),
            ColonnePdf('N° Facture', largeur: 3),
            ColonnePdf('Date Vente', largeur: 2),
            ColonnePdf('Échéance', largeur: 2),
            ColonnePdf(
              'Montant Initial',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf(
              'Acomptes',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf(
              'Solde Dû',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Retard', alignement: AlignementPdf.centre, largeur: 2),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 2),
          ],
          lignes: [
            for (final c in creances)
              [
                CellulePdf(c.code),
                CellulePdf(c.client),
                CellulePdf(c.numeroFacture),
                CellulePdf(Formats.date(c.dateVente)),
                CellulePdf(
                  // « — » et non la date de vente : aucun delai n'a ete
                  // convenu sur cette creance.
                  c.echeance == null ? '—' : Formats.date(c.echeance!),
                  teinte: c.echeance == null
                      ? TeintePdf.attenuee
                      : TeintePdf.normale,
                ),
                _montant(c.montantInitial),
                _montant(c.acomptes),
                CellulePdf.montant(
                  Formats.nombre(c.soldeDu),
                  teinte: TeintePdf.negative,
                ),
                CellulePdf(
                  c.enRetard ? '${c.joursDeRetard}j' : '—',
                  teinte: c.enRetard ? TeintePdf.negative : TeintePdf.attenuee,
                ),
                CellulePdf(c.statut),
              ],
          ],
          pied: [
            CellulePdf('TOTAL (${creances.length})'),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf(
              Formats.nombre(creances.fold<double>(0, (s, c) => s + c.soldeDu)),
            ),
            const CellulePdf(''),
            const CellulePdf(''),
          ],
          note:
              'La colonne « Échéance » reprend la date de vente : ni le point '
              'de vente ni la table VENTES ne saisissent de délai de paiement.',
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Onglet 4

  static DocumentPdf dettes(RapportsViewModel vm) {
    final dettes = vm.dettesFiltrees;

    return DocumentPdf(
      titre: 'Dettes Fournisseurs',
      periode: _periode(vm),
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Total Dettes', Formats.montant(vm.totalDettes)),
        IndicateurPdf('Dettes Urgentes', Formats.montant(vm.dettesUrgentes)),
        IndicateurPdf(
          'Fournisseurs Créditeurs',
          '${vm.fournisseursCrediteurs}',
        ),
      ],
      messageSiVide:
          'Aucune dette fournisseur : tous les achats sont intégralement '
          'réglés.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Code', largeur: 2),
            ColonnePdf('Fournisseur', largeur: 5),
            ColonnePdf('N° Bon/Facture', largeur: 3),
            ColonnePdf('Date Achat', largeur: 2),
            ColonnePdf('Échéance', largeur: 2),
            ColonnePdf(
              'Montant Total',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Réglé', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Solde Restant',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 2),
          ],
          lignes: [
            for (final d in dettes)
              [
                CellulePdf(d.code),
                CellulePdf(d.fournisseur),
                CellulePdf(d.reference),
                CellulePdf(Formats.date(d.dateAchat)),
                CellulePdf(
                  d.echeance == null ? '—' : Formats.date(d.echeance!),
                  teinte: d.echeance == null
                      ? TeintePdf.attenuee
                      : TeintePdf.normale,
                ),
                _montant(d.montantTotal),
                _montant(d.regle),
                CellulePdf.montant(
                  Formats.nombre(d.soldeRestant),
                  teinte: TeintePdf.negative,
                ),
                CellulePdf(d.statut),
              ],
          ],
          pied: [
            CellulePdf('TOTAL (${dettes.length})'),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf(Formats.nombre(vm.totalDettes)),
            const CellulePdf(''),
          ],
          note:
              'Même limite que pour les créances : ACHATS ne porte pas '
              'd\'échéance ; la date d\'achat en tient lieu.',
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Onglet 5

  static DocumentPdf elevage(RapportsViewModel vm) {
    final donnees = vm.donnees;

    return DocumentPdf(
      titre: 'Rapport Élevage',
      periode: _periode(vm),
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Effectif Total', '${donnees.effectifTotal}'),
        IndicateurPdf('Sujets Malades', '${donnees.sujetsMalades}'),
        IndicateurPdf(
          'Taux Éclosion Moyen',
          donnees.tauxEclosionMoyen == null
              ? '—'
              : Formats.pourcentage(donnees.tauxEclosionMoyen!),
        ),
        IndicateurPdf('Cycles en Cours', '${donnees.cyclesEnCours}'),
      ],
      messageSiVide:
          'Aucune journée d\'élevage saisie sur la période et aucun cycle '
          'd\'incubation enregistré.',
      tableaux: [
        TableauPdf(
          titre: 'Tableau 1 — Recensement & Structure du Cheptel',
          colonnes: const [
            ColonnePdf('Lot / Souche', largeur: 3),
            ColonnePdf(
              'Effectif Total',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf(
              'Géniteurs / Matures',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
            ColonnePdf('Jeunes', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Morts', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Dons', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Effectif Malade',
              alignement: AlignementPdf.centre,
              largeur: 3,
            ),
          ],
          lignes: [
            for (final r in donnees.recensement)
              [
                CellulePdf(r.lot, gras: true),
                CellulePdf('${r.effectifTotal}'),
                CellulePdf('${r.effectifMatures}', teinte: TeintePdf.positive),
                CellulePdf('${r.effectifJeunes}'),
                CellulePdf(
                  '${r.mortsPeriode}',
                  teinte: r.mortsPeriode > 0
                      ? TeintePdf.negative
                      : TeintePdf.normale,
                ),
                CellulePdf('${r.donsPeriode}'),
                CellulePdf('${r.effectifMalade}'),
              ],
          ],
        ),
        TableauPdf(
          titre: 'Tableau 2 — Mouvements, Traitements & Ventes',
          colonnes: const [
            ColonnePdf('Lot', largeur: 3),
            ColonnePdf(
              'Qté Vendue',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf(
              'Montant Vente',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
            ColonnePdf(
              'Effectif Final',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Traitement Administré', largeur: 4),
            ColonnePdf('Signes Observés', largeur: 4),
            ColonnePdf(
              'Provende Servie (g/j)',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
          ],
          lignes: [
            for (final m in donnees.mouvementsElevage)
              [
                CellulePdf(m.lot, gras: true),
                CellulePdf('${m.quantiteVendue}'),
                _montant(m.montantVente, teinte: TeintePdf.positive),
                CellulePdf('${m.effectifFinal}'),
                CellulePdf(m.traitementAdministre),
                CellulePdf(m.signesObserves),
                CellulePdf(Formats.nombre(m.provendeServieGrammes)),
              ],
          ],
        ),
        TableauPdf(
          titre: 'Tableau 3 — Couvoir & Suivi d\'Incubation',
          colonnes: const [
            ColonnePdf('Code Lot', largeur: 3),
            ColonnePdf('Mise en Couvoir', largeur: 3),
            ColonnePdf('Éclosion Attendue', largeur: 3),
            ColonnePdf(
              'Œufs Couvés',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Nés', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Taux d\'Éclosion',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
            ColonnePdf(
              'Morts au Démarrage',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 2),
          ],
          lignes: [
            for (final c in donnees.couvoir)
              [
                CellulePdf(c.codeLot),
                CellulePdf(Formats.date(c.miseEnCouvoir)),
                CellulePdf(Formats.date(c.eclosionAttendue)),
                CellulePdf('${c.oeufsCouves}'),
                CellulePdf(c.nes == null ? '—' : '${c.nes}'),
                CellulePdf(
                  c.tauxEclosion == null
                      ? '—'
                      : Formats.pourcentage(c.tauxEclosion!),
                  teinte: c.tauxEclosion == null
                      ? TeintePdf.attenuee
                      : TeintePdf.positive,
                ),
                CellulePdf(
                  c.mortsAuDemarrage == null ? '—' : '${c.mortsAuDemarrage}',
                  teinte: (c.mortsAuDemarrage ?? 0) > 0
                      ? TeintePdf.negative
                      : TeintePdf.normale,
                ),
                CellulePdf(c.statut),
              ],
          ],
          note:
              'L\'éclosion attendue dépend de l\'espèce : 21 jours pour un '
              'goliath, 27 pour une pintade. Un taux vide signifie que le cycle '
              'n\'a pas encore éclos, jamais un échec.',
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Onglet 6

  static DocumentPdf stocks(RapportsViewModel vm) {
    final stocks = vm.stocksFiltres;

    return DocumentPdf(
      titre: 'Rapport de Stocks',
      periode: _periode(vm),
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf(
          'Valeur Totale du Stock',
          Formats.montant(vm.valeurTotaleStock),
        ),
        IndicateurPdf('Articles en Alerte', '${vm.articlesEnAlerte}'),
        IndicateurPdf('Références Actives', '${vm.referencesActives}'),
      ],
      messageSiVide: 'Aucun article ne correspond aux filtres retenus.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('SKU', largeur: 2),
            ColonnePdf('Désignation', largeur: 5),
            ColonnePdf('Catégorie', largeur: 3),
            ColonnePdf(
              'Stock Final',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Unité', largeur: 2),
            ColonnePdf('CMUP', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Valeur Totale',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 2),
          ],
          lignes: [
            for (final s in stocks)
              [
                CellulePdf(s.sku),
                CellulePdf(s.designation, gras: true),
                CellulePdf(s.categorie),
                CellulePdf(
                  Formats.nombre(s.stockFinal),
                  teinte: s.critique ? TeintePdf.negative : TeintePdf.normale,
                ),
                CellulePdf(s.unite),
                s.cmup == null
                    ? const CellulePdf('—', teinte: TeintePdf.attenuee)
                    : _montant(s.cmup!),
                s.valeurTotale == null
                    ? const CellulePdf(
                        'Non valorisé',
                        teinte: TeintePdf.attenuee,
                      )
                    : CellulePdf.montant(Formats.nombre(s.valeurTotale!)),
                CellulePdf(s.statut),
              ],
          ],
          note:
              'Le CMUP des intrants est le Prix Moyen Pondéré tenu par Gestion '
              'Stocks. Celui des produits finis est leur prix de vente '
              'indicatif : le catalogue ne porte aucun coût de revient, cette '
              'valorisation est donc une valeur de marché, pas un coût.',
        ),
      ],
    );
  }
}
