<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * `47s_` — stock ciblé : une opération web qui a un effet de stock désigne un POSTE DE STOCK.
 *
 *  - `poste_cible` (device_id du poste, nullable) sur les faits concernés : achats, ventes et
 *    les deux journaux de mouvements. Posé à la création, immuable ensuite. Les lignes
 *    existantes restent à NULL : aucun effet rétroactif.
 *  - `effets_stock` : la trace que le poste désigné remonte quand il a appliqué l'effet
 *    (ou l'a refusé, ou l'a appliqué avec un avertissement). Fait immuable, une ligne par
 *    (fait, nature) : le web y lit « appliqué / en attente / avertissement ».
 *  - `postes_stock_defauts` : le poste proposé par défaut à chaque compte, par type
 *    d'opération (réception d'achat, vente web, correction de stock).
 */
return new class extends Migration
{
    public function up(): void
    {
        foreach (['achats', 'ventes', 'mouvements_intrant', 'mouvements_produit'] as $table) {
            if (! Schema::hasColumn($table, 'poste_cible')) {
                Schema::table($table, function (Blueprint $t) {
                    $t->uuid('poste_cible')->nullable();
                });
            }
        }

        if (! Schema::hasTable('effets_stock')) {
            Schema::create('effets_stock', function (Blueprint $table) {
                $table->uuid('id')->primary();
                // Le poste qui a appliqué l'effet (le nom de son jeton).
                $table->uuid('device_id');
                $table->string('fait_type', 20);
                $table->uuid('fait_id');
                $table->string('nature', 30);
                $table->string('reference', 60)->nullable();
                $table->text('libelle');
                $table->string('etat', 15);
                $table->text('avertissement')->nullable();
                $table->dateTime('applique_le', 6);
                $table->dateTime('serveur_modifie_le', 6)->index();
                $table->unique(['fait_id', 'nature']);
            });
        }

        if (! Schema::hasTable('postes_stock_defauts')) {
            Schema::create('postes_stock_defauts', function (Blueprint $table) {
                $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
                $table->string('operation', 30);
                $table->uuid('poste_device_id');
                $table->timestamps();
                $table->primary(['user_id', 'operation']);
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('postes_stock_defauts');
        Schema::dropIfExists('effets_stock');
        foreach (['achats', 'ventes', 'mouvements_intrant', 'mouvements_produit'] as $table) {
            if (Schema::hasColumn($table, 'poste_cible')) {
                Schema::table($table, function (Blueprint $t) {
                    $t->dropColumn('poste_cible');
                });
            }
        }
    }
};
