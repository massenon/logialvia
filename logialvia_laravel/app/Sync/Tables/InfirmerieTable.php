<?php

namespace App\Sync\Tables;

use App\Models\EntreeInfirmerie;
use App\Sync\TableSync;
use Illuminate\Validation\Rule;

/**
 * Infirmerie / quarantaine : FAIT saisi au poste, dernier ecrivain gagne, par UUID
 * (`46_` §2.3, `46c_`).
 *
 * `categorie_mortalite` dit « ce deces est deja compte dans la fiche d'elevage du poste
 * qui l'a declare » : le serveur la conserve et la redistribue telle quelle, sans jamais
 * la rejouer (aucun effet sur une fiche).
 */
class InfirmerieTable extends TableSync
{
    public const NIVEAUX = ['Simple surveillance', 'Infirmerie', 'Quarantaine stricte'];

    public const STATUTS = ['En cours', 'Réintégré', 'Décédé'];

    public function nom(): string
    {
        return 'infirmerie';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return EntreeInfirmerie::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-elevage';
    }

    public function droitEcriture(): ?string
    {
        return 'manage-elevage';
    }

    public function colonnesEcrites(): array
    {
        return [
            'date_entree', 'sujet', 'motif', 'niveau_isolement', 'statut', 'date_sortie', 'espece',
            'categorie_mortalite',
        ];
    }

    public function regles(): array
    {
        return [
            'date_entree' => ['required', 'date_format:Y-m-d'],
            'date_sortie' => ['nullable', 'date_format:Y-m-d'],
            'sujet' => ['required', 'string', 'max:255'],
            'motif' => ['required', 'string', 'max:255'],
            'niveau_isolement' => ['required', Rule::in(self::NIVEAUX)],
            'statut' => ['required', Rule::in(self::STATUTS)],
            'espece' => ['nullable', 'string', 'max:40'],
            'categorie_mortalite' => ['nullable', 'integer', 'min:0'],
        ];
    }

    public function messages(): array
    {
        return [
            'date_entree.required' => "La date d'entrée est invalide.",
            'date_entree.date_format' => "La date d'entrée est invalide.",
            'date_sortie.date_format' => 'La date de sortie est invalide.',
            'sujet.required' => 'Le sujet est obligatoire.',
            'sujet.max' => 'Le sujet est trop long.',
            'motif.required' => 'Le motif est obligatoire.',
            'motif.max' => 'Le motif est trop long.',
            'niveau_isolement.required' => "Ce niveau d'isolement n'existe pas.",
            'niveau_isolement.in' => "Ce niveau d'isolement n'existe pas.",
            'statut.required' => "Le statut de l'entrée est invalide.",
            'statut.in' => "Le statut de l'entrée est invalide.",
            'categorie_mortalite.integer' => 'La marque de mortalité ne vaut que pour un sujet décédé.',
            'categorie_mortalite.min' => 'La marque de mortalité ne vaut que pour un sujet décédé.',
        ];
    }

    protected function controler(array $ligne): ?string
    {
        $sortie = $ligne['date_sortie'] ?? null;
        $statut = $ligne['statut'];

        if ($sortie !== null && $sortie < $ligne['date_entree']) {
            return "La sortie ne peut précéder l'entrée.";
        }
        if ($statut !== 'En cours' && $sortie === null) {
            return 'Une entrée clôturée doit avoir une date de sortie.';
        }
        if ($statut === 'En cours' && $sortie !== null) {
            return "Une entrée en cours n'a pas de date de sortie.";
        }
        if (($ligne['categorie_mortalite'] ?? null) !== null && $statut !== 'Décédé') {
            return 'La marque de mortalité ne vaut que pour un sujet décédé.';
        }

        return null;
    }
}
