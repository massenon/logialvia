/// Règle commune aux référentiels tirés du serveur (`46_` §2.2 et §9).
///
/// Le serveur gagne — **mais seulement quand il a réellement décidé**. Une ligne
/// que personne n'a jamais modifiée côté serveur porte ses valeurs de
/// **semis** (`updated_at == created_at`) : le web vient d'être installé, vide,
/// alors que le poste, lui, tient les vraies données de l'entreprise. L'absorber
/// effacerait l'IFU, le RCCM et les modules choisis par la Gérante, sans
/// qu'aucun chemin de retour n'existe encore (`POST /sync/demandes`, W4+).
///
/// Elle ne vaut qu'au serveur : une ligne **absente** du poste est toujours
/// créée.
bool serveurADecide(Map<String, dynamic> ligne) {
  final cree = _instant(ligne['created_at']);
  final modifie = _instant(ligne['updated_at']);
  if (cree == null || modifie == null) return false;
  return modifie.isAfter(cree);
}

DateTime? _instant(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// `true`/`false`, `1`/`0`. `null` pour toute autre valeur : l'absorbeur strict
/// refuse alors la ligne au lieu de deviner.
bool? lireBool(Object? v) {
  if (v is bool) return v;
  if (v is num && (v == 0 || v == 1)) return v == 1;
  return null;
}
