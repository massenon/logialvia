<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Devis de prestations (`47a2_`) : FAIT synchronise, dernier ecrivain gagne.
     *
     *  - `reference` est le numero OFFICIEL, jamais renumerote : `DV-P2-2026-001` (poste),
     *    `DV-WEB-2026-001` (web), `DV-2026-001` (poste jamais appaire). `portee_reference` fait l'unicite :
     *    vide pour une reference a code (poste ou WEB), l'identifiant du poste sinon ;
     *  - `statut` : emis, accepte, refuse. « Expire » se deduit de la date, il n'est jamais stocke ;
     *  - `supprime_le` : pierre tombale (la ligne reste, le numero n'est jamais reutilise).
     */
    public function up(): void
    {
        Schema::create('devis', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->string('reference', 40);
            $table->string('portee_reference', 36)->default('');
            $table->string('client');
            $table->string('objet', 500);
            $table->double('montant_estime');
            $table->unsignedInteger('validite_jours')->default(15);
            $table->dateTime('date_emission', 6);
            $table->string('statut', 10)->default('emis');
            $table->dateTime('supprime_le', 6)->nullable();
            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->unique(['portee_reference', 'reference']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('devis');
    }
};
