<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Parametres de l'entreprise — UNE seule ligne. Miroir des colonnes NON
     * SECRETES de `PARAMETRES_ENTREPRISE` du poste. Les secrets (mot de passe
     * SMTP, jeton e-MECeF) auront leur propre colonne chiffree avec l'ecran
     * d'administration (`42_`) : jamais ici en clair.
     */
    public function up(): void
    {
        Schema::create('parametres_entreprise', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('raison_sociale')->default('ALLMANY ET COMPAGNIE');
            $table->string('nom_promoteur')->nullable();
            $table->string('adresse_siege')->nullable();
            $table->string('telephone')->nullable();
            $table->string('email')->nullable();
            $table->string('ifu')->nullable();
            $table->string('rccm')->nullable();

            $table->boolean('mecef_actif')->default(false);
            $table->string('mecef_url')->nullable();
            $table->string('mecef_nim')->nullable();

            $table->string('smtp_serveur')->nullable();
            $table->unsignedInteger('smtp_port')->nullable();
            $table->string('smtp_securite', 20)->nullable();

            $table->string('chemin_logo')->nullable();
            $table->string('chemin_favicon')->nullable();
            $table->unsignedInteger('delai_paiement_jours')->nullable();
            $table->boolean('mode_donnees_test')->default(false);

            // Numerotation des bandes et sujets (memes valeurs par defaut que le poste).
            $table->string('prefixe_enclos', 4)->default('E');
            $table->string('prefixe_cage', 4)->default('C');
            $table->string('prefixe_bande', 4)->default('B');
            $table->string('prefixe_bassin', 4)->default('B');
            $table->string('prefixe_bac', 4)->default('BAC');
            $table->string('prefixe_parc', 4)->default('PARC');

            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('parametres_entreprise');
    }
};
