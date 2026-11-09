<?php

namespace App\Livewire;

use App\Models\FicheJournee;
use App\Models\LigneVente;
use App\Models\ModuleActif;
use App\Support\FilieresElevage;
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
        $config = FilieresElevage::configuration($espece);
        $base = [
            'espece' => $espece, 'libelle' => $config['libelle'], 'route' => $config['route'],
            'libelle_jeunes' => self::LIBELLE_JEUNES[$espece] ?? 'Jeunes',
            'effectif' => 0, 'matures' => 0, 'jeunes' => 0, 'mortalite' => 0.0, 'a_des_donnees' => false,
        ];

        $derniere = FicheJournee::query()->where('espece', $espece)->where('is_recorded', true)->orderByDesc('date')->first();
        if ($derniere === null) {
            return $base;
        }

        $debutMois = $this->maintenant()->startOfMonth()->format('Y-m-d');
        $jours = FicheJournee::query()->where('espece', $espece)->where('is_recorded', true)
            ->where('date', '>=', $debutMois)->orderBy('date')->get();

        $mortalite = 0.0;
        if ($jours->isNotEmpty()) {
            $morts = fn (FicheJournee $j): int => $j->mort_cat1 + $j->mort_cat2 + $j->mort_cat3 + ($j->mort_cat4 ?? 0);
            $premier = $jours->first();
            $denominateur = $premier->effectif + $morts($premier);
            $mortalite = $denominateur === 0 ? 0.0 : $jours->sum($morts) / $denominateur * 100;
        }

        return [
            'effectif' => $derniere->effectif, 'matures' => $derniere->eff_cat3_day,
            'jeunes' => $derniere->eff_cat2_day, 'mortalite' => $mortalite, 'a_des_donnees' => true,
        ] + $base;
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
            'peutParametrer' => Auth::user()?->can('view-parametres') ?? false,
        ])->title('Dashboard Élevage');
    }
}
