<?php

namespace Tests\Feature;

use Tests\TestCase;

class ExampleTest extends TestCase
{
    /** L'application est protegee : un visiteur est renvoye vers la connexion. */
    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/')->assertRedirect(route('login'));
    }
}
