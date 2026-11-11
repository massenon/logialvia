<?php

namespace App\Livewire;

use App\Support\PlanSyscohada;
use App\Livewire\Concerns\LitLeLivre;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\MoteurComptable;
use App\Services\Comptabilite\Saisie;
use App\Services\Comptabilite\Verrous;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;
use App\Support\ExportXlsx;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Saisie des Depenses (Dart : `SaisieDepensesScreen`, `saisie_depenses_screen.dart`).
 *
 * ## Comment une depense devient une ecriture (lu dans le Dart)
 * Une depense n'a PAS de table : c'est une PIECE de 2 lignes, journal `CA`, numero `DEP-<poste>-AAAA-NNNN` —
 * la charge au DEBIT d'un compte de classe 6 (hors 601/602, alimentes par les achats ; SYSCOHADA), la
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

    /**
     * Piece de la depense en cours de CORRECTION : une piece acceptee est immuable, « corriger » =
     * l'annuler (ecriture inverse) puis passer la piece corrigee, en UNE transaction (tout ou rien).
     */
    public ?string $corrigeDe = null;

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
        $saisie = new Saisie(Auth::user());
        $corrige = $this->corrigeDe;
        $motif = null;
        try {
            DB::transaction(function () use (&$motif, $saisie, $corrige, $instant, $numero, $libelle, $montant) {
                if ($corrige !== null && ($refus = $saisie->contrepasser($corrige)) !== null) {
                    $motif = $refus;
                    throw new \RuntimeException('refus');
                }
                $motif = $saisie->enregistrer($instant, 'CA', $numero, [
                    // Seule la ligne de CHARGE porte le centre : la contrepartie n'appartient a aucune filiere.
                    ['compte' => $this->categorie, 'debit' => $montant, 'credit' => 0, 'libelle' => $libelle, 'axe' => $this->centre !== '' ? $this->centre : null],
                    ['compte' => $this->reglement, 'debit' => 0, 'credit' => $montant, 'libelle' => $libelle],
                ]);
                if ($motif !== null) {
                    throw new \RuntimeException('refus');
                }
            });
        } catch (\RuntimeException) {
            // `$motif` porte le refus : l'annulation eventuelle de la piece d'origine est annulee avec lui.
        }
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = ($corrige !== null ? "Dépense corrigée : l'ancienne pièce est annulée, " : '')."Dépense $numero enregistrée — ".\App\Support\FormatComptable::montant($montant)." imputés au compte {$this->categorie}.";
        // Comme `submitExpense()` : le formulaire est reinitialise, l'ecran enchaine les saisies.
        $this->reset(['libelle', 'categorie', 'montant', 'reglement', 'centre', 'corrigeDe']);
    }

    /** Pre-remplit le formulaire avec la depense a corriger (annulee puis ressaisie a l'enregistrement). */
    public function corriger(string $pieceId): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->erreur = null;

        [$ecritures] = $this->ecritures($this->annee());
        $d = collect(MoteurComptable::depenses($ecritures, LivreComptable::plan()))->firstWhere('piece_id', $pieceId);
        if ($d === null) {
            $this->erreur = 'Cette dépense n\'existe plus ou est déjà annulée.';

            return;
        }
        $this->corrigeDe = $pieceId;
        $this->libelle = $d['libelle'];
        $this->categorie = $d['compte'];
        $this->montant = (string) $d['montant'];
        $this->reglement = $d['compte_regle'];
        $this->centre = (string) ($d['centre'] ?? '');
        $this->jour = $d['date']->format('Y-m-d');
    }

    public function renoncerCorrection(): void
    {
        $this->reset(['libelle', 'categorie', 'montant', 'reglement', 'centre', 'corrigeDe', 'erreurs', 'erreur']);
        $this->jour = now(config('logialvia.fuseau'))->format('Y-m-d');
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
        return $plan->filter(fn ($c) => $c->classe === '6' && ! str_starts_with($c->numero_compte, PlanSyscohada::ACHATS_MARCHANDISES) && ! str_starts_with($c->numero_compte, PlanSyscohada::ACHATS_MATIERES));
    }

    /** Tresorerie (classe 5) ou « a credit » sur un compte fournisseur (40x). */
    private function comptesDeReglement($plan)
    {
        return $plan->filter(fn ($c) => $c->classe === '5' || str_starts_with($c->numero_compte, '40'));
    }

    /** Donnees de l'ecran : la vue ET l'export XLSX lisent la meme source. */
    private function donnees(): array
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

        return $this->communes($annee) + [
            'titre' => 'Saisie des Dépenses',
            'icone' => 'request_page',
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
        ];
    }

    public function render()
    {
        return view('livewire.comptabilite.depenses', $this->donnees())->title('Saisie des Dépenses');
    }

    /** Export XLSX du tableau affiche (memes filtres) : `view-comptabilite`, verifie ici. */
    public function exporter(): \Symfony\Component\HttpFoundation\StreamedResponse
    {
        abort_unless(\Illuminate\Support\Facades\Auth::user()?->can('view-comptabilite'), 403);

        $d = $this->donnees();
        $lignes = [['Dépenses — exercice '.$d['annee']], ['Date', 'Pièce', 'Libellé', 'Compte', 'Montant', 'Statut', 'Centre']];
        foreach ($d['depenses'] as $x) {
            $lignes[] = [$x['date']->format('d/m/Y'), $x['numero_piece'], $x['libelle'], $x['compte'], (int) round($x['montant']), $x['payee'] ? 'Payée' : 'En attente', (string) $x['centre']];
        }
        $lignes[] = ['Total affiché', '', '', '', (int) round($d['totalAffiche'])];

        $annee = $this->annee();

        return \App\Support\ExportXlsx::telecharger($lignes, 'depenses-'.$annee.'.xlsx', 'Saisie des Dépenses');
    }
}
