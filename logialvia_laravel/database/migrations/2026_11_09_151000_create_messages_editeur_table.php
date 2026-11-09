<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Messages a l'editeur (doc 47u §4, poste v45) : un FAIT saisi au poste ou au web, dernier
     * ecrivain gagne par UUID, comme les clients. AUCUN e-mail n'est envoye : le message est
     * enregistre ; `statut` passe a « Transmis » quand un humain l'a transmis lui-meme.
     * La suppression voyage comme une pierre tombale (`supprime_le`).
     */
    public function up(): void
    {
        Schema::create('messages_editeur', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->nullable();
            $table->dateTime('horodatage', 6);
            // `question` ou `bug` : les deux onglets du formulaire.
            $table->string('type', 10);
            $table->string('sujet');
            $table->text('message');
            $table->text('etapes')->nullable();
            // « Nom (identifiant) — Role » : l'identifiant local d'un poste n'a pas de sens ailleurs.
            $table->string('auteur')->nullable();
            $table->string('statut', 20)->default('En attente');

            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->dateTime('supprime_le', 6)->nullable();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('messages_editeur');
    }
};
