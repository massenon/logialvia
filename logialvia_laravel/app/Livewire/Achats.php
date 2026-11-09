<?php

namespace App\Livewire;

use App\Models\Achat;
use App\Models\Fournisseur;
use App\Sync\Tables\AchatsTable;
use Carbon\CarbonImmutable;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Achats & Commandes (Dart : `AchatsScreen`, `achats_fournisseurs_screens.dart`).
 *
 * LECTURE SEULE au web. La commande (panier), la reception (entree de stock, PMP) et le
 * reglement d'une dette appartiennent au poste : le stock et le PMP lui sont propres et
 * l'achat y est modifie. Ici : KPI, liste (statut, total, paye, solde du, anciennete) et
 * detail des lignes. Aucune ecriture, donc aucun droit `manage-achats` a verifier.
 */
#[Layout('components.layouts.app')]
class Achats extends Component
{
    public const ANCIENNETE_JOURS = 10;

    /** Meme plafond que le poste (`chargerAchats(limite: 200)`). */
    public const LIMITE = 200;

    public string $recherche = '';

    public string $statut = '';

    /** Achat dont le detail des lignes est deplie. */
    public ?string $ouvert = null;

    public function basculer(string $id): void
    {
        $this->ouvert = $this->ouvert === $id ? null : $id;
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

        $achats = Achat::query()
            ->when(in_array($this->statut, AchatsTable::STATUTS, true), fn ($q) => $q->where('statut', $this->statut))
            ->when($terme !== '', function ($q) use ($terme, $noms) {
                $ids = $noms->filter(fn (string $nom) => mb_stripos($nom, $terme) !== false)->keys();
                $q->where(fn ($w) => $w->where('reference', 'like', "%$terme%")->orWhereIn('fournisseur_id', $ids));
            })
            ->orderByDesc('date_achat')->orderByDesc('reference')
            ->limit(self::LIMITE)
            ->get();

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
        ])->title('Achats & Commandes');
    }
}
