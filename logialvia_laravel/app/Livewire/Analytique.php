<?php

namespace App\Livewire;

use App\Livewire\Concerns\LitLeLivre;
use App\Services\Comptabilite\MoteurComptable;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Comptabilite Analytique (Dart : `ComptabiliteAnalytiqueScreen`, `comptabilite_analytique_screen.dart`).
 *
 * Marges par centre de profit, ventilees depuis l'AXE analytique des ecritures quand il est
 * renseigne (il prime), a defaut depuis le numero de compte. Une ligne comptee par l'axe n'est
 * jamais recomptee. Les charges de structure ne sont JAMAIS reparties au prorata : une cle de
 * repartition que personne n'a fixee donnerait des marges fausses avec l'air d'etre exactes.
 *
 * LECTURE seule, calculee sur toutes les ecritures recues de tous les postes.
 * Ecart avec le Dart : pas d'export PDF.
 */
#[Layout('components.layouts.app')]
class Analytique extends Component
{
    use LitLeLivre;

    /** Donnees de l'ecran : la vue ET l'export XLSX lisent la meme source. */
    private function donnees(): array
    {
        $annee = $this->annee();
        [$ecritures] = $this->ecritures($annee);
        $a = MoteurComptable::analytique($ecritures);
        $centres = $a['centres'];

        $revenus = array_sum(array_column($centres, 'revenus'));
        $couts = array_sum(array_column($centres, 'couts'));
        $marge = $revenus - $couts;

        return $this->communes($annee) + [
            'titre' => 'Comptabilité Analytique',
            'description' => "Marges réelles par activité, calculées sur les écritures de l'exercice $annee.",
            'centres' => $centres,
            'totalRevenus' => $revenus,
            'totalCouts' => $couts,
            'totalMarge' => $marge,
            'tauxTotal' => abs($revenus) < 0.01 ? null : $marge / $revenus * 100,
            'chargesNonAffectees' => $a['charges_non_affectees'],
            'revenuMaximum' => $centres === [] ? 0.0 : max(0.0, ...array_column($centres, 'revenus')),
        ];
    }

    public function render()
    {
        return view('livewire.comptabilite.analytique', $this->donnees())->title('Comptabilité Analytique');
    }

    /** Export XLSX du tableau affiche (memes filtres) : `view-comptabilite`, verifie ici. */
    public function exporter(): \Symfony\Component\HttpFoundation\StreamedResponse
    {
        abort_unless(\Illuminate\Support\Facades\Auth::user()?->can('view-comptabilite'), 403);

        $d = $this->donnees();
        $lignes = [['Comptabilité Analytique — exercice '.$d['annee']], ['Centre', 'Revenus', 'Coûts', 'Marge']];
        foreach ($d['centres'] as $c) {
            $lignes[] = [$c['nom'], (int) round($c['revenus']), (int) round($c['couts']), (int) round($c['revenus'] - $c['couts'])];
        }
        $lignes[] = ['Total', (int) round($d['totalRevenus']), (int) round($d['totalCouts']), (int) round($d['totalMarge'])];
        $lignes[] = ['Charges non affectées', '', (int) round($d['chargesNonAffectees'])];

        $annee = $this->annee();

        return \App\Support\ExportXlsx::telecharger($lignes, 'comptabilite-analytique-'.$annee.'.xlsx', 'Comptabilité Analytique');
    }
}
