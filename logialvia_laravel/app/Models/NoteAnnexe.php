<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Note annexe — fait « dernier ecrivain gagne » par (exercice, numero). */
class NoteAnnexe extends Model
{
    use HasUuids;

    protected $table = 'notes_annexes';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'exercice_annee' => 'integer',
            'numero_note' => 'integer',
        ];
    }
}
