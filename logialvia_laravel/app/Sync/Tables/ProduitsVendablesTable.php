<?php

namespace App\Sync\Tables;

use App\Models\ProduitVendable;
use App\Sync\TableSync;

/**
 * Referentiel : le serveur gagne. Un poste ne l'ENVOIE pas, il le PROPOSE
 * (`POST /api/sync/demandes`, type `produit_vendable`). Le stock n'est jamais servi.
 */
class ProduitsVendablesTable extends TableSync
{
    public function nom(): string
    {
        return 'produits_vendables';
    }

    public function nature(): string
    {
        return self::REFERENTIEL;
    }

    protected function modele(): string
    {
        return ProduitVendable::class;
    }

    public function colonneCurseur(): string
    {
        return 'updated_at';
    }

    public function droitLecture(): ?string
    {
        return 'view-ventes';
    }
}
