<?php

namespace App\Sync\Tables;

use App\Models\Client;
use App\Sync\TableSync;

/**
 * Fait saisi au poste : dernier ecrivain gagne, par UUID. `solde_creance` est
 * DERIVE (ventes) : calcule par le serveur, jamais accepte d'un poste.
 */
class ClientsTable extends TableSync
{
    public function nom(): string
    {
        return 'clients';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return Client::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-ventes';
    }

    public function droitEcriture(): ?string
    {
        return 'manage-ventes';
    }

    /** Colonnes qu'un poste peut ecrire (le reste est derive ou pose par le serveur). */
    public function colonnesEcrites(): array
    {
        return ['nom', 'telephone', 'date_naissance', 'dernier_contact', 'supprime_le'];
    }

    /** Regles de validation d'une ligne poussee. */
    public function regles(): array
    {
        return [
            'nom' => ['required', 'string', 'max:255'],
            'telephone' => ['nullable', 'string', 'max:40'],
            'date_naissance' => ['nullable', 'date'],
            'dernier_contact' => ['nullable', 'date'],
            'supprime_le' => ['nullable', 'date'],
        ];
    }

    public function messages(): array
    {
        return [
            'nom.required' => 'Le nom du client est obligatoire.',
            'nom.max' => 'Le nom du client est trop long.',
            'date_naissance.date' => 'La date de naissance est invalide.',
            'dernier_contact.date' => 'La date du dernier contact est invalide.',
        ];
    }
}
