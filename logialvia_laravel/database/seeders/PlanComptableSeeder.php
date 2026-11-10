<?php

namespace Database\Seeders;

use App\Models\ExerciceComptable;
use App\Models\PlanComptable;
use App\Support\PlanSyscohada;
use Carbon\CarbonImmutable;
use Illuminate\Database\Seeder;

/**
 * Plan comptable SYSCOHADA revise seme A L'IDENTIQUE du poste (`PlanSyscohada::COMPTES`, copie de
 * `plan_syscohada.dart`, 60 comptes). `tests/Feature/ConformitePlanSyscohadaDartTest.php` le compare au Dart.
 *
 * Idempotent : un compte deja present (renomme, archive par la Gerante) n'est jamais touche ; seuls les
 * numeros absents sont ajoutes. Les comptes sont des valeurs de SEMIS (`updated_at == created_at`) : un poste
 * ne les prend pas pour une decision du serveur. Ouvre aussi l'exercice de l'annee courante.
 */
class PlanComptableSeeder extends Seeder
{
    public function run(): void
    {
        foreach (PlanSyscohada::COMPTES as [$numero, $libelle, $classe]) {
            PlanComptable::query()->firstOrCreate(
                ['numero_compte' => $numero],
                ['libelle' => $libelle, 'classe' => $classe, 'archive' => false, 'plan_version' => PlanSyscohada::VERSION],
            );
        }

        ExerciceComptable::query()->firstOrCreate(
            ['annee' => (int) CarbonImmutable::now(config('logialvia.fuseau'))->year],
            ['is_cloture' => false],
        );
    }
}
