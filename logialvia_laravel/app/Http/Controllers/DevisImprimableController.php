<?php

namespace App\Http\Controllers;

use App\Models\Devis;
use App\Models\ParametresEntreprise;
use Illuminate\Contracts\View\View;

/**
 * Vue IMPRIMABLE d'un devis de prestations (`47a2_`), rangee en PDF par « Imprimer » du navigateur (CSS `@media print`).
 * Un devis n'est pas une facture : le document le dit (« Devis — sans valeur de facture »). Un devis supprime
 * (pierre tombale) n'existe plus : 404. Droit : `view-ventes`.
 */
class DevisImprimableController extends Controller
{
    public function __invoke(string $devis): View
    {
        $devis = Devis::query()->whereNull('supprime_le')->findOrFail($devis);

        return view('devis.imprimable', [
            'devis' => $devis,
            'entreprise' => ParametresEntreprise::courant(),
            'fuseau' => config('logialvia.fuseau'),
            'expire' => $devis->statut === 'emis' && now()->greaterThan($devis->dateExpiration()),
        ]);
    }
}
