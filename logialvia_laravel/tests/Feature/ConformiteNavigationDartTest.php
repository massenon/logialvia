<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * Conformité de la barre laterale : web = poste Flutter.
 *
 * Le poste porte l'arborescence dans `navigation_model.dart`. Ce test la relit et exige
 * les memes groupes, dans le meme ordre, avec les memes entrees (libelle, icone, route,
 * module) et les memes roles par groupe. Toute entree ajoutee d'un seul cote echoue.
 */
class ConformiteNavigationDartTest extends TestCase
{
    private const NAVIGATION = __DIR__.'/../../../logialvia_app/lib/core/router/navigation_model.dart';

    /** @return list<array{titre: string, roles: list<string>, entrees: list<array<string, mixed>>}> */
    private function groupesDuPoste(): array
    {
        $dart = file_get_contents(self::NAVIGATION);
        $this->assertNotFalse($dart, 'navigation_model.dart introuvable');
        $dart = preg_replace('#//[^\n]*#', '', $dart);

        preg_match_all(
            "/GroupeNavigation\\(\\s*titre:\\s*'([^']*)',\\s*roles:\\s*\\{([^}]*)\\},\\s*entrees:\\s*\\[(.*?)\\n    \\),\\n/s",
            $dart,
            $blocs,
            PREG_SET_ORDER,
        );

        $groupes = [];
        foreach ($blocs as [, $titre, $roles, $corps]) {
            preg_match_all("/'(\\w+)'/", $roles, $r);
            preg_match_all('/EntreeNavigation\((.*?)\),\s*(?=EntreeNavigation|\])/s', $corps.']', $e);

            $liste = [];
            foreach ($e[1] as $c) {
                preg_match("/libelle:\\s*(?:'((?:[^'\\\\]|\\\\.)*)'|\"([^\"]*)\")/", $c, $lib);
                preg_match('/Symbols\.(\w+)/', $c, $ic);
                preg_match("/route:\\s*'([^']*)'/", $c, $ro);
                preg_match("/moduleId:\\s*'([^']*)'/", $c, $mo);
                $liste[] = [
                    'libelle' => str_replace("\\'", "'", $lib[1] !== '' ? $lib[1] : ($lib[2] ?? '')),
                    'icone' => $ic[1],
                    'route' => $ro[1],
                    'module' => $mo[1] ?? null,
                ];
            }

            $groupes[] = ['titre' => $titre, 'roles' => $r[1], 'entrees' => $liste];
        }

        return $groupes;
    }

    public function test_la_barre_du_web_est_celle_du_poste(): void
    {
        $poste = $this->groupesDuPoste();

        $this->assertNotEmpty($poste, 'Aucun groupe lu dans le Dart : le motif de lecture est cassé.');
        $this->assertSame($poste, config('navigation'));
    }

    public function test_toute_entree_de_la_barre_a_sa_route_dans_la_matrice_des_droits(): void
    {
        foreach (config('navigation') as $groupe) {
            foreach ($groupe['entrees'] as $e) {
                $this->assertArrayHasKey($e['route'], config('logialvia.routes'), "Route sans droit : {$e['route']}");
                $this->assertSame(
                    $e['module'],
                    config('logialvia.routes')[$e['route']][1],
                    "Module de {$e['route']} différent entre la barre et la matrice.",
                );
            }
        }
    }
}
