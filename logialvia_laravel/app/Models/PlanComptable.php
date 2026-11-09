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

    /** Un compte cree sans version est du plan SYSCOHADA courant (les anciens comptes sont migres). */
    protected $attributes = ['plan_version' => \App\Support\PlanSyscohada::VERSION];

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
        // Comptes debiteurs au milieu de classes crediteuses (SYSCOHADA revise) : 409 fournisseurs debiteurs,
        // 421 personnel avances, 445 Etat TVA recuperable, 4449 credit de TVA a reporter (`47p_`).
        if (str_starts_with($n, '409') || str_starts_with($n, '421') || str_starts_with($n, '445') || str_starts_with($n, '4449')) {
            return true;
        }
        if (str_starts_with($n, '419') || str_starts_with($n, '40')
            || str_starts_with($n, '42') || str_starts_with($n, '43') || str_starts_with($n, '44')) {
            return false;
        }

        return true;
    }
}
