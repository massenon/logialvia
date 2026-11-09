<?php

namespace Tests\Feature\Sync;

use App\Models\Client;
use App\Services\PostesService;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * L'ESSAI A DEUX POSTES (`46_` §5) : deux postes qui travaillent hors ligne, se
 * reconnectent dans le desordre, rejouent leurs lots, et doivent tous deux
 * converger vers la meme base — celle que le serveur arbitre.
 */
class DeuxPostesTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    /** @return array{lignes: list<array>, curseur: string} Un tirage COMPLET (toutes les pages). */
    private function tirer(array $poste, ?string $depuis = null): array
    {
        $url = '/api/sync/pull'.($depuis ? '?since='.urlencode($depuis) : '');
        $page = $this->avecJeton($poste['jeton'])->getJson($url)->assertOk()->json();
        $lignes = $page['tables']['clients'] ?? [];
        $until = urlencode($page['server_time']);

        for ($n = 2; $n <= $page['last_page']; $n++) {
            $suite = $this->avecJeton($poste['jeton'])->getJson("/api/sync/pull?page=$n&until=$until".($depuis ? '&since='.urlencode($depuis) : ''))->assertOk()->json();
            $lignes = array_merge($lignes, $suite['tables']['clients'] ?? []);
        }

        // Le curseur n'avance qu'apres la DERNIERE page.
        return ['lignes' => $lignes, 'curseur' => $page['server_time']];
    }

    private function pousser(array $poste, array $lignes)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => 'initiale',
            'tables' => ['clients' => $lignes],
        ]);
    }

    private function horodatage(int $microsecondes): string
    {
        return CarbonImmutable::parse('2026-11-01 08:00:00', 'UTC')->addMicroseconds($microsecondes)->format('Y-m-d\TH:i:s.u\Z');
    }

    // ------------------------------------------------------------------ Recits

    public function test_deux_postes_s_echangent_leurs_clients(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');

        $c1 = $this->ligneClient(['nom' => 'Client de A', 'updated_at' => $this->horodatage(1_000_000)]);
        $this->pousser($a, [$c1])->assertOk();

        // B arrive, recoit tout.
        $tirageB = $this->tirer($b);
        $this->assertSame(['Client de A'], array_column($tirageB['lignes'], 'nom'));

        // B cree un client et CORRIGE celui de A (saisie plus recente).
        $c2 = $this->ligneClient(['nom' => 'Client de B', 'updated_at' => $this->horodatage(2_000_000)]);
        $c1b = array_merge($c1, ['nom' => 'Client de A (corrigé par B)', 'updated_at' => $this->horodatage(3_000_000)]);
        $this->pousser($b, [$c2, $c1b])->assertOk();

        // A, qui avait deja son curseur, recoit les deux changements.
        // Le tirage incremental re-sert volontairement la fenetre de recouvrement : A peut
        // recevoir deux fois une meme ligne (sans effet), jamais une ligne inconnue.
        $tirageA = $this->tirer($a, $this->tirer($a)['curseur']);
        $this->assertEmpty(array_diff(array_column($tirageA['lignes'], 'nom'), ['Client de A (corrigé par B)', 'Client de B']));
        $apres = $this->tirer($a);
        $this->assertEqualsCanonicalizing(['Client de A (corrigé par B)', 'Client de B'], array_column($apres['lignes'], 'nom'));
    }

    public function test_un_poste_hors_ligne_trois_jours_n_est_pas_oublie_par_les_autres(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');

        // A est a jour, son curseur est a MAINTENANT.
        $curseurA = $this->tirer($a)['curseur'];

        // B revient apres trois jours hors ligne : sa saisie date d'il y a 3 jours,
        // BIEN AVANT le curseur de A. C'est le cas qui perd des donnees si le tirage
        // se base sur l'instant de saisie plutot que sur l'instant de reception.
        $vieille = $this->ligneClient(['nom' => 'Saisi il y a 3 jours', 'updated_at' => now()->subDays(3)->format('Y-m-d\TH:i:s.u\Z')]);
        $this->travel(5)->seconds();
        $this->pousser($b, [$vieille])->assertOk();

        $noms = array_column($this->tirer($a, $curseurA)['lignes'], 'nom');

        $this->assertSame(['Saisi il y a 3 jours'], $noms);
    }

    public function test_une_modification_ancienne_arrivee_en_retard_ne_gagne_pas(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $id = (string) Str::uuid();

        // B a saisi plus tard (11 h) et se connecte le premier ; A, hors ligne, avait saisi a 10 h.
        $this->pousser($b, [$this->ligneClient(['id' => $id, 'nom' => 'Version de 11 h', 'updated_at' => $this->horodatage(3_600_000_000)])]);
        $this->pousser($a, [$this->ligneClient(['id' => $id, 'nom' => 'Version de 10 h', 'updated_at' => $this->horodatage(0)])])->assertOk();

        $this->assertSame('Version de 11 h', Client::query()->find($id)->nom);
        // Et les deux postes voient la meme chose.
        $this->assertSame('Version de 11 h', $this->tirer($a)['lignes'][0]['nom']);
        $this->assertSame('Version de 11 h', $this->tirer($b)['lignes'][0]['nom']);
    }

    public function test_un_poste_revoque_ne_peut_plus_rien_envoyer(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $b = $this->poste('caissier', 'bako');
        $this->assertSame(1, app(PostesService::class)->revoquer($b['device'], $admin['utilisateur']));

        $this->pousser($b, [$this->ligneClient()])->assertStatus(401);

        $this->assertSame(0, Client::query()->count(), 'Les saisies du poste revoque restent sur le poste.');
    }

    public function test_un_poste_ne_signe_pas_au_nom_d_un_autre(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');

        $this->avecJeton($b['jeton'])->postJson('/api/sync/push', [
            'device_id' => $a['device'],
            'reset_mark' => 'initiale',
            'tables' => ['clients' => [$this->ligneClient()]],
        ])->assertStatus(403);

        $this->assertSame(0, Client::query()->count());
    }

    public function test_deux_postes_peuvent_creer_chacun_un_client_de_meme_nom(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');

        $this->pousser($a, [$this->ligneClient(['nom' => 'Mama Rita'])]);
        $this->pousser($b, [$this->ligneClient(['nom' => 'Mama Rita'])]);

        $this->assertCount(2, $this->tirer($a)['lignes']);
        $this->assertSame(
            collect($this->tirer($a)['lignes'])->pluck('id')->sort()->values()->all(),
            collect($this->tirer($b)['lignes'])->pluck('id')->sort()->values()->all(),
        );
    }

    // ------------------------------------------- Simulation : tout converge

    /** @return array<string, array{0: int}> */
    public static function graines(): array
    {
        return ['graine 1' => [1], 'graine 2' => [2], 'graine 3' => [3], 'graine 4' => [4], 'graine 5' => [5], 'graine 6' => [6]];
    }

    /**
     * Deux postes enchainent, dans un ordre ALEATOIRE (mais reproductible : graine
     * fixe), des saisies, des envois partiels, des rejeux de lots deja recus et des
     * tirages incrementaux. Quoi qu'il arrive, a la fin :
     *  - chaque poste, par tirages INCREMENTAUX seulement, a exactement l'etat attendu ;
     *  - un tirage complet donne le meme etat, a l'identique.
     * L'etat attendu = pour chaque UUID, la saisie la plus recente (dernier ecrivain gagne).
     *
     * @dataProvider graines
     */
    public function test_les_deux_postes_convergent_quel_que_soit_l_ordre(int $graine): void
    {
        mt_srand($graine);
        config(['logialvia.sync.lignes_par_page' => 4]);

        $postes = ['A' => $this->poste('caissier', 'amina'), 'B' => $this->poste('caissier', 'bako')];
        $horloge = 0;
        $attendu = [];                                  // id => nom de la saisie la plus recente
        $saisies = [];                                  // id => microsecondes de cette saisie
        $enAttente = ['A' => [], 'B' => []];           // saisies pas encore envoyees
        $envoyes = ['A' => [], 'B' => []];             // pour pouvoir REJOUER un ancien lot
        $curseur = ['A' => null, 'B' => null];
        $etat = ['A' => [], 'B' => []];                 // ce que chaque poste a recu : id => nom
        $connus = ['A' => [], 'B' => []];

        $saisir = function (string $p) use (&$horloge, &$attendu, &$saisies, &$enAttente, &$connus) {
            $tous = array_unique(array_merge($connus['A'], $connus['B']));
            $existant = $connus[$p] !== [] && mt_rand(1, 100) <= 55 ? $connus[$p][array_rand($connus[$p])] : null;
            $id = $existant ?? (string) Str::uuid();
            $horloge += mt_rand(1, 5_000_000);          // le temps passe, toujours strictement
            $nom = "n{$horloge}";
            $ligne = ['id' => $id, 'nom' => $nom, 'telephone' => null, 'updated_at' => $this->horodatage($horloge)];
            $enAttente[$p][] = $ligne;
            $connus[$p][] = $id;
            if (! isset($saisies[$id]) || $horloge > $saisies[$id]) {
                $saisies[$id] = $horloge;
                $attendu[$id] = $nom;
            }
        };

        $envoyer = function (string $p) use (&$enAttente, &$envoyes, $postes) {
            if ($enAttente[$p] === []) {
                return;
            }
            // Parfois on n'envoie qu'une partie du lot : le reste attendra (connexion coupee).
            $lot = $enAttente[$p];
            if (mt_rand(1, 100) <= 30 && count($lot) > 1) {
                $moitie = intdiv(count($lot), 2);
                $envoyes[$p] = array_merge($envoyes[$p], array_slice($lot, 0, $moitie));
                $this->pousser($postes[$p], array_slice($lot, 0, $moitie))->assertOk();
                $enAttente[$p] = array_slice($lot, $moitie);

                return;
            }
            $this->pousser($postes[$p], $lot)->assertOk();
            $envoyes[$p] = array_merge($envoyes[$p], $lot);
            $enAttente[$p] = [];
        };

        $tirer = function (string $p) use (&$curseur, &$etat, &$connus, $postes) {
            $tirage = $this->tirer($postes[$p], $curseur[$p]);
            foreach ($tirage['lignes'] as $ligne) {
                $etat[$p][$ligne['id']] = $ligne['nom'];
                $connus[$p][] = $ligne['id'];
            }
            $curseur[$p] = $tirage['curseur'];
        };

        for ($i = 0; $i < 140; $i++) {
            $p = mt_rand(0, 1) ? 'A' : 'B';
            $de = mt_rand(1, 100);
            if ($de <= 50) {
                $saisir($p);
            } elseif ($de <= 72) {
                $envoyer($p);
            } elseif ($de <= 82 && $envoyes[$p] !== []) {
                // Rejeu d'un ancien lot deja recu (reponse perdue, poste qui reessaie).
                $rejeu = array_slice($envoyes[$p], -mt_rand(1, min(5, count($envoyes[$p]))));
                $this->pousser($postes[$p], $rejeu)->assertOk();
            } else {
                $tirer($p);
            }
        }

        // Fin de journee : tout est envoye, puis chaque poste fait un tirage INCREMENTAL.
        foreach (['A', 'B'] as $p) {
            $envoyer($p);
            while ($enAttente[$p] !== []) {
                $envoyer($p);
            }
        }
        foreach (['A', 'B'] as $p) {
            $tirer($p);
        }
        // Un dernier tour : ce qu'un poste a envoye a la fin n'etait pas encore chez l'autre.
        foreach (['A', 'B'] as $p) {
            $tirer($p);
        }

        ksort($attendu);
        foreach (['A', 'B'] as $p) {
            ksort($etat[$p]);
            $this->assertSame($attendu, $etat[$p], "Le poste $p (tirages incrementaux seulement) ne converge pas vers l'etat attendu.");

            $complet = [];
            foreach ($this->tirer($postes[$p])['lignes'] as $ligne) {
                $complet[$ligne['id']] = $ligne['nom'];
            }
            ksort($complet);
            $this->assertSame($attendu, $complet, "Le tirage complet du poste $p differe de l'etat attendu.");
        }

        $this->assertSame(count($attendu), Client::query()->count(), 'Aucun doublon, aucune ligne perdue.');
    }
}
