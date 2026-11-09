<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** Compte du plan comptable — REFERENTIEL, cle naturelle : le numero de compte. */
class PlanComptable extends Model
{
    protected $table = 'plan_comptable';

    protected $primaryKey = 'numero_compte';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return ['archive' => 'boolean', 'saisi_le' => 'datetime'];
    }

    /** Sens naturel du solde (BR-CPT-007) : classes 2, 3, 6 debitrices ; 1, 7 creditrices. */
    public function estDebiteurParNature(): bool
    {
        if (in_array($this->classe, ['2', '3', '6'], true)) {
            return true;
        }
        if (in_array($this->classe, ['1', '7'], true)) {
            return false;
        }
        $n = (string) $this->numero_compte;
        if (str_starts_with($n, '419') || str_starts_with($n, '40')
            || str_starts_with($n, '42') || str_starts_with($n, '43') || str_starts_with($n, '44')) {
            return false;
        }

        return true;
    }
}
