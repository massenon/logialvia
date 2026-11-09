<?php

namespace App\Livewire;

use App\Models\Bande;
use App\Models\FicheJournee;
use App\Services\FichesElevage;
use App\Support\AgregationHebdomadaire;
use App\Support\CalculFicheJournaliere;
use App\Support\FilieresElevage;
use App\Support\Navigation;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Locked;
use Livewire\Component;

/**
 * Fiche d'elevage d'une filiere (Dart : `fiche_espece_screen.dart`) — UN composant pour les
 * 7 routes `/elevage/<filiere>` (Strict Avoid §5 : jamais plusieurs implementations).
 * `/elevage/poulets-pondeuses` porte deux onglets (Poulets, Pondeuses).
 *
 * Les ecritures passent par `FichesElevage` : `TableSync::absorber` des tables
 * `fiche_journee` et `bandes` (device web), meme validation et meme regle « dernier
 * ecrivain gagne » que pour un poste. Les effectifs sont recalcules, jamais saisis.
 *
 * ## Ecarts assumes avec le Dart (donnees absentes du serveur)
 *  - pas de tableau de rationnement (provende) : les baremes de ration ne sont pas
 *    synchronises ; la pesee est neanmoins enregistree ;
 *  - pas de prophylaxie du jour, de calendrier de prophylaxie ni de soins planifies : tables
 *    non synchronisees (`P7c`) ;
 *  - pas d'icones Material Symbols (police non embarquee) ;
 *  - code de bande propose avec le prefixe par defaut `B` (le prefixe se regle aux Parametres
 *    Elevage du poste) ;
 *  - la clôture d'une bande est datee du jour (fuseau de l'entreprise), comme au poste.
 */
#[Layout('components.layouts.app')]
class FicheEspece extends Component
{
    /** Routes web des fiches et filieres qu'elles portent (la premiere est l'onglet par defaut). */
    public const ROUTES = [
        '/elevage/goliaths' => ['goliaths'],
        '/elevage/pintades' => ['pintades'],
        '/elevage/lapins' => ['lapins'],
        '/elevage/poissons-chats' => ['poissons-chats'],
        '/elevage/escargots' => ['escargots'],
        '/elevage/bovins' => ['bovins'],
        '/elevage/poulets-pondeuses' => ['poulets', 'pondeuses'],
    ];

    public const MOIS = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

    #[Locked]
    public string $route = '';

    #[Locked]
    public string $espece = '';

    public string $jour = '';

    public bool $hebdomadaire = false;

    // Saisie du jour (chaines : un champ vide ou illisible est detecte, jamais devine).
    public $achat = 0;

    public $ne = 0;

    /** @var array<int, mixed> */
    public array $morts = [];

    /** @var array<int, mixed> */
    public array $dons = [];

    public $poids = '';

    public string $observation = '';

    public bool $traitementValide = false;

    public $oeufsPondus = 0;

    public $oeufsCasses = 0;

    public $sortiesPlateaux = 0;

    public ?string $erreur = null;

    public ?string $message = null;

    // Bande
    public bool $formulaireBande = false;

    public string $bandeCode = '';

    public string $bandeDate = '';

    public $bandeEffectif = '';

    public string $bandeObservations = '';

    public ?string $erreurBande = null;

    public bool $confirmerCloture = false;

    /** `$route` n'est fourni que par les tests : sur le web, la route est celle de la requete. */
    public function mount(?string $route = null): void
    {
        $this->route = $route ?? '/'.ltrim(request()->path(), '/');
        abort_unless(array_key_exists($this->route, self::ROUTES), 404);

        $this->espece = self::ROUTES[$this->route][0];
        $this->jour = $this->aujourdhui();
        $this->chargerFormulaire();
    }

    // ----------------------------------------------------------------- Gardes

    private function peutGerer(): bool
    {
        return Auth::user()?->can('manage-elevage') ?? false;
    }

    /** Droit d'ecrire ET module de la filiere actif (la page a pu etre ouverte avant sa desactivation). */
    private function autoriser(): void
    {
        abort_unless($this->peutGerer(), 403);
        abort_unless(array_key_exists($this->route, self::ROUTES), 404);
        abort_unless(Navigation::moduleDeRouteActif($this->route), 404);
    }

    private function service(): FichesElevage
    {
        return new FichesElevage($this->espece);
    }

    // ------------------------------------------------------------- Utilitaires

    private function aujourdhui(): string
    {
        return CarbonImmutable::now(config('logialvia.fuseau'))->format('Y-m-d');
    }

    private function jourValide(string $jour): bool
    {
        $analyse = \DateTime::createFromFormat('!Y-m-d', $jour);
        if ($analyse === false || $analyse->format('Y-m-d') !== $jour) {
            return false;
        }
        // Bornes du selecteur du Dart : du 1er janvier 2020 au 31 decembre de l'an prochain.
        $an = (int) CarbonImmutable::now(config('logialvia.fuseau'))->year;

        return $jour >= '2020-01-01' && $jour <= ($an + 1).'-12-31';
    }

    /** Entier >= 0 lu d'un champ ; `null` si illisible (un champ vide vaut 0, comme le Dart). */
    private function entier(mixed $valeur): ?int
    {
        if ($valeur === null || $valeur === '') {
            return 0;
        }
        if (is_int($valeur)) {
            return $valeur;
        }
        if (is_string($valeur) && preg_match('/^-?\d{1,9}$/', trim($valeur)) === 1) {
            return (int) trim($valeur);
        }

        return null;
    }

    // ------------------------------------------------------------- Navigation

    public function choisirOnglet(string $espece): void
    {
        abort_unless(in_array($espece, self::ROUTES[$this->route] ?? [], true), 404);
        $this->espece = $espece;
        $this->reinitialiserEcran();
    }

    public function updatedJour(): void
    {
        if (! $this->jourValide($this->jour)) {
            $this->jour = $this->aujourdhui();
            $this->erreur = 'Cette date n\'est pas valide : le jour du jour est affiché.';
        } else {
            $this->erreur = null;
        }
        $this->message = null;
        $this->chargerFormulaire();
    }

    public function selectionnerJour(int $numero): void
    {
        $date = CarbonImmutable::createFromFormat('!Y-m-d', $this->jour);
        abort_unless($numero >= 1 && $numero <= $date->daysInMonth, 422);
        $this->jour = $date->setDay($numero)->format('Y-m-d');
        $this->erreur = null;
        $this->message = null;
        $this->chargerFormulaire();
    }

    public function basculer(bool $hebdomadaire): void
    {
        $this->hebdomadaire = $hebdomadaire;
    }

    private function reinitialiserEcran(): void
    {
        $this->erreur = $this->message = null;
        $this->formulaireBande = $this->confirmerCloture = false;
        $this->chargerFormulaire();
    }

    /** Valeurs du formulaire = la journee enregistree, sinon une journee vierge. */
    private function chargerFormulaire(): void
    {
        $n = FilieresElevage::nombreCategories($this->espece);
        $f = $this->service()->journee($this->jour);
        $d = $f ? $this->service()->versDomaine($f) : null;

        $this->achat = $d['achat'] ?? 0;
        $this->ne = $d['ne'] ?? 0;
        $this->morts = $d['morts'] ?? array_fill(0, $n, 0);
        $this->dons = $d['dons'] ?? array_fill(0, $n, 0);
        $this->poids = isset($d['poids_general_g']) ? (string) $d['poids_general_g'] : '';
        $this->observation = (string) ($d['traitement_obs'] ?? '');
        $this->traitementValide = (bool) ($d['traitement_valide'] ?? false);
        $this->oeufsPondus = $d['oeufs_pondus'] ?? 0;
        $this->oeufsCasses = $d['oeufs_casses'] ?? 0;
        $this->sortiesPlateaux = $d['sorties_plateaux'] ?? 0;
    }

    // ----------------------------------------------------------------- Saisie

    /**
     * Mouvements lus du formulaire ; `null` si un champ est illisible.
     *
     * @return array{achat: int, ne: int, vente: int, morts: list<int>, dons: list<int>}|null
     */
    private function mouvements(int $vente): ?array
    {
        $n = FilieresElevage::nombreCategories($this->espece);
        $morts = $dons = [];
        for ($i = 0; $i < $n; $i++) {
            $morts[] = $this->entier($this->morts[$i] ?? 0);
            $dons[] = $this->entier($this->dons[$i] ?? 0);
        }
        $achat = $this->entier($this->achat);
        $ne = $this->entier($this->ne);

        if (in_array(null, [$achat, $ne, ...$morts, ...$dons], true)) {
            return null;
        }

        return ['achat' => $achat, 'ne' => $ne, 'vente' => $vente, 'morts' => $morts, 'dons' => $dons];
    }

    public function enregistrer(): void
    {
        $this->autoriser();
        $this->message = $this->erreur = null;

        if (! $this->jourValide($this->jour)) {
            $this->erreur = 'Cette date n\'est pas valide.';

            return;
        }

        $service = $this->service();
        $mouvements = $this->mouvements($service->venteDuJour($this->jour));
        $oeufs = null;
        if ($this->espece === 'pondeuses') {
            $pondus = $this->entier($this->oeufsPondus);
            $casses = $this->entier($this->oeufsCasses);
            $sorties = $this->entier($this->sortiesPlateaux);
            if (in_array(null, [$pondus, $casses, $sorties], true)) {
                $mouvements = null;
            } else {
                $oeufs = ['pondus' => $pondus, 'casses' => $casses, 'sorties' => $sorties];
            }
        }
        if ($mouvements === null) {
            $this->erreur = 'Chaque champ de la saisie doit être un nombre entier.';

            return;
        }

        $poids = trim((string) $this->poids) === '' ? null : $this->entier($this->poids);
        $observation = $this->observation === '' ? null : $this->observation;

        $motif = $service->enregistrer($this->jour, $mouvements, $poids, $observation, $this->traitementValide, $oeufs);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = 'Saisie du jour '.(int) substr($this->jour, 8, 2).' enregistrée avec succès.';
        $this->chargerFormulaire();
    }

    // ----------------------------------------------------------------- Bande

    public function ouvrirBande(): void
    {
        $this->autoriser();
        $this->reset(['erreurBande', 'bandeEffectif', 'bandeObservations']);
        $this->bandeCode = $this->service()->prochainCodeBande();
        $this->bandeDate = $this->jour;
        $this->formulaireBande = true;
    }

    public function declarerBande(): void
    {
        $this->autoriser();
        $this->erreurBande = null;

        $effectif = trim((string) $this->bandeEffectif) === '' ? null : $this->entier($this->bandeEffectif);
        if (trim((string) $this->bandeEffectif) !== '' && $effectif === null) {
            $this->erreurBande = 'L\'effectif mis en place doit être un nombre entier.';

            return;
        }

        $motif = $this->service()->declarerBande($this->bandeCode, $this->bandeDate, $effectif, $this->bandeObservations);
        if ($motif !== null) {
            $this->erreurBande = $motif;

            return;
        }

        $this->message = 'Bande '.trim($this->bandeCode).' déclarée.';
        $this->formulaireBande = false;
    }

    public function demanderCloture(): void
    {
        $this->autoriser();
        $this->confirmerCloture = $this->service()->bandeCouvrant($this->jour) !== null;
    }

    public function cloturerBande(): void
    {
        $this->autoriser();
        $this->confirmerCloture = false;
        $bande = $this->service()->bandeCouvrant($this->jour);
        if ($bande === null) {
            $this->erreur = 'Aucune bande en cours.';

            return;
        }

        $motif = $this->service()->cloturerBande($bande, $this->aujourdhui());
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        $this->message = "Bande {$bande->code} clôturée.";
    }

    public function annuler(): void
    {
        $this->formulaireBande = false;
        $this->confirmerCloture = false;
        $this->erreurBande = null;
    }

    // ------------------------------------------------------------------ Rendu

    public function render()
    {
        $service = $this->service();
        $config = FilieresElevage::configuration($this->espece);
        $date = CarbonImmutable::createFromFormat('!Y-m-d', $this->jour);
        $n = FilieresElevage::nombreCategories($this->espece);

        $lignes = $service->mois($date->year, $date->month);
        $journees = $lignes->map(fn (FicheJournee $f) => $service->versDomaine($f))->all();
        $saisies = collect($journees)->filter(fn (array $j) => $j['is_recorded'])->sortKeys();
        $derniere = $saisies->last();

        // KPI : derniere journee saisie du mois affiche (comme le Dart).
        $categories = $config['categories'];
        $kpi = [
            'effectif' => $derniere['effectif'] ?? 0,
            'matures' => $derniere['effectifs'][2] ?? 0,
            'immatures' => $derniere['effectifs'][1] ?? 0,
            'mortalite' => 0.0,
            'libelle_mature' => count($categories) > 2 ? $categories[2][0] : 'Matures',
            'libelle_immature' => count($categories) > 1 ? $categories[1][0] : 'Immatures',
            'a_des_donnees' => $saisies->isNotEmpty(),
        ];
        if ($saisies->isNotEmpty()) {
            $premiere = $saisies->first();
            $base = $premiere['effectif'] + array_sum($premiere['morts']);
            $morts = $saisies->sum(fn (array $j) => array_sum($j['morts']));
            $kpi['mortalite'] = $base > 0 ? $morts / $base * 100 : 0.0;
        }
        $effectifReport = 0;
        if ($saisies->isNotEmpty()) {
            $p = $saisies->first();
            $effectifReport = $p['effectif'] - $p['achat'] - $p['ne'] + array_sum($p['morts']) + $p['vente'] + array_sum($p['dons']);
        }

        // Totaux en direct du formulaire (le Dart : `calculerEnDirect`).
        $veille = $service->veille($this->jour);
        $veilleDomaine = $veille ? $service->versDomaine($veille) : null;
        $venteDuJour = $service->venteDuJour($this->jour);
        $mouvements = $this->mouvements($venteDuJour) ?? ['achat' => 0, 'ne' => 0, 'vente' => $venteDuJour, 'morts' => array_fill(0, $n, 0), 'dons' => array_fill(0, $n, 0)];
        $totaux = CalculFicheJournaliere::calculerJour(
            $this->espece,
            $veilleDomaine['effectifs'] ?? array_fill(0, $n, 0),
            $veilleDomaine['effectif'] ?? 0,
            $mouvements,
        );

        $oeufs = null;
        if ($this->espece === 'pondeuses') {
            $oeufs = CalculFicheJournaliere::stockOeufs(
                $veilleDomaine['stock_final_oeufs'] ?? 0,
                max(0, $this->entier($this->oeufsPondus) ?? 0),
                max(0, $this->entier($this->oeufsCasses) ?? 0),
                max(0, $this->entier($this->sortiesPlateaux) ?? 0),
            );
        }

        $poidsTotal = $this->entier($this->poids);
        $bande = $service->bandeCouvrant($this->jour);

        return view('livewire.fiche-espece', [
            'config' => $config,
            'onglets' => count(self::ROUTES[$this->route]) > 1 ? self::ROUTES[$this->route] : [],
            'date' => $date,
            'nombreJours' => $date->daysInMonth,
            'journees' => $journees,
            'semaines' => $this->hebdomadaire ? AgregationHebdomadaire::calculer($date->daysInMonth, $journees, $effectifReport) : [],
            'kpi' => $kpi,
            'venteDuJour' => $venteDuJour,
            'totaux' => $totaux,
            'oeufs' => $oeufs,
            'srh' => $veilleDomaine['stock_final_oeufs'] ?? 0,
            'poidsMoyen' => ($totaux['effectif_total'] > 0 && trim((string) $this->poids) !== '' && $poidsTotal !== null)
                ? CalculFicheJournaliere::poidsMoyenGrammes($poidsTotal, $totaux['effectif_total'])
                : null,
            'bande' => $bande,
            'jourDeCycle' => $bande ? FichesElevage::jourDeCycle($bande, $this->jour) : null,
            'peutGerer' => $this->peutGerer(),
            'libelleMois' => self::MOIS[$date->month - 1].' '.$date->year,
        ])->title('Fiche '.$config['libelle']);
    }
}
