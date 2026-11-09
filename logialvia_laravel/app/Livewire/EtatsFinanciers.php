<?php

namespace App\Livewire;

use App\Livewire\Concerns\LitLeLivre;
use App\Models\NoteAnnexe;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\MoteurComptable;
use App\Services\Comptabilite\Saisie;
use App\Services\Comptabilite\Soldes;
use App\Support\UuidDeterministe;
use App\Sync\Tables\NotesAnnexesTable;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Etats Financiers (Dart : `EtatsFinanciersScreen`, `etats_financiers_screen.dart`).
 *
 * Quatre onglets — Bilan, Compte de Resultat, Flux de Tresorerie (TAFIRE), Notes Annexes — lus par
 * UN SEUL moteur sur TOUTES les ecritures recues : le Resultat Net est le meme partout (BR-CPT-005).
 * Notes 2, 3 et 4 sont CALCULEES depuis la balance ; notes 1 et 5 sont redactionnelles, enregistrees
 * par `NotesAnnexesTable::absorber` (dernier ecrivain gagne, comme un poste).
 *
 * Ecart avec le Dart : pas d'export PDF.
 */
#[Layout('components.layouts.app')]
class EtatsFinanciers extends Component
{
    use LitLeLivre;

    public const ONGLETS = [
        'bilan' => 'Bilan',
        'resultat' => 'Compte de Résultat',
        'flux' => 'Flux de Trésorerie',
        'notes' => 'Notes Annexes',
    ];

    public const TITRES_NOTES = [
        1 => 'Méthodes Comptables', 2 => 'Immobilisations', 3 => 'Stocks',
        4 => 'Créances et Dettes', 5 => 'Engagements Hors Bilan',
    ];

    public const NOTE_1_PAR_DEFAUT = 'Les immobilisations sont amorties selon la méthode linéaire. Les stocks (intrants provende et produits finis) sont valorisés au Prix Moyen Pondéré (PMP). La monnaie de présentation est le Franc CFA (FCFA), sans décimale.';

    public const NOTE_5_PAR_DEFAUT = 'Néant à la date de clôture de la période présentée.';

    public string $onglet = 'bilan';

    /** Texte des notes redactionnelles (1 et 5) en cours de saisie. */
    public array $notes = [];

    public ?string $message = null;

    public ?string $erreur = null;

    public function mount(): void
    {
        $this->chargerNotes();
    }

    public function updatedExercice(): void
    {
        $this->message = null;
        $this->erreur = null;
        $this->chargerNotes();
    }

    private function chargerNotes(): void
    {
        $annee = $this->annee();
        $enregistrees = NoteAnnexe::query()->where('exercice_annee', $annee)->pluck('contenu', 'numero_note');
        $this->notes = [
            1 => $enregistrees[1] ?? '' ?: self::NOTE_1_PAR_DEFAUT,
            5 => $enregistrees[5] ?? '' ?: self::NOTE_5_PAR_DEFAUT,
        ];
    }

    public function choisir(string $onglet): void
    {
        if (array_key_exists($onglet, self::ONGLETS)) {
            $this->onglet = $onglet;
        }
    }

    public function enregistrerNote(int $numero): void
    {
        abort_unless(Auth::user()?->can('manage-comptabilite'), 403);
        abort_unless(in_array($numero, [1, 5], true), 422);
        $this->message = null;
        $this->erreur = null;

        $annee = $this->annee();
        $motif = (new NotesAnnexesTable)->absorber(Catalogue::POSTE_WEB, [
            'id' => UuidDeterministe::note($annee, $numero),
            'exercice_annee' => $annee,
            'numero_note' => $numero,
            'titre' => self::TITRES_NOTES[$numero],
            'contenu' => trim((string) ($this->notes[$numero] ?? '')),
            'updated_at' => Saisie::instantMaintenant(),
        ]);

        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        $this->message = "Note $numero enregistrée.";
    }

    public function render()
    {
        $annee = $this->annee();
        [$ecritures, $anterieures] = $this->ecritures($annee);
        $soldes = Soldes::depuis($ecritures);
        $ouverture = Soldes::depuis($anterieures);
        $plan = LivreComptable::plan();
        $balance = MoteurComptable::balance($plan, $anterieures, $ecritures);

        $bilan = MoteurComptable::bilan($soldes);
        $tafire = MoteurComptable::tafire($soldes, $ouverture);
        $tresorerieBilan = $soldes->debiteursParClasse('5');
        $ecartTafire = $tafire['tresorerie_cloture'] - $tresorerieBilan;

        // Notes 2, 3 et 4 : calculees depuis la balance, jamais saisies.
        $classe2 = array_filter($balance, fn ($l) => str_starts_with($l['numero'], '2'));
        $brutes = array_values(array_filter($classe2, fn ($l) => ! str_starts_with($l['numero'], '28')));
        $amortissements = array_values(array_filter($classe2, fn ($l) => str_starts_with($l['numero'], '28')));
        $immobilisations = array_map(function ($l) use ($amortissements) {
            $brut = $l['final_debit'] - $l['final_credit'];
            $suffixe = substr($l['numero'], 1);
            $amort = 0.0;
            foreach ($amortissements as $a) {
                if (str_starts_with($a['numero'], '28'.$suffixe)) {
                    $amort += $a['final_credit'] - $a['final_debit'];
                }
            }

            return ['libelle' => $l['libelle'], 'brut' => $brut, 'amort' => $amort, 'net' => $brut - $amort];
        }, $brutes);
        $totalBrut = array_sum(array_map(fn ($l) => $l['final_debit'] - $l['final_credit'], $brutes));
        $totalAmort = array_sum(array_map(fn ($l) => $l['final_credit'] - $l['final_debit'], $amortissements));

        $stocks = array_values(array_filter($balance, fn ($l) => str_starts_with($l['numero'], '3')));
        $tiers = array_values(array_filter(
            $balance,
            fn ($l) => str_starts_with($l['numero'], '4') && (abs($l['final_debit']) >= 0.01 || abs($l['final_credit']) >= 0.01),
        ));

        return view('livewire.comptabilite.etats-financiers', $this->communes($annee) + [
            'titre' => 'États Financiers',
            'description' => 'Bilan, Compte de Résultat, Tableau des Flux de Trésorerie et Notes Annexes — conformité SYSCOHADA.',
            'onglets' => self::ONGLETS,
            'titresNotes' => self::TITRES_NOTES,
            'bilan' => $bilan,
            'resultat' => MoteurComptable::compteResultat($soldes),
            'tafire' => $tafire,
            'tresorerieBilan' => $tresorerieBilan,
            'ecartTafire' => $ecartTafire,
            'tafireCoherent' => abs($ecartTafire) < MoteurComptable::TOLERANCE,
            'immobilisations' => $immobilisations,
            'totalBrut' => $totalBrut,
            'totalAmort' => $totalAmort,
            'stocks' => $stocks,
            'totalStocks' => array_sum(array_map(fn ($l) => $l['final_debit'] - $l['final_credit'], $stocks)),
            'tiers' => $tiers,
            'aujourdhui' => now(config('logialvia.fuseau'))->format('d/m/Y'),
            'peutGerer' => (bool) Auth::user()?->can('manage-comptabilite'),
        ])->title('États Financiers');
    }
}
