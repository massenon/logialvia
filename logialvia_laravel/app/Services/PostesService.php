<?php

namespace App\Services;

use App\Models\Poste;
use App\Models\User;
use App\Support\Audit;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\PersonalAccessToken;

/** Appairage et revocation des postes : un seul endroit, API et web. */
class PostesService
{
    /**
     * Appaire un poste a un utilisateur : UN seul jeton actif par poste (se
     * reconnecter supprime l'ancien), duree 90 jours, code de poste stable.
     *
     * @return array{poste: Poste, jeton: string, expire_le: \Illuminate\Support\Carbon}
     */
    public function appairer(User $utilisateur, string $deviceId): array
    {
        return DB::transaction(function () use ($utilisateur, $deviceId) {
            // Meme nom = meme poste : l'ancien jeton meurt, quel que soit le compte.
            PersonalAccessToken::query()->where('name', $deviceId)->delete();

            $poste = Poste::query()->where('device_id', $deviceId)->first();
            if ($poste === null) {
                $poste = Poste::query()->create([
                    'device_id' => $deviceId,
                    'code' => Poste::prochainCode(),
                ]);
            }

            $poste->forceFill([
                'dernier_utilisateur_id' => $utilisateur->id,
                'appaire_le' => now(),
                'dernier_contact_le' => now(),
                'revoque_le' => null, // reappairer leve la revocation ; le code reste.
            ])->save();

            $expireLe = now()->addDays((int) config('logialvia.jeton_duree_jours'));
            $jeton = $utilisateur->createToken($deviceId, ['*'], $expireLe);

            $utilisateur->forceFill(['last_login_at' => now()])->save();

            return ['poste' => $poste, 'jeton' => $jeton->plainTextToken, 'expire_le' => $expireLe];
        });
    }

    /**
     * Revoque un poste : supprime TOUS ses jetons, tous comptes confondus. Le poste
     * recevra 401, suspendra sa synchronisation et redemandera une connexion.
     *
     * @return int|null Nombre de jetons supprimes, `null` si le poste est inconnu.
     */
    public function revoquer(string $deviceId, User $acteur): ?int
    {
        $poste = Poste::query()->where('device_id', $deviceId)->first();

        if ($poste === null) {
            return null;
        }

        return DB::transaction(function () use ($poste, $deviceId, $acteur) {
            $supprimes = PersonalAccessToken::query()->where('name', $deviceId)->delete();
            $poste->forceFill(['revoque_le' => now()])->save();

            Audit::enregistrer('sync.appairage_revoque', $acteur, [
                'poste' => $poste->code,
                'device_id' => $deviceId,
                'jetons_supprimes' => $supprimes,
            ]);

            return $supprimes;
        });
    }
}
