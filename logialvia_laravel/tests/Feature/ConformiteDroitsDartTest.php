<?php

namespace Tests\Feature;

use App\Support\Droits;
use Tests\TestCase;

/**
 * Conformité des droits : web = poste Flutter.
 *
 * Le poste porte sa matrice dans `permission_service.dart`. Le web suit les
 * DECISIONS VALIDEES (DV-06, DV-07, DV-15). Ce test lit le Dart et exige :
 *
 *  - le MEME ensemble de routes que le poste (rien d'oublie, rien d'inventé) ;
 *  - pour chaque rôle commun, les mêmes accès — à une exception près : les écarts
 *    CONNUS et DECLARES dans `config/logialvia.php` (`ecarts_poste_connus`), que
 *    le poste doit corriger ;
 *  - qu'un écart déclaré existe bien encore : s'il a été corrigé au poste, la
 *    déclaration est périmée et le test le dit.
 *
 * Tout autre écart fait échouer le test.
 */
class ConformiteDroitsDartTest extends TestCase
{
    private const PERMISSION_SERVICE = __DIR__.'/../../../logialvia_app/lib/core/router/permission_service.dart';

    private const APP_ROUTER = __DIR__.'/../../../logialvia_app/lib/core/router/app_router.dart';

    private const NAVIGATION = __DIR__.'/../../../logialvia_app/lib/core/router/navigation_model.dart';

    private function source(string $chemin): string
    {
        $contenu = file_get_contents($chemin);
        $this->assertNotFalse($contenu, "Fichier Dart introuvable : $chemin");

        // Les commentaires contiennent des apostrophes et des chemins : on les retire.
        return preg_replace('#//[^\n]*#', '', $contenu);
    }

    /** @return array<string, list<string>> role => routes ('*' pour l'administrateur) */
    private function matriceDuPoste(): array
    {
        $dart = $this->source(self::PERMISSION_SERVICE);
        $matrice = [];

        preg_match_all("/'(admin|caissier|animalier)':\\s*\\{(.*?)\\}/s", $dart, $blocs, PREG_SET_ORDER);

        foreach ($blocs as [, $role, $corps]) {
            preg_match_all("/'(\\/[^']*|\\*)'/", $corps, $routes);
            $matrice[$role] = array_values(array_unique($routes[1]));
        }

        return $matrice;
    }

    /** @return list<string> Routes authentifiees connues du poste. */
    private function routesDuPoste(): array
    {
        $routes = [];

        preg_match_all("/route:\\s*'(\\/[a-z0-9\\/-]+)'/", $this->source(self::NAVIGATION), $nav);
        $routes = array_merge($routes, $nav[1]);

        // Cartes de routes du routeur (hub de comptabilite, menu du profil, specifications).
        preg_match_all("/^\\s*'(\\/[a-z0-9\\/-]+)':/m", $this->source(self::APP_ROUTER), $carte);
        $routes = array_merge($routes, $carte[1]);

        return array_values(array_unique($routes));
    }

    public function test_le_web_declare_les_memes_routes_que_le_poste(): void
    {
        $poste = $this->routesDuPoste();
        $web = array_keys(Droits::routes());
        sort($poste);
        sort($web);

        $this->assertSame(
            [],
            array_values(array_diff($poste, $web)),
            'Routes du poste absentes du web.',
        );
        $this->assertSame(
            [],
            array_values(array_diff($web, $poste)),
            'Routes du web inconnues du poste.',
        );
        $this->assertCount(36, $web, '36 routes authentifiees (39 moins les 3 publiques).');
    }

    public function test_le_poste_a_bien_les_trois_roles_attendus(): void
    {
        $this->assertEqualsCanonicalizing(['admin', 'caissier', 'animalier'], array_keys($this->matriceDuPoste()));
        $this->assertSame(['*'], $this->matriceDuPoste()['admin']);
    }

    public function test_les_roles_communs_ont_les_memes_acces_hors_ecarts_declares(): void
    {
        $poste = $this->matriceDuPoste();
        $ecarts = config('logialvia.ecarts_poste_connus');

        foreach (['caissier', 'animalier'] as $role) {
            $web = Droits::routesAutorisees($role);
            $attendu = array_merge($web, $ecarts[$role] ?? []);
            sort($attendu);
            $reel = $poste[$role];
            sort($reel);

            $this->assertSame(
                array_values(array_unique($attendu)),
                array_values($reel),
                "Les acces du rôle $role diffèrent du poste, hors écarts déclarés.",
            );
        }
    }

    public function test_l_administrateur_ouvre_toutes_les_routes(): void
    {
        $this->assertEqualsCanonicalizing(array_keys(Droits::routes()), Droits::routesAutorisees('admin'));
    }

    public function test_les_ecarts_declares_existent_encore_au_poste(): void
    {
        $poste = $this->matriceDuPoste();

        foreach (config('logialvia.ecarts_poste_connus') as $role => $routes) {
            foreach ($routes as $route) {
                $this->assertContains(
                    $route,
                    $poste[$role],
                    "L'écart « $role $route » n'existe plus au poste : retirez-le de ecarts_poste_connus.",
                );
                $this->assertNotContains(
                    $route,
                    Droits::routesAutorisees($role),
                    "Un écart déclaré doit être refusé au web ($role $route).",
                );
            }
        }
    }

    public function test_le_role_comptable_n_existe_qu_au_web_pour_l_instant(): void
    {
        $this->assertArrayNotHasKey('comptable', $this->matriceDuPoste());
        $this->assertNotEmpty(Droits::routesAutorisees('comptable'));
        $this->assertContains('/comptabilite', Droits::routesAutorisees('comptable'));
        $this->assertNotContains('/inventaire', Droits::routesAutorisees('comptable'));
    }

    public function test_les_modules_et_leurs_especes_sont_ceux_du_poste(): void
    {
        $dart = $this->source(__DIR__.'/../../../logialvia_app/lib/administration/data/seed/modules_actifs_seeder.dart');

        preg_match_all("/static const String (\\w+) = '(\\w+)';/", $dart, $constantes, PREG_SET_ORDER);
        $identifiants = [];
        foreach ($constantes as [, $nom, $valeur]) {
            $identifiants[$nom] = $valeur;
        }

        preg_match('/especeParModule = \\{(.*?)\\};/s', $dart, $carte);
        preg_match_all("/(\\w+):\\s*'([a-z-]+)'/", $carte[1], $paires, PREG_SET_ORDER);

        $poste = [];
        foreach ($paires as [, $constante, $espece]) {
            $poste[$identifiants[$constante]] = $espece;
        }

        $this->assertSame($poste, config('logialvia.modules'));
    }
}
