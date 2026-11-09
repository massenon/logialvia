<?php

namespace App\Sync\Tables;

use App\Models\Intrant;
use App\Models\MouvementIntrant;
use App\Models\User;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Validator;

/**
 * Journal des mouvements d'intrants : FAIT IMMUABLE.
 *
 * Decision du client : « stock propre a chaque poste + journal partage ». Le serveur
 * enregistre et redistribue l'historique ; il ne l'applique a AUCUN stock, et un poste
 * qui recoit le mouvement d'un autre ne change pas le sien. Un mouvement ne se modifie
 * jamais : rejoue, il est accepte sans rien changer.
 */
class MouvementsIntrantTable extends TableSync
{
    public const TYPES = ['Entrée', 'Sortie', 'Ajustement'];

    public const DROITS_LECTURE = ['view-stocks', 'view-achats', 'view-elevage'];

    /** Qui produit des mouvements : stocks, achats (reception), elevage (consommation). */
    public const DROITS_ECRITURE = ['manage-stocks', 'manage-achats', 'manage-elevage'];

    public function nom(): string
    {
        return 'mouvements_intrant';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return MouvementIntrant::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function peutLire(User $utilisateur): bool
    {
        return $this->aUnDesDroits($utilisateur, self::DROITS_LECTURE);
    }

    public function peutEcrire(User $utilisateur): bool
    {
        return $this->aUnDesDroits($utilisateur, self::DROITS_ECRITURE);
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        $v = Validator::make($ligne, [
            'id' => ['required', 'uuid'],
            'horodatage' => ['required', 'date'],
            'intrant_code' => ['required', 'string', 'max:40'],
            'article' => ['required', 'string', 'max:255'],
            'type' => ['required', 'string', 'in:'.implode(',', self::TYPES)],
            'motif' => ['required', 'string', 'max:255'],
            'quantite' => ['required', 'numeric'],
            'reference' => ['nullable', 'string', 'max:60'],
        ], [
            'id.required' => "L'identifiant du mouvement est obligatoire.",
            'id.uuid' => "L'identifiant du mouvement doit être un UUID.",
            'horodatage.required' => "La date du mouvement est obligatoire.",
            'horodatage.date' => 'La date du mouvement est invalide.',
            'intrant_code.required' => "Le code de l'intrant est obligatoire.",
            'type.in' => 'Le type de mouvement est inconnu.',
            'motif.required' => 'Le motif du mouvement est obligatoire.',
            'quantite.required' => 'La quantité du mouvement est obligatoire.',
            'quantite.numeric' => 'La quantité du mouvement est invalide.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if ((float) $ligne['quantite'] == 0.0) {
            return 'La quantité d\'un mouvement ne peut pas être nulle.';
        }
        if (! Intrant::query()->whereKey($ligne['intrant_code'])->exists()) {
            return "Intrant inconnu du serveur : « {$ligne['intrant_code']} ».";
        }

        // Immuable : un mouvement deja connu est accepte sans rien changer (rejeu).
        if (MouvementIntrant::query()->whereKey($ligne['id'])->exists()) {
            return null;
        }

        (new MouvementIntrant)->forceFill([
            'id' => $ligne['id'],
            'device_id' => $deviceId,
            'horodatage' => CarbonImmutable::parse($ligne['horodatage'])->utc(),
            'intrant_code' => $ligne['intrant_code'],
            'article' => $ligne['article'],
            'type' => $ligne['type'],
            'motif' => $ligne['motif'],
            'quantite' => $ligne['quantite'],
            'reference' => $ligne['reference'] ?? null,
            'serveur_modifie_le' => CarbonImmutable::now('UTC'),
        ])->save();

        return null;
    }
}
