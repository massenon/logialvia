<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\DemandesSynchronisationService;
use App\Services\PostesService;
use App\Services\RemiseAZeroService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PostesController extends Controller
{
    public function __construct(
        private readonly PostesService $postes,
        private readonly DemandesSynchronisationService $demandes,
        private readonly RemiseAZeroService $remiseAZero,
    ) {}

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

    /** « Synchroniser maintenant » : un poste, ou tous (sans `device_name`). */
    public function synchroniser(Request $request): JsonResponse
    {
        $donnees = $request->validate(['device_name' => ['nullable', 'uuid']], [
            'device_name.uuid' => "L'identifiant du poste doit être un UUID.",
        ]);

        $this->demandes->demander($request->user(), $donnees['device_name'] ?? null);

        return response()->json(['message' => 'Demande de synchronisation déposée (valable 60 minutes).']);
    }

    /** « Renvoyer vers ce poste » : tirage complet au prochain contact. */
    public function renvoyer(Request $request): JsonResponse
    {
        $donnees = $request->validate(['device_name' => ['required', 'uuid']], [
            'device_name.required' => "L'identifiant du poste est obligatoire.",
            'device_name.uuid' => "L'identifiant du poste doit être un UUID.",
        ]);

        if ($this->demandes->renvoyer($request->user(), $donnees['device_name']) === null) {
            return response()->json(['message' => 'Poste inconnu.'], 404);
        }

        return response()->json(['message' => 'Le poste repartira d\'un tirage complet à son prochain contact.']);
    }

    public function remiseAZero(Request $request): JsonResponse
    {
        $donnees = $request->validate(['confirmation' => ['required', 'string']], [
            'confirmation.required' => 'Le mot de confirmation est obligatoire.',
        ]);

        $refus = $this->remiseAZero->executer($request->user(), $donnees['confirmation']);
        if ($refus !== null) {
            return response()->json(['message' => $refus], 403);
        }

        return response()->json(['message' => 'Données d\'activité effacées. Les postes seront remis à zéro à leur prochain tirage.']);
    }
}
