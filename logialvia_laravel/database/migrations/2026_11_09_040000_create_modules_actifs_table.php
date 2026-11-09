<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Modules (filieres) basculables — miroir de `MODULES_ACTIFS` du poste.
     * Referentiel : le serveur gagne, le poste le recoit (`46_` §2.2).
     * Goliaths et Pintades n'ont volontairement AUCUNE ligne : toujours actifs.
     */
    public function up(): void
    {
        Schema::create('modules_actifs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            // Identifiant technique (jamais un nom d'espece) : `pisciculture`...
            $table->string('module_id', 60)->unique();
            $table->boolean('is_actif')->default(false);
            // Espece de la fiche associee : `poissons-chats`...
            $table->string('espece', 40)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('modules_actifs');
    }
};
