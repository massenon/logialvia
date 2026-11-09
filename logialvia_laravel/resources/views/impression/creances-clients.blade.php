@php($fcfa = fn ($n) => number_format($n, 0, ',', ' '))
<x-layouts.impression titre="Suivi des Soldes Clients" :entreprise="$entreprise" :paysage="true">
    <div class="indicateurs">
        <div><span>Créances ouvertes</span><strong>{{ $creances->count() }}</strong></div>
        <div><span>Solde Total Restant Dû</span><strong>{{ $fcfa($solde) }} FCFA</strong></div>
    </div>
    <table data-table="creances-impression">
        <thead><tr><th>Client</th><th>Référence</th><th>Date</th><th>Échéance</th><th class="droite">Total</th><th class="droite">Payé</th><th class="droite">Reste Dû</th><th class="centre">Ancienneté</th></tr></thead>
        <tbody>
            @forelse ($creances as $v)
                @php($jours = (int) $v->date_vente->diffInDays($maintenant, true))
                <tr data-creance="{{ $v->reference }}">
                    <td>{{ $v->client }}</td><td>{{ $v->reference }}</td><td>{{ $v->date_vente->timezone($fuseau)->format('d/m/Y') }}</td>
                    <td>{{ $v->echeance?->timezone($fuseau)->format('d/m/Y') ?? '—' }}</td>
                    <td class="droite">{{ $fcfa($v->total) }}</td><td class="droite">{{ $fcfa($v->paye) }}</td>
                    <td class="droite">{{ $fcfa($v->total - $v->paye) }}</td><td class="centre">{{ $jours }} j</td>
                </tr>
            @empty
                <tr><td colspan="8">Aucune créance en cours : toutes les ventes sont intégralement réglées.</td></tr>
            @endforelse
        </tbody>
        <tfoot><tr><td colspan="6">TOTAL ({{ $creances->count() }})</td><td class="droite">{{ $fcfa($solde) }}</td><td></td></tr></tfoot>
    </table>
</x-layouts.impression>
