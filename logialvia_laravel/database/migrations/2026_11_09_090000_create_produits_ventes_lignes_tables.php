<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // REFERENTIEL : cree/modifie au poste, propose au serveur (demande), redescend.
        // Le STOCK n'y figure volontairement pas : donnee derivee (ventes, achats),
        // jamais synchronisee (`46_` §2.2).
        Schema::create('produits_vendables', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('sku', 40)->nullable();
            $table->string('name');
            $table->string('cat', 80);
            $table->double('price');
            $table->double('price_max')->nullable();
            $table->string('unit', 40);
            $table->string('icon', 80);
            $table->double('cout_revient')->nullable();
            $table->string('groupe_taxe', 5)->default('A');
            $table->unsignedInteger('threshold')->default(0);
            $table->string('espece', 40)->nullable();
            // Instant de SAISIE de la derniere demande acceptee : sert a refuser une
            // demande plus ancienne (dernier ecrivain gagne).
            $table->dateTime('saisi_le', 6);
            $table->timestamps();
            $table->index('updated_at');
        });

        // FAIT : saisi au poste, jamais fusionne. `reference` est le numero OFFICIEL
        // remis au client (DV-21). `portee_reference` fait l'unicite : vide pour une
        // reference a code de poste (unique pour tous), l'identifiant du poste pour une
        // ancienne reference sans code (unique par poste).
        Schema::create('ventes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->string('reference', 40);
            $table->string('portee_reference', 36)->default('');
            $table->string('client');
            $table->foreignUuid('client_id')->nullable()->constrained('clients')->nullOnDelete();
            $table->dateTime('date_vente', 6);
            $table->string('mode', 40);
            $table->string('status', 20);
            $table->double('total');
            $table->double('paye');
            $table->string('motif_annulation')->nullable();
            $table->string('livraison_mode', 40)->nullable();
            $table->double('livraison_frais')->nullable();
            $table->string('livraison_adresse')->nullable();
            $table->string('livraison_contact')->nullable();
            $table->dateTime('echeance', 6)->nullable();
            $table->string('ligne_mobile_money')->nullable();
            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->unique(['portee_reference', 'reference']);
        });

        Schema::create('lignes_vente', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('vente_id')->constrained('ventes')->cascadeOnDelete();
            $table->foreignUuid('produit_id')->constrained('produits_vendables');
            $table->string('name');
            $table->double('qte');
            $table->double('pu');
            $table->string('espece', 40)->nullable();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('lignes_vente');
        Schema::dropIfExists('ventes');
        Schema::dropIfExists('produits_vendables');
    }
};
