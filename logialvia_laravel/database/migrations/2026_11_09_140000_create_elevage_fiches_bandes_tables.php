<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Elevage, palier 7a (`46a_`) : fiches journalieres, compteurs de ventes du jour
     * et bandes. Trois tables de FAITS, mises a jour par « dernier ecrivain gagne ».
     *
     *  - `updated_at`          instant de SAISIE (pose par le poste) : il departage
     *                          deux ecritures ;
     *  - `serveur_modifie_le`  instant de RECEPTION : c'est le curseur du tirage.
     */
    public function up(): void
    {
        // Une ligne par (espece, jour). L'UUID est DETERMINISTE de cette cle : deux
        // postes qui saisissent le meme jour ecrivent la MEME ligne (ligne entiere).
        // `effectif` et ses derives sont les valeurs CALCULEES par le poste qui a saisi.
        Schema::create('fiche_journee', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->nullable();
            $table->string('espece', 30);
            $table->date('date');

            $table->unsignedInteger('achat')->default(0);
            $table->unsignedInteger('ne')->default(0);
            $table->unsignedInteger('vente')->default(0);

            $table->unsignedInteger('mort_cat1')->default(0);
            $table->unsignedInteger('mort_cat2')->default(0);
            $table->unsignedInteger('mort_cat3')->default(0);
            $table->unsignedInteger('mort_cat4')->nullable();
            $table->unsignedInteger('don_cat1')->default(0);
            $table->unsignedInteger('don_cat2')->default(0);
            $table->unsignedInteger('don_cat3')->default(0);
            $table->unsignedInteger('don_cat4')->nullable();

            $table->unsignedInteger('effectif')->default(0);
            $table->unsignedInteger('eff_cat1_day')->default(0);
            $table->unsignedInteger('eff_cat2_day')->default(0);
            $table->unsignedInteger('eff_cat3_day')->default(0);
            $table->unsignedInteger('eff_cat4_day')->nullable();

            // Pondeuses uniquement : saisies (oeufs_*, sorties_plateaux) et resultats calcules.
            $table->unsignedInteger('srh')->nullable();
            $table->unsignedInteger('ts')->nullable();
            $table->unsignedInteger('stock_final_oeufs')->nullable();
            $table->unsignedInteger('oeufs_pondus')->nullable();
            $table->unsignedInteger('oeufs_casses')->nullable();
            $table->unsignedInteger('sorties_plateaux')->nullable();

            $table->unsignedInteger('poids_general_g')->nullable();
            $table->text('traitement_obs')->nullable();
            $table->boolean('traitement_valide')->default(false);
            $table->boolean('is_recorded')->default(false);

            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();

            $table->unique(['espece', 'date']);
        });

        // Compteur CUMULATIF de la caisse : UNE LIGNE PAR POSTE. La lecture somme les
        // lignes du jour ; aucun poste ne reecrit le compteur d'un autre.
        Schema::create('fiche_ventes_jour', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->string('espece', 30);
            $table->date('date');
            $table->unsignedInteger('qte')->default(0);

            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();

            $table->unique(['device_id', 'espece', 'date']);
            $table->index(['espece', 'date']);
        });

        // Une bande : des sujets mis en place a une date. `effectif_initial` est une
        // DECLARATION indicative ; l'effectif reel n'est jamais stocke (il se recalcule
        // des fiches journalieres).
        Schema::create('bandes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->nullable();
            $table->string('espece', 30);
            $table->string('code', 60);
            $table->date('date_mise_en_bande');
            $table->unsignedInteger('effectif_initial')->nullable();
            $table->date('date_cloture')->nullable();
            $table->text('observations')->nullable();

            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();

            $table->unique(['espece', 'code']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('bandes');
        Schema::dropIfExists('fiche_ventes_jour');
        Schema::dropIfExists('fiche_journee');
    }
};
