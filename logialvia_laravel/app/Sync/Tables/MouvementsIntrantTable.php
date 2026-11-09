<?php

namespace App\Sync\Tables;

use App\Models\Intrant;
use App\Models\MouvementIntrant;
use App\Models\User;
use App\Services\PosteDeStock;
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
            'poste_cible' => ['nullable', 'uuid'],
        ], [
            'poste_cible.uuid' => 'Le poste de stock doit être un identifiant de poste valide.',
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
        if (! Intrant::withoutGlobalScopes()->whereKey($ligne['intrant_code'])->exists()) {
            return "Intrant inconnu du serveur : « {$ligne['intrant_code']} ».";
        }

        // Immuable : un mouvement deja connu est accepte sans rien changer (rejeu).
        if (MouvementIntrant::query()->whereKey($ligne['id'])->exists()) {
            return null;
        }

        // `47s_` : INFORMATIF — le poste que le web a désigné pour la réception ou l'annulation
        // qui produit cette ligne. L'effet de stock est porté par l'ACHAT, jamais par ce journal.
        // Pas de contrôle « révoqué » ici : annuler une commande dont le poste a été révoqué
        // depuis doit rester possible (l'écran prévient que l'effet ne s'appliquera pas).
        $cible = $ligne['poste_cible'] ?? null;
        if ($cible !== null && $deviceId !== \App\Livewire\Catalogue::POSTE_WEB) {
            return PosteDeStock::MOTIF_SEUL_LE_WEB;
        }

        (new MouvementIntrant)->forceFill([
            'id' => $ligne['id'],
            'device_id' => $deviceId,
            'poste_cible' => $cible,
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
