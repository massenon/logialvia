<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // FAIT plat : dernier ecrivain gagne par UUID, comme les clients.
        Schema::create('fournisseurs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->string('nom');
            $table->string('telephone', 40)->nullable();
            $table->string('adresse')->nullable();
            $table->string('fournit')->nullable();
            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->dateTime('supprime_le', 6)->nullable();
        });

        // FAIT : un achat et ses lignes forment un lot. `reference` est le numero
        // OFFICIEL (`ACH-P2-2026-001`, DV-21) ; `portee_reference` fait l'unicite (vide
        // pour une reference a code de poste, identifiant du poste sinon).
        Schema::create('achats', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->string('reference', 40);
            $table->string('portee_reference', 36)->default('');
            $table->foreignUuid('fournisseur_id')->constrained('fournisseurs');
            $table->dateTime('date_achat', 6);
            $table->string('statut', 20);
            $table->double('total');
            $table->double('paye')->default(0);
            $table->string('mode', 40)->nullable();
            $table->dateTime('echeance', 6)->nullable();
            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->unique(['portee_reference', 'reference']);
        });

        // `intrant_code` : pas de cle etrangere. Les intrants (et leur stock, leur PMP)
        // ne sont pas encore synchronises : le serveur enregistre le fait d'achat tel
        // que le poste l'a saisi, sans rejouer d'entree de stock.
        Schema::create('lignes_achat', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('achat_id')->constrained('achats')->cascadeOnDelete();
            $table->string('intrant_code', 40);
            $table->string('nom');
            $table->double('qte');
            $table->double('pu_achat');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('lignes_achat');
        Schema::dropIfExists('achats');
        Schema::dropIfExists('fournisseurs');
    }
};
