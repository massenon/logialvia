/// Pattern uniforme de gestion des erreurs — Doc K1 §8.
/// Evite les exceptions non gerees qui remonteraient jusqu'a l'UI sans message
/// utilisateur clair (Doc G2 §2, aucune action silencieuse — echecs compris).
sealed class Resultat<T> {
  const Resultat();
}

class Succes<T> extends Resultat<T> {
  const Succes(this.valeur);
  final T valeur;
}

class Echec<T> extends Resultat<T> {
  const Echec(this.message);

  /// Message deja traduit et destine a l'utilisateur final — jamais une stack
  /// trace brute (Doc I3 §3).
  final String message;
}
