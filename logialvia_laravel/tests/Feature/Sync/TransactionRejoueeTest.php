<?php

namespace Tests\Feature\Sync;

use App\Support\ServeurOccupe;
use App\Support\TransactionRejouee;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

/**
 * Interblocages et doublons de concurrence (`47r_`) : constates sur MySQL 8 avec 4 postes qui
 * envoient en meme temps les memes lignes en sens inverse (23 echecs 500 sur 48 envois avant, 0 apres).
 * SQLite ne les montre jamais ; on les SIMULE ici pour que la regle ne regresse pas.
 */
class TransactionRejoueeTest extends TestCase
{
    use RefreshDatabase;

    private function erreur(int $codeMysql, string $sqlstate): QueryException
    {
        $p = new \PDOException('simulee');
        $p->errorInfo = [$sqlstate, $codeMysql, 'simulee'];

        return new QueryException('mysql', 'update clients set x = ?', [1], $p);
    }

    public function test_un_interblocage_est_rejoue_puis_reussit(): void
    {
        $essais = 0;
        $resultat = TransactionRejouee::executer(function () use (&$essais) {
            if (++$essais < 4) {
                throw $this->erreur(1213, '40001');
            }

            return 'ok';
        });

        $this->assertSame('ok', $resultat);
        $this->assertSame(4, $essais);
    }

    public function test_un_interblocage_persistant_devient_serveur_occupe(): void
    {
        $essais = 0;
        try {
            TransactionRejouee::executer(function () use (&$essais) {
                $essais++;
                throw $this->erreur(1213, '40001');
            }, 3);
            $this->fail('ServeurOccupe attendu');
        } catch (ServeurOccupe $e) {
            $this->assertSame(3, $essais);
            $this->assertStringContainsString('occupé', $e->getMessage());
        }
    }

    public function test_un_doublon_de_concurrence_est_rejoue_et_une_vraie_violation_remonte(): void
    {
        $essais = 0;
        $this->assertSame('ok', TransactionRejouee::executer(function () use (&$essais) {
            if (++$essais < 2) {
                throw $this->erreur(1062, '23000');
            }

            return 'ok';
        }));

        $essais = 0;
        $this->expectException(QueryException::class);
        try {
            TransactionRejouee::executer(function () use (&$essais) {
                $essais++;
                throw $this->erreur(1062, '23000');
            });
        } finally {
            $this->assertSame(6, $essais, 'cinq rejeux puis l\'erreur d\'origine, pas un 503');
        }
    }

    public function test_une_autre_erreur_sql_n_est_jamais_rejouee(): void
    {
        $essais = 0;
        try {
            TransactionRejouee::executer(function () use (&$essais) {
                $essais++;
                throw $this->erreur(1064, '42000');
            });
            $this->fail('QueryException attendue');
        } catch (QueryException) {
            $this->assertSame(1, $essais);
        }
    }

    public function test_l_api_repond_503_avec_retry_after_et_non_500(): void
    {
        Route::get('/api/_essai_occupe', fn () => throw new ServeurOccupe('Le serveur est occupé (verrou de base de données) : réessayez dans un instant.'));

        $this->getJson('/api/_essai_occupe')
            ->assertStatus(503)
            ->assertHeader('Retry-After', '1')
            ->assertJsonPath('code', 'serveur_occupe');
    }
}
