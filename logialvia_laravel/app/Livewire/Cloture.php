<?php

namespace App\Livewire;

use App\Livewire\Concerns\LitLeLivre;
use App\Models\CloturePeriodique;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\MoteurComptable;
use App\Services\Comptabilite\ReportANouveau;
use App\Services\Comptabilite\Saisie;
use App\Services\Comptabilite\Soldes;
use App\Support\Audit;
use App\Support\UuidDeterministe;
use App\Sync\Tables\ClotureExerciceTable;
use App\Sync\Tables\CloturesPeriodiquesTable;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Cloture d'Exercice (Dart : `ClotureExerciceScreen`, `cloture_exercice_screen.dart`).
 *
 * - Cloture PERIODIQUE (BR-CPT-006) : clore un mois = `manage-comptabilite` ; le DECLORE (le rouvrir
 *   pour correction) = `close-fiscal-year`, l'administratrice seule, avec trace d'audit.
 * - Cloture ANNUELLE (BR-CPT-001) : un fait LOURD, `close-fiscal-year` seul, balance equilibree.
 *   Definitive : aucune decloture. Les deux passent par les tables de synchronisation, comme un
 *   poste : memes regles, memes motifs de refus.
 *
 * Une ecriture saisie hors ligne sur un poste pour une periode que cette cloture verrouille est
 * REFUSEE avec son motif quand ce poste se reconnecte (elle reste, marquee, dans ses livres).
 */
#[Layout('components.layouts.app')]
class Cloture extends Component
{
    use LitLeLivre;

    public const MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

    public ?string $message = null;

    public ?string $erreur = null;

    /** La confirmation de la cloture annuelle est ouverte. */
    public bool $confirmation = false;

    /** La confirmation de la reouverture est ouverte. */
    public bool $confirmationReouverture = false;

    /** Affectation du benefice (decision de l'Assemblee), saisie en FCFA ; le reste va au report a nouveau (121). */
    public string $reserveLegale = '';

    public string $autresReserves = '';

    public string $dividendes = '';

    private function lireMontant(string $texte): float
    {
        $propre = str_replace([' ', "\u{202f}", "\u{a0}"], '', $texte);

        return is_numeric(str_replace(',', '.', $propre)) ? max(0.0, (float) str_replace(',', '.', $propre)) : 0.0;
    }

    /** @return array{reserve_legale: float, autres_reserves: float, dividendes: float} */
    private function affectationSaisie(): array
    {
        return ReportANouveau::affectation([
            'reserve_legale' => $this->lireMontant($this->reserveLegale),
            'autres_reserves' => $this->lireMontant($this->autresReserves),
            'dividendes' => $this->lireMontant($this->dividendes),
        ]);
    }

    /** Apercu de la cloture (rien n'est ecrit) : resultat, pieces, a-nouveaux, anomalies. */
    private function apercu(int $annee): array
    {
        return ReportANouveau::calculer(
            LivreComptable::toutes()->all(),
            $annee,
            $this->affectationSaisie(),
            LivreComptable::plan()->keys()->map(fn ($k) => (string) $k)->all(),
        );
    }

    private function nomDuMois(int $mois): string
    {
        return ucfirst(self::MOIS[$mois - 1]);
    }

    /** La balance de l'exercice est-elle equilibree ? Ecart debit − credit sinon. */
    private function ecartBalance(int $annee): float
    {
        [, $ouverture] = $this->ecritures($annee);

        return MoteurComptable::ecartBalance(MoteurComptable::balanceDepuis(LivreComptable::plan(), $ouverture, $this->duLivre($annee)));
    }

    private function refuserSiDesequilibre(int $annee, string $suite): bool
    {
        $ecart = $this->ecartBalance($annee);
        if (abs($ecart) < MoteurComptable::TOLERANCE) {
            return false;
        }
        $this->erreur = 'Balance déséquilibrée de '.number_format(abs($ecart), 0, ',', ' ')." FCFA. $suite (BR-CPT-004).";

        return true;
    }

    public function basculerMois(int $mois): void
    {
        abort_unless($mois >= 1 && $mois <= 12, 422);
        $utilisateur = Auth::user();
        abort_unless($utilisateur?->can('manage-comptabilite'), 403);
        $this->message = null;
        $this->erreur = null;

        $annee = $this->annee();
        $clos = CloturePeriodique::query()->where('annee', $annee)->where('mois', $mois)->where('is_cloture', true)->exists();
        $nom = $this->nomDuMois($mois);

        if ($clos) {
            // Declôturer : l'administratrice seule (BR-CPT-006).
            abort_unless($utilisateur->can('close-fiscal-year'), 403);
        } else {
            if ($this->exerciceEstCloture($annee)) {
                $this->erreur = 'L\'exercice est déjà clôturé.';

                return;
            }
            if ($this->refuserSiDesequilibre($annee, 'Corrigez la saisie avant toute clôture')) {
                return;
            }
        }

        $instant = Saisie::instantMaintenant();
        $motif = (new CloturesPeriodiquesTable)->pourUtilisateur($utilisateur)->absorber(Catalogue::POSTE_WEB, [
            'id' => UuidDeterministe::cloturePeriodique($annee, $mois),
            'annee' => $annee,
            'mois' => $mois,
            'is_cloture' => ! $clos,
            'date_cloture' => $clos ? null : $instant,
            'decloture_par' => $clos ? $utilisateur->username : null,
            'updated_at' => $instant,
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        if ($clos) {
            Audit::enregistrer('comptabilite.decloture', $utilisateur, ['annee' => $annee, 'mois' => $mois]);
        }
        $this->message = $clos
            ? "Mois de $nom déclôturé — action tracée dans le journal d'audit."
            : "Mois de $nom clôturé.";
    }

    public function demanderCloture(): void
    {
        abort_unless(Auth::user()?->can('close-fiscal-year'), 403);
        $this->message = null;
        $this->erreur = null;
        $this->confirmation = true;
    }

    public function annuler(): void
    {
        $this->confirmation = false;
    }

    public function cloturerExercice(): void
    {
        $utilisateur = Auth::user();
        abort_unless($utilisateur?->can('close-fiscal-year'), 403);
        $this->confirmation = false;
        $this->message = null;
        $this->erreur = null;

        $annee = $this->annee();
        if ($this->exerciceEstCloture($annee)) {
            $this->erreur = 'Cet exercice est déjà clôturé.';

            return;
        }
        if ($this->refuserSiDesequilibre($annee, 'Une clôture annuelle est définitive : elle ne peut pas s\'exécuter sur une comptabilité déséquilibrée')) {
            return;
        }

        $apercu = $this->apercu($annee);
        if ($apercu['anomalies'] !== []) {
            $this->erreur = implode(' ', $apercu['anomalies']);

            return;
        }

        $instant = Saisie::instantMaintenant();
        $motif = DB::transaction(fn () => (new ClotureExerciceTable)->pourUtilisateur($utilisateur)->absorber(Catalogue::POSTE_WEB, [
            'id' => UuidDeterministe::clotureExercice($annee),
            'annee' => $annee,
            'date_cloture' => $instant,
            'updated_at' => $instant,
            'affectation' => $this->affectationSaisie(),
        ]));
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = "Exercice $annee clôturé. L'exercice ".($annee + 1).' est ouvert.';
    }

    public function demanderReouverture(): void
    {
        abort_unless(Auth::user()?->can('close-fiscal-year'), 403);
        $this->message = null;
        $this->erreur = null;
        $this->confirmationReouverture = true;
    }

    public function annulerReouverture(): void
    {
        $this->confirmationReouverture = false;
    }

    /** Rouvre l'exercice : retire la cloture (CL) et les a-nouveaux (AN) de l'exercice suivant. Administratrice seule. */
    public function rouvrirExercice(): void
    {
        $utilisateur = Auth::user();
        abort_unless($utilisateur?->can('close-fiscal-year'), 403);
        $this->confirmationReouverture = false;
        $this->message = null;
        $this->erreur = null;

        $annee = $this->annee();
        $motif = (new ClotureExerciceTable)->pourUtilisateur($utilisateur)->rouvrir($annee);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        $this->message = "Exercice $annee rouvert : écritures de clôture et à-nouveaux retirés.";
    }

    public function render()
    {
        $annee = $this->annee();
        [, $ouverture] = $this->ecritures($annee);
        $soldes = $this->soldesFin($annee);
        $balance = MoteurComptable::balanceDepuis(LivreComptable::plan(), $ouverture, $this->duLivre($annee));
        $cloture = $this->exerciceEstCloture($annee);
        $mois = CloturePeriodique::query()->where('annee', $annee)->pluck('is_cloture', 'mois')->map(fn ($v) => (bool) $v);
        $ecart = MoteurComptable::ecartBalance($balance);
        $utilisateur = Auth::user();

        return view('livewire.comptabilite.cloture', $this->communes($annee) + [
            'titre' => 'Clôture d\'Exercice',
            'description' => 'Verrouillage de l\'exercice fiscal et report à nouveau vers l\'exercice suivant.',
            'frise' => array_reverse(LivreComptable::exercices()),
            'moisClos' => $mois,
            'noms' => array_map(fn (int $m) => $this->nomDuMois($m), range(1, 12)),
            'resultat' => MoteurComptable::resultatNet($soldes),
            'produits' => MoteurComptable::produits($soldes),
            'charges' => MoteurComptable::charges($soldes),
            'comptesDeGestion' => count(array_filter(
                $balance,
                fn ($l) => (str_starts_with($l['numero'], '6') || str_starts_with($l['numero'], '7'))
                    && (abs($l['mouvements_debit']) >= 0.01 || abs($l['mouvements_credit']) >= 0.01),
            )),
            'equilibree' => abs($ecart) < MoteurComptable::TOLERANCE,
            'ecart' => $ecart,
            'tousMoisClos' => $mois->filter()->count() === 12,
            'peutGerer' => (bool) $utilisateur?->can('manage-comptabilite'),
            'peutClore' => (bool) $utilisateur?->can('close-fiscal-year'),
            'apercu' => $this->apercu($annee),
            'affectationSaisie' => $this->affectationSaisie(),
            'ouvertureParANouveaux' => collect(LivreComptable::toutes())->contains(fn ($e) => $e->exercice === $annee && $e->journal === ReportANouveau::A_NOUVEAU),
            'affectationCloture' => ($brut = \App\Models\ExerciceComptable::query()->whereKey($annee)->value('affectation')) ? ReportANouveau::affectation(json_decode($brut, true)) : ReportANouveau::affectation(null),
        ])->title('Clôture d\'Exercice');
    }
}
