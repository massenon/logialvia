<?php

namespace App\Sync\Tables;

use App\Models\NoteAnnexe;
use App\Services\Comptabilite\Verrous;
use App\Support\UuidDeterministe;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Validator;

/**
 * Notes annexes (les 5 notes obligatoires SYSCOHADA de chaque exercice).
 *
 * « Dernier ecrivain gagne » a l'instant de SAISIE (strictement), par la cle naturelle
 * (exercice, numero) : l'identifiant est derive (`UuidDeterministe::note`), deux postes
 * qui redigent la meme note ne creent pas de doublon. Rien n'est fusionne.
 */
class NotesAnnexesTable extends TableSync
{
    public function nom(): string
    {
        return 'notes_annexes';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return NoteAnnexe::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-comptabilite';
    }

    public function droitEcriture(): ?string
    {
        return 'manage-comptabilite';
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        $v = Validator::make($ligne, [
            'id' => ['required', 'uuid'],
            'exercice_annee' => ['required', 'integer'],
            'numero_note' => ['required', 'integer', 'between:1,5'],
            'titre' => ['required', 'string', 'max:255'],
            'contenu' => ['present', 'nullable', 'string', 'max:20000'],
            'updated_at' => ['required', 'date'],
        ], [
            'id.required' => "L'identifiant de la note est obligatoire.",
            'id.uuid' => "L'identifiant de la note doit être un UUID.",
            'exercice_annee.required' => "L'exercice de la note est obligatoire.",
            'numero_note.between' => 'Le numéro de note va de 1 à 5.',
            'titre.required' => 'Le titre de la note est obligatoire.',
            'contenu.present' => 'Le contenu de la note est obligatoire (il peut être vide).',
            'contenu.max' => 'Le contenu de la note est trop long.',
            'updated_at.required' => 'La date de saisie de la note est obligatoire.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if ($ligne['id'] !== UuidDeterministe::note((int) $ligne['exercice_annee'], (int) $ligne['numero_note'])) {
            return "L'identifiant de la note ne désigne pas la note {$ligne['numero_note']} de {$ligne['exercice_annee']}.";
        }
        if (Verrous::exercice((int) $ligne['exercice_annee']) === null) {
            return "Exercice {$ligne['exercice_annee']} hors des bornes acceptées.";
        }

        $saisie = CarbonImmutable::parse($ligne['updated_at'])->utc();
        $existante = NoteAnnexe::query()->find($ligne['id']);
        $champs = [
            'titre' => $ligne['titre'],
            'contenu' => (string) ($ligne['contenu'] ?? ''),
        ];

        if ($existante === null) {
            (new NoteAnnexe)->forceFill($champs + [
                'id' => $ligne['id'],
                'device_id' => $deviceId,
                'exercice_annee' => (int) $ligne['exercice_annee'],
                'numero_note' => (int) $ligne['numero_note'],
                'updated_at' => $saisie,
                'serveur_modifie_le' => CarbonImmutable::now('UTC'),
            ])->save();
        } elseif ($saisie->greaterThan($existante->updated_at)) {
            $existante->forceFill($champs + [
                'device_id' => $deviceId,
                'updated_at' => $saisie,
                'serveur_modifie_le' => CarbonImmutable::now('UTC'),
            ])->save();
        }

        return null;
    }
}
