<?php

namespace Database\Seeders;

use App\Models\ExerciceComptable;
use App\Models\PlanComptable;
use Carbon\CarbonImmutable;
use Illuminate\Database\Seeder;

/**
 * Plan comptable seme A L'IDENTIQUE du poste (`plan_comptable_seeder.dart`, 19 comptes :
 * les 12 comptes reels de `plan-comptable.html`, 3 comptes de capitaux et 4 comptes de
 * depenses). `tests/Feature/ConformitePlanComptableDartTest.php` le compare au Dart.
 *
 * Idempotent : un compte deja present (renomme, archive par la Gerante) n'est jamais
 * touche ; seuls les numeros absents sont ajoutes. Les comptes sont des valeurs de SEMIS
 * (`updated_at == created_at`) : un poste ne les prend pas pour une decision du serveur.
 * Ouvre aussi l'exercice de l'annee courante.
 */
class PlanComptableSeeder extends Seeder
{
    /** @var list<array{0: string, 1: string, 2: string}> numero, libelle, classe */
    public const COMPTES = [
        ['31', 'Stocks de Marchandises (Commerce Annexe)', '3'],
        ['32', 'Stocks de Matières (Intrants Provende)', '3'],
        ['401', 'Fournisseurs', '4'],
        ['411', 'Clients', '4'],
        ['419', 'Clients — Avances Reçues', '4'],
        ['512', 'Banques — Mobile Money', '5'],
        ['531', 'Caisse', '5'],
        ['601', 'Achats de Matières (Intrants Provende)', '6'],
        ['602', 'Achats de Marchandises (Commerce Annexe)', '6'],
        ['622', 'Frais Vétérinaires', '6'],
        ['701', 'Ventes de Produits Avicoles', '7'],
        ['707', 'Ventes de Marchandises (Commerce Annexe)', '7'],
        ['101', 'Capital Social', '1'],
        ['121', 'Report à Nouveau', '1'],
        ['131', 'Résultat de l\'Exercice', '1'],
        ['613', 'Locations', '6'],
        ['616', 'Assurances', '6'],
        ['624', 'Transports', '6'],
        ['628', 'Charges Diverses de Gestion', '6'],
        // Comptes de la cloture annuelle (`47c_`) : reserves, report debiteur, perte, dividendes.
        ['111', 'Réserve Légale', '1'],
        ['118', 'Autres Réserves', '1'],
        ['129', 'Report à Nouveau — Solde Débiteur', '1'],
        ['139', 'Résultat Net : Perte', '1'],
        ['465', 'Associés — Dividendes à Payer', '4'],
    ];

    public function run(): void
    {
        foreach (self::COMPTES as [$numero, $libelle, $classe]) {
            PlanComptable::query()->firstOrCreate(
                ['numero_compte' => $numero],
                ['libelle' => $libelle, 'classe' => $classe, 'archive' => false],
            );
        }

        ExerciceComptable::query()->firstOrCreate(
            ['annee' => (int) CarbonImmutable::now(config('logialvia.fuseau'))->year],
            ['is_cloture' => false],
        );
    }
}
