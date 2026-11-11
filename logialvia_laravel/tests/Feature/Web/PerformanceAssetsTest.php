<?php

namespace Tests\Feature\Web;

use Tests\TestCase;

/**
 * Garde CI de poids (PWA-PERF, 47x_) : le build Vite ne doit pas grossir sans qu'on le voie.
 * Echoue si le JS total depasse 300 Ko ou le CSS total 100 Ko (non compresses), si Livewire/Alpine retournent dans
 * le bundle applicatif ou dans un <script> bloquant, ou si le CSS critique n'est plus precharge.
 * En CI (`CI` defini) l'absence de build est une ERREUR, pas un test ignore : `npm run build` precede toujours les tests.
 */
class PerformanceAssetsTest extends TestCase
{
    public const BUDGET_JS_OCTETS = 300 * 1000;

    public const BUDGET_CSS_OCTETS = 100 * 1000;

    /** @return list<string> */
    private function fichiers(string $extension): array
    {
        $liste = glob(public_path("build/assets/*.$extension")) ?: [];
        if ($liste === []) {
            if (getenv('CI')) {
                $this->fail("Aucun build Vite (*.$extension) : lancer `npm run build` avant les tests.");
            }
            $this->markTestSkipped('Build Vite absent (npm run build).');
        }

        return $liste;
    }

    private function total(array $fichiers): int
    {
        return array_sum(array_map('filesize', $fichiers));
    }

    public function test_le_javascript_total_reste_sous_300_ko(): void
    {
        $fichiers = $this->fichiers('js');
        $detail = implode(', ', array_map(fn ($f) => basename($f).' '.filesize($f).' o', $fichiers));

        $this->assertLessThanOrEqual(self::BUDGET_JS_OCTETS, $this->total($fichiers), "JS > 300 Ko : $detail");
    }

    public function test_le_css_total_reste_sous_100_ko(): void
    {
        $fichiers = $this->fichiers('css');

        $this->assertLessThanOrEqual(self::BUDGET_CSS_OCTETS, $this->total($fichiers), 'CSS > 100 Ko : '.implode(', ', array_map('basename', $fichiers)));
    }

    public function test_livewire_et_alpine_ont_leur_propre_fichier(): void
    {
        $this->fichiers('js');
        $vendor = glob(public_path('build/assets/vendor-livewire-*.js')) ?: [];
        $this->assertCount(1, $vendor, 'chunk vendor-livewire manquant : revoir manualChunks dans vite.config.js');
        $this->assertStringContainsString('Livewire', (string) file_get_contents($vendor[0]));

        $app = glob(public_path('build/assets/app-*.js')) ?: [];
        $this->assertCount(1, $app);
        $this->assertLessThan(40_000, filesize($app[0]), 'le bundle applicatif ne doit pas embarquer Livewire/Alpine (code applicatif seul < 40 Ko)');
        $this->assertStringNotContainsString('morphdom', (string) file_get_contents($app[0]));
    }

    public function test_les_pages_precharge_le_css_critique_et_n_ont_aucun_script_bloquant(): void
    {
        $this->fichiers('css');

        foreach (['/login'] as $chemin) {
            $html = $this->get($chemin)->assertOk()->getContent();

            $this->assertMatchesRegularExpression('#<link rel="preload" href="[^"]+/build/assets/app-[^"]+\.css" as="style">#', $html, "$chemin : CSS critique non precharge");
            $this->assertStringNotContainsString('livewire.min.js', $html, "$chemin : script Livewire bloquant");
            $this->assertStringContainsString('window.livewireScriptConfig', $html, "$chemin : @livewireScriptConfig manquant");
            // Tout <script src> doit etre un module (differe) : aucun script classique bloquant dans la page.
            preg_match_all('#<script\b[^>]*\bsrc=[^>]*>#', $html, $m);
            foreach ($m[0] as $balise) {
                $this->assertStringContainsString('type="module"', $balise, "$chemin : script bloquant $balise");
            }
        }
    }
}
