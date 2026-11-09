<?php

namespace Tests\Concerns;

use App\Models\EcritureComptable;
use App\Models\ExerciceComptable;
use App\Models\PieceComptable;
use App\Models\PlanComptable;
use App\Models\User;
use Carbon\CarbonImmutable;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\PlanComptableSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Support\Str;

/**
 * Un JEU D'ECRITURES CONSTRUIT A LA MAIN, partage avec le Dart : les memes ecritures, les memes
 * montants, les memes chiffres attendus (`logialvia_app/test/comptabilite/jeu_commun_chiffres_test.dart`).
 * Si le web et le poste s'ecartent, l'un des deux tests rougit.
 *
 * Exercice N−1 : l'apport de depart (531 D 100 000 / 101 C 100 000) — il forme l'OUVERTURE.
 * Exercice N, de P1 a P8 : apport, deux ventes, un achat, deux depenses, un encaissement, une
 * immobilisation. Totaux : debit = credit = 987 000.
 */
trait JeuComptable
{
    protected function amorcerPourLesEcrans(): void
    {
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        $this->seed(PlanComptableSeeder::class);
    }

    protected function utilisateurAvecRole(string $role, string $username = 'u'): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    protected function annee(): int
    {
        return (int) now(config('logialvia.fuseau'))->year;
    }

    /** Une piece posee EN BASE comme le serveur l'aurait recue d'un poste (fait immuable). */
    protected function poserPiece(
        string $numero,
        int $annee,
        int $mois,
        int $jour,
        string $journal,
        array $lignes,
        array $surcharge = [],
        string $device = '11111111-1111-4111-8111-111111111111',
    ): PieceComptable {
        ExerciceComptable::query()->firstOrCreate(['annee' => $annee], ['is_cloture' => false]);
        $date = CarbonImmutable::create($annee, $mois, $jour, 10, 0, 0, config('logialvia.fuseau'))->utc();

        $piece = (new PieceComptable)->forceFill(array_merge([
            'id' => (string) Str::uuid(),
            'device_id' => $device,
            'numero_piece' => $numero,
            'date_ecriture' => $date,
            'exercice_annee' => $annee,
            'journal_code' => $journal,
            'vente_ref' => null,
            'achat_ref' => null,
            'contrepasse_de' => null,
            'updated_at' => $date,
            'serveur_modifie_le' => now(),
        ], $surcharge));
        $piece->save();

        foreach ($lignes as [$compte, $debit, $credit, $axe]) {
            (new EcritureComptable)->forceFill([
                'id' => (string) Str::uuid(),
                'piece_id' => $piece->id,
                'numero_compte' => $compte,
                'debit' => $debit,
                'credit' => $credit,
                'libelle' => 'Libelle '.$numero,
                'axe_analytique' => $axe,
            ])->save();
        }

        return $piece;
    }

    /** Le jeu commun : voir l'en-tete du trait. */
    protected function poserLeJeuCommun(): void
    {
        $n = $this->annee();
        PlanComptable::query()->firstOrCreate(
            ['numero_compte' => '231'],
            ['libelle' => 'Bâtiments', 'classe' => '2', 'archive' => false],
        );

        $this->poserPiece('OD-P1-'.($n - 1).'-0001', $n - 1, 12, 20, 'OD', [['531', 100000, 0, null], ['101', 0, 100000, null]]);

        $this->poserPiece('OD-P1-'.$n.'-0001', $n, 1, 2, 'OD', [['531', 500000, 0, null], ['101', 0, 500000, null]]);
        $this->poserPiece('V-P1-'.$n.'-001', $n, 2, 15, 'VT', [['531', 120000, 0, null], ['701', 0, 120000, 'Goliaths']], ['vente_ref' => 'V-P1-'.$n.'-001']);
        $this->poserPiece('V-P1-'.$n.'-002', $n, 3, 10, 'VT', [['531', 30000, 0, null], ['411', 50000, 0, null], ['707', 0, 80000, null]], ['vente_ref' => 'V-P1-'.$n.'-002']);
        $this->poserPiece('ACH-P1-'.$n.'-001', $n, 4, 12, 'AC', [['601', 40000, 0, null], ['531', 0, 10000, null], ['401', 0, 30000, null]], ['achat_ref' => 'ACH-P1-'.$n.'-001']);
        $this->poserPiece('DEP-P1-'.$n.'-0001', $n, 5, 5, 'CA', [['624', 15000, 0, 'Pintades'], ['531', 0, 15000, null]]);
        $this->poserPiece('DEP-P1-'.$n.'-0002', $n, 5, 20, 'CA', [['616', 12000, 0, null], ['401', 0, 12000, null]]);
        $this->poserPiece('REG-V-P1-'.$n.'-002', $n, 6, 15, 'CA', [['531', 20000, 0, null], ['411', 0, 20000, null]], ['vente_ref' => 'V-P1-'.$n.'-002']);
        $this->poserPiece('OD-P1-'.$n.'-0002', $n, 7, 1, 'OD', [['231', 200000, 0, null], ['531', 0, 200000, null]]);
    }
}
