<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Colonnes JSON -> LONGTEXT sur MySQL (`47r_`).
 *
 * Le type JSON natif de MySQL 8 NORMALISE ce qu'on lui confie : clefs reordonnees (par longueur
 * puis ordre alphabetique), espaces refaits. Sur SQLite et MariaDB (JSON = LONGTEXT) le texte
 * reste identique octet pour octet. Or le projet compare des tableaux entiers (variantes d'une
 * fiche journaliere : un rejeu etait pris pour une nouvelle variante) et garde les saisies du
 * poste telles quelles. LONGTEXT rend les trois moteurs identiques ; le cast `array` des modeles
 * (json_encode / json_decode) ne change pas. MariaDB et SQLite : rien a faire.
 */
return new class extends Migration
{
    private const COLONNES = [
        ['audit_logs', 'detail', true],
        ['demandes_referentiel', 'donnees', false],
        ['fiche_journee', 'variantes', true],
    ];

    public function up(): void
    {
        if (DB::getDriverName() !== 'mysql') {
            return;
        }

        foreach (self::COLONNES as [$table, $colonne, $nullable]) {
            DB::statement("ALTER TABLE `$table` MODIFY `$colonne` LONGTEXT ".($nullable ? 'NULL' : 'NOT NULL'));
        }
    }

    public function down(): void
    {
        // Irreversible a dessein : LONGTEXT contient deja du JSON valide.
    }
};
