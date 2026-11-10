<?php

namespace App\Livewire;

use App\Models\Achat;
use App\Models\CycleCouveuse;
use App\Models\FicheJournee;
use App\Models\Intrant;
use App\Models\LigneAchat;
use App\Models\LigneVente;
use App\Models\MouvementIntrant;
use App\Models\MouvementProduit;
use App\Models\Poste;
use App\Models\ProduitVendable;
use App\Support\FilieresElevage;
use App\Support\SuiviIncubation;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Inventaire (Dart : `inventaire_screen.dart`, `inventaire_view_model.dart`,
 * `inventaire_repository_drift.dart`) — LECTURE SEULE, jamais d'ecriture en base.
 *
 * DECISION DU CLIENT : « stock propre a chaque poste + journal partage » (`46_` §14 et §15).
 * Le serveur n'a NI le stock NI le PMP : ce composant ne calcule et n'affiche JAMAIS un stock
 * initial, un stock final, une valeur de stock ni une valorisation. Tout bloc du Dart qui en
 * depend (KPI de valeur, colonnes stock / PMP / valeur, totaux, controle d'equilibre) devient
 * un encart grise « Disponible sur le poste ».
 *
 * Ce qui se deduit des FAITS synchronises sur la periode (memes bornes que le Dart : du debut
 * a 00:00 jusqu'au lendemain de la fin a 00:00 EXCLU, en heure de Porto-Novo ; les colonnes
 * sont en UTC) :
 *  - intrants : entrees (quantite > 0) et sorties (quantite < 0, affichees positives) du journal
 *    de TOUS les postes, comme le Dart les separe par le signe ; ajustements (type) en plus ;
 *    achats livres en plus ;
 *  - produits : quantites vendues (lignes des ventes NON annulees), corrections de stock du
 *    journal des produits ;
 *  - animaux sur pied : dernier effectif REELLEMENT saisi a la fin de la periode, par filiere.
 */
#[Layout('components.layouts.app')]
class Inventaire extends Component
{
    /** Periodes de la barre de filtres (Dart : `PeriodeInventaire`). */
    public const PERIODES = [
        'jour' => 'Journalier',
        'semaine' => 'Hebdomadaire',
        'mois' => 'Mensuel',
        'plage' => 'Plage personnalisée',
    ];

    /** Lignes des deux journaux affichees (le total reel est annonce). */
    public const LIMITE_JOURNAL = 200;

    public string $periode = 'jour';

    /** Bornes `Y-m-d` (jours civils de Porto-Novo). */
    public string $debut = '';

    public string $fin = '';

    public string $recherche = '';

    public function boot(): void
    {
        // A chaque requete (affichage ET appels Livewire) : la route seule ne suffit pas.
        abort_unless(Auth::user()?->can('view-stocks'), 403);
    }

    public function mount(): void
    {
        $this->appliquerPeriode('jour');
    }

    private function maintenant(): CarbonImmutable
    {
        return CarbonImmutable::now(config('logialvia.fuseau'));
    }

    /** Dart : `_appliquerPeriode`. La plage garde les bornes deja choisies. */
    private function appliquerPeriode(string $periode): void
    {
        $this->periode = $periode;
        $jour = $this->maintenant()->startOfDay();

        switch ($periode) {
            case 'jour':
                $this->debut = $this->fin = $jour->format('Y-m-d');
                break;
            case 'semaine':
                // Semaine calendaire, du lundi au jour affiche.
                $this->debut = $jour->startOfWeek(Carbon::MONDAY)->format('Y-m-d');
                $this->fin = $jour->format('Y-m-d');
                break;
            case 'mois':
                $this->debut = $jour->startOfMonth()->format('Y-m-d');
                $this->fin = $jour->format('Y-m-d');
                break;
        }
    }

    public function changerPeriode(string $periode): void
    {
        // « Plage personnalisee » n'est pas cliquable (Dart : `onTap: null`) : elle s'active en choisissant une date.
        if (in_array($periode, ['jour', 'semaine', 'mois'], true)) {
            $this->appliquerPeriode($periode);
        }
    }

    /** Dart : `definirPlage` — la derniere borne choisie fait foi et entraine l'autre si besoin. */
    public function updatedDebut(): void
    {
        $this->periode = 'plage';
        $debut = $this->jour($this->debut);
        $fin = $this->jour($this->fin);
        if ($debut !== null && $fin !== null && $fin->lessThan($debut)) {
            $this->fin = $this->debut;
        }
    }

    public function updatedFin(): void
    {
        $this->periode = 'plage';
        $debut = $this->jour($this->debut);
        $fin = $this->jour($this->fin);
        if ($debut !== null && $fin !== null && $fin->lessThan($debut)) {
            $this->debut = $this->fin;
        }
    }

    /** Jour `Y-m-d` saisi (minuit de Porto-Novo), ou null s'il est invalide. */
    private function jour(string $valeur): ?CarbonImmutable
    {
        try {
            $date = CarbonImmutable::createFromFormat('!Y-m-d', $valeur, config('logialvia.fuseau'));
        } catch (\Carbon\Exceptions\InvalidFormatException) {
            return null;
        }

        return ($date !== false && $date->format('Y-m-d') === $valeur) ? $date : null;
    }

    /** Borne SQL (UTC, a la microseconde comme les colonnes `horodatage` et `date_*`). */
    private static function borne(CarbonImmutable $instant): string
    {
        return $instant->utc()->format('Y-m-d H:i:s.u');
    }

    /** Quantite lisible : jusqu'a 3 decimales utiles, separateur de milliers (le Dart arrondit a l'entier). */
    public static function qte(float $valeur): string
    {
        $v = round($valeur, 3);
        if ($v == 0) {
            return '0';
        }

        return rtrim(rtrim(number_format($v, 3, ',', ' '), '0'), ',');
    }

    /** Poste d'origine d'un mouvement : « Web », son code (`P2`), ou repli sur l'identifiant. */
    private function libellePoste(string $deviceId, array $codes): string
    {
        if ($deviceId === Catalogue::POSTE_WEB) {
            return 'Web';
        }

        return $codes[$deviceId] ?? 'Poste '.Str::substr($deviceId, 0, 8);
    }

    private static function contient(string $terme, string ...$champs): bool
    {
        foreach ($champs as $champ) {
            if (str_contains(mb_strtolower($champ), $terme)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Intrants : une ligne par article du referentiel (Dart : tous, par nom), entrees / sorties du journal.
     *
     * @return list<array<string, mixed>>
     */
    private function intrants(string $depuis, string $jusqua, array $codes, string $terme): array
    {
        $mouvements = MouvementIntrant::query()
            ->where('horodatage', '>=', $depuis)->where('horodatage', '<', $jusqua)
            ->selectRaw("intrant_code,
                SUM(CASE WHEN quantite > 0 THEN quantite ELSE 0 END) AS entrees,
                SUM(CASE WHEN quantite < 0 THEN -quantite ELSE 0 END) AS sorties,
                SUM(CASE WHEN type = 'Ajustement' THEN quantite ELSE 0 END) AS ajustements,
                COUNT(*) AS nombre")
            ->groupBy('intrant_code')->get()->keyBy('intrant_code');

        $postes = MouvementIntrant::query()
            ->where('horodatage', '>=', $depuis)->where('horodatage', '<', $jusqua)
            ->select('intrant_code', 'device_id')->distinct()->get()
            ->groupBy('intrant_code')
            ->map(fn ($lignes) => $lignes->map(fn ($l) => $this->libellePoste($l->device_id, $codes))->sort()->values()->all());

        $achetes = LigneAchat::query()
            ->join('achats', 'achats.id', '=', 'lignes_achat.achat_id')
            ->where('achats.statut', 'Livré')
            ->where('achats.date_achat', '>=', $depuis)->where('achats.date_achat', '<', $jusqua)
            ->selectRaw('lignes_achat.intrant_code AS code, SUM(lignes_achat.qte) AS qte')
            ->groupBy('lignes_achat.intrant_code')->pluck('qte', 'code');

        $lignes = [];
        foreach (Intrant::query()->orderBy('name')->get() as $i) {
            if ($terme !== '' && ! self::contient($terme, $i->name, $i->code, $i->cat)) {
                continue;
            }
            $m = $mouvements->get($i->code);
            $lignes[] = [
                'code' => $i->code,
                'article' => $i->name,
                'categorie' => $i->cat,
                'unite' => $i->unit,
                'entrees' => (float) ($m->entrees ?? 0),
                'sorties' => (float) ($m->sorties ?? 0),
                'ajustements' => (float) ($m->ajustements ?? 0),
                'achetes' => (float) ($achetes[$i->code] ?? 0),
                'postes' => $postes->get($i->code, []),
            ];
        }

        return $lignes;
    }

    /**
     * Produits : vendus (ventes non annulees) et corrections de stock sur la periode.
     * Un produit archive n'apparait que s'il a bouge sur la periode.
     *
     * @return list<array<string, mixed>>
     */
    private function produits(string $depuis, string $jusqua, string $terme): array
    {
        $vendus = LigneVente::query()
            ->join('ventes', 'ventes.id', '=', 'lignes_vente.vente_id')
            ->where('ventes.status', '!=', 'Annulée')
            ->where('ventes.date_vente', '>=', $depuis)->where('ventes.date_vente', '<', $jusqua)
            ->selectRaw('lignes_vente.produit_id AS produit, SUM(lignes_vente.qte) AS qte')
            ->groupBy('lignes_vente.produit_id')->pluck('qte', 'produit');

        $corriges = MouvementProduit::query()
            ->where('horodatage', '>=', $depuis)->where('horodatage', '<', $jusqua)
            ->selectRaw('produit_id AS produit, SUM(quantite) AS net, COUNT(*) AS nombre')
            ->groupBy('produit_id')->get()->keyBy('produit');

        $lignes = [];
        foreach (ProduitVendable::query()->orderBy('name')->get() as $p) {
            $vendu = (float) ($vendus[$p->id] ?? 0);
            $correction = $corriges->get($p->id);
            if ($p->archive_le !== null && $vendu == 0.0 && $correction === null) {
                continue;
            }
            if ($terme !== '' && ! self::contient($terme, $p->name, $p->sku ?? '—', $p->cat)) {
                continue;
            }
            $lignes[] = [
                'sku' => $p->sku ?? '—',
                'produit' => $p->name,
                'categorie' => $p->cat,
                'unite' => $p->unit,
                'vendu' => $vendu,
                'corrections' => (float) ($correction->net ?? 0),
                'nombreCorrections' => (int) ($correction->nombre ?? 0),
                'coutRevient' => $p->cout_revient,
                'archive' => $p->archive_le !== null,
            ];
        }

        return $lignes;
    }

    /**
     * Effectifs : par filiere, la derniere journee REELLEMENT saisie a la fin de la periode (Dart :
     * `_effectifs` — une journee projetee ne temoigne d'aucun comptage).
     *
     * @return list<array{espece: string, libelle: string, effectif: int, dateSaisie: ?string}>
     */
    private function effectifs(CarbonImmutable $fin): array
    {
        $lignes = [];
        foreach (FilieresElevage::LIBELLES as $espece => $libelle) {
            $jour = FicheJournee::query()
                ->where('espece', $espece)->where('is_recorded', true)
                ->whereDate('date', '<=', $fin->format('Y-m-d'))
                ->orderByDesc('date')->first();

            $lignes[] = [
                'espece' => $espece,
                'libelle' => $libelle,
                'effectif' => (int) ($jour?->effectif ?? 0),
                'dateSaisie' => $jour === null ? null : Carbon::parse($jour->date)->format('d/m/Y'),
            ];
        }

        return $lignes;
    }

    /** Œufs encore en machine a la fin de la periode (Dart : `_oeufsEnIncubation`). */
    private function oeufsEnIncubation(CarbonImmutable $fin): int
    {
        return (int) CycleCouveuse::query()
            ->whereNull('supprime_le')
            ->where('statut', SuiviIncubation::EN_INCUBATION)
            ->whereDate('date_incubation', '<=', $fin->format('Y-m-d'))
            ->get()
            ->sum(fn (CycleCouveuse $l) => $l->oeufs_couves - ($l->oeufs_blancs_j7 ?? 0) - ($l->oeufs_gates_j14 ?? 0));
    }

    public function render()
    {
        $debut = $this->jour($this->debut);
        $fin = $this->jour($this->fin);
        $periodeValide = $debut !== null && $fin !== null && $debut->lessThanOrEqualTo($fin);
        if (! $periodeValide) {
            // Periode invalide : on retombe sur le jour (et on le dit) plutot que d'inventer un zero.
            $debut = $fin = $this->maintenant()->startOfDay();
        }

        $jusqua = $fin->addDay();
        $depuis = self::borne($debut);
        $jusquaSql = self::borne($jusqua);
        $terme = mb_strtolower(trim($this->recherche));
        $codes = Poste::query()->pluck('code', 'device_id')->all();
        $zone = config('logialvia.fuseau');

        $journalIntrants = MouvementIntrant::query()
            ->where('horodatage', '>=', $depuis)->where('horodatage', '<', $jusquaSql)
            ->orderByDesc('horodatage');
        $journalProduits = MouvementProduit::query()
            ->where('horodatage', '>=', $depuis)->where('horodatage', '<', $jusquaSql)
            ->orderByDesc('horodatage');

        $effectifs = $this->effectifs($fin);

        return view('livewire.inventaire', [
            'periodeValide' => $periodeValide,
            'libellePeriode' => $debut->equalTo($fin)
                ? 'Situation au '.$fin->format('d/m/Y')
                : 'Du '.$debut->format('d/m/Y').' au '.$fin->format('d/m/Y'),
            'intrants' => $this->intrants($depuis, $jusquaSql, $codes, $terme),
            'produits' => $this->produits($depuis, $jusquaSql, $terme),
            'effectifs' => $effectifs,
            'effectifTotal' => array_sum(array_column($effectifs, 'effectif')),
            'oeufs' => $this->oeufsEnIncubation($fin),
            'journalIntrants' => (clone $journalIntrants)->limit(self::LIMITE_JOURNAL)->get()
                ->map(fn (MouvementIntrant $m) => ['m' => $m, 'poste' => $this->libellePoste($m->device_id, $codes), 'quand' => $m->horodatage->setTimezone($zone)]),
            'totalJournalIntrants' => $journalIntrants->count(),
            'journalProduits' => (clone $journalProduits)->limit(self::LIMITE_JOURNAL)->get()
                ->map(fn (MouvementProduit $m) => ['m' => $m, 'poste' => $this->libellePoste($m->device_id, $codes), 'quand' => $m->horodatage->setTimezone($zone)]),
            'totalJournalProduits' => $journalProduits->count(),
        ])->title('Inventaire');
    }
}
