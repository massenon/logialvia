<?php

namespace App\Http\Controllers;

use App\Models\Achat;
use App\Models\Fournisseur;
use App\Models\Intrant;
use App\Models\MouvementIntrant;
use App\Models\PieceComptable;
use App\Models\Poste;
use App\Services\Comptabilite\Saisie;
use App\Sync\Tables\AchatsTable;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;

/**
 * Vues IMPRIMABLES de l'approvisionnement (equivalent des PDF du poste, `documents_appro.dart`) :
 * pages HTML en `@media print` avec un bouton « Imprimer / PDF ». Lecture seule : le droit de lecture
 * (`view-achats`, `view-stocks`) et le module actif sont poses sur la route.
 *
 * Ecart avec le poste : le bon de commande n'existe pas au poste (il n'imprime que les listes) ; le
 * releve fournisseur y est remplace par le tableau « Fournisseurs & Dettes ». Les achats annules sont
 * listes mais ne comptent dans aucun total (le PDF du poste les compterait).
 */
class ImpressionsAchats extends Controller
{
    public function bonDeCommande(Achat $achat)
    {
        return view('impressions.bon-de-commande', [
            'achat' => $achat->load('lignes'),
            'fournisseur' => Fournisseur::query()->find($achat->fournisseur_id),
        ]);
    }

    /** Historique des achats : memes filtres que l'ecran (statut, reference ou fournisseur). */
    public function historique(Request $requete)
    {
        $statut = (string) $requete->query('statut', '');
        $terme = trim((string) $requete->query('recherche', ''));
        $noms = Fournisseur::query()->pluck('nom', 'id');
        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));

        $tous = Achat::query()->get();
        $enCours = $tous->where('statut', 'Commandé');
        $duMois = $tous->filter(fn (Achat $a) => $a->statut !== 'Annulé' && $a->date_achat->greaterThanOrEqualTo($maintenant->startOfMonth()));

        $achats = Achat::query()
            ->when(in_array($statut, AchatsTable::STATUTS, true), fn ($q) => $q->where('statut', $statut))
            ->when($terme !== '', function ($q) use ($terme, $noms) {
                $ids = $noms->filter(fn (string $nom) => mb_stripos($nom, $terme) !== false)->keys();
                $q->where(fn ($w) => $w->where('reference', 'like', "%$terme%")->orWhereIn('fournisseur_id', $ids));
            })
            ->orderByDesc('date_achat')->orderByDesc('reference')
            ->limit(\App\Livewire\Achats::LIMITE)
            ->get();

        return view('impressions.achats-historique', [
            'achats' => $achats,
            'noms' => $noms,
            'enCours' => $enCours->count(),
            'engage' => $enCours->sum('total'),
            'achatsDuMois' => $duMois->sum('total'),
            'filtres' => collect([$statut !== '' ? "statut « $statut »" : null, $terme !== '' ? "recherche « $terme »" : null])->filter()->implode(', '),
        ]);
    }

    /** Releve d'un fournisseur : commandes, reglements enregistres, ancienneté, echeance, solde. */
    public function releve(Fournisseur $fournisseur)
    {
        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));
        $achats = Achat::query()->where('fournisseur_id', $fournisseur->id)->where('statut', '!=', 'Annulé')
            ->orderBy('date_achat')->orderBy('reference')->get();

        return view('impressions.releve-fournisseur', [
            'fournisseur' => $fournisseur,
            'achats' => $achats,
            'reglements' => $this->reglements($achats),
            'maintenant' => $maintenant,
        ]);
    }

    /** Fournisseurs & dettes : le tableau des fournisseurs puis les dettes en cours (PDF du poste). */
    public function fournisseurs()
    {
        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));
        $fournisseurs = Fournisseur::query()->whereNull('supprime_le')->orderBy('nom')->get();
        $achats = Achat::query()->where('statut', '!=', 'Annulé')->orderByDesc('date_achat')->get();
        $noms = $fournisseurs->pluck('nom', 'id');

        $agregats = $fournisseurs->mapWithKeys(function (Fournisseur $f) use ($achats) {
            $siens = $achats->where('fournisseur_id', $f->id);

            return [$f->id => ['solde' => (float) $siens->sum(fn (Achat $a) => $a->total - $a->paye), 'total' => (float) $siens->sum('total'), 'commandes' => $siens->count()]];
        });

        return view('impressions.fournisseurs-dettes', [
            'fournisseurs' => $fournisseurs,
            'agregats' => $agregats,
            'dettes' => $achats->filter(fn (Achat $a) => $noms->has($a->fournisseur_id) && ($a->total - $a->paye) > 0)->values(),
            'noms' => $noms,
            'maintenant' => $maintenant,
            'detteTotale' => $agregats->sum('solde'),
        ]);
    }

    /** Depenses de l'exercice courant (annulees exclues), memes filtres que l'ecran. */
    public function depenses(Request $requete)
    {
        $annee = \App\Services\Comptabilite\LivreComptable::exerciceChoisi(null);
        $toutes = \App\Services\Comptabilite\LivreComptable::toutes();
        $plan = \App\Services\Comptabilite\LivreComptable::plan();
        $statut = (string) $requete->query('statut', '');
        $terme = mb_strtolower(trim((string) $requete->query('recherche', '')));

        $depenses = array_values(array_filter(
            \App\Services\Comptabilite\MoteurComptable::depenses(\App\Services\Comptabilite\LivreComptable::exercice($toutes, $annee), $plan),
            function (array $d) use ($statut, $terme) {
                if (($statut === 'payee' && ! $d['payee']) || ($statut === 'attente' && $d['payee'])) {
                    return false;
                }

                return $terme === '' || str_contains(mb_strtolower($d['libelle']), $terme) || str_contains(mb_strtolower($d['libelle_compte']), $terme)
                    || str_contains($d['compte'], $terme) || str_contains(mb_strtolower($d['numero_piece']), $terme);
            },
        ));

        return view('impressions.depenses', ['depenses' => $depenses, 'annee' => $annee]);
    }

    /** Intrants et journal des mouvements (sans stock, PMP ni valeur : propres a chaque poste). */
    public function journalStocks()
    {
        $codes = Poste::query()->pluck('code', 'device_id')->all();
        $journal = MouvementIntrant::query()->orderByDesc('horodatage')->limit(\App\Livewire\GestionStocks::LIMITE_JOURNAL)->get()
            ->map(fn (MouvementIntrant $m) => ['mouvement' => $m, 'poste' => Saisie::libellePoste($m->device_id, $codes)]);

        return view('impressions.stocks-journal', [
            'intrants' => Intrant::query()->orderBy('name')->get(),
            'journal' => $journal,
        ]);
    }

    /**
     * Reglements enregistres (pieces `REG-<reference>` non annulees) des achats donnes.
     *
     * @return Collection<int, array{date: CarbonImmutable, numero: string, reference: string, montant: float, compte: string}>
     */
    private function reglements(Collection $achats): Collection
    {
        $references = $achats->pluck('reference')->all();
        $pieces = PieceComptable::query()->with('lignes')->whereIn('achat_ref', $references)->where('journal_code', 'CA')->get();
        $annulees = PieceComptable::query()->whereNotNull('contrepasse_de')->whereIn('achat_ref', $references)->pluck('contrepasse_de')->flip();

        return $pieces->filter(fn (PieceComptable $p) => $p->contrepasse_de === null && ! $annulees->has($p->id))
            ->map(function (PieceComptable $p) {
                $debit401 = $p->lignes->where('numero_compte', '401')->sum('debit');
                $tresorerie = $p->lignes->where('credit', '>', 0)->first();

                return [
                    'date' => CarbonImmutable::instance($p->date_ecriture)->timezone(config('logialvia.fuseau')),
                    'numero' => (string) $p->numero_piece,
                    'reference' => $p->achat_ref,
                    'montant' => (float) $debit401,
                    'compte' => $tresorerie?->numero_compte ?? '—',
                ];
            })->sortBy('date')->values();
    }
}
