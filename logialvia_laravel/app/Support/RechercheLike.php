<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;

/**
 * Recherche « contient » PORTABLE (SQLite, MySQL, MariaDB).
 *
 * L'ancien `escape '\'` cassait MySQL/MariaDB : le antislash y est lui-meme un caractere
 * d'echappement du litteral (`'\'` ne se ferme plus). On echappe donc avec `!`, neutre partout.
 * Les jokers `%` et `_` saisis par l'utilisateur restent litteraux.
 * Casse : insensible sur les trois moteurs (accents aussi sur MySQL `utf8mb4_unicode_ci`).
 */
final class RechercheLike
{
    private const ECHAPPEMENT = '!';

    /** Motif « contient `$terme` », jokers litteraux. */
    public static function motif(string $terme): string
    {
        return '%'.str_replace(['!', '%', '_'], ['!!', '!%', '!_'], $terme).'%';
    }

    /**
     * Ajoute au constructeur « (col1 like %t% ou col2 like %t% ...) ». Sans terme : rien.
     *
     * @param  \Illuminate\Database\Eloquent\Builder|\Illuminate\Database\Query\Builder  $requete
     * @param  list<string>  $colonnes
     */
    public static function appliquer($requete, array $colonnes, string $terme): void
    {
        $terme = trim($terme);
        if ($terme === '') {
            return;
        }

        $motif = self::motif($terme);
        $grammaire = DB::connection()->getQueryGrammar();
        $requete->where(function ($w) use ($colonnes, $motif, $grammaire) {
            foreach ($colonnes as $colonne) {
                $w->orWhereRaw($grammaire->wrap($colonne).' like ? escape \''.self::ECHAPPEMENT.'\'', [$motif]);
            }
        });
    }
}
