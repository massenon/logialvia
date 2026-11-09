/// Normalise l'adresse du serveur saisie par la Gérante (`46_` §4, blueprint §2).
///
/// - le schéma est ajouté s'il manque : **`http://` pour un réseau local**
///   (`localhost`, `127.*`, `10.*`, `192.168.*`, `172.16-31.*`, nom sans point),
///   **`https://` sinon** ;
/// - les `/` finaux sont retirés ;
/// - `null` si l'adresse est vide, n'a pas d'hôte ou utilise un autre schéma.
String? normaliserAdresseServeur(String saisie) {
  var texte = saisie.trim();
  if (texte.isEmpty) return null;

  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(texte)) {
    texte = '${_estReseauLocal(texte) ? 'http' : 'https'}://$texte';
  }

  final uri = Uri.tryParse(texte);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;

  return texte.replaceAll(RegExp(r'/+$'), '');
}

bool _estReseauLocal(String texte) {
  final hote = texte.split(RegExp(r'[/:]')).first.toLowerCase();
  if (hote == 'localhost' || !hote.contains('.')) return true;
  if (hote.startsWith('127.') ||
      hote.startsWith('10.') ||
      hote.startsWith('192.168.')) {
    return true;
  }
  final m = RegExp(r'^172\.(\d{1,3})\.').firstMatch(hote);
  if (m != null) {
    final second = int.parse(m.group(1)!);
    return second >= 16 && second <= 31;
  }
  return false;
}
