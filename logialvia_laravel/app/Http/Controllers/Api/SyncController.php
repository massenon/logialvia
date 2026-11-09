<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;

/**
 * Synchronisation. Le MOTEUR (pull/push) est l'etape W3 : en attendant, ces
 * routes existent pour que les garde-fous d'identite (le jeton dit qui parle)
 * soient en place et testes, et repondent honnetement « pas encore disponible ».
 */
class SyncController extends Controller
{
    public function push(): JsonResponse
    {
        return $this->pasEncoreDisponible();
    }

    public function pull(): JsonResponse
    {
        return $this->pasEncoreDisponible();
    }

    private function pasEncoreDisponible(): JsonResponse
    {
        return response()->json([
            'message' => "Le moteur de synchronisation n'est pas encore disponible sur ce serveur.",
            'code' => 'synchronisation_indisponible',
        ], 501);
    }
}
