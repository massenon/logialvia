<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Couveuse (palier 7b, `46b_`) : les incubateurs et les lots d'incubation, avec leurs
     * mirages. Deux FAITS saisis au poste, dernier ecrivain gagne par UUID (comme les
     * clients) ; la suppression d'un lot voyage comme une pierre tombale.
     *
     * Pas de cle etrangere : `machine_id` est verifie dans `CyclesCouveuseTable` (un lot
     * dont l'incubateur est inconnu est refuse avec son motif), et `lot_parent_id` peut
     * arriver AVANT le lot qu'il designe (ordre libre des lots au tirage). La remise a
     * zero efface les tables dans l'ordre de `sync.tables` : une cle etrangere
     * bloquerait la suppression des incubateurs avant celle des lots.
     */
    public function up(): void
    {
        Schema::create('machines_incubateur', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->nullable();
            $table->string('code', 40)->index();
            $table->string('libelle');
            $table->unsignedInteger('capacite_oeufs')->nullable();
            $table->boolean('active')->default(true);

            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->dateTime('supprime_le', 6)->nullable();
        });

        Schema::create('cycle_couveuse', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->nullable();
            // Numero officiel du lot (`C-P2-2026-001`, DV-21 etendu) ; jamais modifie.
            $table->string('code_incubation', 40)->index();
            // Unicite du code : vide pour un code a poste (`C-P2-...`, unique pour tous),
            // identifiant du poste createur sinon (`C-2026-001`, unique par poste). Pose a la
            // creation, jamais modifie.
            $table->string('portee_code', 36)->default('');
            $table->string('espece', 20);
            $table->date('date_incubation');
            $table->unsignedInteger('oeufs_couves');
            $table->unsignedInteger('poussins_nes')->nullable();
            $table->unsignedInteger('oeufs_perdus')->nullable();
            $table->string('statut', 30);
            $table->uuid('machine_id')->nullable();
            // Mirages : saisis dans le temps, `null` = pas encore mire (!= zero oeuf).
            $table->unsignedInteger('oeufs_blancs_j7')->nullable();
            $table->unsignedInteger('oeufs_gates_j14')->nullable();
            $table->uuid('lot_parent_id')->nullable();

            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->dateTime('supprime_le', 6)->nullable();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cycle_couveuse');
        Schema::dropIfExists('machines_incubateur');
    }
};
