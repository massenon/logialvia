<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Marque de remise a zero : chaque envoi d'un poste porte celle qu'il connait ;
     * une marque inconnue donne 409, pour qu'aucune donnee d'avant une remise a zero
     * ne ressuscite (blueprint §6).
     */
    public function up(): void
    {
        Schema::table('parametres_entreprise', function (Blueprint $table) {
            $table->string('marque_remise_a_zero', 40)->default('initiale');
        });
    }

    public function down(): void
    {
        Schema::table('parametres_entreprise', function (Blueprint $table) {
            $table->dropColumn('marque_remise_a_zero');
        });
    }
};
