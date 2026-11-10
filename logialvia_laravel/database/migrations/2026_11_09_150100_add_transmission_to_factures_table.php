<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Verrou de transmission d'une facture emise au WEB (`47a2_`) : le poste qui a reserve sa transmission
     * et jusqu'a quand. Detail d'implementation du serveur : jamais servi aux postes. Ne concerne que les
     * factures dont `device_id` est le poste web ; ne modifie ni leur contenu ni leur curseur de tirage.
     */
    public function up(): void
    {
        Schema::table('factures', function (Blueprint $table) {
            $table->uuid('transmission_poste')->nullable();
            $table->dateTime('transmission_reservee_jusqua', 6)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('factures', function (Blueprint $table) {
            $table->dropColumn(['transmission_poste', 'transmission_reservee_jusqua']);
        });
    }
};
