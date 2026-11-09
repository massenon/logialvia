<?php

namespace App\Livewire;

use App\Models\CycleCouveuse;
use App\Models\MachineIncubateur;
use App\Support\SuiviIncubation;
use Carbon\CarbonImmutable;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Statistiques des Mirages (Dart : `statistiques_mirages_screen.dart`, `statistiques_mirages.dart`).
 *
 * Le TER seul ne dit pas D'OU vient une mauvaise eclosion : trop de clairs au J+7 accusent les
 * reproducteurs, trop de gates au J+14 la conduite de la machine, peu d'eclos sur les retenus la
 * fin d'incubation. Lecture seule : les mirages se saisissent sur l'ecran « Cycle Couveuse ».
 * Les taux sont calcules par `SuiviIncubation` (port des calculs du poste).
 *
 * Ecart avec le Dart : le filtre porte sur l'espece (« Toutes filieres ») et l'incubateur, comme
 * au poste ; la date de reference des mirages manquants est celle d'aujourd'hui (fuseau de
 * l'exploitation) — le poste y applique « Situation au » du Cycle Couveuse, qui n'existe pas ici.
 */
#[Layout('components.layouts.app')]
class StatistiquesMirages extends Component
{
    public string $filtreEspece = '';

    public string $filtreMachine = '';

    public function render()
    {
        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));
        $machines = MachineIncubateur::query()->whereNull('supprime_le')->orderBy('code')->get();

        $lots = CycleCouveuse::query()->whereNull('supprime_le')
            ->orderByDesc('date_incubation')->orderByDesc('code_incubation')->get()
            ->filter(fn (CycleCouveuse $l) => ($this->filtreEspece === '' || $l->espece === $this->filtreEspece)
                && ($this->filtreMachine === '' || $l->machine_id === $this->filtreMachine))
            ->values();

        return view('livewire.statistiques-mirages', [
            'lots' => $lots,
            'agregat' => SuiviIncubation::agregat($lots),
            'manquants' => SuiviIncubation::miragesManquants($lots, $maintenant),
            'machines' => $machines,
            'especes' => SuiviIncubation::ESPECES,
        ])->title('Statistiques des Mirages');
    }
}
