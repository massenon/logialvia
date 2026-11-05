import 'approvisionnement.dart';

/// Fabrication de provende — `#modal-fabrication` de `gestion-stocks.html`.
///
/// ## Pourquoi cette opération existe
///
/// La note de la modale invoque une exigence contractuelle :
///
/// > « Toute sortie d'intrant pour la fabrication de provende doit être
/// > justifiée par cette opération — **jamais une simple sortie de stock
/// > isolée** (Cahier des Charges Technique §6.2, §8.3). »
///
/// Autrement dit : on ne sort pas 25 kg de maïs « comme ça ». Une sortie
/// d'intrant de provende est toujours la contrepartie d'une fabrication, et les
/// 5 intrants sont décrémentés **en une seule opération**, jamais séparément.
///
/// ## ⚠️ Ce que le prototype ne fait pas
///
/// `confirmFabrication()` affiche `showToast('Fabrication de provende
/// enregistrée — stocks des 5 intrants décrémentés automatiquement.')` puis
/// **ne décrémente rien**. Le toast annonce une écriture qui n'a pas lieu : le
/// patron interdit par le Master Prompt §2.3, aggravé ici par un message qui
/// affirme le contraire de ce qui se passe.
class FabricationProvende {
  const FabricationProvende(this.quantites);

  /// Quantité en kg par code d'intrant. Une entrée à 0 est ignorée.
  final Map<String, double> quantites;

  /// Composition retenue — les seules lignes qui seront réellement sorties.
  Map<String, double> get composition => {
    for (final entree in quantites.entries)
      if (entree.value > 0) entree.key: entree.value,
  };

  /// « Total Provende Fabriquée », en kg.
  double get totalKg => composition.values.fold(0, (s, q) => s + q);

  bool get estVide => composition.isEmpty;

  /// Intrants dont la quantité demandée dépasse le stock disponible.
  ///
  /// Le prototype liste les manquants avec leur disponible entre parenthèses
  /// (« Maïs (18 kg dispo) ») — ce libellé est repris tel quel.
  List<String> manquants(List<Intrant> intrants) {
    final parCode = {for (final i in intrants) i.code: i};
    final resultat = <String>[];
    for (final entree in composition.entries) {
      final intrant = parCode[entree.key];
      if (intrant == null) continue;
      if (entree.value > intrant.stock) {
        resultat.add('${intrant.nom} (${intrant.stock} ${intrant.unite} dispo)');
      }
    }
    return resultat;
  }

  /// `null` si la fabrication peut être lancée.
  String? valider(List<Intrant> intrants) {
    if (estVide) {
      return 'Renseignez au moins un intrant pour lancer une fabrication.';
    }
    if (quantites.values.any((q) => q < 0)) {
      return 'Une quantité ne peut pas être négative.';
    }
    final insuffisants = manquants(intrants);
    if (insuffisants.isNotEmpty) {
      return 'Stock insuffisant : ${insuffisants.join(', ')}.';
    }
    return null;
  }

  /// Composition par défaut du prototype — 25/10/5/3/2 kg, soit 45 kg.
  ///
  /// ⚠️ Sur les stocks réels du socle, cette composition est **déjà en
  /// dépassement** : le Maïs n'a que 18 kg pour 25 demandés. Ce n'est pas une
  /// erreur de recopie, c'est l'état du prototype — le Maïs y est justement
  /// l'intrant sous son seuil critique. L'alerte s'affiche donc dès
  /// l'ouverture, ce qui est le comportement attendu.
  static const Map<String, double> compositionParDefaut = {
    'INT-001': 25, // Maïs
    'INT-002': 10, // Soja
    'INT-003': 5, // Coquille d'huître
    'INT-004': 3, // Poudre de poisson
    'INT-005': 2, // Tourteau de palmiste
  };
}
