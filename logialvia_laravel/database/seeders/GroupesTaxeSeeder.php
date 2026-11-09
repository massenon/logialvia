<?php

namespace Database\Seeders;

use App\Models\GroupeTaxe;
use App\Support\UuidDeterministe;
use Illuminate\Database\Seeder;

/**
 * Grille de taxation, SEMEE A L'IDENTIQUE du poste (`GroupesTaxeSeeder` Dart) : deux groupes,
 * `A` Exonere (l'elevage, arbitrage de la Gerante) et `B` Taux normal 18 %. Les autres lettres de
 * la grille DGI ne sont pas inventees. Idempotent : un groupe present garde son etat.
 * `created_at == updated_at` : valeur de semis, jamais une « decision » du serveur.
 */
class GroupesTaxeSeeder extends Seeder
{
    public const GRILLE = [
        ['code' => 'A', 'libelle' => 'Exonéré', 'taux' => 0.0, 'ordre' => 1],
        ['code' => 'B', 'libelle' => 'Taux normal 18 %', 'taux' => 18.0, 'ordre' => 2],
    ];

    public function run(): void
    {
        foreach (self::GRILLE as $g) {
            GroupeTaxe::query()->firstOrCreate(
                ['code' => $g['code']],
                ['id' => UuidDeterministe::de('groupe_taxe:'.$g['code'])] + $g,
            );
        }
    }
}
