<?php

namespace App\Services\Comptabilite;

use Carbon\CarbonImmutable;

/**
 * Une ligne d'ecriture telle que les lectures la voient (Dart : `Ecriture`). La date est
 * dans le fuseau de l'exploitation : « le mois » et « le jour » d'une ecriture s'y entendent.
 */
final class LigneEcriture
{
    public function __construct(
        public readonly string $id,
        public readonly string $pieceId,
        public readonly int $exercice,
        public readonly string $compte,
        public readonly CarbonImmutable $date,
        public readonly float $debit,
        public readonly float $credit,
        public readonly string $libelle,
        public readonly string $journal,
        public readonly ?string $numeroPiece,
        public readonly ?string $venteRef,
        public readonly ?string $achatRef,
        public readonly ?string $axe,
        public readonly ?string $contrepasseDe,
        public readonly string $deviceId,
        public readonly bool $verrouillee,
    ) {}

    /** Origine automatique : une ecriture generee par une vente ou un achat. */
    public function estAutomatique(): bool
    {
        return $this->venteRef !== null || $this->achatRef !== null;
    }
}
