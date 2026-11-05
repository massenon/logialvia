import 'package:flutter/services.dart';

/// Filtres de frappe des champs numériques — **un seul endroit** pour toute
/// l'application.
///
/// ## Pourquoi ils existent
///
/// 43 champs numériques étaient déclarés `keyboardType: TextInputType.number`
/// et **aucun** ne portait d'`inputFormatters`. Sur un poste Windows, le clavier
/// n'est pas contraint : `TextInputType.number` n'est qu'une indication pour les
/// claviers virtuels. Rien n'empêchait donc de taper des lettres, un signe moins
/// ou une phrase entière dans un champ « Nombre d'Œufs ».
///
/// La saisie était ensuite lue par `int.tryParse(...) ?? 0` : une frappe erronée
/// devenait **zéro sans un mot**. Sur une quantité d'œufs chargés ou un effectif,
/// c'est un chiffre faux qui part dans les calculs.
///
/// Le filtrage à la frappe est le seul contrôle qui ne peut pas être contourné
/// par distraction : ce qui ne peut pas être saisi n'a pas à être validé.
class FormatteursSaisie {
  FormatteursSaisie._();

  /// Entiers positifs seuls : ni lettre, ni espace, ni signe, ni séparateur.
  ///
  /// C'est le cas de la très grande majorité des champs — œufs, effectifs,
  /// jours, seuils, quantités, rémanence.
  static const List<TextInputFormatter> entierPositif = [
    _ChiffresSeuls(),
  ];

  /// Chiffres et **un seul** séparateur décimal, virgule ou point.
  ///
  /// Réservé aux montants. Le franc CFA n'a pas de sous-unité en circulation,
  /// mais le modèle stocke des réels (prix, coût de revient, PMP) : interdire
  /// la décimale ici bloquerait une saisie que la base accepte.
  static const List<TextInputFormatter> montant = [
    _MontantPositif(),
  ];
}

/// Ne laisse passer que `0-9`.
class _ChiffresSeuls extends TextInputFormatter {
  const _ChiffresSeuls();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue ancien,
    TextEditingValue nouveau,
  ) {
    final propre = nouveau.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (propre == nouveau.text) return nouveau;
    return _replacer(nouveau, propre);
  }
}

/// Chiffres, plus au maximum un séparateur décimal.
class _MontantPositif extends TextInputFormatter {
  const _MontantPositif();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue ancien,
    TextEditingValue nouveau,
  ) {
    var propre = nouveau.text.replaceAll(RegExp(r'[^0-9.,]'), '');

    // Un seul separateur : les suivants sont ignores plutot que de produire
    // « 12,5,3 », que `double.tryParse` rendrait nul — donc zero, en silence.
    var vu = false;
    final tampon = StringBuffer();
    for (final c in propre.split('')) {
      if (c == ',' || c == '.') {
        if (vu) continue;
        vu = true;
      }
      tampon.write(c);
    }
    propre = tampon.toString();

    if (propre == nouveau.text) return nouveau;
    return _replacer(nouveau, propre);
  }
}

/// Réécrit la valeur en gardant le curseur à une position valide.
///
/// Sans ce recalage, effacer un caractère refusé renverrait le curseur en fin
/// de champ : corriger un chiffre au milieu d'un nombre deviendrait pénible.
TextEditingValue _replacer(TextEditingValue nouveau, String propre) {
  final retires = nouveau.text.length - propre.length;
  final position = (nouveau.selection.baseOffset - retires).clamp(
    0,
    propre.length,
  );
  return TextEditingValue(
    text: propre,
    selection: TextSelection.collapsed(offset: position),
  );
}
