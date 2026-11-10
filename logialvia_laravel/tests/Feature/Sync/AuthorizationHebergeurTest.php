<?php

namespace Tests\Feature\Sync;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** En-tete `Authorization` retire par l'hebergeur (`47r_`) : le jeton passe par `X-Authorization`. */
class AuthorizationHebergeurTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    public function test_un_sans_en_tete_authorization_est_dit_et_un_jeton_mort_aussi(): void
    {
        $a = $this->poste('admin', 'gerante');

        $this->app['auth']->forgetGuards();
        $this->getJson('/api/sync/pull')->assertStatus(401)->assertJsonPath('code', 'jeton_absent');

        $this->app['auth']->forgetGuards();
        $this->withToken('0|jeton-qui-n-existe-pas')->getJson('/api/sync/pull')
            ->assertStatus(401)->assertJsonPath('code', 'jeton_invalide');

        // L'hebergeur a retire `Authorization` : le MEME jeton passe par `X-Authorization`.
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $this->withHeaders(['X-Authorization' => 'Bearer '.$a['jeton']])->getJson('/api/sync/pull')->assertOk();
    }
}
