<?php

namespace App\Livewire;

use App\Models\FicheJournee;
use App\Models\LigneVente;
use App\Models\ModuleActif;
use App\Models\CycleCouveuse;
use App\Models\SoinCalendrier;
use App\Services\TableauBordService;
use App\Support\FilieresElevage;
use App\Support\SuiviIncubation;
use App\Support\ReperesZootechniques;
use App\Support\RetardDeSoin;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Dashboard Elevage (Dart : `dashboard_elevage_screen.dart`) : les filieres actives en un
 * ecran. Lecture seule.
 *
 * ## Ecarts assumes avec le Dart (donnees absentes du serveur)
 *  - carte « Couveuse », « Rappels Veterinaires a Venir » et « Alertes Sanitaires du Jour » :
 *    cycles de couveuse, soins et stock d'intrants sont propres a d'autres paliers (`P7b`,
 *    `P7c`) ou au poste : cartes grisees « Disponible sur le poste », jamais un zero invente ;
 *  - pas d'export PDF, pas de rappel de prophylaxie a l'ouverture (calendrier non synchronise) ;
 *  - pas d'icones Material Symbols (police non embarquee) ;
 *  - « Revenus Elevage » = ventes d'activite Avicole du mois (hors « Commerce Annexe »), du
 *    1er du mois a maintenant, comme le Dart ; les couts et la marge restent « — » (Dart).
 */
#[Layout('components.layouts.app')]
class DashboardElevage extends Component
{
    /** Categorie des produits comptee a part (Dart : `cat == 'Commerce Annexe'`). */
    public const CATEGORIE_COMMERCE = 'Commerce Annexe';

    /** Filieres toujours actives (Dart : `TableauBordViewModel.especesPermanentes`). */
    public const ESPECES_PERMANENTES = ['goliaths', 'pintades'];

    /** Libelle des jeunes de chaque filiere (Dart : `_libelleJeunesParEspece`). */
    public const LIBELLE_JEUNES = [
        'goliaths' => 'Goliathaux',
        'pintades' => 'Pintadaux',
        'lapins' => 'Lapereaux',
        'escargots' => 'Naissains',
        'bovins' => 'Veaux',
        'poulets' => 'Poulettes',
        'pondeuses' => 'Poulettes',
        'poissons-chats' => 'Juvéniles',
    ];

    /** Filieres a activer, avec leur apercu verrouille (Dart : `_apercus`). */
    public const APERCUS = [
        'cuniculture' => ['Lapins', 'Filière Cuniculture disponible — non activée pour le moment.'],
        'aviculture_classique' => ['Poulets / Pondeuses', 'Filière aviculture classique disponible — non activée pour le moment.'],
        'pisciculture' => ['Poissons-Chats', 'Filière Pisciculture disponible — non activée pour le moment.'],
        'heliciculture' => ['Escargots', 'Filière Héliciculture disponible — non activée pour le moment.'],
        'bovins' => ['Bovins', 'Filière Bovins disponible — non activée pour le moment.'],
    ];

    private function maintenant(): CarbonImmutable
    {
        return CarbonImmutable::now(config('logialvia.fuseau'));
    }

    /** @return array<string, bool> module => actif */
    private function modules(): array
    {
        return ModuleActif::query()->pluck('is_actif', 'module_id')->map(fn ($v) => (bool) $v)->all();
    }

    /** @return list<string> Filieres actives : les permanentes puis celles dont le module est actif. */
    private function especesActives(array $modules): array
    {
        $especes = self::ESPECES_PERMANENTES;
        foreach (config('logialvia.modules') as $module => $espece) {
            if (($modules[$module] ?? false) === true) {
                $especes[] = $espece;
            }
        }

        return $especes;
    }

    /**
     * Recensement d'une filiere (Dart : `recensementFiliere`) : la derniere journee SAISIE
     * (toutes dates), et la mortalite du mois = morts / (effectif du 1er jour saisi + ses morts).
     *
     * @return array<string, mixed>
     */
    private function recensement(string $espece): array
    {
        return app(TableauBordService::class)->recensement($espece, $this->maintenant());
    }

    /**
     * GMQ (g/j/sujet) des filieres actives sur les 28 derniers jours, d'apres les pesees des fiches
     * (poids moyen = pesee / effectif) ; une filiere sans deux pesees n'a pas de GMQ (`47e_`).
     *
     * @param  list<string>  $especes
     * @return array<string, array{gmq: float, poids_initial_g: float, poids_final_g: float, jours: int}>
     */
    private function gmqParFiliere(array $especes): array
    {
        $debut = $this->maintenant()->startOfDay()->subDays(28)->format('Y-m-d');
        $resultat = [];
        foreach ($especes as $espece) {
            $pesees = FicheJournee::query()->where('espece', $espece)->where('is_recorded', true)
                ->whereNotNull('poids_general_g')->where('date', '>=', $debut)->get()
                ->map(fn (FicheJournee $f) => ['date' => $f->date, 'poids_total_g' => (int) $f->poids_general_g, 'effectif' => (int) $f->effectif])->all();
            $gmq = ReperesZootechniques::gmqSurPesees($pesees);
            if ($gmq !== null) {
                $resultat[$espece] = $gmq;
            }
        }

        return $resultat;
    }

    /** @return \Illuminate\Support\Collection<int, SoinCalendrier> Les 5 prochains soins non effectues (Dart : `prochainsSoins`). */
    private function prochainsSoins()
    {
        return SoinCalendrier::query()->where('statut', '!=', 'Effectué')->orderBy('date_prevue')->limit(5)->get();
    }

    /** Statistiques de la couveuse (Dart : `statistiquesCouveuse`) depuis les lots synchronises. */
    private function couveuse(): array
    {
        $lots = CycleCouveuse::query()->whereNull('supprime_le')->get();
        $enCours = $lots->filter(fn (CycleCouveuse $l) => SuiviIncubation::enCours($l));

        return [
            'cycles_en_cours' => $enCours->count(),
            'oeufs_charges' => (int) $enCours->sum('oeufs_couves'),
            'taux_eclosion' => SuiviIncubation::tauxBrutMoyen($lots),
            'poussins_attendus' => SuiviIncubation::poussinsAttendus($lots),
        ];
    }

    /** Revenus Elevage : ventes non annulees du mois hors « Commerce Annexe » (Dart : `.avicole`). */
    private function revenusElevage(): float
    {
        $maintenant = $this->maintenant();
        $borne = fn (CarbonImmutable $i): string => $i->utc()->format('Y-m-d H:i:s.u');

        return (float) LigneVente::query()
            ->join('ventes', 'ventes.id', '=', 'lignes_vente.vente_id')
            ->join('produits_vendables', 'produits_vendables.id', '=', 'lignes_vente.produit_id')
            ->whereBetween('ventes.date_vente', [$borne($maintenant->startOfMonth()), $borne($maintenant)])
            ->where('ventes.status', '!=', 'Annulée')
            ->where('produits_vendables.cat', '!=', self::CATEGORIE_COMMERCE)
            ->get(['lignes_vente.qte', 'lignes_vente.pu'])
            ->sum(fn ($l) => $l->qte * $l->pu);
    }

    public function render()
    {
        $modules = $this->modules();

        return view('livewire.dashboard-elevage', [
            'filieres' => array_map(fn (string $e) => $this->recensement($e), $this->especesActives($modules)),
            'apercus' => collect(self::APERCUS)->filter(fn ($a, $module) => ! ($modules[$module] ?? false))->all(),
            'revenus' => $this->revenusElevage(),
            'gmq' => $this->gmqParFiliere($this->especesActives($modules)),
            'couveuse' => $this->couveuse(),
            'aujourdhui' => $this->maintenant()->format('Y-m-d'),
            'rappels' => $this->prochainsSoins(),
            'alertes' => SoinCalendrier::query()->where('statut', '!=', 'Effectué')->orderBy('date_prevue')->get()
                ->filter(fn (SoinCalendrier $s) => RetardDeSoin::estEnRetard($s, $this->maintenant()->format('Y-m-d')))->values(),
            'libellesEspeces' => FilieresElevage::LIBELLES,
            'peutParametrer' => Auth::user()?->can('view-parametres') ?? false,
        ])->title('Dashboard Élevage');
    }
}
