<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // PIERRE TOMBALE : un produit supprime au poste n'est jamais efface du serveur (des
        // ventes, des mouvements ou un autre poste peuvent encore le citer) ; il est
        // marque archive et redescend ainsi vers tous les postes. NULL = actif.
        Schema::table('produits_vendables', function (Blueprint $table) {
            $table->dateTime('archive_le', 6)->nullable()->after('saisi_le');
        });
    }

    public function down(): void
    {
        Schema::table('produits_vendables', function (Blueprint $table) {
            $table->dropColumn('archive_le');
        });
    }
};
