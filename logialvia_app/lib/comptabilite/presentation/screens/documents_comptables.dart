import '../../../core/formatage/formats.dart';
import '../../../core/pdf/document_pdf.dart';
import '../../domain/entities/comptabilite.dart';
import '../../domain/services/bilan_entreprise.dart';
import '../viewmodels/comptabilite_view_model.dart';

/// Construction des documents imprimables du module Comptabilité — Doc F6.
///
/// Chaque fonction traduit l'état affiché à l'écran en [DocumentPdf]. Elles
/// exportent **ce qui est affiché**, filtres compris : le prototype clone le
/// panneau DOM de l'onglet actif, donc déjà filtré (Doc F7 §Structure Commune).
class DocumentsComptables {
  DocumentsComptables._();

  static String _montant(double valeur) =>
      valeur.abs() < 0.01 ? '—' : Formats.nombre(valeur);

  static CellulePdf _cellMontant(double valeur, {TeintePdf? teinte}) =>
      valeur.abs() < 0.01
      ? const CellulePdf('—', teinte: TeintePdf.attenuee)
      : CellulePdf.montant(
          Formats.nombre(valeur),
          teinte: teinte ?? TeintePdf.normale,
        );

  // ------------------------------------------------------------- Journal

  static DocumentPdf journal(ComptabiliteViewModel vm) {
    final lignes = vm.journalFiltre;
    final equilibre =
        (vm.totalDebitJournal - vm.totalCreditJournal).abs() < 0.01;

    return DocumentPdf(
      titre: 'Journal Comptable',
      periode: 'Exercice ${vm.exercice}',
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Écritures', '${lignes.length}'),
        IndicateurPdf('Total Débit', Formats.montant(vm.totalDebitJournal)),
        IndicateurPdf('Total Crédit', Formats.montant(vm.totalCreditJournal)),
        IndicateurPdf('Équilibre', equilibre ? 'Équilibré' : 'Écart détecté'),
      ],
      messageSiVide:
          'Aucune écriture sur l\'exercice ${vm.exercice}. Chaque vente et '
          'chaque achat enregistré génère automatiquement son écriture.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('N° Pièce', largeur: 3),
            ColonnePdf('Date', largeur: 2),
            ColonnePdf('Jal', largeur: 1),
            ColonnePdf('Compte', largeur: 4),
            ColonnePdf('Libellé', largeur: 6),
            ColonnePdf('Débit', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Crédit', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: [
            for (final e in lignes)
              [
                CellulePdf(e.numeroPiece ?? '—'),
                CellulePdf(Formats.date(e.date)),
                CellulePdf(e.journalCode),
                CellulePdf(
                  '${e.numeroCompte} — ${_libelleCompte(vm, e.numeroCompte)}',
                ),
                CellulePdf(e.libelle),
                _cellMontant(e.debit),
                _cellMontant(e.credit),
              ],
          ],
          pied: [
            const CellulePdf('TOTAUX'),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf(_montant(vm.totalDebitJournal)),
            CellulePdf(_montant(vm.totalCreditJournal)),
          ],
        ),
      ],
    );
  }

  static String _libelleCompte(ComptabiliteViewModel vm, String numero) {
    for (final c in vm.plan) {
      if (c.numero == numero) return c.libelle;
    }
    return 'Compte inconnu';
  }

  // --------------------------------------------------------- Grand Livre

  static DocumentPdf grandLivre(ComptabiliteViewModel vm) {
    final compte = vm.compteCourant;
    final lignes = vm.grandLivre;

    return DocumentPdf(
      titre: compte == null
          ? 'Grand Livre'
          : 'Grand Livre — ${compte.numero} ${compte.libelle}',
      periode: _periodeGrandLivre(vm),
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf(
          'Solde d\'Ouverture',
          Formats.montant(vm.soldeOuvertureCompte),
        ),
        IndicateurPdf('Total Débit', Formats.montant(vm.totalDebitCompte)),
        IndicateurPdf('Total Crédit', Formats.montant(vm.totalCreditCompte)),
        IndicateurPdf('Solde Final', Formats.montant(vm.soldeFinalCompte)),
      ],
      messageSiVide: compte == null
          ? 'Aucun compte sélectionné.'
          : 'Aucune écriture sur ce compte pour la période retenue.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Date', largeur: 2),
            ColonnePdf('Origine', largeur: 3),
            ColonnePdf('Libellé', largeur: 6),
            ColonnePdf('Débit', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Crédit', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Solde Progressif',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
          ],
          lignes: [
            // La ligne de report ouvre le tableau, comme a l'ecran : sans elle,
            // la premiere valeur du solde progressif sortirait de nulle part.
            [
              const CellulePdf(''),
              const CellulePdf(''),
              const CellulePdf(
                'Report — solde d\'ouverture',
                teinte: TeintePdf.attenuee,
              ),
              const CellulePdf('', teinte: TeintePdf.attenuee),
              const CellulePdf('', teinte: TeintePdf.attenuee),
              CellulePdf(
                _montant(vm.soldeOuvertureCompte),
                teinte: TeintePdf.attenuee,
              ),
            ],
            for (final l in lignes)
              [
                CellulePdf(Formats.date(l.ecriture.date)),
                CellulePdf(
                  l.ecriture.venteRef ??
                      l.ecriture.achatRef ??
                      l.ecriture.numeroPiece ??
                      '—',
                ),
                CellulePdf(l.ecriture.libelle),
                _cellMontant(l.ecriture.debit, teinte: TeintePdf.positive),
                _cellMontant(l.ecriture.credit, teinte: TeintePdf.negative),
                CellulePdf.montant(Formats.nombre(l.soldeProgressif)),
              ],
          ],
        ),
      ],
    );
  }

  static String _periodeGrandLivre(ComptabiliteViewModel vm) {
    final debut = vm.debutGrandLivre;
    final fin = vm.finGrandLivre;
    if (debut == null && fin == null) return 'Exercice ${vm.exercice}';
    final d = debut == null ? 'début' : Formats.date(debut);
    final f = fin == null ? 'fin' : Formats.date(fin);
    return 'du $d au $f';
  }

  // ------------------------------------------------------------- Balance

  static DocumentPdf balance(ComptabiliteViewModel vm) {
    final lignes = vm.balance;

    return DocumentPdf(
      titre: 'Balance Générale',
      // Le perimetre doit figurer sur le document : deux balances du meme
      // exercice n'ont pas les memes soldes d'ouverture selon qu'elles
      // couvrent le mois ou l'annee.
      periode: vm.balanceMoisCourant
          ? 'Exercice ${vm.exercice} — mois de ${vm.libelleMoisBalance}'
          : 'Exercice ${vm.exercice} — exercice complet',
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf(
          'Total Débits',
          Formats.montant(vm.balanceTotalDebit),
        ),
        IndicateurPdf(
          'Total Crédits',
          Formats.montant(vm.balanceTotalCredit),
        ),
        IndicateurPdf(
          'Écart (doit être 0)',
          Formats.montant(vm.balanceEcart.abs()),
        ),
      ],
      messageSiVide:
          'Aucun compte mouvementé sur l\'exercice ${vm.exercice}.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('N° Compte', largeur: 2),
            ColonnePdf('Libellé', largeur: 5),
            ColonnePdf('Ouv. D', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Ouv. C', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Mvt D', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Mvt C', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Final D',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf(
              'Final C',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
          ],
          lignes: [
            for (final l in lignes)
              [
                CellulePdf(l.numeroCompte),
                CellulePdf(l.libelle),
                _cellMontant(l.ouvertureDebit),
                _cellMontant(l.ouvertureCredit),
                _cellMontant(l.mouvementsDebit),
                _cellMontant(l.mouvementsCredit),
                _cellMontant(l.finalDebit, teinte: TeintePdf.positive),
                _cellMontant(l.finalCredit, teinte: TeintePdf.negative),
              ],
          ],
          pied: [
            const CellulePdf('TOTAUX'),
            const CellulePdf(''),
            CellulePdf(
              _montant(lignes.fold(0, (s, l) => s + l.ouvertureDebit)),
            ),
            CellulePdf(
              _montant(lignes.fold(0, (s, l) => s + l.ouvertureCredit)),
            ),
            CellulePdf(
              _montant(lignes.fold(0, (s, l) => s + l.mouvementsDebit)),
            ),
            CellulePdf(
              _montant(lignes.fold(0, (s, l) => s + l.mouvementsCredit)),
            ),
            CellulePdf(_montant(vm.balanceTotalDebit)),
            CellulePdf(_montant(vm.balanceTotalCredit)),
          ],
          note: vm.balanceEstEquilibree
              ? 'Balance équilibrée : total débiteur = total créditeur '
                    '(BR-CPT-004).'
              : 'ATTENTION — Balance déséquilibrée de '
                    '${Formats.montant(vm.balanceEcart.abs())}. Une clôture est '
                    'impossible tant que cet écart subsiste (BR-CPT-004).',
        ),
      ],
    );
  }

  // ------------------------------------------------------- Plan comptable

  static DocumentPdf planComptable(
    ComptabiliteViewModel vm,
    List<CompteComptable> comptes,
  ) {
    return DocumentPdf(
      titre: 'Plan Comptable',
      periode: 'SYSCOHADA Révisée',
      // Un referentiel n'est pas un etat de gestion : il ne se signe pas.
      signatures: false,
      messageSiVide: 'Aucun compte ne correspond aux filtres retenus.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('N° Compte', largeur: 2),
            ColonnePdf('Intitulé', largeur: 7),
            ColonnePdf('Classe', largeur: 3),
            ColonnePdf('Sens', largeur: 2),
            ColonnePdf('État', largeur: 2),
          ],
          lignes: [
            for (final c in comptes)
              [
                CellulePdf(c.numero),
                CellulePdf(c.libelle),
                CellulePdf(
                  CompteComptable.libellesClasses[c.classe] ?? c.classe,
                ),
                CellulePdf(
                  c.estDebiteurParNature ? 'Débiteur' : 'Créditeur',
                ),
                CellulePdf(
                  c.archive ? 'Archivé' : 'Actif',
                  teinte: c.archive
                      ? TeintePdf.attenuee
                      : TeintePdf.normale,
                ),
              ],
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------- États financiers

  static DocumentPdf bilan(ComptabiliteViewModel vm) {
    final bilan = vm.bilan;

    List<List<CellulePdf>> postes(List<PosteEtat> liste) => [
      for (final p in liste)
        if (!p.estTotal)
          [
            CellulePdf(
              p.detail == null ? p.libelle : '${p.libelle}  (${p.detail})',
              gras: p.estSousTotal,
            ),
            _cellMontant(p.montant),
          ],
    ];

    return DocumentPdf(
      titre: 'Bilan',
      periode: 'Exercice ${vm.exercice} — situation au '
          '${Formats.date(DateTime.now())}',
      indicateurs: [
        IndicateurPdf('Total Actif', Formats.montant(bilan.totalActif)),
        IndicateurPdf('Total Passif', Formats.montant(bilan.totalPassif)),
        IndicateurPdf('Résultat Net', Formats.montant(vm.resultatNet)),
      ],
      messageSiVide:
          'Aucune écriture sur l\'exercice : le bilan est vide de part et '
          'd\'autre.',
      tableaux: [
        TableauPdf(
          titre: 'ACTIF (Emplois)',
          colonnes: const [
            ColonnePdf('Rubrique', largeur: 5),
            ColonnePdf('Montant', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: postes(bilan.actif),
          pied: [
            const CellulePdf('TOTAL GÉNÉRAL ACTIF'),
            CellulePdf(_montant(bilan.totalActif)),
          ],
        ),
        TableauPdf(
          titre: 'PASSIF (Ressources)',
          colonnes: const [
            ColonnePdf('Rubrique', largeur: 5),
            ColonnePdf('Montant', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: postes(bilan.passif),
          pied: [
            const CellulePdf('TOTAL GÉNÉRAL PASSIF'),
            CellulePdf(_montant(bilan.totalPassif)),
          ],
          note: bilan.estEquilibre
              ? 'Actif = Passif : le bilan est équilibré.'
              : 'ATTENTION — Déséquilibre de '
                    '${Formats.montant((bilan.totalActif - bilan.totalPassif).abs())} '
                    'entre l\'actif et le passif.',
        ),
      ],
    );
  }

  /// `exportBilanPdf()` de `bilan-entreprise.html` — la version 7 lignes.
  ///
  /// Distincte de [bilan] : celle-ci nomme les comptes réels et affiche l'écart
  /// éventuel au lieu de le fondre dans le capital. Voir
  /// `BilanEntrepriseCalculator`.
  static DocumentPdf bilanEntreprise(ComptabiliteViewModel vm) {
    final b = vm.bilanEntreprise;

    List<List<CellulePdf>> postes(List<PosteBilanEntreprise> liste) => [
      for (final p in liste)
        [
          CellulePdf('${p.libelle}  (${p.compte})'),
          _cellMontant(p.montant),
        ],
    ];

    return DocumentPdf(
      titre: 'Bilan de l\'Entreprise',
      periode: 'Exercice ${vm.exercice} — au ${Formats.date(DateTime.now())}',
      indicateurs: [
        IndicateurPdf('Total Actif', Formats.montant(b.totalActif)),
        IndicateurPdf('Total Passif', Formats.montant(b.totalPassif)),
        IndicateurPdf(
          'Équilibre',
          b.estEquilibre ? 'Vérifié' : 'Écart ${Formats.montant(b.ecart.abs())}',
        ),
      ],
      messageSiVide:
          'Aucune écriture sur l\'exercice : il n\'y a encore ni bien à '
          'inscrire à l\'actif, ni dette au passif.',
      tableaux: [
        TableauPdf(
          titre: 'ACTIF',
          colonnes: const [
            ColonnePdf('Poste', largeur: 5),
            ColonnePdf('Montant', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: postes(b.actif),
          pied: [
            const CellulePdf('TOTAL ACTIF'),
            CellulePdf(_montant(b.totalActif)),
          ],
        ),
        TableauPdf(
          titre: 'PASSIF',
          colonnes: const [
            ColonnePdf('Poste', largeur: 5),
            ColonnePdf('Montant', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: [
            ...postes(b.passif),
            if (!b.estEquilibre && !b.estVide)
              [
                const CellulePdf('Origine non enregistrée  (a saisir au 101)'),
                _cellMontant(b.ecart),
              ],
          ],
          pied: [
            const CellulePdf('TOTAL PASSIF'),
            CellulePdf(_montant(b.totalPassif)),
          ],
          note: b.estEquilibre
              ? 'Total Actif = Total Passif : equilibre comptable verifie.'
              : 'ECART DE ${Formats.montant(b.ecart.abs())} — '
                    'des biens figurent a l\'actif sans que leur origine ait '
                    'ete enregistree au passif. Saisir l\'apport correspondant '
                    'au compte 101 (Capital) retablit l\'equilibre.',
        ),
      ],
    );
  }

  static DocumentPdf compteDeResultat(ComptabiliteViewModel vm) {
    final cr = vm.compteResultat;

    return DocumentPdf(
      titre: 'Compte de Résultat',
      periode: 'Exercice ${vm.exercice}',
      indicateurs: [
        IndicateurPdf('Total Produits', Formats.montant(vm.totalProduits)),
        IndicateurPdf('Total Charges', Formats.montant(vm.totalCharges)),
        IndicateurPdf('Résultat Net', Formats.montant(cr.resultatNet)),
      ],
      messageSiVide: 'Aucun produit ni charge sur l\'exercice.',
      tableaux: [
        TableauPdf(
          titre: 'Structure en cascade SYSCOHADA',
          colonnes: const [
            ColonnePdf('Poste', largeur: 5),
            ColonnePdf('Montant', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: [
            for (final p in cr.postes)
              [
                CellulePdf(
                  p.detail == null ? p.libelle : '${p.libelle}  (${p.detail})',
                  gras: p.estTotal || p.estSousTotal,
                ),
                _cellMontant(p.montant),
              ],
          ],
          note:
              'Le Résultat Net ci-dessus provient de la même source que celui '
              'du Bilan et du TAFIRE (BR-CPT-005) : les trois états affichent '
              'toujours la même valeur.',
        ),
      ],
    );
  }

  static DocumentPdf tafire(ComptabiliteViewModel vm) {
    final tafire = vm.tafire;
    final ecart = tafire.tresorerieCloture - vm.tresorerie;

    return DocumentPdf(
      titre: 'Tableau des Flux de Trésorerie',
      periode: 'Exercice ${vm.exercice}',
      indicateurs: [
        IndicateurPdf(
          'Trésorerie Ouverture',
          Formats.montant(tafire.tresorerieOuverture),
        ),
        IndicateurPdf('Variation', Formats.montant(tafire.variation)),
        IndicateurPdf(
          'Trésorerie Clôture',
          Formats.montant(tafire.tresorerieCloture),
        ),
      ],
      messageSiVide: 'Aucun flux de trésorerie sur l\'exercice.',
      tableaux: [
        TableauPdf(
          titre: 'TAFIRE simplifié',
          colonnes: const [
            ColonnePdf('Poste', largeur: 5),
            ColonnePdf('Montant', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: [
            for (final p in tafire.postes)
              [
                CellulePdf(
                  p.detail == null ? p.libelle : '${p.libelle}  (${p.detail})',
                  gras: p.estTotal || p.estSousTotal,
                ),
                _cellMontant(p.montant),
              ],
          ],
          note: ecart.abs() < 0.01
              ? 'Contrôle : Trésorerie de clôture = Trésorerie-Actif du Bilan '
                    '(${Formats.montant(vm.tresorerie)}).'
              : 'ATTENTION — Incohérence de ${Formats.montant(ecart.abs())} '
                    'entre la Trésorerie de clôture et la Trésorerie-Actif du '
                    'Bilan.',
        ),
      ],
    );
  }

  static DocumentPdf notesAnnexes(ComptabiliteViewModel vm) {
    final immobilisations = vm.balance.where(
      (l) => l.numeroCompte.startsWith('2'),
    );
    final stocks = vm.balance.where((l) => l.numeroCompte.startsWith('3'));
    final tiers = vm.balance.where(
      (l) =>
          l.numeroCompte.startsWith('4') &&
          (l.finalDebit.abs() >= 0.01 || l.finalCredit.abs() >= 0.01),
    );

    return DocumentPdf(
      titre: 'Notes Annexes',
      periode: 'Exercice ${vm.exercice}',
      paragraphes: [
        const ParagraphePdf('Note 1 — Méthodes Comptables', gras: true),
        ParagraphePdf(
          vm.contenuNote(1).isEmpty
              ? 'Les immobilisations sont amorties selon la méthode linéaire. '
                    'Les stocks sont valorisés au Prix Moyen Pondéré (PMP). La '
                    'monnaie de présentation est le Franc CFA (FCFA), sans '
                    'décimale.'
              : vm.contenuNote(1),
        ),
        const ParagraphePdf('Note 5 — Engagements Hors Bilan', gras: true),
        ParagraphePdf(
          vm.contenuNote(5).isEmpty
              ? 'Néant à la date de clôture de la période présentée.'
              : vm.contenuNote(5),
        ),
      ],
      tableaux: [
        TableauPdf(
          titre: 'Note 2 — Immobilisations',
          colonnes: const [
            ColonnePdf('Nature', largeur: 5),
            ColonnePdf('Brut', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Amort. cumulés',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Net', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: [
            for (final l in immobilisations.where(
              (l) => !l.numeroCompte.startsWith('28'),
            ))
              () {
                final brut = l.finalDebit - l.finalCredit;
                final amort = immobilisations
                    .where(
                      (a) => a.numeroCompte.startsWith(
                        '28${l.numeroCompte.substring(1)}',
                      ),
                    )
                    .fold<double>(0, (s, a) => s + a.finalCredit - a.finalDebit);
                return [
                  CellulePdf(l.libelle),
                  _cellMontant(brut),
                  _cellMontant(amort, teinte: TeintePdf.negative),
                  _cellMontant(brut - amort),
                ];
              }(),
          ],
        ),
        TableauPdf(
          titre: 'Note 3 — Stocks',
          colonnes: const [
            ColonnePdf('Catégorie', largeur: 7),
            ColonnePdf('Valeur', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: [
            for (final l in stocks)
              [
                CellulePdf(l.libelle),
                _cellMontant(l.finalDebit - l.finalCredit),
              ],
          ],
        ),
        TableauPdf(
          titre: 'Note 4 — Créances et Dettes',
          colonnes: const [
            ColonnePdf('Compte', largeur: 2),
            ColonnePdf('Intitulé', largeur: 5),
            ColonnePdf('Nature', largeur: 2),
            ColonnePdf('Montant', alignement: AlignementPdf.droite, largeur: 2),
          ],
          lignes: [
            for (final l in tiers)
              [
                CellulePdf(l.numeroCompte),
                CellulePdf(l.libelle),
                CellulePdf(l.finalDebit.abs() >= 0.01 ? 'Créance' : 'Dette'),
                CellulePdf.montant(
                  Formats.nombre(
                    l.finalDebit.abs() >= 0.01 ? l.finalDebit : l.finalCredit,
                  ),
                  teinte: TeintePdf.negative,
                ),
              ],
          ],
          note:
              'Les notes 2, 3 et 4 sont calculées depuis la Balance : elles ne '
              'peuvent pas contredire le bilan qu\'elles commentent. '
              'L\'ancienneté des créances relève du suivi client (module '
              'Ventes) et ne figure pas ici.',
        ),
      ],
      messageSiVide:
          'Aucun compte de classe 2, 3 ou 4 mouvementé sur l\'exercice.',
    );
  }

  // ------------------------------------------------------------- Clôture

  static DocumentPdf cloture(ComptabiliteViewModel vm) {
    const nomsMois = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];

    return DocumentPdf(
      titre: 'Clôture d\'Exercice ${vm.exercice}',
      periode: 'Exercice ${vm.exercice}',
      indicateurs: [
        IndicateurPdf('Résultat Provisoire', Formats.montant(vm.resultatNet)),
        IndicateurPdf(
          'Balance',
          vm.balanceEstEquilibree ? 'Équilibrée' : 'Déséquilibrée',
        ),
        IndicateurPdf(
          'Exercice',
          vm.exerciceEstCloture ? 'Clôturé' : 'En cours',
        ),
      ],
      tableaux: [
        TableauPdf(
          titre: 'État des clôtures périodiques',
          colonnes: const [
            ColonnePdf('Mois', largeur: 3),
            ColonnePdf('État', largeur: 2),
          ],
          lignes: [
            for (var mois = 1; mois <= 12; mois++)
              [
                CellulePdf(nomsMois[mois - 1]),
                CellulePdf(
                  (vm.cloturesMois[mois] ?? false) ? 'Clôturé' : 'Ouvert',
                  teinte: (vm.cloturesMois[mois] ?? false)
                      ? TeintePdf.attenuee
                      : TeintePdf.normale,
                ),
              ],
          ],
          note: vm.balanceEstEquilibree
              ? 'La balance est équilibrée : la clôture annuelle est possible.'
              : 'Une clôture est impossible tant que la balance présente un '
                    'écart de ${Formats.montant(vm.balanceEcart.abs())} '
                    '(BR-CPT-004).',
        ),
      ],
    );
  }

  // ---------------------------------------------------------- Analytique

  static DocumentPdf analytique(ComptabiliteViewModel vm) {
    final centres = vm.centresAnalytiques;
    final totalRevenus = centres.fold<double>(0, (s, c) => s + c.revenus);
    final totalCouts = centres.fold<double>(0, (s, c) => s + c.couts);

    return DocumentPdf(
      titre: 'Comptabilité Analytique',
      periode: 'Exercice ${vm.exercice}',
      messageSiVide:
          'Aucun produit ni charge d\'exploitation sur l\'exercice.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Centre de Coût / Profit', largeur: 5),
            ColonnePdf('Revenus', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Coûts Directs',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Marge', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Taux de Marge',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
          ],
          lignes: [
            for (final c in centres)
              [
                CellulePdf('${c.nom}  (${c.detail})'),
                _cellMontant(c.revenus, teinte: TeintePdf.positive),
                _cellMontant(c.couts, teinte: TeintePdf.negative),
                _cellMontant(c.marge),
                CellulePdf(
                  c.tauxMarge == null
                      ? '—'
                      : Formats.pourcentage(c.tauxMarge!),
                ),
              ],
          ],
          pied: [
            const CellulePdf('TOTAL'),
            CellulePdf(_montant(totalRevenus)),
            CellulePdf(_montant(totalCouts)),
            CellulePdf(_montant(totalRevenus - totalCouts)),
            CellulePdf(
              totalRevenus.abs() < 0.01
                  ? '—'
                  : Formats.pourcentage(
                      (totalRevenus - totalCouts) / totalRevenus * 100,
                    ),
            ),
          ],
          note:
              'Ventilation par activité, et non par filière : '
              'ECRITURE_COMPTABLE ne porte aucun axe analytique et aucun écran '
              'ne le saisit. Charges de structure non affectées : '
              '${Formats.montant(vm.chargesNonAffectees)}.',
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Dépenses

  static DocumentPdf depenses(ComptabiliteViewModel vm) {
    final depenses = vm.depensesFiltrees;

    return DocumentPdf(
      titre: 'Saisie des Dépenses',
      periode: 'Exercice ${vm.exercice}',
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Dépenses du Mois', Formats.montant(vm.depensesDuMois)),
        IndicateurPdf('Charges Fixes', Formats.montant(vm.chargesFixes)),
        IndicateurPdf(
          'Charges Variables',
          Formats.montant(vm.chargesVariables),
        ),
      ],
      messageSiVide:
          'Aucune dépense enregistrée sur l\'exercice ${vm.exercice}.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('N° Pièce', largeur: 3),
            ColonnePdf('Date', largeur: 2),
            ColonnePdf('Libellé', largeur: 5),
            ColonnePdf('Catégorie', largeur: 5),
            ColonnePdf('Montant', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Statut', largeur: 2),
          ],
          lignes: [
            for (final d in depenses)
              [
                CellulePdf(d.numeroPiece),
                CellulePdf(Formats.date(d.date)),
                CellulePdf(d.libelle),
                CellulePdf(d.categorie),
                CellulePdf.montant(Formats.nombre(d.montant)),
                CellulePdf(
                  d.payee ? 'Payée' : 'En attente',
                  teinte: d.payee ? TeintePdf.normale : TeintePdf.negative,
                ),
              ],
          ],
          pied: [
            CellulePdf('TOTAL (${depenses.length})'),
            const CellulePdf(''),
            const CellulePdf(''),
            const CellulePdf(''),
            CellulePdf(
              _montant(depenses.fold(0, (s, d) => s + d.montant)),
            ),
            const CellulePdf(''),
          ],
        ),
      ],
    );
  }
}
