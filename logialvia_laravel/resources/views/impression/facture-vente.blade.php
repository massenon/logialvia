@php($fcfa = fn ($n) => number_format($n, 0, ',', ' '))
<x-layouts.impression :titre="'Facture de Vente — '.$vente->reference" :entreprise="$entreprise">
    <div class="indicateurs">
        <div><span>Référence</span><strong>{{ $vente->reference }}</strong></div>
        <div><span>Date</span><strong>{{ $vente->date_vente->timezone($fuseau)->format('d/m/Y') }}</strong></div>
        <div><span>Mode de règlement</span><strong>{{ $vente->mode }}</strong></div>
        <div><span>Total</span><strong>{{ $fcfa($vente->total) }} FCFA</strong></div>
    </div>
    <p>Client : <strong>{{ $vente->client }}</strong></p>
    @if ($vente->status === 'Annulée')
        <p class="alerte" data-annulee>VENTE ANNULÉE — {{ $vente->motif_annulation ?? 'motif non précisé' }}. Ce document ne vaut pas justificatif de vente.</p>
    @endif
    <table data-table="facture">
        <thead><tr><th>Article</th><th class="centre">Quantité</th><th class="droite">Prix Unitaire</th><th class="droite">Montant</th></tr></thead>
        <tbody>
            @foreach ($vente->lignes as $l)
                <tr><td>{{ $l->name }}</td><td class="centre">{{ $fcfa($l->qte) }}</td><td class="droite">{{ $fcfa($l->pu) }}</td><td class="droite">{{ $fcfa($l->qte * $l->pu) }}</td></tr>
            @endforeach
            @if ($vente->livraison_mode === 'facturee' && $vente->livraison_frais > 0)
                <tr data-frais-livraison><td colspan="3">Frais de livraison</td><td class="droite">{{ $fcfa($vente->livraison_frais) }}</td></tr>
            @endif
        </tbody>
        <tfoot><tr><td colspan="3">TOTAL</td><td class="droite">{{ $fcfa($vente->total) }} FCFA</td></tr></tfoot>
    </table>
    <p class="note" data-reglement>
        @if ($vente->status !== 'Annulée' && $vente->total - $vente->paye > 0)
            Réglé : {{ $fcfa($vente->paye) }} FCFA — Reste dû : {{ $fcfa($vente->total - $vente->paye) }} FCFA.
        @elseif ($vente->status !== 'Annulée')
            Vente intégralement réglée.
        @endif
    </p>
</x-layouts.impression>
