<?php

namespace App\Livewire;

use App\Models\BaremeRation;
use App\Models\EcheanceProphylaxie;
use App\Models\Intrant;
use App\Models\ParametresEntreprise;
use App\Models\TauxRationPoids;
use App\Support\FilieresElevage;
use App\Sync\DemandesReferentiel;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Parametres Elevage (Dart : `parametres_elevage_screen.dart`). Trois REFERENTIELS
 * (rationnement, taux par classe de poids, calendrier de prophylaxie) et la numerotation.
 *
 * Toute ecriture passe par `DemandesReferentiel::traiter` : les MEMES regles que pour un
 * poste (validation, droit `manage-elevage`, `archive-elevage` pour une suppression, cle
 * naturelle, dernier ecrivain gagne, audit, historique). Une suppression est une PIERRE
 * TOMBALE que les postes archivent a leur tour.
 *
 * ECARTS declares avec le Dart (voir `46c_`) :
 *  - « Intrants de Provende » en lecture seule, sans stock ni prix indicatif (propres a
 *    chaque poste) ; l'ajout et la modification d'un intrant se font dans Gestion Stocks ;
 *  - une ligne supprimee n'est pas restaurable depuis le web (pas de corbeille) ;
 *  - la numerotation exige le droit `manage-parametres` (celui du serveur) ;
 *  - les filieres proposees pour une creation sont limitees aux filieres actives ;
 *  - pas de « Reinitialiser le brouillon » de numerotation ni d'avertissement de
 *    modifications non enregistrees ; pas de visite guidee.
 */
#[Layout('components.layouts.app')]
class ParametresElevage extends Component
{
    public string $onglet = 'rationnement';

    // ---- filtres
    public string $rechercheRation = '';

    public string $especeRation = '';

    public string $especeProphylaxie = 'goliaths';

    public string $rechercheProphylaxie = '';

    public string $rechercheProvende = '';

    // ---- formulaires
    /** `bareme-ajout`, `bareme-edition`, `taux`, `echeance` ou `null`. */
    public ?string $formulaire = null;

    public ?string $cibleId = null;

    public string $espece = '';

    public string $stade = '';

    public string $ration = '';

    public string $poidsMin = '';

    public string $poidsMax = '';

    public string $taux = '';

    public string $jour = '';

    public string $traitement = '';

    public string $produit = '';

    public string $dose = '';

    public string $remanence = '0';

    /** Suppression en attente de confirmation : `['type' => 'bareme'|'taux'|'echeance', 'id' => ...]`. */
    public ?array $suppression = null;

    // ---- numerotation
    /** @var array<string, string> */
    public array $formats = ['enclos' => 'E', 'cage' => 'C', 'bande' => 'B', 'bassin' => 'B', 'bac' => 'BAC', 'parc' => 'PARC'];

    public ?string $erreur = null;

    public ?string $message = null;

    public function mount(): void
    {
        $this->chargerFormats();
        $actives = array_keys(FilieresElevage::parametrablesActives());
        $this->especeProphylaxie = in_array('goliaths', $actives, true) ? 'goliaths' : ($actives[0] ?? 'goliaths');
    }

    // ------------------------------------------------------------------ outils

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-elevage'), 403);
    }

    private function verifierDroitDarchiver(): void
    {
        abort_unless(Auth::user()?->can('archive-elevage'), 403);
    }

    private function verifierDroitNumerotation(): void
    {
        abort_unless(Auth::user()?->can('manage-parametres'), 403);
    }

    private function entier(string $valeur): ?int
    {
        $valeur = trim(str_replace(' ', '', $valeur));

        return preg_match('/^-?\d+$/', $valeur) ? (int) $valeur : null;
    }

    private function nombre(string $valeur): ?float
    {
        $valeur = trim(str_replace([' ', ','], ['', '.'], $valeur));

        return $valeur !== '' && is_numeric($valeur) ? (float) $valeur : null;
    }

    /** Propose une ligne au serveur, comme le ferait un poste. */
    private function proposer(string $type, array $donnees): ?string
    {
        $bilan = app(DemandesReferentiel::class)->traiter(Auth::user(), Catalogue::POSTE_WEB, [[
            'id' => (string) Str::uuid(),
            'type' => $type,
            'saisi_le' => CarbonImmutable::now('UTC')->format('Y-m-d\TH:i:s.u\Z'),
            'donnees' => $donnees,
        ]]);

        return $bilan['rejected'][0]['motif'] ?? null;
    }

    private function plafondRation(string $espece): int
    {
        return $espece === 'bovins' ? 20000 : 5000;
    }

    private function especeProposee(string $espece): bool
    {
        return array_key_exists($espece, FilieresElevage::parametrablesActives());
    }

    public function choisirOnglet(string $onglet): void
    {
        $this->onglet = in_array($onglet, ['rationnement', 'prophylaxie', 'provende', 'numerotation'], true) ? $onglet : 'rationnement';
        $this->message = null;
        if ($this->onglet === 'numerotation') {
            $this->chargerFormats();
        }
    }

    public function annuler(): void
    {
        $this->formulaire = null;
        $this->suppression = null;
        $this->erreur = null;
    }

    private function ouvrir(string $formulaire): void
    {
        $this->verifierDroitDeGerer();
        $this->reset(['cibleId', 'espece', 'stade', 'ration', 'poidsMin', 'poidsMax', 'taux', 'jour', 'traitement', 'produit', 'dose', 'erreur', 'message', 'suppression']);
        $this->remanence = '0';
        $this->formulaire = $formulaire;
    }

    // ------------------------------------------------------------ rationnement

    public function nouveauBareme(): void
    {
        $this->ouvrir('bareme-ajout');
        $this->espece = array_key_first(FilieresElevage::parametrablesActives()) ?? 'goliaths';
    }

    public function modifierBareme(string $id): void
    {
        $this->verifierDroitDeGerer();
        $b = BaremeRation::query()->whereNull('archive_le')->find($id);
        if ($b === null) {
            return;
        }
        $this->ouvrir('bareme-edition');
        $this->cibleId = $b->id;
        $this->espece = $b->espece;
        $this->stade = $b->stade;
        $this->ration = (string) $b->ration_grammes_par_jour;
    }

    private function donneesBareme(BaremeRation $b, int $ration, bool $confirme): array
    {
        return [
            'id' => $b->id, 'espece' => $b->espece, 'stade' => $b->stade,
            'ration_grammes_par_jour' => $ration, 'confirme' => $confirme,
        ];
    }

    public function enregistrerBareme(bool $valider = false): void
    {
        $this->verifierDroitDeGerer();

        if ($this->formulaire === 'bareme-edition') {
            $this->modifierRation($valider);

            return;
        }
        if ($this->formulaire !== 'bareme-ajout') {
            return;
        }

        $valeur = $this->entier($this->ration);
        if (trim($this->stade) === '' || $valeur === null || $valeur <= 0) {
            $this->erreur = 'Veuillez renseigner le stade et la ration.';

            return;
        }
        if (! $this->especeProposee($this->espece)) {
            $this->erreur = 'Cette filière n\'est pas active.';

            return;
        }
        if ($valeur > $this->plafondRation($this->espece)) {
            $this->erreur = 'Une ration de plus de '.number_format($this->plafondRation($this->espece), 0, ',', ' ').' g par tête et par jour est invraisemblable.';

            return;
        }

        // Comme le poste : ajouter deux fois le meme stade met la ration a jour (identifiant
        // deterministe, ou celui de la ligne deja connue, supprimee ou non).
        $stade = trim($this->stade);
        $existant = BaremeRation::query()->where('espece', $this->espece)->where('stade', $stade)->first();
        $motif = $this->proposer(DemandesReferentiel::TYPE_BAREME, [
            'id' => $existant->id ?? FilieresElevage::idBareme($this->espece, $stade),
            'espece' => $this->espece, 'stade' => $stade,
            'ration_grammes_par_jour' => $valeur,
            'confirme' => $existant !== null && $existant->archive_le === null ? $existant->confirme : false,
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = 'Ration ajoutée pour '.FilieresElevage::libelle($this->espece).' / '.$stade.'.';
        $this->annuler();
    }

    private function modifierRation(bool $valider): void
    {
        $b = $this->cibleId ? BaremeRation::query()->whereNull('archive_le')->find($this->cibleId) : null;
        if ($b === null) {
            $this->erreur = 'Ce barème n\'existe plus.';

            return;
        }
        $valeur = $this->entier($this->ration);
        if ($valeur === null || $valeur <= 0) {
            $this->erreur = 'La ration doit être un nombre de grammes positif.';

            return;
        }
        if ($valeur > $this->plafondRation($b->espece)) {
            $this->erreur = 'Une ration de plus de '.number_format($this->plafondRation($b->espece), 0, ',', ' ').' g par tête et par jour est invraisemblable.';

            return;
        }

        // « Valider » confirme ; une valeur changee ramene le repere a « a valider ».
        $confirme = $valider ? true : ($valeur !== $b->ration_grammes_par_jour ? false : $b->confirme);
        $motif = $this->proposer(DemandesReferentiel::TYPE_BAREME, $this->donneesBareme($b, $valeur, $confirme));
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = ($valider ? 'Ration validée : ' : 'Ration mise à jour : ').$valeur.' g/j.';
        $this->annuler();
    }

    // -------------------------------------------------------------------- taux

    public function nouveauTaux(): void
    {
        $this->ouvrir('taux');
        $this->espece = array_key_first($this->especesPoidsVif()) ?? '';
    }

    public function modifierTaux(string $id): void
    {
        $this->verifierDroitDeGerer();
        $t = TauxRationPoids::query()->whereNull('archive_le')->find($id);
        if ($t === null) {
            return;
        }
        $this->ouvrir('taux');
        [, $facteur] = FilieresElevage::POIDS_VIF[$t->espece] ?? ['kg', 1000];
        $this->cibleId = $t->id;
        $this->espece = $t->espece;
        $this->poidsMin = $this->grandeur($t->poids_min_g / $facteur);
        $this->poidsMax = $t->poids_max_g === null ? '' : $this->grandeur($t->poids_max_g / $facteur);
        $this->taux = str_replace('.', ',', (string) $t->taux_pourcent);
    }

    private function grandeur(float $v): string
    {
        return $v == round($v) ? (string) (int) round($v) : str_replace('.', ',', (string) $v);
    }

    /** @return array<string, string> */
    private function especesPoidsVif(): array
    {
        return collect(FilieresElevage::parametrablesActives())
            ->filter(fn ($libelle, $id) => array_key_exists($id, FilieresElevage::POIDS_VIF))
            ->all();
    }

    public function enregistrerTaux(bool $valider = false): void
    {
        $this->verifierDroitDeGerer();
        if ($this->formulaire !== 'taux') {
            return;
        }

        $existant = $this->cibleId ? TauxRationPoids::query()->whereNull('archive_le')->find($this->cibleId) : null;
        if ($this->cibleId !== null && $existant === null) {
            $this->erreur = 'Cette classe n\'existe plus.';

            return;
        }
        $espece = $existant->espece ?? $this->espece;
        if (! array_key_exists($espece, FilieresElevage::POIDS_VIF)) {
            $this->erreur = 'Cette espèce n\'est pas rationnée sur le poids vif : le tableau ne s\'applique qu\'aux bovins et aux poissons-chats.';

            return;
        }
        if ($existant === null && ! $this->especeProposee($espece)) {
            $this->erreur = 'Cette filière n\'est pas active.';

            return;
        }
        [$unite, $facteur, $tauxMax] = FilieresElevage::POIDS_VIF[$espece];

        $minKg = trim($this->poidsMin) === '' ? 0.0 : $this->nombre($this->poidsMin);
        $tauxValeur = $this->nombre($this->taux);
        if ($minKg === null || $minKg < 0 || $tauxValeur === null) {
            $this->erreur = 'Veuillez renseigner le poids minimum et le taux.';

            return;
        }
        $maxKg = null;
        if (trim($this->poidsMax) !== '') {
            $maxKg = $this->nombre($this->poidsMax);
            if ($maxKg === null) {
                $this->erreur = 'Le poids maximum doit être un nombre de '.($unite === 'g' ? 'grammes' : 'kilos').'.';

                return;
            }
            if ($maxKg <= $minKg) {
                $this->erreur = 'Le poids maximum doit dépasser le poids minimum.';

                return;
            }
        }
        if ($tauxValeur <= 0 || $tauxValeur > $tauxMax) {
            $this->erreur = 'Le taux doit être compris entre 0 et '.(int) $tauxMax.' % du poids vif (ou de la biomasse) par jour.';

            return;
        }

        $minG = (int) round($minKg * $facteur);
        $maxG = $maxKg === null ? null : (int) round($maxKg * $facteur);

        // Deux classes qui se chevauchent donneraient deux taux pour un meme animal.
        foreach (TauxRationPoids::query()->whereNull('archive_le')->where('espece', $espece)->get() as $autre) {
            if ($autre->id === $existant?->id) {
                continue;
            }
            $seChevauchent = ($autre->poids_max_g === null || $minG < $autre->poids_max_g)
                && ($maxG === null || $autre->poids_min_g < $maxG);
            if ($seChevauchent) {
                $this->erreur = 'Cette classe chevauche « '.$autre->libelleClasse().' » : un animal aurait deux taux.';

                return;
            }
        }

        $confirme = $existant === null
            ? false
            : ($valider ? true : ((($minG !== $existant->poids_min_g) || ($maxG !== $existant->poids_max_g) || (abs($tauxValeur - $existant->taux_pourcent) > 1e-9)) ? false : $existant->confirme));
        $motif = $this->proposer(DemandesReferentiel::TYPE_TAUX_POIDS, [
            'id' => $existant->id ?? FilieresElevage::idTaux($espece, $minG),
            'espece' => $espece, 'poids_min_g' => $minG, 'poids_max_g' => $maxG,
            'taux_pourcent' => $tauxValeur, 'confirme' => $confirme,
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = $valider ? 'Classe de poids validée.' : ($existant === null ? 'Classe de poids ajoutée.' : 'Classe de poids mise à jour.');
        $this->annuler();
    }

    // ----------------------------------------------------------- prophylaxie

    public function nouvelleEcheance(): void
    {
        $this->ouvrir('echeance');
        $this->espece = $this->especeProphylaxie;
    }

    public function modifierEcheance(string $id): void
    {
        $this->verifierDroitDeGerer();
        $e = EcheanceProphylaxie::query()->whereNull('archive_le')->find($id);
        if ($e === null) {
            return;
        }
        $this->ouvrir('echeance');
        $this->cibleId = $e->id;
        $this->espece = $e->espece;
        $this->jour = (string) $e->jour_cycle;
        $this->traitement = $e->traitement;
        $this->produit = $e->produit;
        $this->dose = (string) $e->dose;
        $this->remanence = (string) $e->remanence_jours;
    }

    public function enregistrerEcheance(): void
    {
        $this->verifierDroitDeGerer();
        if ($this->formulaire !== 'echeance') {
            return;
        }

        $existante = $this->cibleId ? EcheanceProphylaxie::query()->whereNull('archive_le')->find($this->cibleId) : null;
        if ($this->cibleId !== null && $existante === null) {
            $this->erreur = 'Cette échéance n\'existe plus.';

            return;
        }
        $espece = $existante->espece ?? $this->espece;

        $jour = $this->entier($this->jour);
        if ($jour === null || trim($this->traitement) === '' || trim($this->produit) === '') {
            $this->erreur = 'Veuillez renseigner le jour, le traitement et le produit.';

            return;
        }
        if ($jour < 1 || $jour > 365) {
            $this->erreur = 'Le jour du cycle doit être compris entre 1 et 365.';

            return;
        }
        $remanence = trim($this->remanence) === '' ? 0 : $this->entier($this->remanence);
        if ($remanence === null || $remanence < 0) {
            $this->erreur = 'La rémanence ne peut pas être négative.';

            return;
        }
        if ($existante === null && ! $this->especeProposee($espece)) {
            $this->erreur = 'Cette filière n\'est pas active.';

            return;
        }

        $motif = $this->proposer(DemandesReferentiel::TYPE_ECHEANCE, [
            // Echeance saisie par l'utilisatrice : UUID aleatoire (pas de cle naturelle unique).
            'id' => $existante->id ?? (string) Str::uuid(),
            'espece' => $espece, 'jour_cycle' => $jour,
            'traitement' => trim($this->traitement), 'produit' => trim($this->produit),
            'remanence_jours' => $remanence,
            'dose' => trim($this->dose) === '' ? null : trim($this->dose),
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = $existante === null
            ? 'Échéance ajoutée au calendrier de prophylaxie.'
            : 'Échéance de prophylaxie modifiée.';
        $this->annuler();
    }

    // ------------------------------------------------------------ suppressions

    public function demanderSuppression(string $type, string $id): void
    {
        $this->verifierDroitDarchiver();
        $this->message = null;
        $existe = match ($type) {
            'bareme' => BaremeRation::query()->whereNull('archive_le')->whereKey($id)->exists(),
            'taux' => TauxRationPoids::query()->whereNull('archive_le')->whereKey($id)->exists(),
            'echeance' => EcheanceProphylaxie::query()->whereNull('archive_le')->whereKey($id)->exists(),
            default => false,
        };
        $this->suppression = $existe ? ['type' => $type, 'id' => $id] : null;
    }

    public function confirmerSuppression(): void
    {
        $this->verifierDroitDarchiver();
        $cible = $this->suppression;
        $this->suppression = null;
        if ($cible === null) {
            return;
        }

        [$modele, $type, $champs, $message] = match ($cible['type']) {
            'bareme' => [BaremeRation::class, DemandesReferentiel::TYPE_BAREME, ['id', 'espece', 'stade', 'ration_grammes_par_jour', 'confirme'], 'Barème supprimé.'],
            'taux' => [TauxRationPoids::class, DemandesReferentiel::TYPE_TAUX_POIDS, ['id', 'espece', 'poids_min_g', 'poids_max_g', 'taux_pourcent', 'confirme'], 'Classe de poids supprimée.'],
            default => [EcheanceProphylaxie::class, DemandesReferentiel::TYPE_ECHEANCE, ['id', 'espece', 'jour_cycle', 'traitement', 'produit', 'remanence_jours', 'dose'], 'Échéance de prophylaxie supprimée.'],
        };
        $ligne = $modele::query()->whereNull('archive_le')->find($cible['id']);
        if ($ligne === null) {
            return;
        }

        // Jamais d'effacement : pierre tombale, que les postes archivent a leur tour.
        $donnees = collect($champs)->mapWithKeys(fn ($c) => [$c => $ligne->{$c}])->all() + ['archive' => true];
        $this->message = $this->proposer($type, $donnees) ?? $message;
    }

    // ------------------------------------------------------------ numerotation

    private function chargerFormats(): void
    {
        $p = ParametresEntreprise::courant();
        $this->formats = [
            'enclos' => (string) $p->prefixe_enclos, 'cage' => (string) $p->prefixe_cage, 'bande' => (string) $p->prefixe_bande,
            'bassin' => (string) $p->prefixe_bassin, 'bac' => (string) $p->prefixe_bac, 'parc' => (string) $p->prefixe_parc,
        ];
    }

    public function enregistrerNumerotation(): void
    {
        $this->verifierDroitNumerotation();

        $noms = ['enclos' => 'Enclos', 'cage' => 'Cage', 'bande' => 'Bande', 'bassin' => 'Bassin', 'bac' => 'Bac', 'parc' => 'Parc'];
        $vides = [];
        foreach ($noms as $cle => $nom) {
            if (trim((string) ($this->formats[$cle] ?? '')) === '') {
                $vides[] = $nom;
            }
        }
        if ($vides !== []) {
            $this->erreur = 'Préfixe manquant : '.implode(', ', $vides).'. Un préfixe vide rendrait les identifiants indistinguables d\'une filière à l\'autre.';

            return;
        }

        $motif = $this->proposer(DemandesReferentiel::TYPE_PARAMETRES, [
            'prefixe_enclos' => trim($this->formats['enclos']), 'prefixe_cage' => trim($this->formats['cage']),
            'prefixe_bande' => trim($this->formats['bande']), 'prefixe_bassin' => trim($this->formats['bassin']),
            'prefixe_bac' => trim($this->formats['bac']), 'prefixe_parc' => trim($this->formats['parc']),
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->erreur = null;
        $this->message = 'Formats enregistrés';
        $this->chargerFormats();
    }

    // -------------------------------------------------------------------- rendu

    public function render()
    {
        $especes = FilieresElevage::parametrablesActives();

        $baremes = BaremeRation::query()->whereNull('archive_le')
            ->when($this->especeRation !== '', fn ($q) => $q->where('espece', $this->especeRation))
            ->orderBy('espece')->orderBy('created_at')->orderBy('stade')->get()
            ->filter(fn (BaremeRation $b) => trim($this->rechercheRation) === ''
                || str_contains(mb_strtolower($b->stade), mb_strtolower(trim($this->rechercheRation)))
                || str_contains(mb_strtolower(FilieresElevage::libelle($b->espece)), mb_strtolower(trim($this->rechercheRation))))
            ->values();

        $afficherTaux = $this->especeRation === '' || array_key_exists($this->especeRation, FilieresElevage::POIDS_VIF);
        $tauxClasses = $afficherTaux
            ? TauxRationPoids::query()->whereNull('archive_le')
                ->when($this->especeRation !== '', fn ($q) => $q->where('espece', $this->especeRation))
                ->orderBy('espece')->orderBy('poids_min_g')->get()
            : collect();

        $terme = mb_strtolower(trim($this->rechercheProphylaxie));
        $echeances = EcheanceProphylaxie::query()->whereNull('archive_le')->where('espece', $this->especeProphylaxie)
            ->orderBy('jour_cycle')->orderBy('created_at')->get()
            ->filter(fn (EcheanceProphylaxie $e) => $terme === ''
                || str_contains(mb_strtolower($e->traitement), $terme) || str_contains(mb_strtolower($e->produit), $terme))
            ->values();

        $termeProvende = mb_strtolower(trim($this->rechercheProvende));
        $provendes = Intrant::query()->where('cat', 'Intrants Provende')->orderBy('code')->get()
            ->filter(fn (Intrant $i) => $termeProvende === '' || str_contains(mb_strtolower($i->name), $termeProvende) || str_contains(mb_strtolower($i->code), $termeProvende))
            ->values();

        return view('livewire.parametres-elevage', [
            'especes' => $especes,
            'toutesEspeces' => FilieresElevage::LIBELLES,
            'baremes' => $baremes,
            'tauxClasses' => $tauxClasses,
            'afficherTaux' => $afficherTaux,
            'especesPoidsVif' => $this->especesPoidsVif(),
            'echeances' => $echeances,
            'provendes' => $provendes,
            'peutGerer' => Auth::user()?->can('manage-elevage') ?? false,
            'peutArchiver' => Auth::user()?->can('archive-elevage') ?? false,
            'peutNumeroter' => Auth::user()?->can('manage-parametres') ?? false,
            'unitePoids' => FilieresElevage::POIDS_VIF[$this->espece][0] ?? 'kg',
            'aConfirmer' => $this->suppression === null ? null : match ($this->suppression['type']) {
                'bareme' => BaremeRation::query()->find($this->suppression['id']),
                'taux' => TauxRationPoids::query()->find($this->suppression['id']),
                default => EcheanceProphylaxie::query()->find($this->suppression['id']),
            },
        ])->title('Paramètres Élevage');
    }
}
