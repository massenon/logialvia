<?php

namespace App\Livewire;

use App\Livewire\Concerns\ReglementDette;
use App\Models\Achat;
use App\Models\Fournisseur;
use App\Models\Intrant;
use App\Services\Achats\GestionAchats;
use App\Sync\Tables\AchatsTable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;
use App\Support\ExportXlsx;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Achats & Commandes (Dart : `AchatsScreen`, `achats_fournisseurs_screens.dart`).
 *
 * PARITE avec le poste : commande (panier d'intrants), reception, reglement ; en plus du Dart, le web
 * MODIFIE une commande « Commandé » et ANNULE avec motif (extourne). Voir `GestionAchats` pour les regles,
 * `EcrituresAutomatiquesAchats` pour les ecritures SYSCOHADA et `docs/logialvia/47b_ACHATS_PARITE.md`.
 *
 * **Decision du client « stock propre a chaque poste + journal partage »** : la reception au web ecrit
 * un mouvement `Entrée` au journal (poste d'origine : web) mais ne met AUCUN stock ni PMP a jour — c'est
 * dit sur l'ecran. Il n'y a donc pas de prix propose (le PMP est propre a chaque poste).
 *
 * Toute ecriture passe par `GestionAchats` → `AchatsTable::absorber` (poste « web »), jamais par un
 * `update` ; le droit `manage-achats` est verifie dans CHAQUE methode d'ecriture.
 */
#[Layout('components.layouts.app')]
class Achats extends Component
{
    use ReglementDette;

    public const ANCIENNETE_JOURS = 10;

    /** Meme plafond que le poste (`chargerAchats(limite: 200)`). */
    public const LIMITE = 200;

    public string $recherche = '';

    public string $statut = '';

    /** Achat dont le detail des lignes est deplie. */
    public ?string $ouvert = null;

    // --- formulaire de commande (le « panier d'achat » du poste) ---

    public bool $formulaire = false;

    /** Achat modifie ; `null` = nouvelle commande. */
    public ?string $achatId = null;

    public string $fournisseurId = '';

    public string $mode = 'Espèces';

    public string $paye = '';

    public string $echeance = '';

    public bool $livree = true;

    /** @var list<array{intrant_code: string, qte: string, pu: string}> */
    public array $lignes = [];

    public string $intrantAjoute = '';

    public ?string $erreur = null;

    public ?string $message = null;

    // --- reception et annulation : confirmations ---

    public ?string $aReceptionner = null;

    public ?string $aAnnuler = null;

    public string $motifAnnulation = '';

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-achats'), 403);
    }

    public function basculer(string $id): void
    {
        $this->ouvert = $this->ouvert === $id ? null : $id;
    }

    // ---------------------------------------------------------------- commande

    public function nouveau(): void
    {
        $this->verifierDroitDeGerer();
        $this->reinitialiser();
        $this->formulaire = true;
    }

    public function modifier(string $id): void
    {
        $this->verifierDroitDeGerer();
        $achat = Achat::query()->with('lignes')->find($id);
        if ($achat === null || $achat->statut !== 'Commandé') {
            $this->message = null;
            $this->erreur = 'Seule une commande en attente de livraison peut être modifiée.';

            return;
        }

        $this->reinitialiser();
        $this->achatId = $achat->id;
        $this->fournisseurId = $achat->fournisseur_id;
        $this->mode = in_array($achat->mode, GestionAchats::MODES, true) ? $achat->mode : 'Espèces';
        $this->paye = $achat->paye > 0 ? (string) $achat->paye : '';
        $this->echeance = $achat->echeance?->timezone(config('logialvia.fuseau'))->format('Y-m-d') ?? '';
        $this->lignes = $achat->lignes->map(fn ($l) => [
            'intrant_code' => $l->intrant_code, 'qte' => (string) (int) $l->qte, 'pu' => (string) $l->pu_achat,
        ])->all();
        $this->formulaire = true;
    }

    /** Clic sur un intrant : ajoute la ligne, ou ajoute 1 a sa quantite (comme `ajouterAuPanier` du poste). */
    public function ajouterIntrant(): void
    {
        $this->verifierDroitDeGerer();
        $code = $this->intrantAjoute;
        $this->intrantAjoute = '';
        if ($code === '' || ! Intrant::query()->whereKey($code)->exists()) {
            return;
        }
        foreach ($this->lignes as $i => $l) {
            if ($l['intrant_code'] === $code) {
                $this->lignes[$i]['qte'] = (string) ((int) $l['qte'] + 1);

                return;
            }
        }
        $this->lignes[] = ['intrant_code' => $code, 'qte' => '1', 'pu' => ''];
    }

    public function retirerLigne(int $index): void
    {
        $this->verifierDroitDeGerer();
        unset($this->lignes[$index]);
        $this->lignes = array_values($this->lignes);
    }

    public function annulerFormulaire(): void
    {
        $this->formulaire = false;
        $this->erreur = null;
    }

    public function enregistrer(): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->erreur = null;

        $donnees = [
            'fournisseur_id' => $this->fournisseurId,
            'mode' => $this->mode,
            'paye' => $this->paye === '' ? 0 : $this->paye,
            'echeance' => $this->echeance,
            'livree' => $this->livree,
            'lignes' => $this->lignes,
        ];
        $gestion = new GestionAchats(Auth::user());
        $bilan = $this->achatId === null ? $gestion->creer($donnees) : $gestion->modifier($this->achatId, $donnees);

        if ($bilan['erreur'] !== null) {
            $this->erreur = $bilan['erreur'];

            return;
        }

        $achat = $bilan['achat'];
        $this->message = $this->achatId === null
            ? "Commande {$achat->reference} enregistrée."
                .($achat->statut === 'Livré' ? ' Entrées inscrites au journal ; le stock et le PMP restent propres à chaque poste.' : '')
            : "Commande {$achat->reference} modifiée (écritures extournées et réécrites).";
        $this->formulaire = false;
    }

    // --------------------------------------------------------------- reception

    public function demanderReception(string $id): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->erreur = null;
        $this->aReceptionner = $id;
    }

    public function annulerReception(): void
    {
        $this->aReceptionner = null;
    }

    public function confirmerReception(): void
    {
        $this->verifierDroitDeGerer();
        $id = $this->aReceptionner;
        $this->aReceptionner = null;
        if ($id === null) {
            return;
        }

        $bilan = (new GestionAchats(Auth::user()))->receptionner($id);
        if ($bilan['erreur'] !== null) {
            $this->erreur = $bilan['erreur'];

            return;
        }
        $this->message = "Commande {$bilan['achat']->reference} réceptionnée : entrées inscrites au journal. Le stock et le PMP ne sont pas modifiés (propres à chaque poste).";
    }

    // -------------------------------------------------------------- annulation

    public function demanderAnnulation(string $id): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->erreur = null;
        $this->motifAnnulation = '';
        $this->aAnnuler = $id;
    }

    public function renoncerAnnulation(): void
    {
        $this->aAnnuler = null;
        $this->erreur = null;
    }

    public function confirmerAnnulation(): void
    {
        $this->verifierDroitDeGerer();
        $id = $this->aAnnuler;
        if ($id === null) {
            return;
        }

        $bilan = (new GestionAchats(Auth::user()))->annuler($id, $this->motifAnnulation);
        if ($bilan['erreur'] !== null) {
            $this->erreur = $bilan['erreur'];

            return;
        }
        $this->aAnnuler = null;
        $this->message = "Commande {$bilan['achat']->reference} annulée : écritures extournées.";
    }

    private function reinitialiser(): void
    {
        $this->reset(['achatId', 'fournisseurId', 'paye', 'echeance', 'lignes', 'intrantAjoute', 'erreur', 'message']);
        $this->mode = 'Espèces';
        $this->livree = true;
    }

    /** Les achats de l'ecran : memes filtres, meme plafond que le poste. */
    private function achatsFiltres($noms)
    {
        $terme = trim($this->recherche);

        return Achat::query()
            ->when(in_array($this->statut, AchatsTable::STATUTS, true), fn ($q) => $q->where('statut', $this->statut))
            ->when($terme !== '', function ($q) use ($terme, $noms) {
                $ids = $noms->filter(fn (string $nom) => mb_stripos($nom, $terme) !== false)->keys();
                $q->where(fn ($w) => $w->where('reference', 'like', "%$terme%")->orWhereIn('fournisseur_id', $ids));
            })
            ->orderByDesc('date_achat')->orderByDesc('reference')
            ->limit(self::LIMITE)
            ->get();
    }

    /** Export XLSX du tableau affiche (memes filtres). Droit de lecture verifie ICI. */
    public function exporter(): StreamedResponse
    {
        abort_unless(Auth::user()?->can('view-achats'), 403);
        $noms = Fournisseur::query()->pluck('nom', 'id');
        $fuseau = config('logialvia.fuseau');
        $lignes = [['Référence', 'Date', 'Fournisseur', 'Mode', 'Statut', 'Total', 'Payé', 'Reste dû', 'Échéance']];
        foreach ($this->achatsFiltres($noms) as $a) {
            $lignes[] = [
                $a->reference, $a->date_achat->timezone($fuseau)->format('d/m/Y'), $noms[$a->fournisseur_id] ?? '—',
                $a->mode ?: '—', $a->statut, (float) $a->total, (float) $a->paye,
                $a->statut === 'Annulé' ? 0.0 : max(0.0, round($a->total - $a->paye, 2)),
                $a->echeance ? $a->echeance->timezone($fuseau)->format('d/m/Y') : '',
            ];
        }

        return ExportXlsx::telecharger($lignes, 'achats.xlsx', 'Achats');
    }

    public function render()
    {
        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));
        $debutMois = $maintenant->startOfMonth();
        $terme = trim($this->recherche);
        $noms = Fournisseur::query()->pluck('nom', 'id');

        $tous = Achat::query()->get();
        $enCours = $tous->where('statut', 'Commandé');
        $duMois = $tous->filter(fn (Achat $a) => $a->statut !== 'Annulé' && $a->date_achat->greaterThanOrEqualTo($debutMois));

        $achats = $this->achatsFiltres($noms);

        $intrants = Intrant::query()->orderBy('name')->get();
        $total = 0.0;
        foreach ($this->lignes as $l) {
            $qte = is_numeric(str_replace(',', '.', $l['qte'])) ? (float) str_replace(',', '.', $l['qte']) : 0;
            $pu = is_numeric(str_replace(',', '.', $l['pu'])) ? (float) str_replace(',', '.', $l['pu']) : 0;
            $total += $qte * $pu;
        }

        return view('livewire.achats', [
            'achats' => $achats,
            'noms' => $noms,
            'statuts' => AchatsTable::STATUTS,
            'enCours' => $enCours->count(),
            'engage' => $enCours->sum('total'),
            'achatsDuMois' => $duMois->sum('total'),
            'maintenant' => $maintenant,
            'detail' => $this->ouvert ? Achat::query()->with('lignes')->find($this->ouvert) : null,
            'aucunAchat' => $tous->isEmpty(),
            'peutGerer' => (bool) Auth::user()?->can('manage-achats'),
            'fournisseurs' => Fournisseur::query()->whereNull('supprime_le')->orderBy('nom')->get(),
            'intrants' => $intrants,
            'intrantsParCode' => $intrants->keyBy('code'),
            'modes' => GestionAchats::MODES,
            'totalPanier' => round($total, 2),
            'confirmationReception' => $this->aReceptionner ? Achat::query()->find($this->aReceptionner) : null,
            'confirmationAnnulation' => $this->aAnnuler ? Achat::query()->find($this->aAnnuler) : null,
            'reglement' => $this->reglementEnCours(),
        ])->title('Achats & Commandes');
    }
}
