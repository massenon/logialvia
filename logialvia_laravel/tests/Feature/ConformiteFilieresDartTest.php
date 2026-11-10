<?php

namespace Tests\Feature;

use App\Support\FilieresElevage;
use Tests\TestCase;

/**
 * Conformité des filières d'élevage : web = poste Flutter.
 *
 * Le Dart (`configuration_espece.dart`) est la source : ce test relit ses 8 configurations
 * (identifiant, libellé, route, catégories avec leurs drapeaux, étapes du cycle, libellés des
 * achats et des naissances) et exige les mêmes valeurs dans `FilieresElevage`. Une filière,
 * une catégorie ou un libellé modifié d'un seul côté échoue.
 */
class ConformiteFilieresDartTest extends TestCase
{
    private const DART = __DIR__.'/../../../logialvia_app/lib/elevage/domain/entities/configuration_espece.dart';

    /** @return array<string, array<string, mixed>> */
    private function configurationsDuPoste(): array
    {
        $dart = file_get_contents(self::DART);
        $this->assertNotFalse($dart, 'configuration_espece.dart introuvable');
        $dart = preg_replace('#^\s*//[^\n]*\n#m', '', $dart);

        preg_match_all('/static const ConfigurationEspece \w+ = ConfigurationEspece\((.*?)\n  \);/s', $dart, $blocs);
        $this->assertNotEmpty($blocs[1]);

        $configs = [];
        foreach ($blocs[1] as $corps) {
            preg_match("/identifiant:\\s*'([^']*)'/", $corps, $id);
            preg_match("/libelle:\\s*'([^']*)',\\s*\\n\\s*icone/", $corps, $libelle);
            preg_match("/icone:\\s*'([^']*)'/", $corps, $icone);
            preg_match("/route:\\s*'([^']*)'/", $corps, $route);
            preg_match("/libelleAchats:\\s*'([^']*)'/", $corps, $achats);
            preg_match("/libelleNaissances:\\s*'([^']*)'/", $corps, $naissances);

            preg_match('/categories:\s*\[(.*?)\n    \],/s', $corps, $cats);
            preg_match_all('/CategorieEspece\((.*?)\)(?:,|\s*\])/s', $cats[1].']', $liste);
            $categories = [];
            foreach ($liste[1] as $c) {
                preg_match("/libelle:\\s*'([^']*)'/", $c, $l);
                preg_match('/rationGrammesParJour:\s*(\d+)/', $c, $r);
                $categories[] = [
                    $l[1], (int) $r[1],
                    (bool) preg_match('/recoitAchatEtNaissances:\s*true/', $c),
                    (bool) preg_match('/deduiteDesVentes:\s*true/', $c),
                ];
            }

            preg_match('/etapesCycle:\s*\[(.*?)\],\s*\n\s*(?:noteRationnement|poidsMaturite|ageMaturite|libelle)/s', $corps, $et);
            preg_match_all("/'([^']*)'/", $et[1], $etapes);

            $configs[$id[1]] = [
                'libelle' => $libelle[1], 'icone' => $icone[1], 'route' => $route[1],
                'categories' => $categories, 'etapes' => $etapes[1],
                'libelle_achats' => $achats[1] ?? 'Achats', 'libelle_naissances' => $naissances[1],
            ];
        }

        return $configs;
    }

    public function test_les_huit_filieres_du_web_sont_celles_du_poste(): void
    {
        $poste = $this->configurationsDuPoste();

        $this->assertSame(array_keys($poste), FilieresElevage::identifiants(), 'memes filieres, dans le meme ordre');
        $this->assertCount(8, $poste);
    }

    public function test_chaque_configuration_est_identique_au_dart(): void
    {
        foreach ($this->configurationsDuPoste() as $id => $dart) {
            $this->assertEquals($dart, FilieresElevage::configuration($id), "filiere « $id »");
        }
    }

    public function test_les_routes_des_filieres_sont_celles_de_la_matrice_des_droits(): void
    {
        $routes = array_keys(config('logialvia.routes'));
        foreach (FilieresElevage::toutes() as $id => $config) {
            $this->assertContains($config['route'], $routes, $id);
        }
    }

    public function test_les_categories_sont_au_nombre_de_trois_sauf_pondeuses(): void
    {
        foreach (FilieresElevage::identifiants() as $id) {
            $this->assertSame($id === 'pondeuses' ? 4 : 3, FilieresElevage::nombreCategories($id), $id);
        }
    }

    public function test_les_libelles_de_jeunes_du_tableau_de_bord_viennent_du_dart(): void
    {
        $depot = file_get_contents(__DIR__.'/../../../logialvia_app/lib/pilotage/data/repositories/tableau_bord_repository_drift.dart');
        preg_match('/_libelleJeunesParEspece = \{(.*?)\};/s', $depot, $bloc);
        preg_match_all("/'([\\w-]+)':\\s*'([^']*)'/", $bloc[1], $paires, PREG_SET_ORDER);
        $dart = [];
        foreach ($paires as [, $espece, $libelle]) {
            $dart[$espece] = $libelle;
        }

        $this->assertEquals($dart, \App\Livewire\DashboardElevage::LIBELLE_JEUNES);
    }
}
