<?php

namespace App\Livewire;

use App\Models\Achat;
use App\Models\Client;
use App\Models\LigneVente;
use App\Models\Vente;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Tableau de Bord Principal (Dart : `dashboard_screen.dart`, `tableau_bord_view_model.dart`,
 * `tableau_bord_repository_drift.dart`) — LECTURE SEULE.
 *
 * Le web n'affiche que ce que le serveur calcule depuis ses tables synchronisees (ventes, lignes,
 * produits, clients, achats). Tresorerie, depenses, resultat net, cheptel, couveuse, stock critique,
 * alertes et rappels veterinaires n'existent pas ici : leurs cartes restent grisees
 * « Disponible sur le poste » — jamais un chiffre invente. Chaque carte n'est montree que si le
 * compte a le droit de la donnee (le Dart, mono-poste, n'a pas ce filtre).
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

        if ($donnees['voirVentes']) {
            // Periode invalide : on retombe sur le mois en cours (et on le dit) plutot que d'inventer un zero.
            $d = $periodeValide ? $debut->startOfDay() : $maintenant->startOfMonth();
            $f = $periodeValide ? $fin->endOfDay() : $maintenant->endOfDay();

            $donnees['ca'] = $this->chiffreAffaires($d, $f);
            $donnees['meilleures'] = $this->meilleuresVentes($d, $f);
            $donnees['clients'] = Client::query()->whereNull('supprime_le')->count();

            // Soldes restant dus : TOUTES les ventes `Avance` (sans filtre de date), total - paye.
            $avances = Vente::query()->where('status', 'Avance')->get(['total', 'paye']);
            $donnees['encours'] = $avances->sum(fn (Vente $v) => $v->total - $v->paye);
            $donnees['encoursNombre'] = $avances->count();

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

        return view('livewire.tableau-de-bord', $donnees)->title('Tableau de Bord');
    }
}
