<?php

namespace App\Sync\Tables;

use App\Models\Fournisseur;
use App\Sync\TableSync;

/** Fait saisi au poste : dernier ecrivain gagne, par UUID (`46_` §2.3). */
class FournisseursTable extends TableSync
{
    public function nom(): string
    {
        return 'fournisseurs';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return Fournisseur::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-achats';
    }

    public function droitEcriture(): ?string
    {
        return 'manage-achats';
    }

    public function colonnesEcrites(): array
    {
        return ['nom', 'telephone', 'adresse', 'fournit', 'supprime_le'];
    }

    public function regles(): array
    {
        return [
            'nom' => ['required', 'string', 'max:255'],
            'telephone' => ['nullable', 'string', 'max:40'],
            'adresse' => ['nullable', 'string', 'max:255'],
            'fournit' => ['nullable', 'string', 'max:255'],
            'supprime_le' => ['nullable', 'date'],
        ];
    }

    public function messages(): array
    {
        return [
            'nom.required' => 'Le nom du fournisseur est obligatoire.',
            'nom.max' => 'Le nom du fournisseur est trop long.',
        ];
    }
}
