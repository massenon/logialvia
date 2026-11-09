<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // REFERENTIEL : la grille de taxation. Cle = la LETTRE du groupe (la meme sur tous
        // les postes) ; `id` est un UUID v5 deterministe (`groupe_taxe:<lettre>`), calcule
        // comme au poste. `created_at == updated_at` = valeur de semis, jamais « decidee ».
        Schema::create('groupes_taxe', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('code', 1)->unique();
            $table->string('libelle');
            $table->double('taux');
            $table->unsignedInteger('ordre')->default(0);
            $table->timestamps(6);
            $table->index('updated_at');
        });

        // FAIT : une facture de vente (FV) ou d'avoir (FA), jamais fusionnee. Le contenu est
        // IMMUABLE apres creation (corriger = emettre un avoir) ; seuls le statut et ce que la
        // DGI a rendu evoluent, et le statut ne regresse jamais (a_transmettre < rejetee <
        // normalisee). `reference` est le numero OFFICIEL (DV-21) ; `portee_reference` fait
        // l'unicite (vide pour une reference a code de poste, le poste sinon).
        // Le serveur n'a NI jeton NI URL e-MECeF : il ne transmet jamais a la DGI.
        Schema::create('factures', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->string('reference', 40);
            $table->string('portee_reference', 36)->default('');
            $table->string('type', 2);
            $table->string('vente_ref', 40)->nullable()->index();
            $table->string('origine_ref', 40)->nullable();
            $table->dateTime('date_facture', 6);
            $table->string('client');
            $table->string('client_ifu', 40)->nullable();
            $table->string('client_adresse')->nullable();
            $table->double('total_ht');
            $table->double('total_taxe');
            $table->double('total_ttc');
            $table->string('motif')->nullable();
            $table->string('statut', 20);
            $table->string('code_mecef')->nullable();
            $table->string('nim', 60)->nullable();
            $table->string('compteur', 40)->nullable();
            $table->string('lien_verification', 1000)->nullable();
            $table->dateTime('date_normalisation', 6)->nullable();
            $table->string('erreur_transmission', 1000)->nullable();
            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->unique(['portee_reference', 'reference']);
        });

        Schema::create('lignes_facture', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('facture_id')->constrained('factures')->cascadeOnDelete();
            $table->string('designation');
            $table->double('quantite');
            $table->string('unite', 40)->nullable();
            $table->double('prix_unitaire_ht');
            $table->string('groupe_taxe', 1);
            $table->double('taux_taxe');
            $table->double('montant_ht');
            $table->double('montant_taxe');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('lignes_facture');
        Schema::dropIfExists('factures');
        Schema::dropIfExists('groupes_taxe');
    }
};
