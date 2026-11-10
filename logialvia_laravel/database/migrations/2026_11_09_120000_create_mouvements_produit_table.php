<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // FAIT immuable : journal des CORRECTIONS de stock d'un produit vendable. Les
        // ventes et leurs annulations voyagent deja avec leurs lignes (`ventes`) : elles ne
        // sont pas recopiees ici. Historique seulement : jamais applique a un stock
        // (decision du client : « stock propre a chaque poste + journal partage »).
        Schema::create('mouvements_produit', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->dateTime('horodatage', 6);
            $table->uuid('produit_id');
            $table->foreign('produit_id')->references('id')->on('produits_vendables');
            $table->string('article');
            $table->string('motif');
            // Variation SIGNEE du stock du poste d'origine (jamais nulle).
            $table->double('quantite');
            $table->dateTime('serveur_modifie_le', 6)->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('mouvements_produit');
    }
};
