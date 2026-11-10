<?php

namespace App\Livewire;

use App\Support\PlanSyscohada;
use App\Livewire\Concerns\LitLeLivre;
use App\Services\Comptabilite\LigneEcriture;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\MoteurComptable;
use App\Services\Comptabilite\Saisie;
use App\Services\Comptabilite\Verrous;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Journal Comptable (Dart : `JournalComptableScreen`, `journal_comptable_screen.dart`).
 *
 * Toutes les ecritures recues de TOUS les postes (le journal est la somme des faits), avec
 * leur poste d'origine. La saisie manuelle (operation diverse : un compte debite, un compte
 * credite, un montant — l'equilibre est garanti par construction) passe par
 * `EcrituresTable::absorber`, comme un poste.
 *
 * Ecarts avec le Dart : une piece est un FAIT IMMUABLE — pas de suppression, « Annuler la
 * piece » passe l'ecriture INVERSE (`ANN-…`), ce que le poste fait pour une piece deja transmise ;
 * pas d'export PDF.
 */
#[Layout('components.layouts.app')]
class Journal extends Component
{
    use LitLeLivre;

    public string $recherche = '';

    public string $journal = '';

    // Modale « Nouvelle Écriture (Opération Diverse) ».
    public bool $formulaire = false;

    public string $jour = '';

    public string $libelle = '';

    public string $compteDebit = PlanSyscohada::CAISSE;

    public string $compteCredit = PlanSyscohada::VENTES_PRODUITS_FINIS;

    public string $montant = '';

    public ?string $erreur = null;

    public ?string $message = null;

    /** Piece dont l'annulation attend la confirmation. */
    public ?string $aAnnuler = null;

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-comptabilite'), 403);
    }

    public function nouvelle(): void
    {
        $this->verifierDroitDeGerer();
        $this->reset(['libelle', 'montant', 'erreur', 'message']);
        $this->jour = now(config('logialvia.fuseau'))->format('Y-m-d');
        $this->compteDebit = PlanSyscohada::CAISSE;
        $this->compteCredit = PlanSyscohada::VENTES_PRODUITS_FINIS;
        $this->formulaire = true;
    }

    public function annuler(): void
    {
        $this->formulaire = false;
        $this->aAnnuler = null;
        $this->erreur = null;
    }

    public function enregistrer(): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;

        $montant = is_numeric(str_replace(',', '.', trim($this->montant))) ? (float) str_replace(',', '.', trim($this->montant)) : null;
        if (trim($this->libelle) === '' || $montant === null || $montant <= 0) {
            $this->erreur = 'Veuillez renseigner le libellé et un montant valide.';

            return;
        }
        if ($this->compteDebit === $this->compteCredit) {
            $this->erreur = 'Le compte Débit et le compte Crédit ne peuvent pas être identiques.';

            return;
        }
        $instant = Saisie::instantDuJour($this->jour);
        if ($instant === null) {
            $this->erreur = 'La date de l\'écriture est invalide.';

            return;
        }
        $actifs = LivreComptable::plan()->where('archive', false);
        if (! $actifs->has($this->compteDebit) || ! $actifs->has($this->compteCredit)) {
            $this->erreur = 'Compte inconnu ou archivé.';

            return;
        }

        [$annee] = Verrous::anneeMois(\Carbon\CarbonImmutable::parse($instant));
        $numero = Saisie::numeroSuivant('OD', $annee);
        $motif = (new Saisie(Auth::user()))->enregistrer($instant, 'OD', $numero, [
            ['compte' => $this->compteDebit, 'debit' => $montant, 'credit' => 0, 'libelle' => trim($this->libelle)],
            ['compte' => $this->compteCredit, 'debit' => 0, 'credit' => $montant, 'libelle' => trim($this->libelle)],
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = "Écriture $numero enregistrée — Débit {$this->compteDebit} / Crédit {$this->compteCredit}.";
        $this->formulaire = false;
        $this->erreur = null;
    }

    public function demanderAnnulation(string $pieceId): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->erreur = null;
        $this->aAnnuler = $pieceId;
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
        $this->message = $motif ?? 'Pièce annulée (écriture inverse passée).';
    }

    /** Donnees de l'ecran : la vue ET l'export XLSX lisent la meme source. */
    private function donnees(): array
    {
        $annee = $this->annee();
        $ecritures = $this->duJournal($annee);
        $plan = LivreComptable::plan();
        $terme = mb_strtolower(trim($this->recherche));
        $codes = Saisie::codesDesPostes();

        $annulees = $ecritures->whereNotNull('contrepasseDe')->pluck('contrepasseDe')->flip();

        // Ordre du poste : date decroissante ; les lignes d'une piece restent groupees.
        $pieces = $ecritures->groupBy('pieceId')
            ->sortByDesc(fn ($lignes) => $lignes->first()->date->getTimestamp())
            ->values();

        $lignes = $pieces->flatMap(fn ($groupe) => $groupe->values()->map(fn (LigneEcriture $e, int $i) => [
            'ecriture' => $e,
            'premiere' => $i === 0,
        ]))->filter(function (array $l) use ($terme) {
            /** @var LigneEcriture $e */
            $e = $l['ecriture'];
            if ($this->journal !== '' && $e->journal !== $this->journal) {
                return false;
            }

            return $terme === ''
                || str_contains(mb_strtolower($e->libelle), $terme)
                || str_contains($e->compte, $terme)
                || str_contains(mb_strtolower((string) $e->numeroPiece), $terme);
        })->values();

        $debit = $lignes->sum(fn ($l) => $l['ecriture']->debit);
        $credit = $lignes->sum(fn ($l) => $l['ecriture']->credit);

        return $this->communes($annee) + [
            'titre' => 'Journal Comptable',
            'description' => 'Écritures automatiques (ventes, achats) et saisie manuelle d\'opérations diverses.',
            'lignes' => $lignes,
            'plan' => $plan,
            'comptesActifs' => $plan->where('archive', false),
            'totalDebit' => $debit,
            'totalCredit' => $credit,
            'equilibre' => abs($debit - $credit) < MoteurComptable::TOLERANCE,
            'annulees' => $annulees,
            'codes' => $codes,
            'aucuneEcriture' => $ecritures->isEmpty(),
            'journaux' => ['VT' => 'Journal des Ventes', 'AC' => 'Journal des Achats', 'CA' => 'Journal de Caisse', 'OD' => 'Opérations Diverses']
                + \App\Services\Comptabilite\ReportANouveau::LIBELLES_JOURNAUX,
            'peutGerer' => (bool) Auth::user()?->can('manage-comptabilite'),
        ];
    }

    public function render()
    {
        return view('livewire.comptabilite.journal', $this->donnees())->title('Journal Comptable');
    }

    /** Export XLSX du tableau affiche (memes filtres) : `view-comptabilite`, verifie ici. */
    public function exporter(): \Symfony\Component\HttpFoundation\StreamedResponse
    {
        abort_unless(\Illuminate\Support\Facades\Auth::user()?->can('view-comptabilite'), 403);

        $d = $this->donnees();
        $lignes = [['Journal Comptable — exercice '.$d['annee']], ['Date', 'Journal', 'Pièce', 'Compte', 'Libellé', 'Débit', 'Crédit']];
        foreach ($d['lignes'] as $l) {
            $e = $l['ecriture'];
            $lignes[] = [$e->date->format('d/m/Y'), $e->journal, (string) $e->numeroPiece, $e->compte, $e->libelle, (int) round($e->debit), (int) round($e->credit)];
        }
        $lignes[] = ['Total', '', '', '', '', (int) round($d['totalDebit']), (int) round($d['totalCredit'])];

        $annee = $this->annee();

        return \App\Support\ExportXlsx::telecharger($lignes, 'journal-comptable-'.$annee.'.xlsx', 'Journal');
    }
}
