<?php

namespace App\Sync\Tables;

use App\Models\Intrant;
use App\Models\User;
use App\Sync\TableSync;

/**
 * Referentiel : le serveur gagne. Un poste ne l'ENVOIE pas, il le PROPOSE
 * (`POST /api/sync/demandes`, type `intrant`). Ni stock, ni PMP : chaque poste tient
 * les siens. Partage entre metiers (stocks, achats, elevage) : lisible par tous.
 */
class IntrantsTable extends TableSync
{
    public const DROITS_LECTURE = ['view-stocks', 'view-achats', 'view-elevage'];

    public function nom(): string
    {
        return 'intrants';
    }

    public function nature(): string
    {
        return self::REFERENTIEL;
    }

    protected function modele(): string
    {
        return Intrant::class;
    }

    /** Les archives (pierres tombales) descendent aussi vers les postes. */
    public function requete(): \Illuminate\Database\Eloquent\Builder
    {
        return Intrant::withoutGlobalScopes();
    }

    public function colonneCurseur(): string
    {
        return 'updated_at';
    }

    public function peutLire(User $utilisateur): bool
    {
        return $this->aUnDesDroits($utilisateur, self::DROITS_LECTURE);
    }

    /** L'ordre de tirage d'un referentiel a cle texte : par code. */
    public function requeteTirage($depuis, $jusqua): \Illuminate\Database\Eloquent\Builder
    {
        $colonne = $this->colonneCurseur();
        $requete = $this->requete()->where($colonne, '<=', $jusqua->format('Y-m-d H:i:s.u'));
        if ($depuis !== null) {
            $requete->where($colonne, '>=', $depuis->format('Y-m-d H:i:s.u'));
        }

        return $requete->orderBy($colonne)->orderBy('code');
    }
}
