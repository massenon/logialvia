<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * P7c — Elevage : soins, infirmerie (FAITS) et parametres d'elevage (REFERENTIELS).
     * Miroir de `soins_calendrier`, `infirmerie`, `baremes_ration`, `taux_ration_poids`
     * et `calendrier_prophylaxie` du poste (schema v40), voir `46c_`.
     */
    public function up(): void
    {
        // ------------------------------------------------------- REFERENTIELS
        // Crees/modifies au poste, proposes au serveur (demande), redescendent. Le
        // serveur ne les efface jamais : une suppression est une PIERRE TOMBALE
        // (`archive_le`), redistribuee aux postes. `saisi_le` : instant de saisie de la
        // derniere demande acceptee (dernier ecrivain gagne).
        Schema::create('baremes_ration', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('espece', 40);
            $table->string('stade');
            $table->unsignedInteger('ration_grammes_par_jour');
            $table->boolean('confirme')->default(false);
            $table->dateTime('saisi_le', 6);
            $table->dateTime('archive_le', 6)->nullable();
            $table->timestamps();
            $table->index('updated_at');
            $table->unique(['espece', 'stade']);
        });

        Schema::create('taux_ration_poids', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('espece', 40);
            $table->unsignedInteger('poids_min_g');
            $table->unsignedInteger('poids_max_g')->nullable();
            $table->double('taux_pourcent');
            $table->boolean('confirme')->default(false);
            $table->dateTime('saisi_le', 6);
            $table->dateTime('archive_le', 6)->nullable();
            $table->timestamps();
            $table->index('updated_at');
            $table->unique(['espece', 'poids_min_g']);
        });

        Schema::create('calendrier_prophylaxie', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('espece', 40);
            $table->unsignedSmallInteger('jour_cycle');
            $table->string('traitement');
            $table->string('produit');
            $table->unsignedSmallInteger('remanence_jours')->default(0);
            $table->string('dose')->nullable();
            $table->dateTime('saisi_le', 6);
            $table->dateTime('archive_le', 6)->nullable();
            $table->timestamps();
            $table->index('updated_at');
        });

        // --------------------------------------------------------------- FAITS
        // Saisis au poste, rejoues tels quels : dernier ecrivain gagne, par UUID.
        // `updated_at` = instant de SAISIE (pose par le poste) ; `serveur_modifie_le` =
        // instant de RECEPTION, curseur du tirage. `bande_id` n'existe pas : les bandes
        // ne sont pas encore synchronisees. `echeance_prophylaxie_id` est verifie par
        // l'application (l'echeance doit etre connue du serveur), sans cle etrangere :
        // la remise a zero efface les faits, jamais les referentiels.
        Schema::create('soins_calendrier', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->nullable();
            $table->string('espece', 40);
            $table->date('date_prevue');
            $table->string('type_soin');
            $table->string('statut', 40);
            $table->text('observations')->nullable();
            $table->string('produit')->nullable();
            $table->string('dose')->nullable();
            $table->unsignedSmallInteger('remanence_jours')->default(0);
            $table->string('veterinaire')->nullable();
            $table->text('symptomes')->nullable();
            $table->unsignedInteger('cout_fcfa')->default(0);
            $table->uuid('echeance_prophylaxie_id')->nullable();
            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
        });

        Schema::create('infirmerie', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->nullable();
            $table->date('date_entree');
            $table->string('sujet');
            $table->string('motif');
            $table->string('niveau_isolement', 40);
            $table->string('statut', 20);
            $table->date('date_sortie')->nullable();
            $table->string('espece', 40)->nullable();
            $table->unsignedSmallInteger('categorie_mortalite')->nullable();
            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('infirmerie');
        Schema::dropIfExists('soins_calendrier');
        Schema::dropIfExists('calendrier_prophylaxie');
        Schema::dropIfExists('taux_ration_poids');
        Schema::dropIfExists('baremes_ration');
    }
};
