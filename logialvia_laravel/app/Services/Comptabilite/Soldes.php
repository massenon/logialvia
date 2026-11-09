<?php

namespace App\Services\Comptabilite;

/**
 * Agregats par compte, base commune de tous les etats financiers (Dart : `SoldesComptes`).
 *
 * BR-CPT-005 applique structurellement : Bilan, Compte de Resultat et TAFIRE lisent tous cette
 * meme agregation. Les soldes sont en NET (debit − credit) : une charge est positive, un produit
 * negatif.
 */
final class Soldes
{
    /** @param array<string, float> $soldes numero de compte => debit − credit */
    public function __construct(private readonly array $soldes = []) {}

    /** @param iterable<LigneEcriture> $ecritures */
    public static function depuis(iterable $ecritures): self
    {
        $soldes = [];
        foreach ($ecritures as $e) {
            $soldes[$e->compte] = ($soldes[$e->compte] ?? 0.0) + $e->debit - $e->credit;
        }

        return new self($soldes);
    }

    public function solde(string $numero): float
    {
        return $this->soldes[$numero] ?? 0.0;
    }

    /** Somme des soldes nets des comptes dont le numero commence par `$prefixe`. */
    public function parPrefixe(string $prefixe): float
    {
        $total = 0.0;
        foreach ($this->soldes as $numero => $solde) {
            if (str_starts_with((string) $numero, $prefixe)) {
                $total += $solde;
            }
        }

        return $total;
    }

    public function parClasse(string $classe): float
    {
        return $this->parPrefixe($classe);
    }

    /** Soldes DEBITEURS des comptes dont le numero commence par `$prefixe`. */
    public function debiteursParPrefixe(string $prefixe): float
    {
        return $this->debiteursParClasse($prefixe);
    }

    /** Soldes CREDITEURS (valeur absolue) des comptes dont le numero commence par `$prefixe`. */
    public function crediteursParPrefixe(string $prefixe): float
    {
        return $this->crediteursParClasse($prefixe);
    }

    /** Soldes DEBITEURS d'une classe (montants positifs uniquement). */
    public function debiteursParClasse(string $classe): float
    {
        $total = 0.0;
        foreach ($this->soldes as $numero => $solde) {
            if (str_starts_with((string) $numero, $classe) && $solde > 0) {
                $total += $solde;
            }
        }

        return $total;
    }

    /** Soldes CREDITEURS d'une classe (valeur absolue des negatifs). */
    public function crediteursParClasse(string $classe): float
    {
        $total = 0.0;
        foreach ($this->soldes as $numero => $solde) {
            if (str_starts_with((string) $numero, $classe) && $solde < 0) {
                $total += -$solde;
            }
        }

        return $total;
    }
}
