<?php

namespace App\Sync\Tables;

use App\Models\EcheanceProphylaxie;
use App\Sync\TableSync;

/**
 * Referentiel : le serveur gagne. Un poste ne l'ENVOIE pas, il le PROPOSE
 * (`POST /api/sync/demandes`, type `echeance_prophylaxie`). Pas de cle naturelle unique :
 * seul l'UUID identifie une echeance (deterministe pour le semis, aleatoire sinon).
 */
class CalendrierProphylaxieTable extends TableSync
{
    public function nom(): string
    {
        return 'calendrier_prophylaxie';
    }

    public function nature(): string
    {
        return self::REFERENTIEL;
    }

    protected function modele(): string
    {
        return EcheanceProphylaxie::class;
    }

    public function colonneCurseur(): string
    {
        return 'updated_at';
    }

    public function droitLecture(): ?string
    {
        return 'view-elevage';
    }
}
