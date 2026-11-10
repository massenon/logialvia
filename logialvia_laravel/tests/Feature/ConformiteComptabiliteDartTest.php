<?php

namespace Tests\Feature;

use App\Models\PlanComptable;
use App\Services\Comptabilite\Verrous;
use App\Support\UuidDeterministe;
use Database\Seeders\PlanComptableSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * La comptabilite du web est celle du poste : plan seme a l'IDENTIQUE, identifiants
 * deterministes identiques, tolerance et sens des soldes identiques. Lus dans le Dart.
 */
class ConformiteComptabiliteDartTest extends TestCase
{
    use RefreshDatabase;

    private function dart(string $chemin): string
    {
        $source = file_get_contents(__DIR__.'/../../../logialvia_app/lib/'.$chemin);
        $this->assertNotFalse($source, "Fichier Dart introuvable : $chemin");

        return $source;
    }

    public function test_le_plan_seme_est_celui_du_poste_compte_pour_compte(): void
    {
        $dart = $this->dart('comptabilite/domain/plan_syscohada.dart');
        preg_match_all(
            "/\\(\\s*numero: '(\\d+)',\\s*libelle:\\s*'((?:[^'\\\\]|\\\\.)*)',\\s*classe: '(\\d)',?\\s*\\)/u",
            $dart,
            $trouves,
            PREG_SET_ORDER,
        );
        $this->assertCount(60, $trouves, 'Le poste doit semer 60 comptes.');

        $attendu = [];
        foreach ($trouves as [, $numero, $libelle, $classe]) {
            $attendu[$numero] = [stripslashes($libelle), $classe];
        }

        $this->seed(PlanComptableSeeder::class);
        $serveur = PlanComptable::query()->orderBy('numero_compte')->get()
            ->mapWithKeys(fn ($c) => [$c->numero_compte => [$c->libelle, $c->classe]])->all();

        ksort($attendu);
        ksort($serveur);
        $this->assertSame($attendu, $serveur);
    }

    public function test_le_semis_est_idempotent_et_ne_touche_jamais_un_compte_modifie(): void
    {
        $this->seed(PlanComptableSeeder::class);
        PlanComptable::query()->whereKey('618')->update(['libelle' => 'Déplacements', 'archive' => true]);

        $this->seed(PlanComptableSeeder::class);

        $this->assertSame(60, PlanComptable::query()->count());
        $this->assertSame('Déplacements', PlanComptable::query()->find('618')->libelle);
        $this->assertTrue(PlanComptable::query()->find('618')->archive);
    }

    public function test_les_identifiants_deterministes_sont_ceux_du_poste(): void
    {
        // Valeurs calculees par `uuidDeterministe` du Dart (identifiant_poste.dart).
        $this->assertSame('9afed1de-64f7-5ec9-b8fe-e226326cbc53', UuidDeterministe::note(2026, 1));
        $this->assertSame('f37e9f17-dfdb-5ea8-87de-daf6d2015c37', UuidDeterministe::note(2025, 3));
        $this->assertSame('ef884aa9-a54f-5eb4-a64d-d142f62e0f68', UuidDeterministe::cloturePeriodique(2026, 3));
        $this->assertSame('b67cd1c1-fbac-5592-892b-43c10199004c', UuidDeterministe::cloturePeriodique(2026, 12));
        $this->assertSame('bdd08acd-c669-5d7a-a0a7-2143cbb727a5', UuidDeterministe::clotureExercice(2026));
    }

    public function test_la_tolerance_d_equilibre_est_celle_du_poste(): void
    {
        $dart = $this->dart('comptabilite/domain/services/moteur_comptable.dart');
        preg_match('/static const double tolerance = ([0-9.]+);/', $dart, $m);

        $this->assertEquals((float) $m[1], Verrous::TOLERANCE);
    }

    public function test_les_journaux_et_les_droits_de_cloture_sont_ceux_du_poste(): void
    {
        $dart = $this->dart('comptabilite/domain/entities/comptabilite.dart');
        preg_match_all("/static const String \\w+ = '([A-Z]{2})';/", $dart, $m);

        $this->assertEqualsCanonicalizing(\App\Sync\Tables\EcrituresTable::JOURNAUX, $m[1]);

        // DV-15 : la cloture annuelle est reservee a l'administratrice, au poste comme ici.
        $vm = $this->dart('comptabilite/presentation/viewmodels/comptabilite_view_model.dart');
        $this->assertStringContainsString("roleId != 'admin'", $vm);
        $this->assertNotContains('close-fiscal-year', config('logialvia.role_permissions.comptable'));
        $this->assertSame('*', config('logialvia.role_permissions.admin'));
    }
}
