import '../../../core/formatage/formats.dart';
import '../../../core/pdf/document_pdf.dart';
import '../../domain/entities/parametres_elevage.dart';
import '../viewmodels/cycle_couveuse_view_model.dart';
import '../viewmodels/parametres_elevage_view_model.dart';
import '../viewmodels/soins_view_model.dart';

/// Documents imprimables du module Élevage — Doc F3.
///
/// Les 3 états de ce module se **signent** : ce sont des documents de terrain,
/// contresignés par l'animalier et la Gérante. Le bloc de signatures du
/// générateur est donc conservé, contrairement au plan comptable ou à la
/// facture (Doc E9, `signatures` réglé appel par appel).
class DocumentsElevage {
  DocumentsElevage._();

  // ------------------------------------------------------- Cycle Couveuse

  static DocumentPdf couveuse(CycleCouveuseViewModel vm) {
    final cycles = vm.cycles;

    return DocumentPdf(
      titre: 'Cycle Couveuse — Suivi d\'Incubation',
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Cycles en Cours', '${vm.cyclesEnCours}'),
        IndicateurPdf('Poussins Attendus', '${vm.poussinsAttendus}'),
        IndicateurPdf('Cycles Affichés', '${cycles.length}'),
      ],
      messageSiVide:
          'Aucun cycle d\'incubation ne correspond aux filtres retenus.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Code', largeur: 3),
            ColonnePdf('Espèce', largeur: 2),
            ColonnePdf('Mise en Couvoir', largeur: 3),
            ColonnePdf('Éclosion Prévue', largeur: 3),
            ColonnePdf(
              'Œufs Chargés',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Éclos', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Perdus', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf(
              'Taux d\'Éclosion',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 2),
          ],
          lignes: [
            for (final c in cycles)
              [
                CellulePdf(c.code),
                CellulePdf(c.espece.libelle),
                CellulePdf(Formats.date(c.dateChargement)),
                CellulePdf(Formats.date(c.dateEclosionPrevue)),
                CellulePdf('${c.oeufsCharges}'),
                CellulePdf(c.poussinsEclos == null ? '—' : '${c.poussinsEclos}'),
                CellulePdf(
                  c.oeufsPerdus == null ? '—' : '${c.oeufsPerdus}',
                  teinte: (c.oeufsPerdus ?? 0) > 0
                      ? TeintePdf.negative
                      : TeintePdf.normale,
                ),
                CellulePdf(
                  c.tauxEclosion == null
                      ? '—'
                      : Formats.pourcentage(c.tauxEclosion!),
                  teinte: c.tauxEclosion == null
                      ? TeintePdf.attenuee
                      : TeintePdf.positive,
                ),
                CellulePdf(c.statut),
              ],
          ],
          note:
              'La durée d\'incubation dépend de l\'espèce — 21 jours pour un '
              'goliath, 27 pour une pintade. Un taux d\'éclosion vide signifie '
              'que le cycle n\'a pas encore éclos, jamais un échec.',
        ),
      ],
    );
  }

  // -------------------------------------------------- Calendrier de Soins

  static DocumentPdf soins(SoinsViewModel vm) {
    final soins = vm.soins;
    final infirmerie = vm.infirmerie;

    return DocumentPdf(
      titre: 'Calendrier de Soins & Infirmerie',
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Doses (Mois)', '${vm.dosesAdministreesMois}'),
        IndicateurPdf('Planifiées à Venir', '${vm.planifieesAVenir}'),
        IndicateurPdf(
          'En Quarantaine / Traitement',
          '${vm.enQuarantaineOuTraitement}',
        ),
        IndicateurPdf(
          'Coût Vétérinaire (Mois)',
          Formats.montant(vm.coutVeterinaireMois),
        ),
      ],
      messageSiVide:
          'Aucun soin ne correspond aux filtres retenus et l\'infirmerie est '
          'vide.',
      tableaux: [
        TableauPdf(
          titre: 'Soins planifiés et réalisés',
          colonnes: const [
            ColonnePdf('Date Prévue', largeur: 2),
            ColonnePdf('Espèce', largeur: 2),
            ColonnePdf('Type de Soin', largeur: 4),
            ColonnePdf('Produit', largeur: 3),
            ColonnePdf('Dose', largeur: 2),
            ColonnePdf(
              'Rémanence',
              alignement: AlignementPdf.centre,
              largeur: 2,
            ),
            ColonnePdf('Coût', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 2),
          ],
          lignes: [
            for (final s in soins)
              [
                CellulePdf(Formats.date(s.datePrevue)),
                CellulePdf(s.espece),
                CellulePdf(s.typeSoin),
                CellulePdf(s.produit ?? '—'),
                CellulePdf(s.dose ?? '—'),
                CellulePdf(
                  s.remanenceJours > 0 ? '${s.remanenceJours} j' : '—',
                  teinte: s.remanenceJours > 0
                      ? TeintePdf.negative
                      : TeintePdf.attenuee,
                ),
                CellulePdf(
                  s.coutFcfa > 0 ? Formats.nombre(s.coutFcfa) : '—',
                ),
                CellulePdf(
                  s.statut,
                  teinte: s.estEnRetard
                      ? TeintePdf.negative
                      : TeintePdf.normale,
                ),
              ],
          ],
          note:
              'Un délai de rémanence court après l\'administration : les '
              'produits (œufs, viande) ne doivent pas être commercialisés '
              'pendant cette période.',
        ),
        TableauPdf(
          titre: 'Infirmerie & quarantaine',
          colonnes: const [
            ColonnePdf('Date d\'Entrée', largeur: 2),
            ColonnePdf('Lot / Sujet', largeur: 3),
            ColonnePdf('Espèce', largeur: 2),
            ColonnePdf('Motif', largeur: 5),
            ColonnePdf('Isolement', largeur: 2),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 2),
            ColonnePdf('Date de Sortie', largeur: 2),
          ],
          lignes: [
            for (final e in infirmerie)
              [
                CellulePdf(Formats.date(e.dateEntree)),
                CellulePdf(e.sujet),
                CellulePdf(e.espece ?? '—'),
                CellulePdf(e.motif),
                CellulePdf(e.niveauIsolement),
                CellulePdf(e.statut),
                CellulePdf(
                  e.dateSortie == null ? '—' : Formats.date(e.dateSortie!),
                ),
              ],
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------- Paramètres Élevage

  /// Exporte l'onglet affiché — le prototype clone le panneau actif.
  static DocumentPdf parametres(int onglet, ParametresElevageViewModel vm) =>
      switch (onglet) {
        0 => rationnement(vm),
        1 => prophylaxie(vm),
        2 => provende(vm),
        _ => numerotation(vm),
      };

  static DocumentPdf rationnement(ParametresElevageViewModel vm) {
    final baremes = vm.baremesFiltres;

    return DocumentPdf(
      titre: 'Fiche de Rationnement',
      // Un bareme est un referentiel de configuration, pas un releve de terrain.
      signatures: false,
      messageSiVide: 'Aucun barème ne correspond aux filtres retenus.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Espèce', largeur: 3),
            ColonnePdf('Stade Physiologique', largeur: 5),
            ColonnePdf(
              'Ration (g/tête/j)',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
            ColonnePdf('Confirmé ?', largeur: 5),
          ],
          lignes: [
            for (final b in baremes)
              [
                CellulePdf(
                  EspecesParametrables.libelle(b.espece),
                  gras: true,
                ),
                CellulePdf(b.stade),
                CellulePdf.montant('${b.rationGrammesParJour} g/j'),
                CellulePdf(
                  b.badge,
                  teinte: b.confirme
                      ? TeintePdf.positive
                      : TeintePdf.normale,
                ),
              ],
          ],
          note:
              'Ces rations pilotent réellement le calcul de provende des fiches '
              'journalières. Un barème « Générique » reste à valider par la '
              'Gérante.',
        ),
      ],
    );
  }

  static DocumentPdf prophylaxie(ParametresElevageViewModel vm) {
    final echeances = vm.echeancesFiltrees;

    return DocumentPdf(
      titre:
          'Calendrier de Prophylaxie — '
          '${EspecesParametrables.libelle(vm.especeProphylaxie)}',
      signatures: false,
      messageSiVide: 'Aucune échéance ne correspond aux filtres retenus.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf(
              'Jour du Cycle',
              alignement: AlignementPdf.centre,
              largeur: 2,
            ),
            ColonnePdf('Traitement', largeur: 4),
            ColonnePdf('Produit', largeur: 3),
            ColonnePdf('Dose', largeur: 4),
            ColonnePdf(
              'Rémanence',
              alignement: AlignementPdf.centre,
              largeur: 2,
            ),
          ],
          lignes: [
            for (final e in echeances)
              [
                CellulePdf(e.libelleJour, gras: true),
                CellulePdf(e.traitement),
                CellulePdf(e.produit),
                CellulePdf(e.dose ?? '—'),
                CellulePdf(
                  e.remanenceJours > 0 ? '${e.remanenceJours} j' : '—',
                  teinte: e.remanenceJours > 0
                      ? TeintePdf.negative
                      : TeintePdf.attenuee,
                ),
              ],
          ],
          note:
              'Référentiel des soins à programmer. L\'injection automatique '
              'dans les fiches journalières suppose une date de mise en bande '
              'que le modèle de données ne stocke pas.',
        ),
      ],
    );
  }

  static DocumentPdf provende(ParametresElevageViewModel vm) {
    final provendes = vm.provendesFiltrees;

    return DocumentPdf(
      titre: 'Intrants de Provende',
      signatures: false,
      messageSiVide: 'Aucun intrant de provende ne correspond à la recherche.',
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Type d\'Intrant', largeur: 5),
            ColonnePdf(
              'Stock Actuel',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
            ColonnePdf(
              'Seuil d\'Alerte',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
            ColonnePdf(
              'Prix Indicatif (FCFA/Kg)',
              alignement: AlignementPdf.droite,
              largeur: 4,
            ),
          ],
          lignes: [
            for (final p in provendes)
              [
                CellulePdf(p.nom, gras: true),
                CellulePdf(
                  '${Formats.nombre(p.stock)} ${p.unite}',
                  teinte: p.critique
                      ? TeintePdf.negative
                      : TeintePdf.normale,
                ),
                CellulePdf(
                  '${Formats.nombre(p.seuil)} ${p.unite}',
                ),
                CellulePdf(Formats.nombre(p.prixIndicatif)),
              ],
          ],
          note:
              'La quantité en stock ne se saisit pas : elle ne bouge que par '
              'une réception de commande, une fabrication de provende ou un '
              'ajustement d\'inventaire, chacun laissant sa trace. Le prix '
              'indicatif est le Prix Moyen Pondéré réellement calculé par le '
              'module Approvisionnement.',
        ),
      ],
    );
  }

  static DocumentPdf numerotation(ParametresElevageViewModel vm) {
    final formats = vm.formats;

    return DocumentPdf(
      titre: 'Numérotation des Bandes et Sujets',
      signatures: false,
      tableaux: [
        TableauPdf(
          colonnes: const [
            ColonnePdf('Filière', largeur: 5),
            ColonnePdf('Convention', largeur: 3),
            ColonnePdf('Préfixe', largeur: 2),
            ColonnePdf('Aperçu', largeur: 4),
          ],
          lignes: [
            [
              const CellulePdf('Aviculture (Goliaths & Pintades)'),
              const CellulePdf('Enclos'),
              CellulePdf(formats.enclos, gras: true),
              CellulePdf(formats.apercuEnclos),
            ],
            [
              const CellulePdf('Cuniculture (Lapins)'),
              const CellulePdf('Cage'),
              CellulePdf(formats.cage, gras: true),
              CellulePdf(formats.apercuCage),
            ],
            [
              const CellulePdf('Cuniculture (Lapins)'),
              const CellulePdf('Bande'),
              CellulePdf(formats.bande, gras: true),
              CellulePdf(formats.apercuBande),
            ],
            [
              const CellulePdf('Pisciculture (Poissons-Chats)'),
              const CellulePdf('Bassin'),
              CellulePdf(formats.bassin, gras: true),
              CellulePdf(formats.apercuBassin),
            ],
            [
              const CellulePdf('Héliciculture (Escargots)'),
              const CellulePdf('Bac'),
              CellulePdf(formats.bac, gras: true),
              CellulePdf(formats.apercuBac),
            ],
            [
              const CellulePdf('Élevage ovin (Ovins)'),
              const CellulePdf('Parc'),
              CellulePdf(formats.parc, gras: true),
              CellulePdf(formats.apercuParc),
            ],
          ],
        ),
      ],
    );
  }
}
