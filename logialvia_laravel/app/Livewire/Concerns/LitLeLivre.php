<?php

namespace App\Livewire\Concerns;

use App\Models\ExerciceComptable;
use App\Services\Comptabilite\LigneEcriture;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\Soldes;
use Illuminate\Support\Collection;

/**
 * Socle des ecrans de lecture de la comptabilite : un exercice choisi, les ecritures du
 * SERVEUR (toutes les pieces recues de tous les postes), les soldes. Tous les ecrans lisent
 * la meme source : ils affichent donc le meme Resultat Net (BR-CPT-005).
 */
trait LitLeLivre
{
    /** Exercice demande ; borne aux exercices connus (voir `LivreComptable::exerciceChoisi`). */
    public ?int $exercice = null;

    protected function annee(): int
    {
        return LivreComptable::exerciceChoisi($this->exercice);
    }

    protected function exerciceEstCloture(int $annee): bool
    {
        return (bool) ExerciceComptable::query()->whereKey($annee)->value('is_cloture');
    }

    /** @return array{0: Collection<int, LigneEcriture>, 1: Collection<int, LigneEcriture>} [exercice, anterieures] */
    protected function ecritures(int $annee): array
    {
        $toutes = LivreComptable::toutes();

        return [LivreComptable::exercice($toutes, $annee), LivreComptable::anterieures($toutes, $annee)];
    }

    protected function soldes(Collection $ecritures): Soldes
    {
        return Soldes::depuis($ecritures);
    }

    /** Variables communes de toutes les vues : exercices proposes, exercice choisi, cloture. */
    protected function communes(int $annee): array
    {
        return [
            'annee' => $annee,
            'exercices' => LivreComptable::exercices(),
            'cloture' => $this->exerciceEstCloture($annee),
        ];
    }
}
