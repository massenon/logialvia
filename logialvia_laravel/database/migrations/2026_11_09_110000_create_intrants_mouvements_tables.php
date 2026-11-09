<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // REFERENTIEL : cree/modifie au poste, propose au serveur (demande), redescend.
        // Le STOCK et le PMP n'y figurent volontairement pas : chaque poste tient les
        // siens (decision du client : « stock propre a chaque poste + journal partage »).
        // La cle est le CODE de l'intrant (cle naturelle partagee par tous les postes).
        Schema::create('intrants', function (Blueprint $table) {
            $table->string('code', 40)->primary();
            $table->string('name');
            $table->string('cat', 80);
            $table->string('unit', 40);
            $table->unsignedInteger('threshold')->default(0);
            // Instant de SAISIE de la derniere demande acceptee (dernier ecrivain gagne).
            $table->dateTime('saisi_le', 6);
            $table->timestamps();
            $table->index('updated_at');
        });

        // FAIT immuable : le JOURNAL des mouvements. Il est un HISTORIQUE : le serveur
        // l'enregistre et le redistribue, il ne l'applique a aucun stock.
        Schema::create('mouvements_intrant', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->dateTime('horodatage', 6);
            $table->string('intrant_code', 40);
            $table->foreign('intrant_code')->references('code')->on('intrants');
            $table->string('article');
            $table->string('type', 20);
            $table->string('motif');
            $table->double('quantite');
            $table->string('reference', 60)->nullable();
            $table->dateTime('serveur_modifie_le', 6)->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('mouvements_intrant');
        Schema::dropIfExists('intrants');
    }
};
