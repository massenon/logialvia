<?php

namespace Tests\Feature;

use App\Support\PlanSyscohada;
use Tests\TestCase;

/**
 * `PlanSyscohada` (web) est le port exact de `plan_syscohada.dart` (poste, source) : constantes, plan,
 * libelles de l'ancien plan et table de correspondance, lus dans le Dart. Aucun numero de compte litteral ne
 * doit subsister ailleurs dans le code applicatif des deux cotes.
 */
class ConformitePlanSyscohadaDartTest extends TestCase
{
    private function dart(): string
    {
        $source = file_get_contents(__DIR__.'/../../../logialvia_app/lib/comptabilite/domain/plan_syscohada.dart');
        $this->assertNotFalse($source);

        return $source;
    }

    public function test_les_constantes_sont_celles_du_dart(): void
    {
        preg_match_all("/static const (?:String|int) (\\w+) = '?([^';]+)'?;/", $this->dart(), $m, PREG_SET_ORDER);
        $this->assertGreaterThanOrEqual(30, count($m));
        foreach ($m as [, $nom, $valeur]) {
            $constante = strtoupper(preg_replace('/([A-Z])/', '_$1', $nom));
            $this->assertTrue(defined(PlanSyscohada::class.'::'.$constante), "constante $constante absente du web");
            $this->assertSame($valeur, (string) constant(PlanSyscohada::class.'::'.$constante), $constante);
        }
    }

    public function test_les_libelles_anciens_et_la_correspondance_sont_ceux_du_dart(): void
    {
        $dart = $this->dart();
        preg_match('/libellesAnciens = \\{(.*?)\\};/s', $dart, $bloc);
        preg_match_all("/'(\\d+)': '((?:[^'\\\\]|\\\\.)*)',/u", $bloc[1], $anc, PREG_SET_ORDER);
        $attendu = [];
        foreach ($anc as [, $n, $l]) {
            $attendu[$n] = stripslashes($l);
        }
        $this->assertSame($attendu, PlanSyscohada::LIBELLES_ANCIENS);

        preg_match_all(
            "/\\(\\s*ancien: '(\\d+)',\\s*nouveau: '(\\d+)',\\s*libelleAncien:\\s*'((?:[^'\\\\]|\\\\.)*)',\\s*fraisLivraisonSeulement: (true|false),?\\s*\\)/u",
            $dart, $reg, PREG_SET_ORDER,
        );
        $regles = array_map(fn ($r) => [
            'ancien' => $r[1], 'nouveau' => $r[2], 'libelle_ancien' => stripslashes($r[3]), 'frais_livraison_seulement' => $r[4] === 'true',
        ], $reg);
        $this->assertCount(12, $regles);
        $this->assertSame($regles, PlanSyscohada::CORRESPONDANCE);
    }

    public function test_aucun_numero_de_compte_litteral_hors_des_classes_de_constantes(): void
    {
        // Les numeros ne vivent QUE dans `PlanSyscohada` (web) et `plan_syscohada.dart` (poste) : toute autre
        // occurrence d'un numero de l'ancien plan comme chaine litterale est une regression.
        $interdits = ['531', '512', '601', '602', '613', '616', '622', '624', '628', '701', '707'];
        $racines = [__DIR__.'/../../app', __DIR__.'/../../resources/views', __DIR__.'/../../../logialvia_app/lib'];
        foreach ($racines as $racine) {
            $it = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine));
            foreach ($it as $f) {
                if (! $f->isFile() || ! preg_match('/\\.(php|dart)$/', $f->getFilename()) || str_ends_with($f->getPathname(), 'Support/PlanSyscohada.php') || str_ends_with($f->getPathname(), 'domain/plan_syscohada.dart') || str_ends_with($f->getPathname(), '.g.dart')) {
                    continue;
                }
                $contenu = file_get_contents($f->getPathname());
                foreach ($interdits as $n) {
                    $this->assertDoesNotMatchRegularExpression('/[\'"]'.$n.'[\'"]/', $contenu, "{$f->getPathname()} : numero litteral $n");
                }
            }
        }
    }
}
