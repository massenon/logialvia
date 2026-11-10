<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Clients — premiere table de FAITS synchronisee (`46_` §2.3). Miroir de
     * `CLIENTS` du poste, plus les colonnes de synchronisation :
     *
     *  - `updated_at`          instant de SAISIE, pose par le poste : il sert a
     *                          departager deux ecritures (dernier ecrivain gagne) ;
     *  - `serveur_modifie_le`  instant de RECEPTION, pose par le serveur : c'est LUI
     *                          qui sert de curseur au tirage. Un poste hors ligne
     *                          trois jours envoie des lignes datees d'il y a trois
     *                          jours : sans cette colonne, les postes deja a jour ne
     *                          les verraient jamais ;
     *  - `supprime_le`         pierre tombale : une suppression doit se propager.
     */
    public function up(): void
    {
        Schema::create('clients', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->nullable();
            $table->string('nom');
            $table->string('telephone')->nullable();
            // DERIVE : calcule par le serveur a partir des ventes, jamais ecrit par un poste.
            $table->decimal('solde_creance', 14, 2)->default(0);
            $table->date('date_naissance')->nullable();
            $table->dateTime('dernier_contact', 6)->nullable();

            $table->dateTime('updated_at', 6);
            $table->dateTime('serveur_modifie_le', 6)->index();
            $table->dateTime('supprime_le', 6)->nullable();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('clients');
    }
};
