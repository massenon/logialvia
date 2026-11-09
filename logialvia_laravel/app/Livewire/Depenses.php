<?php

namespace App\Livewire;

use App\Livewire\Concerns\LitLeLivre;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\MoteurComptable;
use App\Services\Comptabilite\Saisie;
use App\Services\Comptabilite\Verrous;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Saisie des Depenses (Dart : `SaisieDepensesScreen`, `saisie_depenses_screen.dart`).
 *
 * ## Comment une depense devient une ecriture (lu dans le Dart)
 * Une depense n'a PAS de table : c'est une PIECE de 2 lignes, journal `CA`, numero `DEP-<poste>-AAAA-NNNN` —
 * la charge au DEBIT d'un compte de classe 6 (hors 601/602, alimentes par les achats), la
 * contrepartie au CREDIT d'un compte de tresorerie (classe 5) ou, « a credit », d'un compte
 * fournisseur (40x). Le centre analytique n'est porte que par la ligne de charge. La liste est
 * reconstruite depuis les ecritures : ligne au debit de classe 6, sans `vente_ref` ni `achat_ref`.
 *
 * Ici la piece passe par `EcrituresTable::absorber`, comme un poste. Ecarts avec le Dart :
 * - une piece acceptee est un FAIT IMMUABLE : pas de « Modifier » ; « Annuler la depense » passe
 *   l'ecriture inverse (`ANN-…`), et la depense annulee sort de la liste ;
 * - pas de piece justificative (aucun stockage de fichier), pas d'export PDF.
 */
#[Layout('components.layouts.app')]
class Depenses extends Component
{
    use LitLeLivre;

    /** Centres analytiques proposes (constante du module, comme au poste). */
    public const CENTRES = ['Goliaths', 'Pintades', 'Lapins', 'Poissons-Chats', 'Poulets', 'Pondeuses', 'Commerce Annexe'];

    public string $recherche = '';

    /** `` (tous), `payee` ou `attente`. */
    public string $statut = '';

    public string $jour = '';

    public string $libelle = '';

    public string $categorie = '';

    public string $montant = '';

    public string $reglement = '';

    public string $centre = '';

    /** @var array<string, string> */
    public array $erreurs = [];

    public ?string $message = null;

    public ?string $erreur = null;

    /** Piece de la depense dont l'annulation attend la confirmation. */
    public ?string $aAnnuler = null;

    public function mount(): void
    {
        $this->jour = now(config('logialvia.fuseau'))->format('Y-m-d');
    }

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-comptabilite'), 403);
    }

    public function reinitialiserFiltres(): void
    {
        $this->recherche = '';
        $this->statut = '';
    }

    public function enregistrer(): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->erreur = null;
        $this->erreurs = [];

        $libelle = trim($this->libelle);
        $montant = is_numeric(str_replace(',', '.', trim($this->montant))) ? (float) str_replace(',', '.', trim($this->montant)) : null;

        $erreurs = [];
        if ($libelle === '') {
            $erreurs['libelle'] = 'Ce champ est obligatoire.';
        }
        if ($montant === null || $montant <= 0) {
            $erreurs['montant'] = 'Montant obligatoire, supérieur à zéro.';
        }
        if ($this->categorie === '') {
            $erreurs['categorie'] = 'Ce champ est obligatoire.';
        }
        if ($this->reglement === '') {
            $erreurs['reglement'] = 'Ce champ est obligatoire.';
        }
        if ($erreurs !== []) {
            $this->erreurs = $erreurs;
            $this->erreur = 'Veuillez compléter les champs obligatoires.';

            return;
        }

        // Les listes proposees sont les seules comptes acceptes : jamais un numero libre.
        $plan = LivreComptable::plan()->where('archive', false);
        if (! $this->comptesDeCharge($plan)->has($this->categorie)
            || ! ($this->comptesDeReglement($plan)->has($this->reglement))) {
            $this->erreur = 'Compte inconnu, archivé ou non proposé à la saisie d\'une dépense.';

            return;
        }
        if ($this->centre !== '' && ! in_array($this->centre, self::CENTRES, true)) {
            $this->erreur = 'Centre analytique inconnu.';

            return;
        }
        $instant = Saisie::instantDuJour($this->jour);
        if ($instant === null) {
            $this->erreur = 'La date de la dépense est invalide.';

            return;
        }

        [$annee] = Verrous::anneeMois(CarbonImmutable::parse($instant));
        $numero = Saisie::numeroSuivant('DEP', $annee);
        $motif = (new Saisie(Auth::user()))->enregistrer($instant, 'CA', $numero, [
            // Seule la ligne de CHARGE porte le centre : la contrepartie n'appartient a aucune filiere.
            ['compte' => $this->categorie, 'debit' => $montant, 'credit' => 0, 'libelle' => $libelle, 'axe' => $this->centre !== '' ? $this->centre : null],
            ['compte' => $this->reglement, 'debit' => 0, 'credit' => $montant, 'libelle' => $libelle],
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = "Dépense $numero enregistrée — ".\App\Support\FormatComptable::montant($montant)." imputés au compte {$this->categorie}.";
        // Comme `submitExpense()` : le formulaire est reinitialise, l'ecran enchaine les saisies.
        $this->reset(['libelle', 'categorie', 'montant', 'reglement', 'centre']);
    }

    public function demanderAnnulation(string $pieceId): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->erreur = null;
        $this->aAnnuler = $pieceId;
    }

    public function annuler(): void
    {
        $this->aAnnuler = null;
    }

    public function confirmerAnnulation(): void
    {
        $this->verifierDroitDeGerer();
        $id = $this->aAnnuler;
        $this->aAnnuler = null;
        if ($id === null) {
            return;
        }

        $motif = (new Saisie(Auth::user()))->contrepasser($id);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        $this->message = 'Dépense annulée (écriture inverse passée).';
    }

    /** Comptes proposes a l'imputation : classe 6, hors comptes d'achats alimentes par les approvisionnements. */
    private function comptesDeCharge($plan)
    {
        return $plan->filter(fn ($c) => $c->classe === '6' && ! str_starts_with($c->numero_compte, '601') && ! str_starts_with($c->numero_compte, '602'));
    }

    /** Tresorerie (classe 5) ou « a credit » sur un compte fournisseur (40x). */
    private function comptesDeReglement($plan)
    {
        return $plan->filter(fn ($c) => $c->classe === '5' || str_starts_with($c->numero_compte, '40'));
    }

    public function render()
    {
        $annee = $this->annee();
        [$ecritures] = $this->ecritures($annee);
        $plan = LivreComptable::plan();
        $actifs = $plan->where('archive', false);

        $toutes = MoteurComptable::depenses($ecritures, $plan);
        $terme = mb_strtolower(trim($this->recherche));
        $filtrees = array_values(array_filter($toutes, function (array $d) use ($terme) {
            if ($this->statut === 'payee' && ! $d['payee']) {
                return false;
            }
            if ($this->statut === 'attente' && $d['payee']) {
                return false;
            }

            return $terme === ''
                || str_contains(mb_strtolower($d['libelle']), $terme)
                || str_contains(mb_strtolower($d['libelle_compte']), $terme)
                || str_contains($d['compte'], $terme)
                || str_contains(mb_strtolower($d['numero_piece']), $terme);
        }));

        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));
        $somme = fn (array $l) => array_sum(array_column($l, 'montant'));
        $fixes = array_filter($toutes, fn ($d) => in_array($d['compte'], MoteurComptable::COMPTES_FIXES, true));
        $variables = array_filter($toutes, fn ($d) => ! in_array($d['compte'], MoteurComptable::COMPTES_FIXES, true));
        $duMois = array_filter($toutes, fn ($d) => (int) $d['date']->year === (int) $maintenant->year && (int) $d['date']->month === (int) $maintenant->month);

        $comptesCharge = $this->comptesDeCharge($actifs);
        $comptesTresorerie = $actifs->filter(fn ($c) => $c->classe === '5');
        $comptesFournisseurs = $actifs->filter(fn ($c) => str_starts_with($c->numero_compte, '40'));

        return view('livewire.comptabilite.depenses', $this->communes($annee) + [
            'titre' => 'Saisie des Dépenses',
            'description' => 'Charges d\'exploitation courantes de la ferme (SYSCOHADA Classe 6) — hors achats d\'intrants, déjà couverts par Achats & Commandes.',
            'depenses' => $filtrees,
            'aucuneDepense' => $toutes === [],
            'totalAffiche' => $somme($filtrees),
            'depensesDuMois' => $somme($duMois),
            'chargesFixes' => $somme($fixes),
            'chargesVariables' => $somme($variables),
            'comptesCharge' => $comptesCharge,
            'comptesTresorerie' => $comptesTresorerie,
            'comptesFournisseurs' => $comptesFournisseurs,
            'planIncomplet' => $comptesCharge->isEmpty() || $comptesTresorerie->isEmpty(),
            'centres' => self::CENTRES,
            'peutGerer' => (bool) Auth::user()?->can('manage-comptabilite'),
        ])->title('Saisie des Dépenses');
    }
}
