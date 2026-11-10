<?php

namespace App\Sync\Tables;

use App\Models\MessageEditeur;
use App\Sync\TableSync;

/**
 * Messages a l'editeur (doc 47u §4) : FAIT saisi au poste ou au web, dernier ecrivain gagne par UUID.
 * Lecture et ecriture ouvertes a tout compte authentifie (comme le poste, ou chacun voit le registre
 * des messages). Aucun envoi d'e-mail n'existe : le serveur CONSERVE le message. La suppression est une
 * pierre tombale (`supprime_le`), redistribuee aux postes.
 */
class MessagesEditeurTable extends TableSync
{
    public const TYPES = ['question', 'bug'];

    public const STATUTS = ['En attente', 'Transmis'];

    public function nom(): string
    {
        return 'messages_editeur';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return MessageEditeur::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function colonnesEcrites(): array
    {
        return ['horodatage', 'type', 'sujet', 'message', 'etapes', 'auteur', 'statut', 'supprime_le'];
    }

    public function regles(): array
    {
        return [
            'horodatage' => ['required', 'date'],
            'type' => ['required', 'in:'.implode(',', self::TYPES)],
            'sujet' => ['required', 'string', 'max:255'],
            'message' => ['required', 'string', 'max:10000'],
            'etapes' => ['nullable', 'string', 'max:10000'],
            'auteur' => ['nullable', 'string', 'max:255'],
            'statut' => ['required', 'in:'.implode(',', self::STATUTS)],
            'supprime_le' => ['nullable', 'date'],
        ];
    }

    public function messages(): array
    {
        return [
            'horodatage.required' => 'La date du message est obligatoire.',
            'horodatage.date' => 'La date du message est invalide.',
            'type.required' => 'Le type du message est obligatoire.',
            'type.in' => 'Le type du message est inconnu (question ou problème).',
            'sujet.required' => 'L\'objet est obligatoire.',
            'sujet.max' => 'L\'objet est trop long.',
            'message.required' => 'Le message est obligatoire.',
            'message.max' => 'Le message est trop long.',
            'statut.required' => 'Le statut du message est obligatoire.',
            'statut.in' => 'Le statut du message est inconnu.',
        ];
    }
}
