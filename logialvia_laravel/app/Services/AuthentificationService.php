<?php

namespace App\Services;

use App\Models\User;
use App\Support\Audit;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Verification d'un couple identifiant / mot de passe, commune a l'API (appairage
 * d'un poste) et au web : les memes regles, les memes messages.
 */
class AuthentificationService
{
    public const MESSAGE_REFUS = 'Identifiant ou mot de passe incorrect.';

    public const MESSAGE_DESACTIVE = "Ce compte a été désactivé. Contactez l'administrateur.";

    /** Empreinte jetable, calculee une fois, au meme cout que les vraies. */
    private static function empreinteFactice(): string
    {
        static $empreinte = null;

        return $empreinte ??= Hash::make(Str::random(32));
    }

    /**
     * @return array{utilisateur: ?User, erreur: ?string, statut: int}
     */
    public function verifier(string $identifiant, string $motDePasse, ?string $ip = null, array $contexte = []): array
    {
        $identifiant = trim($identifiant);

        // Nom d'utilisateur court OU e-mail (colonne `email` si « @ » present).
        $colonne = str_contains($identifiant, '@') ? 'email' : 'username';
        $utilisateur = User::query()->where($colonne, $identifiant)->first();

        // Hash::check meme sans utilisateur : meme duree de reponse, on ne
        // revele pas si l'identifiant existe.
        $valide = Hash::check($motDePasse, $utilisateur?->password ?? self::empreinteFactice());

        if (! $valide || $utilisateur === null) {
            Audit::enregistrer('login.failed', null, $contexte, $identifiant, $ip);

            return ['utilisateur' => null, 'erreur' => self::MESSAGE_REFUS, 'statut' => 401];
        }

        if (! $utilisateur->is_active) {
            Audit::enregistrer('login.refused_inactive', $utilisateur, $contexte, null, $ip);

            return ['utilisateur' => null, 'erreur' => self::MESSAGE_DESACTIVE, 'statut' => 403];
        }

        return ['utilisateur' => $utilisateur, 'erreur' => null, 'statut' => 200];
    }
}
