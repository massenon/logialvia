<?php

namespace App\Livewire;

use App\Livewire\Concerns\LitLeLivre;
use App\Services\Comptabilite\LigneEcriture;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\MoteurComptable;
use Carbon\CarbonImmutable;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Balance Generale (Dart : `BalanceGeneraleScreen`, `balance_generale_screen.dart`).
 *
 * Format a 6 colonnes (Solde Ouverture / Mouvements Periode / Solde Final) calcule par le serveur
 * sur TOUTES les ecritures recues. « Mois en cours » deplace la frontiere entre ouverture et
 * mouvements : tout ce qui precede le 1er du mois — exercices anterieurs compris — bascule dans
 * l'ouverture ; ne filtrer que les lignes affichees donnerait un solde final faux.
 *
 * LECTURE seule. Ecart avec le Dart : pas d'export PDF.
 */
#[Layout('components.layouts.app')]
class BalanceGenerale extends Component
{
    use LitLeLivre;

    public const MOIS = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

    /** `exercice` (complet) ou `mois` (mois en cours). */
    public string $perimetre = 'exercice';

    public function render()
    {
        $annee = $this->annee();
        [$ecritures, $anterieures] = $this->ecritures($annee);
        $plan = LivreComptable::plan();

        // Sur un exercice passe, « mois en cours » n'a pas de sens : on prend decembre.
        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));
        $mois = $annee === (int) $maintenant->year ? (int) $maintenant->month : 12;
        $borne = CarbonImmutable::create($annee, $mois, 1, 0, 0, 0, config('logialvia.fuseau'));
        $libelleMois = self::MOIS[$mois - 1].' '.$annee;

        if ($this->perimetre === 'mois') {
            $lignes = MoteurComptable::balance(
                $plan,
                $anterieures->concat($ecritures->filter(fn (LigneEcriture $e) => $e->date->lessThan($borne))),
                $ecritures->filter(fn (LigneEcriture $e) => ! $e->date->lessThan($borne)),
            );
        } else {
            $lignes = MoteurComptable::balance($plan, $anterieures, $ecritures);
        }

        $somme = fn (string $cle) => array_sum(array_column($lignes, $cle));

        return view('livewire.comptabilite.balance', $this->communes($annee) + [
            'titre' => 'Balance Générale',
            'description' => 'Synthèse des soldes de tous les comptes utilisés sur la période — vérification de l\'équilibre avant clôture.',
            'lignes' => $lignes,
            'totaux' => [
                'ouverture_debit' => $somme('ouverture_debit'),
                'ouverture_credit' => $somme('ouverture_credit'),
                'mouvements_debit' => $somme('mouvements_debit'),
                'mouvements_credit' => $somme('mouvements_credit'),
                'final_debit' => $somme('final_debit'),
                'final_credit' => $somme('final_credit'),
            ],
            'ecart' => MoteurComptable::ecartBalance($lignes),
            'equilibree' => MoteurComptable::balanceEquilibree($lignes),
            'libelleMois' => $libelleMois,
        ])->title('Balance Générale');
    }
}
