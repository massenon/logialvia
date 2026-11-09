/// Numéros officiels des pièces commerciales (DV-21, `46_` §3).
///
/// Le préfixe de **poste** fait l'unicité entre postes sans passer par le
/// serveur : `V-P2-2026-001`. Une pièce déjà remise au client ne change jamais
/// de numéro. Un poste **jamais appairé** garde l'ancien format `V-2026-001`.
///
/// Les références existantes restent valides telles quelles ; la séquence est
/// continue **par poste et par année**.
class NumerotationPieces {
  const NumerotationPieces._();

  /// `V-P2-2026-` ou, sans code de poste, `V-2026-`.
  static String prefixeVente(int annee, String? codePoste) =>
      codePoste == null || codePoste.isEmpty
      ? 'V-$annee-'
      : 'V-$codePoste-$annee-';

  /// `ACH-P2-2026-` ou, sans code de poste, `ACH-2026-`. (Le contrat parlait de
  /// `A-…` : le préfixe réel des achats du poste est `ACH`, conservé.)
  static String prefixeAchat(int annee, String? codePoste) =>
      codePoste == null || codePoste.isEmpty
      ? 'ACH-$annee-'
      : 'ACH-$codePoste-$annee-';

  /// Le numéro d'ordre d'une référence qui porte ce [prefixe], ou `null`.
  static int? sequence(String reference, String prefixe) {
    if (!reference.startsWith(prefixe)) return null;
    return int.tryParse(reference.substring(prefixe.length));
  }

  /// `prefixe` + séquence sur 3 chiffres au moins.
  static String composer(String prefixe, int numero) =>
      '$prefixe${numero.toString().padLeft(3, '0')}';
}
