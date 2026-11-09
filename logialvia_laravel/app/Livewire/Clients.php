<?php

namespace App\Livewire;

use App\Models\Client;
use App\Models\Vente;
use App\Services\Commerce\VentesWeb;
use App\Support\ExportXlsx;
use App\Sync\Tables\ClientsTable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Clients et Creances (Dart : `clients_screen.dart`).
 *
 * Les clients sont des FAITS (dernier ecrivain gagne). Le web ecrit par `ClientsTable::absorber`
 * — la meme validation et la meme regle que pour un poste. `solde_creance` est DERIVE des
 * ventes : jamais saisi ici. Le recouvrement d'une creance (`VentesWeb::recouvrer`) modifie la vente
 * par `VentesTable::absorber` (le solde est recalcule par le serveur) et passe l'ecriture 411 / tresorerie.
 */
#[Layout('components.layouts.app')]
class Clients extends Component
{
    public const ANCIENNETE_JOURS = 10;

    public const HORIZON_CRM_JOURS = 7;

    public string $recherche = '';

    public bool $formulaire = false;

    public ?string $clientId = null;

    public string $nom = '';

    public string $telephone = '';

    public string $dateNaissance = '';

    public ?string $erreur = null;

    public ?string $message = null;

    public ?string $aSupprimer = null;

    public ?string $recouvrementId = null;

    public string $recMontant = '';

    public string $recMode = 'Espèces';

    public ?string $erreurRecouvrement = null;

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-ventes'), 403);
    }

    public function nouveau(): void
    {
        $this->verifierDroitDeGerer();
        $this->reset(['clientId', 'nom', 'telephone', 'dateNaissance', 'erreur', 'message']);
        $this->formulaire = true;
    }

    public function modifier(string $id): void
    {
        $this->verifierDroitDeGerer();
        $client = Client::query()->whereNull('supprime_le')->find($id);
        if ($client === null) {
            return;
        }

        $this->reset(['erreur', 'message']);
        $this->clientId = $client->id;
        $this->nom = $client->nom;
        $this->telephone = (string) $client->telephone;
        $this->dateNaissance = $client->date_naissance?->format('Y-m-d') ?? '';
        $this->formulaire = true;
    }

    public function annuler(): void
    {
        $this->formulaire = false;
        $this->aSupprimer = null;
        $this->erreur = null;
    }

    public function enregistrer(): void
    {
        $this->verifierDroitDeGerer();

        if ($this->clientId !== null && ! Client::query()->whereNull('supprime_le')->whereKey($this->clientId)->exists()) {
            $this->erreur = 'Ce client n\'existe plus.';

            return;
        }

        $motif = $this->ecrire([
            'id' => $this->clientId ?? (string) Str::uuid(),
            'nom' => trim($this->nom),
            'telephone' => trim($this->telephone) === '' ? null : trim($this->telephone),
            'date_naissance' => $this->dateNaissance === '' ? null : $this->dateNaissance,
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = $this->clientId === null ? 'Client enregistré.' : 'Client modifié.';
        $this->formulaire = false;
        $this->erreur = null;
    }

    public function demanderSuppression(string $id): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->aSupprimer = Client::query()->whereNull('supprime_le')->whereKey($id)->exists() ? $id : null;
    }

    public function confirmerSuppression(): void
    {
        $this->verifierDroitDeGerer();
        $client = $this->aSupprimer ? Client::query()->whereNull('supprime_le')->find($this->aSupprimer) : null;
        $this->aSupprimer = null;
        if ($client === null) {
            return;
        }

        // Suppression DOUCE (`supprime_le`) : ses ventes gardent leur client.
        $motif = $this->ecrire(['id' => $client->id, 'nom' => $client->nom, 'supprime_le' => $this->maintenant()]);
        $this->message = $motif ?? "Client « {$client->nom} » supprimé.";
    }

    public function demanderRecouvrement(string $venteId): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->erreurRecouvrement = null;
        $vente = $this->creances()->firstWhere('id', $venteId);
        $this->recouvrementId = $vente?->id;
        $this->recMontant = '';
        $this->recMode = $vente !== null && in_array($vente->mode, VentesWeb::MODES, true) ? $vente->mode : 'Espèces';
    }

    public function fermerRecouvrement(): void
    {
        $this->recouvrementId = null;
        $this->erreurRecouvrement = null;
    }

    public function enregistrerRecouvrement(): void
    {
        $this->verifierDroitDeGerer();
        $id = $this->recouvrementId;
        if ($id === null) {
            return;
        }
        $texte = str_replace([' ', "\u{00A0}", "\u{202F}", ','], ['', '', '', '.'], trim($this->recMontant));
        $montant = $texte !== '' && is_numeric($texte) ? (float) $texte : 0.0;

        $motif = (new VentesWeb(Auth::user()))->recouvrer($id, $montant, $this->recMode);
        if ($motif !== null) {
            $this->erreurRecouvrement = $motif;

            return;
        }
        $reference = Vente::query()->whereKey($id)->value('reference');
        $this->message = "Paiement enregistré sur la vente $reference.";
        $this->recouvrementId = null;
        $this->erreurRecouvrement = null;
    }

    /** Export XLSX des creances ouvertes : memes colonnes que l'ecran. Droit `export-ventes`. */
    public function exporterCreances(): StreamedResponse
    {
        abort_unless(Auth::user()?->can('export-ventes'), 403);
        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));
        $fuseau = config('logialvia.fuseau');
        $lignes = [['Client', 'Référence Vente', 'Date', 'Échéance', 'Montant Total', 'Déjà Réglé', 'Solde Restant Dû', 'Ancienneté (jours)']];
        foreach ($this->creances() as $v) {
            $lignes[] = [
                $v->client, $v->reference, $v->date_vente->timezone($fuseau)->format('d/m/Y'),
                $v->echeance?->timezone($fuseau)->format('d/m/Y') ?? '—',
                (int) round($v->total), (int) round($v->paye), (int) round($v->total - $v->paye),
                (int) $v->date_vente->diffInDays($maintenant, true),
            ];
        }

        return ExportXlsx::telecharger(array_map(fn ($l) => array_map(ExportXlsx::typer(...), $l), $lignes), 'creances-clients.xlsx', 'Créances');
    }

    private function maintenant(): string
    {
        return CarbonImmutable::now('UTC')->format('Y-m-d\TH:i:s.u\Z');
    }

    private function ecrire(array $ligne): ?string
    {
        return (new ClientsTable)->absorber(Catalogue::POSTE_WEB, $ligne + ['updated_at' => $this->maintenant()]);
    }

    /** Ventes en avance dont il reste a payer (creances ouvertes). */
    private function creances()
    {
        return Vente::query()->where('status', 'Avance')->whereColumn('total', '>', 'paye')
            ->orderBy('date_vente')->get();
    }

    public function render()
    {
        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));
        $terme = trim($this->recherche);

        $clients = Client::query()->whereNull('supprime_le')
            ->when($terme !== '', fn ($q) => $q->where(fn ($w) => $w->where('nom', 'like', "%$terme%")->orWhere('telephone', 'like', "%$terme%")))
            ->orderBy('nom')->get();
        $tous = Client::query()->whereNull('supprime_le')->get();

        $creances = $this->creances();
        $evenements = $tous->filter(fn (Client $c) => $c->date_naissance !== null)
            ->map(function (Client $c) use ($maintenant) {
                $prochain = $maintenant->startOfDay()->setDate($maintenant->year, $c->date_naissance->month, $c->date_naissance->day);
                if ($prochain->lessThan($maintenant->startOfDay())) {
                    $prochain = $prochain->addYear();
                }

                return ['client' => $c, 'date' => $prochain];
            })
            ->filter(fn (array $e) => $e['date']->lessThanOrEqualTo($maintenant->startOfDay()->addDays(self::HORIZON_CRM_JOURS)))
            ->sortBy(fn (array $e) => $e['date'])->values();

        return view('livewire.clients', [
            'clients' => $clients,
            'nombre' => $tous->count(),
            'soldeTotal' => $tous->sum('solde_creance'),
            'creances' => $creances,
            'anciens' => $creances->filter(fn (Vente $v) => $v->date_vente->diffInDays($maintenant, true) > self::ANCIENNETE_JOURS)->count(),
            'evenements' => $evenements,
            'maintenant' => $maintenant,
            'peutGerer' => Auth::user()?->can('manage-ventes') ?? false,
            'peutExporter' => Auth::user()?->can('export-ventes') ?? false,
            'aRecouvrer' => $this->recouvrementId ? $this->creances()->firstWhere('id', $this->recouvrementId) : null,
            'modes' => VentesWeb::MODES,
            'aConfirmer' => $this->aSupprimer ? Client::query()->find($this->aSupprimer) : null,
        ])->title('Clients et Créances');
    }
}
