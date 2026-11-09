<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Report a nouveau (`47c_`) : la decision d'affectation du resultat voyage avec la cloture
 * (`affectation`, JSON `{reserve_legale, autres_reserves, dividendes}`), et la reouverture
 * d'un exercice est un fait date (`rouvert_le`) que les postes suivent.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('clotures_exercice', function (Blueprint $table) {
            $table->text('affectation')->nullable();
        });
        Schema::table('exercices_comptables', function (Blueprint $table) {
            $table->text('affectation')->nullable();
            $table->dateTime('rouvert_le', 6)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('exercices_comptables', function (Blueprint $table) {
            $table->dropColumn(['affectation', 'rouvert_le']);
        });
        Schema::table('clotures_exercice', function (Blueprint $table) {
            $table->dropColumn('affectation');
        });
    }
};
