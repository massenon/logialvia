<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Droits et horloge (`47g_`) : un refus pour droit insuffisant n'est plus JAMAIS memorise (la
 * demande, renvoyee quand le droit est accorde, est jugee de nouveau). Les refus de ce genre
 * deja memorises rendraient pour toujours leur ancien refus a la meme demande (idempotence par
 * UUID) : on les oublie, une seule fois. Les refus definitifs (donnees invalides, stock...)
 * restent.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('demandes_referentiel')
            ->where('statut', 'refusee')
            ->where('motif', 'like', 'Droit insuffisant%')
            ->delete();
    }

    public function down(): void
    {
        // Rien a restaurer : ces refus etaient provisoires par nature.
    }
};
