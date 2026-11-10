<?php

namespace App\Support;

use App\Models\AuditLog;
use App\Models\User;

/** Point de passage UNIQUE du journal d'audit. Jamais de mot de passe dans le detail. */
class Audit
{
    /** @param array<string, mixed> $detail */
    public static function enregistrer(
        string $action,
        ?User $utilisateur = null,
        array $detail = [],
        ?string $identifiant = null,
        ?string $ip = null,
    ): AuditLog {
        unset($detail['password'], $detail['mot_de_passe']);

        return AuditLog::query()->create([
            'action' => $action,
            'utilisateur_id' => $utilisateur?->id,
            'identifiant' => $identifiant ?? $utilisateur?->username,
            'detail' => $detail ?: null,
            'ip' => $ip ?? request()->ip(),
        ]);
    }
}
