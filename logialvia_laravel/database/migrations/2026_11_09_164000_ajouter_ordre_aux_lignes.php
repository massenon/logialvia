<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ordre des lignes (`47r_`) : les lignes ont un UUID pour cle ; SQLite les rendait dans l'ordre
 * d'insertion (rowid), MySQL/InnoDB dans l'ordre de la cle primaire, donc ALEATOIRE. Une colonne
 * `ordre` (rang dans le lot du poste) rend l'ordre identique partout.
 */
return new class extends Migration
{
    private const TABLES = ['lignes_vente', 'lignes_achat', 'lignes_facture'];

    public function up(): void
    {
        foreach (self::TABLES as $nom) {
            if (! Schema::hasColumn($nom, 'ordre')) {
                Schema::table($nom, fn (Blueprint $table) => $table->unsignedSmallInteger('ordre')->default(0));
            }
        }
    }

    public function down(): void
    {
        foreach (self::TABLES as $nom) {
            if (Schema::hasColumn($nom, 'ordre')) {
                Schema::table($nom, fn (Blueprint $table) => $table->dropColumn('ordre'));
            }
        }
    }
};
