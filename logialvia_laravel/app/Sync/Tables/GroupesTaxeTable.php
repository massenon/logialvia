<?php

namespace App\Sync\Tables;

use App\Models\GroupeTaxe;
use App\Sync\TableSync;

/**
 * Grille de taxation (e-MECeF) : REFERENTIEL, le serveur gagne (`46_` §2.2, `46e_` §1).
 *
 * Le poste ne l'envoie pas (un envoi direct est ignore et journalise) et n'a aucun ecran pour la
 * modifier ; le web non plus (ecart declare). La cle est la LETTRE du groupe, l'`id` un UUID v5
 * deterministe (`groupe_taxe:<lettre>`). Une ligne dont `updated_at == created_at` est une valeur de
 * SEMIS : le poste ne l'applique jamais sur une grille qu'il a corrigee.
 */
class GroupesTaxeTable extends TableSync
{
    public function nom(): string
    {
        return 'groupes_taxe';
    }

    public function nature(): string
    {
        return self::REFERENTIEL;
    }

    protected function modele(): string
    {
        return GroupeTaxe::class;
    }

    public function colonneCurseur(): string
    {
        return 'updated_at';
    }

    public function droitLecture(): ?string
    {
        return 'view-facturation';
    }
}
