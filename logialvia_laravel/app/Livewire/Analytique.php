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

    public function render()
    {
        $annee = $this->annee();
        [$ecritures] = $this->ecritures($annee);
        $a = MoteurComptable::analytique($ecritures);
        $centres = $a['centres'];

        $revenus = array_sum(array_column($centres, 'revenus'));
        $couts = array_sum(array_column($centres, 'couts'));
        $marge = $revenus - $couts;

        return view('livewire.comptabilite.analytique', $this->communes($annee) + [
            'titre' => 'Comptabilité Analytique',
            'description' => "Marges réelles par activité, calculées sur les écritures de l'exercice $annee.",
            'centres' => $centres,
            'totalRevenus' => $revenus,
            'totalCouts' => $couts,
            'totalMarge' => $marge,
            'tauxTotal' => abs($revenus) < 0.01 ? null : $marge / $revenus * 100,
            'chargesNonAffectees' => $a['charges_non_affectees'],
            'revenuMaximum' => $centres === [] ? 0.0 : max(0.0, ...array_column($centres, 'revenus')),
        ])->title('Comptabilité Analytique');
    }
}
