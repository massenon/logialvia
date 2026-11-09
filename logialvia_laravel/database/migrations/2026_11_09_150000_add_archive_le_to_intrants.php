<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // PIERRE TOMBALE (47h D4) : un intrant supprime au poste n'est jamais efface du serveur
        // (achats, mouvements, autres postes peuvent encore le citer) ; il est marque archive
        // et redescend vers tous les postes. NULL = actif. Meme regle que les produits.
        Schema::table('intrants', function (Blueprint $table) {
            $table->dateTime('archive_le', 6)->nullable()->after('saisi_le');
        });
    }

    public function down(): void
    {
        Schema::table('intrants', function (Blueprint $table) {
            $table->dropColumn('archive_le');
        });
    }
};
