<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Laravel\Sanctum\PersonalAccessToken;

/** Poste appaire (voir la migration `postes`). */
class Poste extends Model
{
    use HasUuids;

    protected $table = 'postes';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'appaire_le' => 'datetime',
            'dernier_contact_le' => 'datetime',
            'revoque_le' => 'datetime',
        ];
    }

    public function dernierUtilisateur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'dernier_utilisateur_id')->withTrashed();
    }

    /** Jetons NON expires portant le nom de ce poste. */
    public function jetonsActifs()
    {
        return PersonalAccessToken::query()
            ->where('name', $this->device_id)
            ->where(fn ($q) => $q->whereNull('expires_at')->orWhere('expires_at', '>', now()));
    }

    /** `appaire` · `revoque` · `sans_jeton` (jeton expire ou supprime). */
    public function etat(): string
    {
        if ($this->revoque_le !== null) {
            return 'revoque';
        }

        return $this->jetonsActifs()->exists() ? 'appaire' : 'sans_jeton';
    }

    /** Code suivant : `P1`, `P2`... (`P0` est reserve a un poste jamais appaire). */
    public static function prochainCode(): string
    {
        $max = self::query()->pluck('code')
            ->map(fn (string $c) => (int) substr($c, 1))
            ->max() ?? 0;

        return 'P'.($max + 1);
    }
}
