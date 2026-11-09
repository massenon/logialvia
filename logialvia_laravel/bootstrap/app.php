<?php

use App\Http\Middleware\ChangementMotDePasseObligatoireApi;
use App\Http\Middleware\ChangementMotDePasseObligatoireWeb;
use App\Http\Middleware\CompteActif;
use App\Http\Middleware\EnregistrerContactPoste;
use App\Http\Middleware\PosteDuJeton;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Http\Exceptions\ThrottleRequestsException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Un visiteur non connecte de l'API recoit 401 en JSON, jamais une redirection.
        $middleware->redirectGuestsTo(
            fn (Request $request) => $request->is('api/*') ? null : route('login'),
        );

        $middleware->alias([
            'compte.actif' => CompteActif::class,
            'ecran.actif' => \App\Http\Middleware\EcranActif::class,
            'mdp.change' => ChangementMotDePasseObligatoireApi::class,
            'mdp.web' => ChangementMotDePasseObligatoireWeb::class,
            'contact.poste' => EnregistrerContactPoste::class,
            'poste.jeton' => PosteDuJeton::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // L'API repond TOUJOURS en JSON, meme sans en-tete Accept.
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );

        $exceptions->render(function (ThrottleRequestsException $e, Request $request) {
            if ($request->is('api/*')) {
                return response()->json([
                    'message' => 'Trop de tentatives. Réessayez dans '.($e->getHeaders()['Retry-After'] ?? 60).' secondes.',
                    'code' => 'trop_de_tentatives',
                ], 429, $e->getHeaders());
            }
        });
    })->create();
