<?php

namespace App\Http\Controllers;

use App\Livewire\Catalogue;
use App\Models\Facture;
use App\Models\ParametresEntreprise;
use App\Models\Poste;
use Illuminate\Contracts\View\View;

/**
 * Vue IMPRIMABLE d'une facture ou d'un avoir (`47a2_`) : reprend le document du poste
 * (`documents_mecef.dart`) et se range en PDF par « Imprimer » du navigateur (CSS `@media print`).
 *
 * Elle dit franchement l'etat de la piece : une facture normalisee porte le code, le NIM et le lien de verification
 * rendus par la DGI ; sinon le document porte la mention « FACTURE NON NORMALISEE » (jamais l'inverse). Aucun QR n'est
 * dessine : celui d'une facture normalisee encode le lien de verification de la DGI, en fabriquer un ici donnerait un carre
 * qui ne verifie rien. Droit : `view-facturation` et module `mecef` actif (route).
 */
class FactureImprimableController extends Controller
{
    public function __invoke(Facture $facture): View
    {
        $facture->load(['lignes' => fn ($q) => $q->orderBy('designation')->orderBy('id')]);

        $groupes = [];
        foreach ($facture->lignes as $l) {
            $groupes[$l->groupe_taxe] ??= ['groupe' => $l->groupe_taxe, 'taux' => $l->taux_taxe, 'base' => 0.0, 'taxe' => 0.0];
            $groupes[$l->groupe_taxe]['base'] += $l->montant_ht;
            $groupes[$l->groupe_taxe]['taxe'] += $l->montant_taxe;
        }
        ksort($groupes);

        $normalisee = $facture->statut === 'normalisee' && trim((string) $facture->code_mecef) !== '';

        return view('factures.imprimable', [
            'facture' => $facture,
            'signe' => $facture->type === 'FA' ? -1 : 1,
            'groupes' => array_values($groupes),
            'normalisee' => $normalisee,
            'entreprise' => ParametresEntreprise::courant(),
            'fuseau' => config('logialvia.fuseau'),
            'emetteur' => $facture->device_id === Catalogue::POSTE_WEB
                ? 'Web'
                : (Poste::query()->where('device_id', $facture->device_id)->value('code') ?: null),
        ]);
    }
}
