<?php

use App\Services\Comptabilite\RenumerotationPlan;
use App\Support\PlanSyscohada;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Plan comptable SYSCOHADA revise (`47p_`) : le plan, les ecritures (CL/AN compris) sont RENUMEROTES par la table
 * de correspondance `PlanSyscohada::CORRESPONDANCE`, en UNE transaction, idempotente, equilibre verifie avant/apres
 * (voir `RenumerotationPlan`). Coordonnee avec la migration v48 du poste.
 *
 * `plan_comptable.plan_version` : 1 = ancien plan (defaut des lignes existantes au moment de l'ajout de la colonne),
 * 2 = SYSCOHADA. La colonne est ajoutee AVANT la renumerotation et passe a 2 DANS sa transaction ; son defaut devient
 * ensuite 2 (un compte cree plus tard est du plan courant).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('plan_comptable', 'plan_version')) {
            Schema::table('plan_comptable', function (Blueprint $table) {
                $table->unsignedSmallInteger('plan_version')->default(1);
            });
        }

        RenumerotationPlan::executer();

        Schema::table('plan_comptable', function (Blueprint $table) {
            $table->unsignedSmallInteger('plan_version')->default(PlanSyscohada::VERSION)->change();
        });
    }

    /** Pas de retour arriere : la renumerotation est a sens unique (restaurer une sauvegarde d'avant). */
    public function down(): void {}
};
