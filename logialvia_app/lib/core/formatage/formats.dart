import 'package:intl/intl.dart';

/// Formats d'affichage transverses — Doc A1 §5 et Doc E6 §6.
///
/// Devise : Franc CFA, separateur de milliers `fr-FR`, suffixe « FCFA »
/// **apres** le nombre — jamais un symbole `$` ou `€`, jamais devant.
class Formats {
  Formats._();

  static final NumberFormat _entier = NumberFormat.decimalPattern('fr_FR');
  static final DateFormat _dateCourte = DateFormat('dd/MM/yyyy', 'fr_FR');
  static final DateFormat _heure = DateFormat('HH:mm', 'fr_FR');

  /// « samedi 15 aout 2026 » — equivalent de `toLocaleDateString('fr-FR', {
  /// weekday, day, month, year })` utilise par `prophylaxie-popup.js`.
  static final DateFormat _dateLongue = DateFormat('EEEE d MMMM yyyy', 'fr_FR');

  /// « 142 000 » — sans suffixe, pour les cas ou l'unite est affichee a part
  /// (KpiCard affiche « FCFA » dans un style plus petit).
  static String nombre(num valeur) => _entier.format(valeur.round());

  /// « 142 000 FCFA »
  static String montant(num valeur) => '${nombre(valeur)} FCFA';

  /// « 2,1 % » — 1 decimale, conformement a Doc E6 §6.
  static String pourcentage(double valeur) =>
      '${valeur.toStringAsFixed(1).replaceAll('.', ',')} %';

  /// « 08/08/2026 »
  static String date(DateTime valeur) => _dateCourte.format(valeur);

  /// « 09:12 »
  static String heure(DateTime valeur) => _heure.format(valeur);

  /// « samedi 15 aout 2026 »
  static String dateLongue(DateTime valeur) => _dateLongue.format(valeur);
}
