<?php

namespace App\Support;

use App\Models\SoinCalendrier;

/**
 * Un soin est EN RETARD quand il est marque ainsi, ou quand il est encore « Planifié » alors que
 * sa date est passee (`47e_`, meme regle que le poste : `_statutEffectif`). Se fier au seul statut
 * saisi laissait un vaccin oublie hors des alertes sanitaires.
 */
final class RetardDeSoin
{
    public static function estEnRetard(SoinCalendrier $soin, string $aujourdhui): bool
    {
        return $soin->statut === 'En retard'
            || ($soin->statut === 'Planifié' && $soin->date_prevue->format('Y-m-d') < $aujourdhui);
    }
}
