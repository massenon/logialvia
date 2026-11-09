<?php

namespace App\Http\Controllers;

use App\Models\ParametresEntreprise;
use App\Models\Vente;
use Carbon\CarbonImmutable;

/**
 * Vues IMPRIMABLES du commerce (Dart : `documents_commercial.dart`) : facture de vente, historique des ventes,
 * suivi des soldes clients, lettre de relance. Le navigateur imprime ou enregistre en PDF
 * (`@media print` + bouton « Imprimer / PDF ») ; aucun fichier n'est genere par le serveur.
 *
 * Droits (poses sur les routes, `routes/ecrans/ventes-impressions.php`) : la facture et la lettre se lisent avec
 * `view-ventes` ; les TABLEAUX (historique, creances) exigent `export-ventes`, comme leur export XLSX.
 */
class ImpressionsCommerce extends Controller
{
    private function entreprise(): ParametresEntreprise
    {
        return ParametresEntreprise::courant();
    }

    /** Facture d'une vente (`DocumentsCommercial.facture`). */
    public function facture(string $vente)
    {
        $v = Vente::query()->with(['lignes' => fn ($q) => $q->orderBy('name')])->findOrFail($vente);

        return view('impression.facture-vente', ['vente' => $v, 'entreprise' => $this->entreprise(), 'fuseau' => config('logialvia.fuseau')]);
    }

    /** Historique des ventes, filtre comme a l'ecran (`recherche`, `statut`). Les annulees sont exclues des totaux. */
    public function historique()
    {
        $statuts = ['Payée', 'Avance', 'Annulée'];
        $statut = request()->query('statut', '');
        $terme = trim((string) request()->query('recherche', ''));
        $echappe = addcslashes($terme, '%_\\');

        $ventes = Vente::query()
            ->when(in_array($statut, $statuts, true), fn ($q) => $q->where('status', $statut))
            ->when($terme !== '', fn ($q) => $q->where(fn ($w) => $w
                ->whereRaw("reference like ? escape '\\'", ["%$echappe%"])
                ->orWhereRaw("client like ? escape '\\'", ["%$echappe%"])))
            ->orderByDesc('date_vente')->orderBy('reference')->get();

        $valides = $ventes->where('status', '!=', 'Annulée');
        $chiffreAffaires = (float) $valides->sum('total');
        $encaisse = (float) $valides->sum('paye');

        return view('impression.historique-ventes', [
            'ventes' => $ventes, 'entreprise' => $this->entreprise(), 'fuseau' => config('logialvia.fuseau'),
            'chiffreAffaires' => $chiffreAffaires, 'encaisse' => $encaisse,
            'filtre' => trim(($statut !== '' ? "statut « $statut »" : '').($terme !== '' ? ' recherche « '.$terme.' »' : '')),
        ]);
    }

    /** Suivi des soldes clients (`DocumentsCommercial.creancesClients`). */
    public function creances()
    {
        $creances = Vente::query()->where('status', 'Avance')->whereColumn('total', '>', 'paye')->orderBy('date_vente')->get();
        $maintenant = CarbonImmutable::now(config('logialvia.fuseau'));

        return view('impression.creances-clients', [
            'creances' => $creances, 'entreprise' => $this->entreprise(), 'fuseau' => config('logialvia.fuseau'),
            'maintenant' => $maintenant, 'solde' => (float) $creances->sum(fn (Vente $v) => $v->total - $v->paye),
        ]);
    }

    /**
     * Lettre de relance (`DocumentsCommercial.lettreRelance`) : sans echeance convenue, on ne peut pas ecrire
     * « reste impayee » — rien ne dit que le paiement etait du : c'est alors un « Rappel de Solde ».
     */
    public function relance(string $vente)
    {
        $v = Vente::query()->where('status', 'Avance')->whereColumn('total', '>', 'paye')->findOrFail($vente);

        return view('impression.lettre-relance', [
            'vente' => $v, 'entreprise' => $this->entreprise(), 'fuseau' => config('logialvia.fuseau'),
            'solde' => $v->total - $v->paye, 'aujourdhui' => CarbonImmutable::now(config('logialvia.fuseau')),
        ]);
    }
}
