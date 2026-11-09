<?php

namespace App\Sync\Tables;

use App\Models\EffetStock;
use App\Models\User;
use App\Support\UuidDeterministe;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Validator;

/**
 * Trace des effets de stock appliqués par le poste que le web a désigné (`47s_`) : FAIT immuable.
 *
 * Le serveur n'applique rien (il n'a pas de stock) : il enregistre ce que le poste a fait, pour
 * que le web affiche « appliqué au poste P2 », « appliqué avec avertissement » ou « en attente »,
 * et le redistribue aux autres postes comme historique (aucun effet chez eux).
 *
 *  - une ligne par (fait, nature) : `id` = UUID v5 de `effet:<nature>:<fait>`, recalculé ici
 *    (un poste ne peut pas forger l'identifiant d'un effet) ;
 *  - immuable : rejoué, accepté sans rien changer ;
 *  - ouvert à tout compte qui écrit : un poste dont le compte ne peut que LIRE les ventes
 *    applique tout de même son effet et doit pouvoir le dire.
 */
class EffetsStockTable extends TableSync
{
    public const FAITS = ['achat', 'vente', 'mouvement_produit'];

    public const NATURES = ['reception', 'annulation_reception', 'vente', 'annulation_vente', 'correction'];

    public const ETATS = ['applique', 'avertissement', 'ignore'];

    public const DROITS_LECTURE = ['view-stocks', 'view-achats', 'view-ventes'];

    public function nom(): string
    {
        return 'effets_stock';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return EffetStock::class;
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
        return true;
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        $v = Validator::make($ligne, [
            'id' => ['required', 'uuid'],
            'fait_type' => ['required', 'string', 'in:'.implode(',', self::FAITS)],
            'fait_id' => ['required', 'uuid'],
            'nature' => ['required', 'string', 'in:'.implode(',', self::NATURES)],
            'reference' => ['nullable', 'string', 'max:60'],
            'libelle' => ['required', 'string'],
            'etat' => ['required', 'string', 'in:'.implode(',', self::ETATS)],
            'avertissement' => ['nullable', 'string'],
            'applique_le' => ['required', 'date'],
        ], [
            'id.required' => "L'identifiant de l'effet est obligatoire.",
            'id.uuid' => "L'identifiant de l'effet doit être un UUID.",
            'fait_type.in' => "Le type du fait de l'effet est inconnu.",
            'fait_id.uuid' => "Le fait de l'effet doit être un UUID.",
            'nature.in' => "La nature de l'effet est inconnue.",
            'libelle.required' => "Le libellé de l'effet est obligatoire.",
            'etat.in' => "L'état de l'effet est inconnu.",
            'applique_le.required' => "La date de l'effet est obligatoire.",
            'applique_le.date' => "La date de l'effet est invalide.",
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if ($ligne['id'] !== UuidDeterministe::effetStock($ligne['fait_id'], $ligne['nature'])) {
            return "L'identifiant de l'effet ne correspond pas à son fait et à sa nature.";
        }

        // Immuable : un effet déjà connu est accepté sans rien changer (rejeu).
        if (EffetStock::query()->whereKey($ligne['id'])->exists()) {
            return null;
        }
        // Une seule trace par (fait, nature) : un autre poste ne peut pas en poser une seconde.
        if (EffetStock::query()->where('fait_id', $ligne['fait_id'])->where('nature', $ligne['nature'])->exists()) {
            return 'Cet effet a déjà été appliqué par un autre poste.';
        }

        (new EffetStock)->forceFill([
            'id' => $ligne['id'],
            'device_id' => $deviceId,
            'fait_type' => $ligne['fait_type'],
            'fait_id' => $ligne['fait_id'],
            'nature' => $ligne['nature'],
            'reference' => $ligne['reference'] ?? null,
            'libelle' => $ligne['libelle'],
            'etat' => $ligne['etat'],
            'avertissement' => $ligne['avertissement'] ?? null,
            'applique_le' => CarbonImmutable::parse($ligne['applique_le'])->utc(),
            'serveur_modifie_le' => CarbonImmutable::now('UTC'),
        ])->save();

        return null;
    }
}
