<?php

namespace App\Services;

use App\Models\Poste;
use App\Models\User;
use App\Support\Audit;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Le web « pousse » vers les postes sans jamais les joindre (blueprint §5) :
 *  1. DEMANDE de synchronisation : un drapeau valable 60 min, servi une fois par poste ;
 *  2. RESYNCHRONISATION (« Renvoyer vers ce poste ») : le poste repart d'un tirage
 *     COMPLET puis acquitte.
 */
class DemandesSynchronisationService
{
    public const VALIDITE_MINUTES = 60;

    /** @param string|null $deviceId null = tous les postes */
    public function demander(User $acteur, ?string $deviceId): void
    {
        DB::table('demandes_synchronisation')->insert([
            'id' => (string) Str::uuid(),
            'device_id' => $deviceId,
            'demandee_par' => $acteur->id,
            'expire_le' => now()->addMinutes(self::VALIDITE_MINUTES),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        Audit::enregistrer('sync.demande', $acteur, ['poste' => $deviceId ?? 'tous']);
    }

    /**
     * Lecture par un poste : vrai s'il existe une demande valide, pas encore servie
     * POUR LUI. La lecture la marque servie : une seule synchronisation par demande.
     */
    public function lirePour(string $deviceId): bool
    {
        return DB::transaction(function () use ($deviceId) {
            $ids = DB::table('demandes_synchronisation as d')
                ->where('d.expire_le', '>', now())
                ->where(fn ($q) => $q->whereNull('d.device_id')->orWhere('d.device_id', $deviceId))
                ->whereNotExists(fn ($q) => $q->select(DB::raw(1))
                    ->from('demandes_synchronisation_servies as s')
                    ->whereColumn('s.demande_id', 'd.id')
                    ->where('s.device_id', $deviceId))
                ->lockForUpdate()
                ->pluck('d.id');

            foreach ($ids as $id) {
                DB::table('demandes_synchronisation_servies')->insert([
                    'demande_id' => $id, 'device_id' => $deviceId, 'servie_le' => now(),
                ]);
            }

            return $ids->isNotEmpty();
        });
    }

    /** Memorise le curseur rendu au poste (a la dernière page d'un tirage). */
    public function memoriserCurseur(string $deviceId, string $curseur): void
    {
        Poste::query()->where('device_id', $deviceId)->update(['curseur_tirage' => $curseur]);
    }

    /** « Renvoyer vers ce poste ». Null si le poste est inconnu. */
    public function renvoyer(User $acteur, string $deviceId): ?bool
    {
        $poste = Poste::query()->where('device_id', $deviceId)->first();
        if ($poste === null) {
            return null;
        }

        $poste->forceFill(['resync_demandee_le' => now()])->save();
        Audit::enregistrer('sync.resynchronisation_demandee', $acteur, ['poste' => $poste->code]);

        return true;
    }

    public function resynchronisationDemandee(string $deviceId): bool
    {
        return Poste::query()->where('device_id', $deviceId)->whereNotNull('resync_demandee_le')->exists();
    }

    /** Acquittement du poste : il a refait un tirage complet. */
    public function acquitter(string $deviceId): void
    {
        Poste::query()->where('device_id', $deviceId)->update(['resync_demandee_le' => null]);
    }
}
