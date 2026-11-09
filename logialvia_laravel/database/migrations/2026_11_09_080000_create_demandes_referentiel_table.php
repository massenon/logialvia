<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Demandes de modification d'un REFERENTIEL faites au poste (`46_` §4.3). Le poste
     * ne les ecrit jamais : il les PROPOSE, le serveur decide. Le journal garde
     * l'issue de chaque demande, ce qui rend l'envoi idempotent (UUID du poste) :
     * une demande rejouee rend la meme reponse sans rien reappliquer.
     */
    public function up(): void
    {
        Schema::create('demandes_referentiel', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->index();
            $table->string('type', 40);
            $table->string('cle', 80);
            $table->json('donnees');
            $table->dateTime('saisi_le', 6);
            $table->string('statut', 20);
            $table->string('motif')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('demandes_referentiel');
    }
};
