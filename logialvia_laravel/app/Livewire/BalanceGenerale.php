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

    /** Donnees de l'ecran : la vue ET l'export XLSX lisent la meme source. */
    private function donnees(): array
    {
        $annee = $this->annee();
        $ecritures = $this->duLivre($annee);
        [, $ouvertureNette] = $this->ecritures($annee);
        $plan = LivreComptable::plan();

        // Sur un exercice passe, « mois en cours » n'a pas de sens : on prend decembre.
        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));
        $mois = $annee === (int) $maintenant->year ? (int) $maintenant->month : 12;
        $borne = CarbonImmutable::create($annee, $mois, 1, 0, 0, 0, config('logialvia.fuseau'));
        $libelleMois = self::MOIS[$mois - 1].' '.$annee;

        if ($this->perimetre === 'mois') {
            // Tout ce qui precede le 1er du mois (a-nouveaux compris) bascule dans l'ouverture.
            $ouverture = $ouvertureNette;
            foreach ($ecritures->filter(fn (LigneEcriture $e) => $e->date->lessThan($borne)) as $e) {
                $ouverture[$e->compte] = ($ouverture[$e->compte] ?? 0.0) + $e->debit - $e->credit;
            }
            $lignes = MoteurComptable::balanceDepuis(
                $plan,
                $ouverture,
                $ecritures->filter(fn (LigneEcriture $e) => ! $e->date->lessThan($borne)),
            );
        } else {
            $lignes = MoteurComptable::balanceDepuis($plan, $ouvertureNette, $ecritures);
        }

        $somme = fn (string $cle) => array_sum(array_column($lignes, $cle));

        return $this->communes($annee) + [
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
        ];
    }

    public function render()
    {
        return view('livewire.comptabilite.balance', $this->donnees())->title('Balance Générale');
    }

    /** Export XLSX du tableau affiche (memes filtres) : `view-comptabilite`, verifie ici. */
    public function exporter(): \Symfony\Component\HttpFoundation\StreamedResponse
    {
        abort_unless(\Illuminate\Support\Facades\Auth::user()?->can('view-comptabilite'), 403);

        $d = $this->donnees();
        $lignes = [['Balance Générale — exercice '.$d['annee']], ['Compte', 'Libellé', 'Ouverture débit', 'Ouverture crédit', 'Mouvements débit', 'Mouvements crédit', 'Solde débit', 'Solde crédit']];
        foreach ($d['lignes'] as $l) {
            $lignes[] = [$l['numero'], $l['libelle'], (int) round($l['ouverture_debit']), (int) round($l['ouverture_credit']), (int) round($l['mouvements_debit']), (int) round($l['mouvements_credit']), (int) round($l['final_debit']), (int) round($l['final_credit'])];
        }
        $t = $d['totaux'];
        $lignes[] = ['Total', '', (int) round($t['ouverture_debit']), (int) round($t['ouverture_credit']), (int) round($t['mouvements_debit']), (int) round($t['mouvements_credit']), (int) round($t['final_debit']), (int) round($t['final_credit'])];

        $annee = $this->annee();

        return \App\Support\ExportXlsx::telecharger($lignes, 'balance-generale-'.$annee.'.xlsx', 'Balance Générale');
    }
}
