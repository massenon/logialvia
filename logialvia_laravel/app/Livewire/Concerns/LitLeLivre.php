<?php

namespace App\Livewire\Concerns;

use App\Models\ExerciceComptable;
use App\Services\Comptabilite\LigneEcriture;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\ReportANouveau;
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

    /**
     * [ecritures COURANTES de l'exercice, soldes d'OUVERTURE]. Les courantes excluent les a-nouveaux
     * (l'ouverture) et les ecritures de cloture (les etats se lisent « avant affectation »). L'ouverture
     * est `compte => solde net` : les a-nouveaux, ou la cloture virtuelle de l'exercice precedent
     * (`ReportANouveau`, `47c_`).
     *
     * @return array{0: Collection<int, LigneEcriture>, 1: array<string, float>}
     */
    protected function ecritures(int $annee): array
    {
        $toutes = LivreComptable::toutes()->all();

        return [
            collect(ReportANouveau::mouvementsCourants($toutes, $annee))->values(),
            ReportANouveau::soldesOuverture($toutes, $annee),
        ];
    }

    /** Lignes du LIVRE (grand livre, balance) : tout sauf les a-nouveaux ; la cloture y figure. */
    protected function duLivre(int $annee): Collection
    {
        return collect(ReportANouveau::mouvementsDuLivre(LivreComptable::toutes()->all(), $annee))->values();
    }

    /** Toutes les lignes de l'exercice, a-nouveaux et cloture compris : le JOURNAL. */
    protected function duJournal(int $annee): Collection
    {
        return LivreComptable::exercice(LivreComptable::toutes(), $annee);
    }

    /** Soldes de FIN d'exercice, ouverture cumulee, cloture exclue : base du bilan, du resultat, du TAFIRE. */
    protected function soldesFin(int $annee): Soldes
    {
        return ReportANouveau::soldesDeFin(LivreComptable::toutes()->all(), $annee);
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
