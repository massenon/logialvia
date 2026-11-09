<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * P8 — Comptabilite SYSCOHADA (`46d_`).
 *
 * Des REFERENTIELS (plan, exercices : le serveur gagne), des FAITS IMMUABLES (pieces
 * comptables et leurs lignes, faits de cloture), des faits « dernier ecrivain gagne »
 * (notes annexes, clotures mensuelles). Toutes les dates sont a la microseconde : le
 * curseur de tirage s'y compare.
 */
return new class extends Migration
{
    public function up(): void
    {
        // REFERENTIEL, cle naturelle : le numero de compte (le meme sur tous les postes,
        // plan seme a l'identique). `saisi_le` : instant de SAISIE de la derniere demande
        // acceptee (dernier ecrivain gagne). Un compte jamais decide a
        // `updated_at == created_at` : c'est une valeur de semis.
        Schema::create('plan_comptable', function (Blueprint $table) {
            $table->string('numero_compte', 20)->primary();
            $table->string('libelle');
            $table->string('classe', 1);
            $table->boolean('archive')->default(false);
            $table->dateTime('saisi_le', 6)->nullable();
            $table->timestamps(6);
            $table->index('updated_at');
        });

        // REFERENTIEL, cle naturelle : l'annee. La cloture est POSEE PAR LE SERVEUR
        // (fait lourd `clotures_exercice`) : jamais de declôture (BR-CPT-001).
        Schema::create('exercices_comptables', function (Blueprint $table) {
            $table->unsignedSmallInteger('annee')->primary();
            $table->boolean('is_cloture')->default(false);
            $table->dateTime('date_cloture', 6)->nullable();
            $table->uuid('cloture_par')->nullable();
            $table->timestamps(6);
            $table->index('updated_at');
        });

        // FAIT lourd : la cloture annuelle recue d'un poste (une ligne par annee).
        Schema::create('clotures_exercice', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->unsignedSmallInteger('annee')->unique();
            $table->uuid('device_id');
            $table->uuid('utilisateur_id')->nullable();
            $table->dateTime('date_cloture', 6);
            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
        });

        // FAIT IMMUABLE : l'entete d'une PIECE comptable (partie double). L'identifiant est
        // le `piece_id` du poste. Le numero de piece n'est PAS unique (`REG-V-…` revient a
        // chaque reglement partiel) ; il porte le prefixe de poste (DV-21).
        Schema::create('pieces_comptables', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->string('numero_piece', 60)->nullable()->index();
            $table->dateTime('date_ecriture', 6);
            $table->unsignedSmallInteger('exercice_annee');
            $table->foreign('exercice_annee')->references('annee')->on('exercices_comptables');
            $table->string('journal_code', 2);
            $table->string('vente_ref', 60)->nullable();
            $table->string('achat_ref', 60)->nullable();
            // `id` de la piece que celle-ci ANNULE (contrepassation), sinon null.
            $table->uuid('contrepasse_de')->nullable()->index();
            // Instant de SAISIE (au poste).
            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->index(['exercice_annee', 'date_ecriture']);
        });

        Schema::create('ecritures_comptables', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('piece_id')->constrained('pieces_comptables')->cascadeOnDelete();
            $table->string('numero_compte', 20);
            $table->foreign('numero_compte')->references('numero_compte')->on('plan_comptable');
            $table->double('debit')->default(0);
            $table->double('credit')->default(0);
            $table->string('libelle');
            $table->string('axe_analytique', 80)->nullable();
        });

        // Dernier ecrivain gagne, par la cle naturelle (exercice, numero).
        Schema::create('notes_annexes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->unsignedSmallInteger('exercice_annee');
            $table->foreign('exercice_annee')->references('annee')->on('exercices_comptables');
            $table->unsignedTinyInteger('numero_note');
            $table->string('titre');
            $table->text('contenu');
            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->unique(['exercice_annee', 'numero_note']);
        });

        // Dernier ecrivain gagne, par (annee, mois) ; l'identifiant est derive.
        Schema::create('clotures_periodiques', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->unsignedSmallInteger('annee');
            $table->unsignedTinyInteger('mois');
            $table->boolean('is_cloture')->default(false);
            $table->dateTime('date_cloture', 6)->nullable();
            $table->string('decloture_par')->nullable();
            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->unique(['annee', 'mois']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('clotures_periodiques');
        Schema::dropIfExists('notes_annexes');
        Schema::dropIfExists('ecritures_comptables');
        Schema::dropIfExists('pieces_comptables');
        Schema::dropIfExists('clotures_exercice');
        Schema::dropIfExists('exercices_comptables');
        Schema::dropIfExists('plan_comptable');
    }
};
