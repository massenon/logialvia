# E9 — Spécification Impression PDF / Facture

Traduction fidèle du pattern déjà construit et validé dans `ventes.html` (`exportFactureVente()` — génère une fenêtre d'impression HTML formatée avec en-tête entreprise, tableau des lignes, total, pied de page).

---

## 1. Packages Requis (rappel de Doc K3/11)

`pdf` (construction du document) + `printing` (aperçu et envoi à l'imprimante système).

---

## 2. Structure de la Facture — fidèle au prototype

```
┌────────────────────────────────────────────────┐
│ ALLMANY ET COMPAGNIE          FACTURE V-2026-XXX │  ← en-tete, 2 colonnes
│ Natitingou, Bénin              JJ/MM/AAAA à HH:MM │
├────────────────────────────────────────────────┤
│ Client : [nom]  |  Règlement : [mode]             │
├────────────────────────────────────────────────┤
│ Article        │ Qté │  PU  │ Total               │  ← en-tete tableau, fond navy, texte blanc
│ ...            │ ... │ ...  │ ...                 │
├────────────────────────────────────────────────┤
│                          TOTAL : XX XXX FCFA       │  ← aligne a droite, gras, vert
├────────────────────────────────────────────────┤
│ LogiALVIA © 2026 — ALLMANY ET COMPAGNIE            │  ← pied de page, petit, gris
└────────────────────────────────────────────────┘
```

---

## 3. Implémentation

```dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class FacturePdfGenerator {
  Future<Uint8List> genererFacture(Vente vente) async {
    final doc = pw.Document();
    final roboto = await PdfGoogleFonts.robotoRegular(); // ou police embarquee locale, Doc 01
    final robotoBold = await PdfGoogleFonts.robotoBold();

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5, // format compact, coherent avec une facture comptoir
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('ALLMANY ET COMPAGNIE', style: pw.TextStyle(font: robotoBold, fontSize: 14)),
              pw.Text('Natitingou, Bénin', style: pw.TextStyle(font: roboto, fontSize: 9)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('FACTURE ${vente.ref}', style: pw.TextStyle(font: robotoBold, fontSize: 11)),
              pw.Text(vente.dateAffichee, style: pw.TextStyle(font: roboto, fontSize: 9)),
            ]),
          ]),
          pw.Divider(color: PdfColor.fromHex('#1F3864')),
          pw.Text('Client : ${vente.client}  |  Règlement : ${vente.mode}',
            style: pw.TextStyle(font: roboto, fontSize: 10)),
          pw.SizedBox(height: 12),
          pw.Table(border: pw.TableBorder.all(color: PdfColor.fromHex('#D8DCE3')), children: [
            pw.TableRow(decoration: pw.BoxDecoration(color: PdfColor.fromHex('#1F3864')),
              children: ['Article', 'Qté', 'PU', 'Total'].map((h) => pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(h, style: pw.TextStyle(font: robotoBold, fontSize: 8, color: PdfColors.white)))).toList()),
            for (final ligne in vente.lignes)
              pw.TableRow(children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(ligne.name, style: pw.TextStyle(font: roboto, fontSize: 9))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${ligne.qte}', style: pw.TextStyle(font: roboto, fontSize: 9))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(formatFCFA(ligne.pu), style: pw.TextStyle(font: roboto, fontSize: 9))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(formatFCFA(ligne.qte * ligne.pu), style: pw.TextStyle(font: robotoBold, fontSize: 9))),
              ]),
          ]),
          pw.SizedBox(height: 12),
          pw.Align(alignment: pw.Alignment.centerRight,
            child: pw.Text('TOTAL : ${formatFCFA(vente.total)}',
              style: pw.TextStyle(font: robotoBold, fontSize: 13, color: PdfColor.fromHex('#3A7D44')))),
          pw.Spacer(),
          pw.Divider(color: PdfColor.fromHex('#D8DCE3')),
          pw.Center(child: pw.Text('LogiALVIA © ${DateTime.now().year} — ALLMANY ET COMPAGNIE',
            style: pw.TextStyle(font: roboto, fontSize: 7, color: PdfColor.fromHex('#6B7280')))),
        ],
      ),
    ));
    return doc.save();
  }
}
```

---

## 4. Déclenchement de l'Impression — 3 modes

Fidèle au comportement `window.onload = function(){ window.print(); ... }` du prototype (impression déclenchée automatiquement à l'ouverture), avec fallback :

```dart
Future<void> imprimerFacture(Vente vente) async {
  final bytes = await FacturePdfGenerator().genererFacture(vente);

  // Mode 1 (par defaut) : boite de dialogue d'impression systeme, equivalent window.print()
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Facture_${vente.ref}.pdf');
}

Future<void> exporterFacturePdf(Vente vente) async {
  // Mode 2 : sauvegarde fichier sans impression directe (repli si aucune imprimante disponible)
  final bytes = await FacturePdfGenerator().genererFacture(vente);
  await Printing.sharePdf(bytes: bytes, filename: 'Facture_${vente.ref}.pdf');
}
```

**Bouton "Imprimer PDF" dans l'UI** : comportement identique à celui du prototype web — même position (bas du volet de détail de vente, Doc E4 §4), même libellé, même icône (`print`), déclenche `imprimerFacture()` au clic.

---

## 5. Autres Documents Imprimables du Système

Le même `FacturePdfGenerator` sert de patron pour les autres exports PDF identifiés dans le prototype (`pdf-export.js` référencé sur les 31 pages) :
- Export de l'Historique des Ventes filtré (tableau complet, pas une facture individuelle)
- Rapports comptables (Journal, Bilan)
- Fiche d'élevage mensuelle imprimable

Chacun réutilise la structure en-tête/tableau/pied de page ci-dessus avec un contenu de tableau différent — **jamais une nouvelle classe de génération PDF par type de document**, un seul générateur paramétré (Strict Avoid §12, zéro duplication).

---

## 6. Constatations d'implémentation (Flutter Desktop) — Strict Avoid §7

Le générateur est livré : `lib/core/pdf/` — `document_pdf.dart` (modèle de contenu), `generateur_pdf.dart` (rendu), `service_impression.dart` (plateforme), `bouton_export_pdf.dart` (widget partagé). **19 écrans** portent désormais un bouton d'export réel.

### 6.1 ⚠️ La facture A5 du §2 n'existe pas

Le §2 décrit une facture **A5** avec sa propre mise en page, présentée comme la traduction de `exportFactureVente()` de `ventes.html`.

Vérification faite : cette fonction n'existe pas. `ventes.html` expose `downloadInvoice()`, qui appelle **`generateOfficialPDF()`** — le même générateur que les 23 autres boutons d'export du prototype. Il n'y a qu'**un seul document type** : A4, en-tête officiel, bandeau de titre, corps, pied de page. La facture n'en est qu'un cas particulier, distingué par `signatures: false`.

Le §5 avait donc raison sur le principe (« jamais une nouvelle classe de génération PDF par type de document ») mais le §2 se trompait de gabarit. C'est la mise en page réelle de `generateOfficialPDF` (`assets/js/common.js` l.405-467) qui est reproduite, couleur par couleur.

### 6.2 ⚠️ `PdfGoogleFonts` télécharge la police — inutilisable ici

Le §3 propose `PdfGoogleFonts.robotoRegular()`. Cet appel **va chercher la police sur Internet**. Sur une exploitation de Natitingou sans connexion garantie, l'export échouerait au moment précis où l'on en a besoin. Le prototype ne fait d'ailleurs pas mieux : sa feuille d'impression déclare `font-family: Arial, sans-serif`, pas Roboto.

La police est donc lue dans les **assets** du logiciel : aucun réseau, aucune dépendance à un service tiers.

### 6.3 ⚠️ Ce que Helvetica coûtait — et ce que Roboto corrige

Les documents ont d'abord été composés avec les polices de base PDF (Helvetica), embarquées dans tout lecteur et gratuites en poids. Constat obtenu à l'exécution, pas supposé : Helvetica couvre Latin-1 — les accents français passent (é, à, ç, è, ô, «, ») — mais **rien au-delà**. Le paquet `pdf` avertit alors « Unable to find a font to draw » et laisse un **blanc** dans le document. Sur un état officiel signé, porté à la banque ou à l'administration, c'est un trou.

Or ces caractères sont partout dans l'interface : le tiret cadratin de « Poussins — Éligible à la Vente », la flèche de « Goliathau (0 → 4 mois) », le « ≥ 2,8 kg », les œufs, l'apostrophe typographique, l'euro.

**Roboto est désormais embarqué** (`assets/fonts/Roboto-Regular.ttf` et `Roboto-Bold.ttf`, Apache 2.0). Vérification faite dans la table de caractères des deux graisses, pas supposée :

| Caractère | Helvetica | Roboto |
|---|---|---|
| `—` `–` `…` `•` | blanc | **rendu** |
| `Œ` `œ` | blanc | **rendu** |
| `≥` `≤` `≠` | blanc | **rendu** |
| `‘` `’` `“` `”` | blanc | **rendu** |
| `€` `№` | blanc | **rendu** |
| `→` `←` | blanc | blanc |
| `ᵉ` `ʳ` `ᵐ` | blanc | blanc |
| espace fine insécable, `✓` | blanc | blanc |

`GenerateurPdf.normaliserPourRoboto` ne substitue donc **que ce qui manque réellement** — aujourd'hui les flèches, les exposants, l'espace fine et la coche. Elle interroge pour cela la table de la police **embarquée** (`TtfParser.charToGlyphIndexMap`) plutôt qu'une liste écrite à la main : le jour où la police change, la substitution suit toute seule. Un caractère absent de la police **et** de la table de repli devient « ? » : visible, donc signalé, plutôt que supprimé en silence.

La normalisation reste appliquée **au moment du rendu et à cet endroit seulement** : l'écran garde sa typographie.

### 6.3-bis Pourquoi la série statique ici, et la variable dans l'interface

L'interface utilise la fonte **variable** Roboto (axe `wght` 100–900), sans quoi les graisses 600 et 800 — posées 45 fois dans le code et 442 fois dans le prototype — seraient approchées par leur voisine.

L'export PDF, lui, prend la série **statique** Regular/Bold. Le paquet `pdf` embarque les contours `glyf` tels quels : d'une fonte variable il ne tirerait que son **instance par défaut** (400). Le gras des titres, des en-têtes de tableau et des totaux deviendrait identique au corps de texte, et la hiérarchie du document disparaîtrait. Deux vraies fontes évitent le pari.

### 6.4 Bogue de pagination trouvé et corrigé

Un `pw.Table` enveloppé dans une `pw.Column` devient **indivisible** pour `MultiPage` : au-delà d'une page, la pagination boucle et le paquet lève `PdfTooBigPageException`. Un journal comptable de 200 lignes est un cas parfaitement ordinaire — le test qui en génère 200 a révélé le défaut. Les tableaux sont désormais rendus à plat, en liste de widgets de premier niveau.

Dans le même esprit, `context.pageNumber` n'est **pas** disponible dans le `build` d'un `MultiPage` (il l'est dans `header`/`footer`, appelés page par page) : y accéder lève une erreur de nullité.

### 6.5 Ajouts par rapport au prototype, motivés

| Ajout | Pourquoi |
|---|---|
| **Pagination** « Page n / N » en pied | Le prototype imprime une page unique. Un état de plusieurs pages sans numéro est inexploitable |
| **En-tête réellement composée** | Le prototype code « Gérante : SIDI ALI Raïmatou » et « Généré par : Administratrice » **en dur**. Un document imprimé par l'Agent de Vente porterait quand même « Administratrice » : sur un état signé, c'est une fausse attribution. Les 3 lignes viennent de `PARAMETRES_ENTREPRISE` et de la session ouverte |
| **IFU / RCCM** dans l'en-tête | Renseignés en Paramètres Généraux, ils n'apparaissaient nulle part à l'impression alors qu'ils sont les mentions légales obligatoires |
| **Message d'état vide** | Un état sans aucune ligne dit **pourquoi**, il ne sort pas une page blanche (Master Prompt §2.2) |
| **Note de bas de tableau** | Porte sur le papier les limites déjà énoncées à l'écran (échéances non saisies, CMUP au prix de vente, ventilation par activité et non par filière). Un état imprimé qui tait ce que l'écran signale induirait son lecteur en erreur |
| **Nom de fichier normalisé** | `LogiALVIA_Balance_Generale.pdf` — accents et ponctuation retirés, valide sur tout système de fichiers |

### 6.6 Les 19 écrans branchés

| Module | Écrans | Particularité |
|---|---|---|
| **F2 Pilotage** | Dashboard Élevage | Dette `TODO(dette)` du code levée |
| **F3 Élevage** | Cycle Couveuse, Calendrier de Soins, Paramètres Élevage | Paramètres exporte l'**onglet affiché** (4 documents) |
| **F4 Commercial** | Ventes (Historique), détail de vente (**Facture**), Clients & Créances, Catalogue | Dette `TODO(dette)` du détail de vente levée |
| **F5 Approvisionnement** | Gestion des Stocks, Achats & Commandes, Fournisseurs | |
| **F6 Comptabilité** | Journal, Grand Livre, Balance, Plan Comptable, États Financiers, Clôture, Analytique, Dépenses | États Financiers exporte l'**onglet actif** (4 documents) |
| **F7 Rapports** | Rapports & États | Un bouton, 6 documents selon l'onglet |

Chaque écran construit un `DocumentPdf` **au moment du clic**, jamais à l'avance : l'export reflète les filtres et la période en vigueur à cet instant, exactement comme le prototype qui clone le panneau DOM affiché.

Le bloc de signatures est réglé document par document, comme le fait le prototype : présent sur les états de gestion et la lettre de relance, absent de la facture, du plan comptable et des référentiels de paramétrage.

### 6.7 Non implémenté, signalé

- **La lettre de relance** (`DocumentsCommercial.lettreRelance`) est construite et prête, mais n'est branchée à aucun bouton : l'écran Clients & Créances de F4 n'expose pas d'action par ligne pour l'instant. Le document existe, il reste à lui donner son point d'entrée.
- **Le logo** de l'en-tête du prototype (`assets/images/favicon.svg`) n'est pas repris : `PARAMETRES_ENTREPRISE.cheminLogo` existe mais aucun fichier n'est encore importé, et le paquet `pdf` ne lit pas le SVG sans dépendance supplémentaire.

### 6.8 État de vérification

| Contrôle | Résultat |
|---|---|
| `flutter analyze` | **0 problème** |
| `flutter test` | **370 tests, 370 réussis** (12 nouveaux sur le générateur) |
| `flutter build windows --debug` | compilé, application relancée avec le greffon `printing` chargé |
| PDF réel produit | Balance Générale de 60 lignes, multi-pages, A4 paysage — 12 344 octets, en-tête `%PDF-1.5` et `%%EOF` conformes |
| Schéma | **inchangé (v13)** — ce chantier ne touche à aucune table |
