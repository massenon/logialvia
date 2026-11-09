<?php

namespace Tests\Feature;

use App\Models\ParametresEntreprise;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Les valeurs par defaut des parametres sont celles du poste : lues dans le Dart.
 */
class ConformiteSocleDartTest extends TestCase
{
    use RefreshDatabase;

    public function test_les_prefixes_de_numerotation_par_defaut_sont_ceux_du_poste(): void
    {
        $dart = file_get_contents(__DIR__.'/../../../logialvia_app/lib/elevage/domain/entities/parametres_elevage.dart');
        $this->assertNotFalse($dart);

        preg_match_all("/this\\.(enclos|cage|bande|bassin|bac|parc) = '(\\w+)'/", $dart, $trouves, PREG_SET_ORDER);
        $this->assertCount(6, $trouves, 'Le poste doit declarer 6 prefixes.');

        $parametres = ParametresEntreprise::courant()->fresh();
        foreach ($trouves as [, $nom, $valeur]) {
            $this->assertSame($valeur, $parametres->{"prefixe_$nom"}, "Prefixe $nom different du poste.");
        }
    }

    public function test_la_raison_sociale_par_defaut_est_celle_du_poste(): void
    {
        $dart = file_get_contents(__DIR__.'/../../../logialvia_app/lib/administration/data/tables/parametres_entreprise_table.dart');
        preg_match("/raisonSociale =>\\s*text\\(\\)\\.withDefault\\(const Constant\\('([^']+)'\\)\\)/", $dart, $m);

        $this->assertSame($m[1], ParametresEntreprise::courant()->fresh()->raison_sociale);
    }
}
