<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Le lien soin -> bande voyage (v38 : la bande est un UUID). Nullable : un soin libre
        // n'a pas de bande. Pas de cle etrangere (une bande peut disparaitre a la remise a
        // zero) : la table verifie que la bande est CONNUE a l'ecriture.
        Schema::table('soins_calendrier', function (Blueprint $table) {
            $table->uuid('bande_id')->nullable()->after('echeance_prophylaxie_id');
            $table->index('bande_id');
        });

        // Divergence d'une fiche journaliere (`47e_`) : les AUTRES versions saisies sans que
        // le poste ait vu la version courante, conservees jusqu'a ce qu'une personne choisisse.
        // Liste JSON de {device_id, updated_at, contenu}. Jamais ecrite directement par un poste.
        Schema::table('fiche_journee', function (Blueprint $table) {
            $table->json('variantes')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('fiche_journee', function (Blueprint $table) {
            $table->dropColumn('variantes');
        });
        Schema::table('soins_calendrier', function (Blueprint $table) {
            $table->dropIndex(['bande_id']);
            $table->dropColumn('bande_id');
        });
    }
};
