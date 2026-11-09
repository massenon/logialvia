<?php

namespace App\Support;

/**
 * Formats d'affichage de la comptabilite (Dart : `Formats` et `communs_compta.dart`).
 * Devise : Franc CFA, separateur de milliers, suffixe « FCFA » APRES le nombre, sans decimale.
 */
final class FormatComptable
{
    /** « 142 000 » — sans suffixe. Arrondi a l'entier, comme `Formats.nombre`. */
    public static function nombre(float|int $valeur): string
    {
        $arrondi = $valeur < 0 ? -round(-$valeur) : round($valeur);

        return number_format($arrondi + 0.0, 0, ',', ' ');
    }

    /** « 142 000 FCFA » */
    public static function montant(float|int $valeur): string
    {
        return self::nombre($valeur).' FCFA';
    }

    /** Un tiret pour zero : une colonne de montants ne crie pas « 0 » a chaque ligne. */
    public static function ouTiret(float|int $valeur): string
    {
        return abs($valeur) < 0.01 ? '—' : self::nombre($valeur);
    }

    /** « 2,1 % » — une decimale. */
    public static function pourcentage(float $valeur): string
    {
        return number_format($valeur, 1, ',', ' ').' %';
    }
}
