<?php

namespace App\Livewire;

use App\Models\Achat;
use App\Models\Fournisseur;
use App\Sync\Tables\FournisseursTable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Fournisseurs (Dart : `FournisseursScreen`, `achats_fournisseurs_screens.dart`).
 *
 * Les fournisseurs sont des FAITS (dernier ecrivain gagne). Le web ecrit par
 * `FournisseursTable::absorber` : meme validation, meme regle qu'un poste. Les agregats
 * (commandes, total achats, solde du) sont RECALCULES depuis les achats, jamais stockes.
 * Le reglement d'une dette reste au poste (il modifie l'achat).
 */
#[Layout('components.layouts.app')]
class Fournisseurs extends Component
{
    public const ANCIENNETE_JOURS = 10;

    public string $recherche = '';

    public bool $formulaire = false;

    public ?string $fournisseurId = null;

    public string $nom = '';

    public string $telephone = '';

    public string $adresse = '';

    public string $fournit = '';

    public ?string $erreur = null;

    public ?string $message = null;

    public ?string $aSupprimer = null;

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-achats'), 403);
    }

    public function nouveau(): void
    {
        $this->verifierDroitDeGerer();
        $this->reset(['fournisseurId', 'nom', 'telephone', 'adresse', 'fournit', 'erreur', 'message']);
        $this->formulaire = true;
    }

    public function modifier(string $id): void
    {
        $this->verifierDroitDeGerer();
        $f = Fournisseur::query()->whereNull('supprime_le')->find($id);
        if ($f === null) {
            return;
        }

        $this->reset(['erreur', 'message']);
        $this->fournisseurId = $f->id;
        $this->nom = $f->nom;
        $this->telephone = (string) $f->telephone;
        $this->adresse = (string) $f->adresse;
        $this->fournit = (string) $f->fournit;
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

        if ($this->fournisseurId !== null && ! Fournisseur::query()->whereNull('supprime_le')->whereKey($this->fournisseurId)->exists()) {
            $this->erreur = 'Ce fournisseur n\'existe plus.';

            return;
        }

        $nom = trim($this->nom);
        if ($nom !== '' && $this->nomDejaPris($nom)) {
            $this->erreur = 'Un fournisseur porte déjà ce nom.';

            return;
        }

        $motif = $this->ecrire([
            'id' => $this->fournisseurId ?? (string) Str::uuid(),
            'nom' => $nom,
            'telephone' => $this->nullSiVide($this->telephone),
            'adresse' => $this->nullSiVide($this->adresse),
            'fournit' => $this->nullSiVide($this->fournit),
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = $this->fournisseurId === null ? 'Fournisseur enregistré.' : 'Fournisseur modifié.';
        $this->formulaire = false;
        $this->erreur = null;
    }

    public function demanderSuppression(string $id): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->erreur = null;
        $this->aSupprimer = null;

        $f = Fournisseur::query()->whereNull('supprime_le')->find($id);
        if ($f === null) {
            return;
        }
        if ($this->aUneDette($f->id)) {
            $this->message = $this->motifDette($f);

            return;
        }
        $this->aSupprimer = $f->id;
    }

    public function confirmerSuppression(): void
    {
        $this->verifierDroitDeGerer();
        $f = $this->aSupprimer ? Fournisseur::query()->whereNull('supprime_le')->find($this->aSupprimer) : null;
        $this->aSupprimer = null;
        if ($f === null) {
            return;
        }
        if ($this->aUneDette($f->id)) {
            $this->message = $this->motifDette($f);

            return;
        }

        // Suppression DOUCE (`supprime_le`) : ses achats gardent leur fournisseur.
        $motif = $this->ecrire(['id' => $f->id, 'nom' => $f->nom, 'supprime_le' => $this->maintenant()]);
        $this->message = $motif ?? "Fournisseur « {$f->nom} » supprimé.";
    }

    private function motifDette(Fournisseur $f): string
    {
        return "Le fournisseur « {$f->nom} » a une dette ouverte : réglez-la sur le poste avant de le supprimer.";
    }

    private function nullSiVide(string $valeur): ?string
    {
        return trim($valeur) === '' ? null : trim($valeur);
    }

    /** Meme nom (sans casse) qu'un AUTRE fournisseur non supprime (Dart : `creerFournisseur`). */
    private function nomDejaPris(string $nom): bool
    {
        $cle = mb_strtolower($nom);

        return Fournisseur::query()->whereNull('supprime_le')
            ->when($this->fournisseurId !== null, fn ($q) => $q->where('id', '!=', $this->fournisseurId))
            ->pluck('nom')
            ->contains(fn (string $autre) => mb_strtolower(trim($autre)) === $cle);
    }

    private function maintenant(): string
    {
        return CarbonImmutable::now('UTC')->format('Y-m-d\TH:i:s.u\Z');
    }

    private function ecrire(array $ligne): ?string
    {
        return (new FournisseursTable)->absorber(Catalogue::POSTE_WEB, $ligne + ['updated_at' => $this->maintenant()]);
    }

    /** Achats non annules (les seuls comptes par le Dart). */
    private function achatsActifs(): Collection
    {
        return Achat::query()->where('statut', '!=', 'Annulé')->orderByDesc('date_achat')->get();
    }

    private function aUneDette(string $fournisseurId): bool
    {
        return $this->achatsActifs()->where('fournisseur_id', $fournisseurId)
            ->sum(fn (Achat $a) => $a->total - $a->paye) > 0;
    }

    public function render()
    {
        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));
        $debutMois = $maintenant->startOfMonth();
        $terme = trim($this->recherche);

        $tous = Fournisseur::query()->whereNull('supprime_le')->orderBy('nom')->get();
        $achats = $this->achatsActifs();

        $agregats = $tous->mapWithKeys(function (Fournisseur $f) use ($achats) {
            $siens = $achats->where('fournisseur_id', $f->id);

            return [$f->id => [
                'commandes' => $siens->count(),
                'total' => (float) $siens->sum('total'),
                'solde' => (float) $siens->sum(fn (Achat $a) => $a->total - $a->paye),
            ]];
        });

        $fournisseurs = $terme === '' ? $tous : $tous->filter(function (Fournisseur $f) use ($terme) {
            foreach ([$f->nom, $f->telephone, $f->fournit] as $champ) {
                if ($champ !== null && mb_stripos($champ, $terme) !== false) {
                    return true;
                }
            }

            return false;
        })->values();

        $duMois = $achats->filter(fn (Achat $a) => $a->date_achat->greaterThanOrEqualTo($debutMois));
        $noms = $tous->pluck('nom', 'id');
        $dettes = $achats->filter(fn (Achat $a) => $noms->has($a->fournisseur_id) && ($a->total - $a->paye) > 0)->values();

        return view('livewire.fournisseurs', [
            'fournisseurs' => $fournisseurs,
            'agregats' => $agregats,
            'nombre' => $tous->count(),
            'detteTotale' => $agregats->sum('solde'),
            'achatsDuMois' => $duMois->sum('total'),
            'dettesSoldeesMois' => $duMois->filter(fn (Achat $a) => $a->total > 0 && ($a->total - $a->paye) <= 0)->count(),
            'dettes' => $dettes,
            'noms' => $noms,
            'maintenant' => $maintenant,
            'peutGerer' => Auth::user()?->can('manage-achats') ?? false,
            'aConfirmer' => $this->aSupprimer ? Fournisseur::query()->find($this->aSupprimer) : null,
        ])->title('Fournisseurs');
    }
}
