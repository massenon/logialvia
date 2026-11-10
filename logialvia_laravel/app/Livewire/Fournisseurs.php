<?php

namespace App\Livewire;

use App\Support\PlanSyscohada;
use App\Livewire\Concerns\ReglementDette;
use App\Models\Achat;
use App\Models\EcritureComptable;
use App\Models\Fournisseur;
use App\Sync\Tables\FournisseursTable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;
use App\Support\ExportXlsx;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Fournisseurs (Dart : `FournisseursScreen`, `achats_fournisseurs_screens.dart`).
 *
 * Les fournisseurs sont des FAITS (dernier ecrivain gagne). Le web ecrit par
 * `FournisseursTable::absorber` : meme validation, meme regle qu'un poste. Les agregats
 * (commandes, total achats, solde du) sont RECALCULES depuis les achats, jamais stockes.
 *
 * PARITE avec le poste : « Régler » une dette (modale `_FormulaireReglement`, trait `ReglementDette` partage
 * avec Achats & Commandes) ; la suppression reste REFUSEE tant qu'une dette est ouverte (regle validee par le
 * client) ; releve d'un fournisseur et etat « Fournisseurs & Dettes » imprimables. Un controle de coherence
 * rapproche les dettes des achats du compte 401 des ecritures d'achat (visible de qui lit la comptabilite).
 */
#[Layout('components.layouts.app')]
class Fournisseurs extends Component
{
    use ReglementDette;

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
        return "Le fournisseur « {$f->nom} » a une dette ouverte : réglez-la avant de le supprimer.";
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

    /** Export XLSX : fournisseurs (solde du) puis dettes en cours. Droit de lecture verifie ICI. */
    public function exporter(): StreamedResponse
    {
        abort_unless(Auth::user()?->can('view-achats'), 403);
        $fuseau = config('logialvia.fuseau');
        $maintenant = CarbonImmutable::now($fuseau);
        $fournisseurs = Fournisseur::query()->whereNull('supprime_le')->orderBy('nom')->get();
        $achats = $this->achatsActifs();
        $noms = $fournisseurs->pluck('nom', 'id');

        $lignes = [['Fournisseurs & Dettes'], ['Nom', 'Téléphone', 'Adresse', 'Fournit', 'Commandes', 'Total achats', 'Solde dû']];
        foreach ($fournisseurs as $f) {
            $siens = $achats->where('fournisseur_id', $f->id);
            $lignes[] = [$f->nom, $f->telephone ?? '', $f->adresse ?? '', $f->fournit ?? '', $siens->count(),
                (float) $siens->sum('total'), (float) $siens->sum(fn (Achat $a) => $a->total - $a->paye)];
        }
        $lignes[] = [];
        $lignes[] = ['Dettes en cours'];
        $lignes[] = ['Fournisseur', 'Référence', 'Total', 'Réglé', 'Solde dû', 'Échéance', 'Ancienneté (jours)'];
        foreach ($achats->filter(fn (Achat $a) => $noms->has($a->fournisseur_id) && ($a->total - $a->paye) > 0) as $d) {
            $lignes[] = [$noms[$d->fournisseur_id], $d->reference, (float) $d->total, (float) $d->paye, round($d->total - $d->paye, 2),
                $d->echeance ? $d->echeance->timezone($fuseau)->format('d/m/Y') : '', max(0, (int) $d->date_achat->diffInDays($maintenant, true))];
        }

        return ExportXlsx::telecharger($lignes, 'fournisseurs-dettes.xlsx', 'Fournisseurs');
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
            'reglement' => $this->reglementEnCours(),
            'coherence' => $this->coherence($achats),
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

    /**
     * Coherence achats ↔ comptabilite : « le solde fournisseur = les dettes 401 ». Les dettes des achats
     * (total − paye, hors annules) sont comparees au solde crediteur du compte 401 sur les SEULES pieces
     * d'achat (`achat_ref`). Un ecart a deux causes connues : un achat anterieur a la comptabilite (sans
     * piece) ou une piece d'un poste pas encore synchronise. Le solde 401 de TOUTES les pieces est donne
     * a part : il compte aussi les depenses « a credit » saisies a la main, qui ne sont pas des achats.
     *
     * @return array{dettes: float, achats_401: float, ecart: float, grand_livre_401: float}|null
     */
    private function coherence(Collection $achats): ?array
    {
        if (! Auth::user()?->can('view-comptabilite')) {
            return null;
        }

        $r = EcritureComptable::query()
            ->join('pieces_comptables as p', 'p.id', '=', 'ecritures_comptables.piece_id')
            ->where('ecritures_comptables.numero_compte', PlanSyscohada::FOURNISSEURS)
            ->selectRaw('COALESCE(SUM(CASE WHEN p.achat_ref IS NOT NULL THEN ecritures_comptables.credit - ecritures_comptables.debit ELSE 0 END), 0) as achats_401')
            ->selectRaw('COALESCE(SUM(ecritures_comptables.credit - ecritures_comptables.debit), 0) as total_401')
            ->first();

        $dettes = round((float) $achats->sum(fn (Achat $a) => $a->total - $a->paye), 2);
        $achats401 = round((float) $r->achats_401, 2);

        return [
            'dettes' => $dettes,
            'achats_401' => $achats401,
            'ecart' => round($achats401 - $dettes, 2),
            'grand_livre_401' => round((float) $r->total_401, 2),
        ];
    }
}
