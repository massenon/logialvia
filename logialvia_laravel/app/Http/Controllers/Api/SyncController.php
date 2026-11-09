<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\DemandesSynchronisationService;
use App\Sync\MoteurSynchronisation;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Tirage et envoi des postes (`46_` §4). La logique est dans le moteur. */
class SyncController extends Controller
{
    public function __construct(
        private readonly MoteurSynchronisation $moteur,
        private readonly DemandesSynchronisationService $demandes,
    ) {}

    /** Le poste, c'est le NOM de son jeton. */
    private function poste(Request $request): string
    {
        return (string) $request->user()->currentAccessToken()->name;
    }

    public function pull(Request $request): JsonResponse
    {
        $donnees = $request->validate([
            'since' => ['nullable', 'date'],
            'until' => ['nullable', 'date'],
            'page' => ['nullable', 'integer', 'min:1'],
        ], [
            'since.date' => 'Le curseur « since » est invalide.',
            'until.date' => 'Le curseur « until » est invalide.',
            'page.integer' => 'La page doit être un nombre entier.',
            'page.min' => 'La page commence à 1.',
        ]);

        $tirage = $this->moteur->tirage(
            $request->user(),
            $donnees['since'] ?? null,
            $donnees['until'] ?? null,
            (int) ($donnees['page'] ?? 1),
        );

        // Le curseur n'est memorise qu'a la DERNIERE page (comme chez le poste).
        if ($tirage['page'] >= $tirage['last_page']) {
            $this->demandes->memoriserCurseur($this->poste($request), $tirage['server_time']);
        }

        return response()->json($tirage);
    }

    /** Interrogee par le poste (toutes les 30 s) : « synchronise maintenant ? ». */
    public function demande(Request $request): JsonResponse
    {
        $poste = $this->poste($request);

        return response()->json([
            'synchroniser' => $this->demandes->lirePour($poste),
            'resynchronisation_complete' => $this->demandes->resynchronisationDemandee($poste),
        ]);
    }

    /** Le poste a refait un tirage complet. */
    public function acquittement(Request $request): JsonResponse
    {
        $this->demandes->acquitter($this->poste($request));

        return response()->json(['message' => 'Resynchronisation acquittée.']);
    }

    public function push(Request $request): JsonResponse
    {
        $donnees = $request->validate([
            'device_id' => ['required', 'uuid'],
            'reset_mark' => ['required', 'string'],
            'tables' => ['present', 'array'],
        ], [
            'reset_mark.required' => 'La marque de remise à zéro est obligatoire.',
            'tables.present' => 'Le lot « tables » est obligatoire (vide si rien à envoyer).',
            'tables.array' => 'Le lot « tables » doit être un objet table => lignes.',
        ]);

        $resultat = $this->moteur->envoi(
            $request->user(),
            $donnees['device_id'],
            $donnees['reset_mark'],
            $donnees['tables'],
        );

        return response()->json($resultat['corps'], $resultat['statut']);
    }
}
