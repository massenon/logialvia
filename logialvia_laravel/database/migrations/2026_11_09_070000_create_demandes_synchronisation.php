<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Le serveur ne joint jamais un poste (eteint, derriere un NAT) : il depose un
     * drapeau que le poste lit (`46_` §4.3). `device_id` NULL = tous les postes.
     * Une demande vaut `expire_le` ; chaque poste la sert UNE fois.
     */
    public function up(): void
    {
        Schema::create('demandes_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->nullable()->index();
            $table->foreignUuid('demandee_par')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('expire_le');
            $table->timestamps();
        });

        Schema::create('demandes_synchronisation_servies', function (Blueprint $table) {
            $table->foreignUuid('demande_id')->constrained('demandes_synchronisation')->cascadeOnDelete();
            $table->uuid('device_id');
            $table->timestamp('servie_le');
            $table->primary(['demande_id', 'device_id']);
        });

        Schema::table('postes', function (Blueprint $table) {
            // Dernier curseur rendu au poste, pose a la DERNIERE page d'un tirage.
            $table->dateTime('curseur_tirage', 6)->nullable();
            // Levee par « Renvoyer vers ce poste » ; abaissee par l'acquittement.
            $table->timestamp('resync_demandee_le')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('postes', function (Blueprint $table) {
            $table->dropColumn(['curseur_tirage', 'resync_demandee_le']);
        });
        Schema::dropIfExists('demandes_synchronisation_servies');
        Schema::dropIfExists('demandes_synchronisation');
    }
};
