@php($fcfa = fn ($n) => number_format($n, 0, ',', ' ').' FCFA')
<x-layouts.impression :titre="($vente->echeance === null ? 'Rappel de Solde — ' : 'Lettre de Relance — ').$vente->client" :entreprise="$entreprise">
    <p>Madame, Monsieur {{ $vente->client }},</p>
    @if ($vente->echeance === null)
        {{-- Aucun delai convenu : le solde est du, mais il n'est pas EN RETARD. --}}
        <p data-corps="rappel">Sauf erreur ou omission de notre part, la facture {{ $vente->reference }} présente un solde de {{ $fcfa($solde) }} restant à régler.</p>
    @else
        <p data-corps="relance">Sauf erreur ou omission de notre part, nous constatons que la facture {{ $vente->reference }}, payable le {{ $vente->echeance->timezone($fuseau)->format('d/m/Y') }}, reste impayée à ce jour pour un montant de {{ $fcfa($solde) }}.</p>
    @endif
    <p>Nous vous remercions de bien vouloir procéder au règlement de ce solde dans les meilleurs délais, ou de nous contacter si un arrangement est nécessaire.</p>
    <p>Dans l'attente de votre règlement, nous vous prions d'agréer, Madame, Monsieur, l'expression de nos salutations distinguées.</p>
    <p class="note">Fait le {{ $aujourdhui->format('d/m/Y') }}.</p>
    <div class="signatures"><div>La Gérante</div><div>Le Client</div></div>
</x-layouts.impression>
