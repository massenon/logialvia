<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Message a l'editeur — FAIT synchronise (doc 47u §4). Dates a la microseconde (curseur de tirage). */
class MessageEditeur extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $table = 'messages_editeur';

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'horodatage' => 'datetime',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'supprime_le' => 'datetime',
        ];
    }

    public function estBug(): bool
    {
        return $this->type === 'bug';
    }
}
