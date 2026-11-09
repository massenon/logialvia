<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\PostesService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PostesController extends Controller
{
    public function __construct(private readonly PostesService $postes) {}

    /** Revoque un poste (droit `manage-users`) : tous ses jetons, tous comptes. */
    public function revoquer(Request $request): JsonResponse
    {
        $donnees = $request->validate([
            'device_name' => ['required', 'uuid'],
        ], [
            'device_name.required' => "L'identifiant du poste est obligatoire.",
            'device_name.uuid' => "L'identifiant du poste doit être un UUID.",
        ]);

        $supprimes = $this->postes->revoquer($donnees['device_name'], $request->user());

        if ($supprimes === null) {
            return response()->json(['message' => 'Poste inconnu.'], 404);
        }

        return response()->json([
            'message' => "Appairage révoqué : $supprimes jeton(s) supprimé(s).",
            'jetons_supprimes' => $supprimes,
        ]);
    }
}
