import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import '../resultat/resultat.dart';
import 'document_pdf.dart';
import 'generateur_pdf.dart';

/// Envoi d'un [DocumentPdf] à l'imprimante ou au disque — Doc E9 §4.
///
/// Séparé de [GenerateurPdf] à dessein : la génération est pure et testable
/// (elle rend des octets), l'impression touche la plateforme et ne l'est pas.
class ServiceImpression {
  const ServiceImpression({this.generateur = const GenerateurPdf()});

  final GenerateurPdf generateur;

  /// Mode 1 — boîte de dialogue d'impression du système, équivalent du
  /// `window.print()` déclenché par le prototype à l'ouverture de sa fenêtre.
  ///
  /// L'utilisatrice y voit un aperçu et peut choisir « Enregistrer au format
  /// PDF » si aucune imprimante n'est branchée : le repli est offert par le
  /// système, il n'y a pas à le reconstruire.
  Future<Resultat<void>> imprimer(
    DocumentPdf document, {
    required EnteteOfficielle entete,
  }) async {
    try {
      final octets = await generateur.generer(document, entete: entete);
      await Printing.layoutPdf(
        onLayout: (_) async => octets,
        name: document.nomFichier,
      );
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec impression: $e');
      return const Echec(
        'Le document n\'a pas pu être envoyé à l\'impression.',
      );
    }
  }

  /// Mode 2 — enregistrement du fichier sans passer par l'imprimante.
  Future<Resultat<void>> exporter(
    DocumentPdf document, {
    required EnteteOfficielle entete,
  }) async {
    try {
      final octets = await generateur.generer(document, entete: entete);
      await Printing.sharePdf(bytes: octets, filename: document.nomFichier);
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec export: $e');
      return const Echec('Le document n\'a pas pu être enregistré.');
    }
  }
}
