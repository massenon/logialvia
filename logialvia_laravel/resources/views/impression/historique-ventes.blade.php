@php($fcfa = fn ($n) => number_format($n, 0, ',', ' '))
<x-layouts.impression titre="Historique des Ventes" :entreprise="$entreprise" :paysage="true">
    @if ($filtre !== '')<p class="note" data-filtre>Filtre : {{ $filtre }}</p>@endif
    <div class="indicateurs">
        <div><span>Ventes</span><strong>{{ $ventes->count() }}</strong></div>
        <div><span>Chiffre d'Affaires</span><strong>{{ $fcfa($chiffreAffaires) }} FCFA</strong></div>
        <div><span>Encaissé</span><strong>{{ $fcfa($encaisse) }} FCFA</strong></div>
        <div><span>Reste Dû</span><strong>{{ $fcfa($chiffreAffaires - $encaisse) }} FCFA</strong></div>
    </div>
    <table data-table="historique-impression">
        <thead><tr><th>Référence</th><th>Date</th><th>Client</th><th>Mode</th><th class="droite">Total</th><th class="droite">Payé</th><th class="droite">Reste Dû</th><th class="centre">Statut</th></tr></thead>
        <tbody>
            @forelse ($ventes as $v)
                <tr data-vente="{{ $v->reference }}">
                    <td>{{ $v->reference }}</td><td>{{ $v->date_vente->timezone($fuseau)->format('d/m/Y') }}</td><td>{{ $v->client }}</td><td>{{ $v->mode }}</td>
                    <td class="droite">{{ $fcfa($v->total) }}</td><td class="droite">{{ $fcfa($v->paye) }}</td>
                    <td class="droite">{{ $v->status !== 'Annulée' && $v->total - $v->paye > 0 ? $fcfa($v->total - $v->paye) : '—' }}</td>
                    <td class="centre">{{ $v->status }}</td>
                </tr>
            @empty
                <tr><td colspan="8">Aucune vente enregistrée.</td></tr>
            @endforelse
        </tbody>
        <tfoot><tr><td colspan="4">TOTAUX ({{ $ventes->count() }})</td><td class="droite">{{ $fcfa($chiffreAffaires) }}</td><td class="droite">{{ $fcfa($encaisse) }}</td><td class="droite">{{ $fcfa($chiffreAffaires - $encaisse) }}</td><td></td></tr></tfoot>
    </table>
    <p class="note">Les ventes annulées figurent dans l'historique mais sont exclues des totaux : leur écriture a été contrepassée.</p>
</x-layouts.impression>
