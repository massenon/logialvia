<?php

namespace App\Sync\Tables;

use App\Models\MouvementProduit;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Services\PosteDeStock;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Validator;

/**
 * Journal des corrections de stock des produits vendables : FAIT IMMUABLE.
 *
 * Meme decision que pour les intrants : le serveur enregistre et redistribue
 * l'historique, il ne l'applique a AUCUN stock. Les ventes et leurs annulations
 * voyagent deja avec leurs lignes : seules les corrections manuelles sont journalisees.
 */
class MouvementsProduitTable extends TableSync
{
    public const DROITS_LECTURE = ['view-ventes', 'view-stocks'];

    public const DROITS_ECRITURE = ['manage-ventes', 'manage-stocks'];

    public function nom(): string
    {
        return 'mouvements_produit';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return MouvementProduit::class;
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
            'produit_id' => ['required', 'uuid'],
            'article' => ['required', 'string', 'max:255'],
            'motif' => ['required', 'string', 'max:255'],
            'quantite' => ['required', 'numeric'],
            'poste_cible' => ['nullable', 'uuid'],
        ], [
            'poste_cible.uuid' => 'Le poste de stock doit être un identifiant de poste valide.',
            'id.required' => "L'identifiant du mouvement est obligatoire.",
            'id.uuid' => "L'identifiant du mouvement doit être un UUID.",
            'horodatage.required' => 'La date du mouvement est obligatoire.',
            'horodatage.date' => 'La date du mouvement est invalide.',
            'produit_id.required' => 'Le produit du mouvement est obligatoire.',
            'produit_id.uuid' => 'Le produit du mouvement doit être un UUID.',
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
        if (! ProduitVendable::query()->whereKey($ligne['produit_id'])->exists()) {
            return "Produit inconnu du serveur : « {$ligne['produit_id']} ».";
        }

        // Immuable : un mouvement deja connu est accepte sans rien changer (rejeu).
        if (MouvementProduit::query()->whereKey($ligne['id'])->exists()) {
            return null;
        }

        // `47s_` : une correction saisie au web désigne le poste dont le stock la subira ; seul ce
        // poste l'applique (une fois). Seul le web désigne, et le poste doit être désignable.
        $cible = $ligne['poste_cible'] ?? null;
        if (($motif = PosteDeStock::controlerDesignation($deviceId, $cible, PosteDeStock::CORRECTION)) !== null) {
            return $motif;
        }

        (new MouvementProduit)->forceFill([
            'id' => $ligne['id'],
            'device_id' => $deviceId,
            'poste_cible' => $cible,
            'horodatage' => CarbonImmutable::parse($ligne['horodatage'])->utc(),
            'produit_id' => $ligne['produit_id'],
            'article' => $ligne['article'],
            'motif' => $ligne['motif'],
            'quantite' => $ligne['quantite'],
            'serveur_modifie_le' => CarbonImmutable::now('UTC'),
        ])->save();

        return null;
    }
}
