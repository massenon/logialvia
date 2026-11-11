<?php

namespace App\Livewire;

use App\Models\Achat;
use App\Models\Client;
use App\Models\LigneVente;
use App\Models\ModuleActif;
use App\Models\Vente;
use App\Services\Comptabilite\LivreComptable;
use App\Services\TableauBordService;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Tableau de Bord Principal (Dart : `dashboard_screen.dart`, `tableau_bord_view_model.dart`,
 * `tableau_bord_repository_drift.dart`) — LECTURE SEULE.
 *
 * Le web n'affiche que ce que le serveur calcule depuis ses tables synchronisees (ventes, lignes,
 * produits, clients, achats, ecritures comptables, fiches d'elevage, couveuse, soins, journal d'audit).
 * Les calculs d'elevage, de comptabilite et d'alertes vivent dans `TableauBordService`. Chaque cle
 * vaut `null` quand le compte n'a pas le droit de la donnee (le Dart, mono-poste, n'a pas ce filtre)
 * ou quand la donnee n'existe pas sur le serveur : `stockCritique` (le STOCK des intrants est propre
 * a chaque poste, jamais synchronise) — jamais un chiffre invente.
 */
#[Layout('components.layouts.app')]
class TableauDeBord extends Component
{
    /** Categorie des produits comptee a part (Dart : `cat == 'Commerce Annexe'`). */
    public const CATEGORIE_COMMERCE = 'Commerce Annexe';

    /** Abreviations de mois du Dart (`_abreviationMois`). */
    public const MOIS = [1 => 'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun', 'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'];

    /** Filtre de periode, `Y-m-d` (Dart : 1er du mois -> aujourd'hui). */
    public string $debut = '';

    public string $fin = '';

    public function mount(): void
    {
        $maintenant = $this->maintenant();
        $this->debut = $maintenant->startOfMonth()->format('Y-m-d');
        $this->fin = $maintenant->format('Y-m-d');
    }

    private function maintenant(): CarbonImmutable
    {
        return CarbonImmutable::now(config('logialvia.fuseau'));
    }

    private function peut(string $droit): bool
    {
        return Auth::user()?->can($droit) ?? false;
    }

    /** Jour `Y-m-d` saisi, ou null s'il est invalide. */
    private function jour(string $valeur): ?CarbonImmutable
    {
        try {
            $date = CarbonImmutable::createFromFormat('!Y-m-d', $valeur, config('logialvia.fuseau'));
        } catch (\Carbon\Exceptions\InvalidFormatException) {
            return null;
        }

        return ($date !== false && $date->format('Y-m-d') === $valeur) ? $date : null;
    }

    /** Borne SQL (UTC, a la microseconde comme les colonnes `date_*`). */
    private static function borne(CarbonImmutable $instant): string
    {
        return $instant->utc()->format('Y-m-d H:i:s.u');
    }

    /** Lignes (qte, pu, nom, categorie) des ventes NON annulees dont la date est dans [debut, fin], bornes incluses. */
    private function lignes(CarbonImmutable $debut, CarbonImmutable $fin)
    {
        return LigneVente::query()
            ->join('ventes', 'ventes.id', '=', 'lignes_vente.vente_id')
            ->join('produits_vendables', 'produits_vendables.id', '=', 'lignes_vente.produit_id')
            ->whereBetween('ventes.date_vente', [self::borne($debut), self::borne($fin)])
            ->where('ventes.status', '!=', 'Annulée')
            ->get(['lignes_vente.name', 'lignes_vente.qte', 'lignes_vente.pu', 'produits_vendables.cat as categorie']);
    }

    /**
     * CA = somme qte x pu, ventile par categorie du produit (`chiffreAffaires` du Dart).
     *
     * @return array{total: float, avicole: float, commerce: float}
     */
    private function chiffreAffaires(CarbonImmutable $debut, CarbonImmutable $fin): array
    {
        $total = $avicole = $commerce = 0.0;

        foreach ($this->lignes($debut, $fin) as $l) {
            $montant = $l->qte * $l->pu;
            $total += $montant;
            if ($l->categorie === self::CATEGORIE_COMMERCE) {
                $commerce += $montant;
            } else {
                $avicole += $montant;
            }
        }

        return ['total' => $total, 'avicole' => $avicole, 'commerce' => $commerce];
    }

    /**
     * Meilleures ventes : CA cumule par designation de ligne, 5 premieres (`meilleuresVentes`).
     *
     * @return list<array{produit: string, quantite: float, ca: float, activite: string}>
     */
    private function meilleuresVentes(CarbonImmutable $debut, CarbonImmutable $fin): array
    {
        $cumuls = [];
        foreach ($this->lignes($debut, $fin) as $l) {
            $cumuls[$l->name] ??= ['produit' => $l->name, 'quantite' => 0.0, 'ca' => 0.0, 'activite' => ''];
            $cumuls[$l->name]['quantite'] += $l->qte;
            $cumuls[$l->name]['ca'] += $l->qte * $l->pu;
            $cumuls[$l->name]['activite'] = $l->categorie === self::CATEGORIE_COMMERCE ? 'Commerce' : 'Avicole';
        }

        usort($cumuls, fn (array $a, array $b) => $b['ca'] <=> $a['ca']);

        return array_slice($cumuls, 0, 5);
    }

    public function render()
    {
        $maintenant = $this->maintenant();

        $debut = $this->jour($this->debut);
        $fin = $this->jour($this->fin);
        $periodeValide = $debut !== null && $fin !== null && $debut->lessThanOrEqualTo($fin);

        $donnees = [
            'maintenant' => $maintenant,
            'periodeValide' => $periodeValide,
            'voirVentes' => $this->peut('view-ventes'),
            'voirAchats' => $this->peut('view-achats'),
            'voirComptabilite' => $this->peut('view-comptabilite'),
            'voirStocks' => $this->peut('view-stocks'),
            'voirElevage' => $this->peut('view-elevage'),
        ];

        // Periode invalide : on retombe sur le mois en cours (et on le dit) plutot que d'inventer un zero.
        $d = $periodeValide ? $debut->startOfDay() : $maintenant->startOfMonth();
        $f = $periodeValide ? $fin->endOfDay() : $maintenant->endOfDay();

        $service = app(TableauBordService::class);

        // Cles ajoutees : `null` tant que le droit manque (ou que la donnee n'existe pas sur le serveur).
        $donnees += [
            'tresorerie' => null, 'depenses' => null, 'resultatNet' => null, 'stockCritique' => null,
            'cheptel' => null, 'couveuse' => null, 'filieres' => null, 'alertes' => null,
            'jours' => null, 'moisDepenses' => null, 'activites' => null, 'transactions' => null,
        ];

        $caPeriode = null;
        $encoursNombre = 0;

        if ($donnees['voirVentes']) {
            $donnees['ca'] = $this->chiffreAffaires($d, $f);
            $caPeriode = $donnees['ca']['total'];
            $donnees['meilleures'] = $this->meilleuresVentes($d, $f);
            $donnees['clients'] = Client::query()->whereNull('supprime_le')->count();

            // Soldes restant dus : TOUTES les ventes `Avance` (sans filtre de date), total - paye.
            $avances = Vente::query()->where('status', 'Avance')->get(['total', 'paye']);
            $donnees['encours'] = $avances->sum(fn (Vente $v) => $v->total - $v->paye);
            $donnees['encoursNombre'] = $encoursNombre = $avances->count();

            // Revenu de la semaine : 7 jours glissants jusqu'a maintenant.
            $donnees['semaine'] = $this->chiffreAffaires($maintenant->subDays(7), $maintenant)['total'];

            // CA par mois, 6 derniers mois (mois civils du fuseau metier).
            $mois = [];
            for ($i = 5; $i >= 0; $i--) {
                $debutMois = $maintenant->startOfMonth()->subMonthsNoOverflow($i);
                $mois[] = [
                    'libelle' => self::MOIS[$debutMois->month],
                    'cle' => $debutMois->format('Y-m'),
                    'ca' => $this->chiffreAffaires($debutMois, $debutMois->endOfMonth())['total'],
                ];
            }
            $donnees['mois'] = $mois;

            $donnees['recentes'] = Vente::query()->orderByDesc('date_vente')->limit(3)->get();
        }

        if ($donnees['voirAchats']) {
            // Dettes fournisseurs : achats non annules dont il reste a payer (`soldeDu` > 0).
            $achats = Achat::query()->where('statut', '!=', 'Annulé')->get(['total', 'paye'])
                ->filter(fn (Achat $a) => $a->total - $a->paye > 0);
            $donnees['dettes'] = $achats->sum(fn (Achat $a) => $a->total - $a->paye);
            $donnees['dettesNombre'] = $achats->count();
        }

        // Comptabilite : UN SEUL chargement du livre (toutes les pieces des postes), relu en memoire.
        $courantes = null;
        if ($donnees['voirComptabilite']) {
            $livre = LivreComptable::toutes();
            $courantes = $service->ecrituresCourantes($livre);

            $donnees['tresorerie'] = $service->tresorerie($livre, $maintenant);
            $donnees['depenses'] = $service->depenses($courantes, $d, $f);
            $donnees['resultatNet'] = $service->resultatNet($courantes, $d, $f, $caPeriode);
            $donnees['moisDepenses'] = $service->depensesParMois(
                $courantes,
                array_map(fn (int $i) => $maintenant->startOfMonth()->subMonthsNoOverflow($i)->format('Y-m'), range(5, 0)),
            );
        }

        if ($donnees['voirVentes']) {
            $donnees['jours'] = $service->jours($maintenant, $courantes);
        }

        if ($donnees['voirElevage']) {
            $modules = ModuleActif::query()->pluck('is_actif', 'module_id')->map(fn ($v) => (bool) $v)->all();
            $elevage = $service->cheptelEtFilieres($service->especesActives($modules), $maintenant);
            $donnees['cheptel'] = $elevage['cheptel'];
            $donnees['filieres'] = $elevage['filieres'];

            $lots = $service->lotsCouveuse();
            $donnees['couveuse'] = $service->couveuse($lots, $maintenant);
        }

        // Alertes : chaque source n'est lue que si le compte a le droit de sa donnee.
        if ($donnees['voirVentes'] || $donnees['voirElevage']) {
            $donnees['alertes'] = $service->alertes(
                $donnees['voirVentes'], $donnees['voirElevage'],
                $donnees['couveuse'] ?? ['eclosionProchaine' => null], $encoursNombre, $maintenant,
            );
        }

        // Fil d'activite = journal d'audit du serveur : meme droit que son ecran (`manage-users`).
        if ($this->peut('manage-users')) {
            $donnees['activites'] = $service->activites($maintenant);
        }

        if ($donnees['voirVentes'] || $donnees['voirAchats'] || $donnees['voirComptabilite']) {
            $donnees['transactions'] = [
                'ventes' => $donnees['voirVentes'] ? $service->ventesRecentes() : [],
                'achats' => $donnees['voirAchats'] ? $service->achatsRecents() : [],
                'depenses' => $courantes !== null ? $service->depensesRecentes($courantes, (int) $maintenant->year) : [],
            ];
        }

        return view('livewire.tableau-de-bord', $donnees)->title('Tableau de Bord');
    }
}
