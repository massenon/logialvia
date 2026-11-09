<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\PostesController;
use App\Http\Controllers\Api\SyncController;
use Illuminate\Support\Facades\Route;

/*
| API des postes. Un jeton Sanctum par poste, nomme d'apres son identifiant (UUID).
*/

// Appairage = connexion (5 par minute et par identifiant/adresse).
Route::post('/auth/login', [AuthController::class, 'login'])->middleware('throttle:connexion-api');

Route::middleware(['auth:sanctum', 'compte.actif', 'contact.poste'])->group(function () {
    // Autorises meme avec un mot de passe temporaire.
    Route::get('/auth/me', [AuthController::class, 'me']);
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::post('/auth/mot-de-passe', [AuthController::class, 'changerMotDePasse']);

    Route::middleware('mdp.change')->group(function () {
        Route::post('/parametres/postes/revoquer', [PostesController::class, 'revoquer'])
            ->middleware('can:manage-users');

        Route::get('/sync/pull', [SyncController::class, 'pull']);
        Route::post('/sync/push', [SyncController::class, 'push'])->middleware('poste.jeton');
    });
});
