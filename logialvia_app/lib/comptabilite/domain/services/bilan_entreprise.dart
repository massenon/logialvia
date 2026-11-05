import 'moteur_comptable.dart';

/// # Bilan de l'Entreprise — la version lisible du bilan
///
/// Porté de `prototype_html/bilan-entreprise.html`.
///
/// ## Pourquoi un second bilan
///
/// Doc F6 §1 avait absorbé cet écran dans l'onglet « Bilan » des États
/// Financiers. C'était une erreur d'analyse : les deux ne s'adressent pas aux
/// mêmes yeux.
///
/// | | États Financiers → Bilan | Bilan de l'Entreprise |
/// |---|---|---|
/// | Destinataire | le comptable, l'administration fiscale | la Gérante |
/// | Structure | rubriques SYSCOHADA, sous-totaux, Actif Immobilisé / Circulant / Trésorerie | **7 lignes**, une par poste réel |
/// | Question posée | « mes états sont-ils conformes ? » | « **qu'est-ce que je possède, qu'est-ce que je dois ?** » |
///
/// Supprimer le second au motif que le premier contient les mêmes chiffres,
/// c'est confondre l'information et sa présentation. On rétablit l'écran.
///
/// ## ⚠️ Le Capital Initial du prototype est une variable d'ajustement
///
/// `bilan-entreprise.html` l.14 :
///
/// ```js
/// var capitalInitial = totalActif - dettesFournisseurs - resultatNet;
/// ```
///
/// Le capital n'est pas lu : il est **déduit** de ce qu'il faut pour que
/// l'égalité tombe juste. Avec des chiffres écrits à la main, le bandeau vert
/// « Bilan équilibré » est donc garanti — il ne vérifie rien.
///
/// On ne reproduit pas ce calcul. Le capital est lu au **compte 101**, comme
/// tout autre poste. Trois conséquences assumées :
///
/// 1. Si aucun apport n'a été saisi au 101, l'Actif dépasse le Passif.
/// 2. L'écart est alors affiché **en clair, sur sa propre ligne**, au lieu
///    d'être fondu dans le capital.
/// 3. Le bandeau devient un vrai contrôle — il peut passer au rouge.
///
/// L'écart n'est pas une anomalie de calcul : c'est de l'argent dont l'origine
/// n'a pas été enregistrée. Le dire est le seul service utile à rendre.
/// Le masquer, c'est le pattern `validateSale()` que le Cahier des Charges
/// §2.3 interdit — un écran qui affiche « tout va bien » sans l'avoir établi.
class BilanEntrepriseCalculator {
  const BilanEntrepriseCalculator();

  BilanEntreprise calculer(SoldesComptes soldes) {
    // ------------------------------------------------------------------ ACTIF
    // Les 4 postes de `bilan-entreprise.html` l.6-11, dans son ordre.
    // Classe 3 : « Stocks (Intrants + Marchandises) », comptes 31 et 32.
    final stocks = soldes.parPrefixe('31') + soldes.parPrefixe('32');
    final clients = soldes.parPrefixe('411');
    final banques = soldes.parPrefixe('512');
    final caisse = soldes.parPrefixe('531');

    final actif = <PosteBilanEntreprise>[
      PosteBilanEntreprise('Stocks (Intrants + Marchandises)', '31/32', stocks),
      PosteBilanEntreprise('Clients (Solde Restant Dû)', '411', clients),
      PosteBilanEntreprise('Banques — Mobile Money', '512', banques),
      PosteBilanEntreprise('Caisse', '531', caisse),
    ];
    final totalActif = stocks + clients + banques + caisse;

    // ----------------------------------------------------------------- PASSIF
    // Comptes de passif : crediteurs, donc de solde negatif dans la convention
    // debit-credit de `SoldesComptes`. On les presente en positif.
    final capital = -soldes.parPrefixe('101');
    final resultatNet = CalculerResultatNet.calculer(soldes);
    final fournisseurs = -soldes.parPrefixe('401');

    final passif = <PosteBilanEntreprise>[
      PosteBilanEntreprise('Capital Initial', '101', capital),
      PosteBilanEntreprise('Résultat de l\'Exercice', '13', resultatNet),
      PosteBilanEntreprise('Fournisseurs (Dettes)', '401', fournisseurs),
    ];
    final totalPassif = capital + resultatNet + fournisseurs;

    return BilanEntreprise(
      actif: actif,
      passif: passif,
      totalActif: totalActif,
      totalPassif: totalPassif,
    );
  }
}

/// Une ligne du bilan : son libellé, le compte qui la porte, son montant.
class PosteBilanEntreprise {
  const PosteBilanEntreprise(this.libelle, this.compte, this.montant);

  final String libelle;
  final String compte;
  final double montant;
}

class BilanEntreprise {
  const BilanEntreprise({
    required this.actif,
    required this.passif,
    required this.totalActif,
    required this.totalPassif,
  });

  final List<PosteBilanEntreprise> actif;
  final List<PosteBilanEntreprise> passif;
  final double totalActif;
  final double totalPassif;

  /// Actif − Passif. Positif : des biens dont l'origine n'est pas enregistrée.
  double get ecart => totalActif - totalPassif;

  /// Tolérance au centime — les arrondis d'une division de TVA ou d'un CMUP ne
  /// doivent pas déclencher une alerte.
  bool get estEquilibre => ecart.abs() < 0.01;

  /// Un bilan **vide** n'est pas un bilan équilibré : c'est un exercice sans
  /// écriture. Le distinguer évite d'afficher « équilibré » sur du néant.
  bool get estVide => totalActif.abs() < 0.01 && totalPassif.abs() < 0.01;
}
