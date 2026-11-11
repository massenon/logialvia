<?php

namespace App\Livewire;

use App\Models\Bande;
use App\Models\EcheanceProphylaxie;
use App\Models\FicheJournee;
use App\Services\FichesElevage;
use App\Support\AgregationHebdomadaire;
use App\Support\CalculFicheJournaliere;
use App\Support\ExportXlsx;
use App\Support\FilieresElevage;
use App\Support\ReperesZootechniques;
use App\Support\Navigation;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Locked;
use Livewire\Component;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Fiche d'elevage d'une filiere (Dart : `fiche_espece_screen.dart`) — UN composant pour les
 * 7 routes `/elevage/<filiere>` (Strict Avoid §5 : jamais plusieurs implementations).
 * `/elevage/poulets-pondeuses` porte deux onglets (Poulets, Pondeuses).
 *
 * Les ecritures passent par `FichesElevage` : `TableSync::absorber` des tables
 * `fiche_journee` et `bandes` (device web), meme validation et meme regle « dernier
 * ecrivain gagne » que pour un poste. Les effectifs sont recalcules, jamais saisis.
 *
 * ## Expertise (`47e_`)
 *  - controle de vraisemblance (erreurs refusees, avertissements en direct), memes regles et memes
 *    messages que le poste ;
 *  - chaine d'effectifs : verification (lecture seule) et bouton « Recalculer la chaine » ;
 *  - fiche « modifiee ailleurs » : les versions en presence, choix explicite de celle a garder ;
 *  - rationnement (provende) et prophylaxie du jour, depuis les baremes et le calendrier
 *    synchronises ; planification d'un soin avec son lien de bande ; recodage d'une bande ;
 *  - ce qui depend du STOCK d'intrants (provende en stock, autonomie) reste propre a chaque
 *    poste : grise « Disponible sur le poste ».
 *
 * ## Ecarts assumes avec le Dart
 *  - pas d'icones Material Symbols (police non embarquee) ;
 *  - code de bande propose avec le prefixe par defaut `B` (le prefixe se regle aux Parametres
 *    Elevage) ;
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
        '/elevage/ovins' => ['ovins'],
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

    // Recodage de la bande
    public bool $formulaireRecodage = false;

    public string $nouveauCode = '';

    public ?string $erreurRecodage = null;

    /** Version de la fiche (`updated_at`) au chargement du formulaire : base de l'ecriture (`47e_`). */
    public ?string $baseMaj = null;

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
        $this->baseMaj = $f?->updated_at === null ? null : CarbonImmutable::instance($f->updated_at)->utc()->format('Y-m-d\TH:i:s.u\Z');

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

        $motif = $service->enregistrer($this->jour, $mouvements, $poids, $observation, $this->traitementValide, $oeufs, true, $this->baseMaj, true);
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

    // ------------------------------------------------------------ Export XLSX

    /** Classeur XLSX du mois affiche (Historique du Mois), meme contenu que l'ecran. Droit `export-elevage`. */
    public function exporter(): StreamedResponse
    {
        abort_unless(Auth::user()?->can('view-elevage') && Auth::user()?->can('export-elevage'), 403);
        abort_unless(array_key_exists($this->route, self::ROUTES), 404);
        abort_unless(Navigation::moduleDeRouteActif($this->route), 404);

        $date = CarbonImmutable::createFromFormat('!Y-m-d', $this->jour);
        $config = FilieresElevage::configuration($this->espece);
        $service = $this->service();
        $lignes = [
            ['Fiche '.$config['libelle'].' — '.self::MOIS[$date->month - 1].' '.$date->year],
            [],
            ['Date', $config['libelle_achats'], $config['libelle_naissances'], 'Vente', 'Morts', 'Dons', 'Effectif', 'Pesée (g)', 'Observation de traitement'],
        ];
        foreach ($service->mois($date->year, $date->month) as $f) {
            if (! $f->is_recorded) {
                continue;
            }
            $j = $service->versDomaine($f);
            $lignes[] = [
                CarbonImmutable::parse($f->date)->format('d/m/Y'), $j['achat'], $j['ne'], $j['vente'],
                array_sum($j['morts']), array_sum($j['dons']), $j['effectif'], $j['poids_general_g'] ?? '', (string) ($j['traitement_obs'] ?? ''),
            ];
        }

        return ExportXlsx::telecharger(
            array_map(fn (array $ligne) => array_map(ExportXlsx::typer(...), $ligne), $lignes),
            'fiche-'.$this->espece.'-'.$date->format('Y-m').'.xlsx',
            $config['libelle'],
        );
    }

    // ------------------------------------------------- Chaine, divergence (`47e_`)

    public function recalculerChaine(): void
    {
        $this->autoriser();
        $this->message = $this->erreur = null;
        try {
            $rapport = $this->service()->recalculerChaine();
        } catch (\Throwable $e) {
            report($e);
            $this->erreur = 'Impossible de recalculer la chaîne des effectifs.';

            return;
        }
        $n = count($rapport['jours_corriges']);
        $this->message = $n === 0
            ? 'La chaîne était déjà cohérente.'
            : "$n jour".($n > 1 ? 's' : '').' recalculé'.($n > 1 ? 's' : '').'.';
        $this->chargerFormulaire();
    }

    public function garderVersion(int $index): void
    {
        $this->autoriser();
        $this->message = $this->erreur = null;
        $motif = $this->service()->resoudreDivergence($this->jour, $index);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        $this->message = 'Version gardée : la fiche n\'est plus en divergence.';
        $this->chargerFormulaire();
    }

    // -------------------------------------------------------- Recodage de bande

    public function ouvrirRecodage(): void
    {
        $this->autoriser();
        $bande = $this->service()->bandeCouvrant($this->jour);
        if ($bande === null) {
            return;
        }
        $this->erreurRecodage = null;
        $this->nouveauCode = $this->service()->codeRecodagePropose($bande);
        $this->formulaireRecodage = true;
    }

    public function recoderBande(): void
    {
        $this->autoriser();
        $bande = $this->service()->bandeCouvrant($this->jour);
        if ($bande === null) {
            $this->erreurRecodage = 'Aucune bande en cours.';

            return;
        }
        $motif = $this->service()->recoderBande($bande, $this->nouveauCode);
        if ($motif !== null) {
            $this->erreurRecodage = $motif;

            return;
        }
        $this->message = 'Bande recodée en '.trim($this->nouveauCode).'.';
        $this->formulaireRecodage = false;
    }

    // ------------------------------------------------------------ Prophylaxie

    public function planifierEcheance(string $echeanceId, string $type): void
    {
        $this->autoriser();
        $this->message = $this->erreur = null;
        $bande = $this->service()->bandeCouvrant($this->jour);
        if ($bande === null) {
            $this->erreur = 'Aucune bande en cours.';

            return;
        }
        $echeance = EcheanceProphylaxie::query()->where('espece', $this->espece)->whereNull('archive_le')->find($echeanceId);
        if ($echeance === null) {
            $this->erreur = 'Cette échéance n\'existe plus.';

            return;
        }
        $motif = $this->service()->planifierEcheance($bande, $echeance, $type);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        $this->message = "{$echeance->traitement} planifié.";
    }

    public function annuler(): void
    {
        $this->formulaireRecodage = false;
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
        $effectifReport = 0;
        if ($saisies->isNotEmpty()) {
            $p = $saisies->first();
            $effectifReport = $p['effectif'] - $p['achat'] - $p['ne'] + array_sum($p['morts']) + $p['vente'] + array_sum($p['dons']);
            // Effectif EXPOSE : effectif de debut de mois + entrees du mois (`47e_`).
            $kpi['mortalite'] = ReperesZootechniques::tauxMortaliteCumule(
                (int) $saisies->sum(fn (array $j) => array_sum($j['morts'])),
                $effectifReport,
                (int) $saisies->sum(fn (array $j) => $j['achat'] + $j['ne']),
            ) ?? 0.0;
        }
        $kpi['niveau_mortalite'] = ReperesZootechniques::niveauMortaliteCumul($kpi['mortalite']);

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

        $oeufsSaisis = null;
        if ($this->espece === 'pondeuses') {
            $oeufsSaisis = ['pondus' => max(0, $this->entier($this->oeufsPondus) ?? 0), 'casses' => max(0, $this->entier($this->oeufsCasses) ?? 0), 'sorties' => max(0, $this->entier($this->sortiesPlateaux) ?? 0)];
        }
        $controle = $service->controle($this->jour, $mouvements, $poidsTotal !== null && trim((string) $this->poids) !== '' ? $poidsTotal : null, $oeufsSaisis);
        $provende = CalculFicheJournaliere::provendeDuJour(
            $this->espece, $totaux['par_categorie'], $service->rationsConfigurees(), $service->tauxParClasse(),
            trim((string) $this->poids) !== '' ? $poidsTotal : null,
        );
        $rations = [];
        foreach ($categories as $i => $categorie) {
            $rations[$i] = CalculFicheJournaliere::rationCategorie($this->espece, $i, $service->rationsConfigurees());
        }

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
            'controle' => $controle,
            'provende' => $provende,
            'rations' => $rations,
            'joursIncoherents' => $service->joursIncoherents(),
            'versions' => $service->versionsEnDivergence($this->jour),
            'modifieeAilleurs' => $service->versionsEnDivergence($this->jour) !== [],
            'prophylaxieDuJour' => $bande ? $service->prophylaxieDuJour($bande, $this->jour) : [],
            'prophylaxieBande' => $bande ? $service->prophylaxieDeLaBande($bande) : [],
            'typesSoin' => \App\Sync\Tables\SoinsCalendrierTable::TYPES,
            'jourDeCycle' => $bande ? FichesElevage::jourDeCycle($bande, $this->jour) : null,
            'peutGerer' => $this->peutGerer(),
            'libelleMois' => self::MOIS[$date->month - 1].' '.$date->year,
        ])->title('Fiche '.$config['libelle']);
    }
}
