import '../../../core/formatage/formats.dart';
import '../../../core/pdf/document_pdf.dart';
import '../viewmodels/dashboard_elevage_view_model.dart';

/// Document imprimable du Dashboard Élevage — Doc F2.
///
/// Le prototype affiche un bouton « Exporter PDF » qui appelle
/// `generateOfficialPDF()`. La dette posée à l'implémentation de F2 (« un bouton
/// qui n'exporterait rien serait décoratif ») est levée : le générateur unique
/// existe désormais.
class DocumentsPilotage {
  DocumentsPilotage._();

  static DocumentPdf dashboardElevage(DashboardElevageViewModel vm) {
    final filieres = vm.filieres.where((f) => f.aDesDonnees).toList();
    final effectifTotal = filieres.fold<int>(0, (s, f) => s + f.effectif);

    return DocumentPdf(
      titre: 'Dashboard Élevage — Vue Consolidée',
      orientation: OrientationPdf.paysage,
      indicateurs: [
        IndicateurPdf('Effectif du Cheptel', '$effectifTotal'),
        IndicateurPdf('Filières Suivies', '${filieres.length}'),
        IndicateurPdf('Revenus Élevage', Formats.montant(vm.revenusElevage)),
        IndicateurPdf('Alertes Sanitaires', '${vm.alertesSanitaires.length}'),
      ],
      messageSiVide:
          'Aucune journée d\'élevage saisie. Le recensement se construit à '
          'partir des fiches journalières.',
      tableaux: [
        TableauPdf(
          titre: 'Recensement par filière',
          colonnes: const [
            ColonnePdf('Filière', largeur: 4),
            ColonnePdf(
              'Effectif',
              alignement: AlignementPdf.droite,
              largeur: 2,
            ),
            ColonnePdf('Matures', alignement: AlignementPdf.droite, largeur: 2),
            ColonnePdf('Jeunes', largeur: 3),
            ColonnePdf(
              'Taux de Mortalité',
              alignement: AlignementPdf.droite,
              largeur: 3,
            ),
          ],
          lignes: [
            for (final f in filieres)
              [
                CellulePdf(f.libelle, gras: true),
                CellulePdf('${f.effectif}'),
                CellulePdf('${f.effectifMatures}', teinte: TeintePdf.positive),
                CellulePdf('${f.effectifJeunes} ${f.libelleJeunes}'),
                CellulePdf(
                  Formats.pourcentage(f.tauxMortalite),
                  teinte: f.tauxMortalite > 0
                      ? TeintePdf.negative
                      : TeintePdf.normale,
                ),
              ],
          ],
          note:
              'Les coûts par filière ne sont pas calculables : le modèle ne '
              'rattache aucune charge à une espèce.',
        ),
        TableauPdf(
          titre: 'Prochains soins programmés',
          colonnes: const [
            ColonnePdf('Date Prévue', largeur: 2),
            ColonnePdf('Espèce', largeur: 3),
            ColonnePdf('Type de Soin', largeur: 5),
            ColonnePdf('Statut', alignement: AlignementPdf.centre, largeur: 2),
          ],
          lignes: [
            for (final s in vm.prochainsSoins)
              [
                CellulePdf(Formats.date(s.datePrevue)),
                CellulePdf(s.espece),
                CellulePdf(s.typeSoin),
                CellulePdf(s.statut),
              ],
          ],
        ),
      ],
    );
  }
}
