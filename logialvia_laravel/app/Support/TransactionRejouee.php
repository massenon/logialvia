<?php

namespace App\Support;

use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Transaction rejouee sur interblocage (`47r_`).
 *
 * MySQL/InnoDB tue l'une de deux transactions qui se verrouillent des lignes en sens inverse
 * (erreur 1213 / SQLSTATE 40001) ; SQLite, qui n'ecrit qu'une transaction a la fois, ne le
 * montre jamais. Plusieurs postes qui envoient en meme temps les memes lignes suffisent.
 * `DB::transaction($f, 3)` rejoue AUSSITOT : les deux transactions se re-heurtent. Ici : jusqu'a
 * [ESSAIS] essais, avec une attente ALEATOIRE croissante (elles se desynchronisent), puis, si
 * l'interblocage persiste, une exception `ServeurOccupe` rendue en 503 + `Retry-After` : le poste
 * rejoue (l'envoi est idempotent), jamais d'erreur 500 muette.
 */
final class TransactionRejouee
{
    public const ESSAIS = 8;

    /**
     * @template T
     *
     * @param  callable(): T  $operation
     * @return T
     */
    public static function executer(callable $operation, int $essais = self::ESSAIS)
    {
        for ($n = 1; ; $n++) {
            try {
                return DB::transaction($operation);
            } catch (QueryException $e) {
                // Deux envois du MEME UUID qui s'executent ensemble (le poste a rejoue apres un delai
                // alors que le premier tourne encore) : les deux ne trouvent rien, les deux inserent,
                // la seconde viole la cle primaire. Rejouee, elle trouve la ligne et applique la
                // regle du dernier ecrivain. Une VRAIE violation se reproduit : 5 essais, puis l'erreur.
                if (self::estDoublon($e) && $n < 6) {
                    usleep(random_int(10_000, 40_000) * $n);

                    continue;
                }
                if (! self::estInterblocage($e)) {
                    throw $e;
                }
                if ($n >= $essais) {
                    throw new ServeurOccupe('Le serveur est occupé (verrou de base de données) : réessayez dans un instant.', 0, $e);
                }
                usleep(random_int(10_000, 40_000) * $n);
            }
        }
    }

    public static function estDoublon(QueryException $e): bool
    {
        return $e instanceof \Illuminate\Database\UniqueConstraintViolationException
            || (int) ($e->errorInfo[1] ?? 0) === 1062;
    }

    public static function estInterblocage(QueryException $e): bool
    {
        $code = (int) ($e->errorInfo[1] ?? 0);

        return (string) $e->getCode() === '40001' || in_array($code, [1213, 1205], true);
    }
}
