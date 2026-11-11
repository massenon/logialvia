<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\PostesController;
use App\Http\Controllers\Api\SyncController;
use Illuminate\Support\Facades\Route;

/*
| API des postes. Un jeton Sanctum par poste, nomme d'apres son identifiant (UUID).
*/

// Appairage = connexion. Aucune limite d'essais (decision du client : pas de blocage de connexion).
Route::post('/auth/login', [AuthController::class, 'login']);

Route::middleware(['auth:sanctum', 'compte.actif', 'contact.poste'])->group(function () {
    // Autorises meme avec un mot de passe temporaire.
    Route::get('/auth/me', [AuthController::class, 'me']);
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::post('/auth/mot-de-passe', [AuthController::class, 'changerMotDePasse']);

    Route::middleware('mdp.change')->group(function () {
        Route::post('/parametres/postes/revoquer', [PostesController::class, 'revoquer'])
            ->middleware('can:manage-users');

        Route::post('/parametres/postes/synchroniser', [PostesController::class, 'synchroniser'])
            ->middleware('can:manage-users');
        Route::post('/parametres/postes/renvoyer', [PostesController::class, 'renvoyer'])
            ->middleware('can:manage-users');
        Route::post('/parametres/remise-a-zero', [PostesController::class, 'remiseAZero'])
            ->middleware('can:manage-parametres');

        Route::get('/sync/demande', [SyncController::class, 'demande']);
        Route::post('/sync/resynchronisation/acquittement', [SyncController::class, 'acquittement']);
        Route::get('/sync/pull', [SyncController::class, 'pull']);
        Route::post('/sync/push', [SyncController::class, 'push'])->middleware('poste.jeton');
        Route::post('/sync/demandes', [SyncController::class, 'demandes'])->middleware('poste.jeton');
        // `47a2_` : reservation de la transmission d'une facture emise au web.
        Route::post('/sync/factures/reserver', [SyncController::class, 'reserverFacture'])->middleware('poste.jeton');
    });
});
