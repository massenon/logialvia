@php
    $nombre = fn ($v) => number_format($v, 0, ',', ' ');
    $fuseau = config('logialvia.fuseau');
@endphp
<x-impressions.mise-en-page titre="Fournisseurs & Dettes" orientation="landscape">
    <table style="margin-bottom:12px"><tr>
        <td style="border:0"><span style="font-size:10px;text-transform:uppercase">Fournisseurs actifs</span><br><strong data-kpi="actifs">{{ $fournisseurs->count() }}</strong></td>
        <td style="border:0"><span style="font-size:10px;text-transform:uppercase">Dette totale</span><br><strong data-kpi="dette">{{ $nombre($detteTotale) }} FCFA</strong></td>
    </tr></table>

    <h2 style="font-weight:700;margin:8px 0">Fournisseurs</h2>
    <table data-table="fournisseurs">
        <thead><tr><th>Nom</th><th>Téléphone</th><th>Adresse</th><th>Fournit</th><th class="droite">Solde dû</th></tr></thead>
        <tbody>
            @forelse ($fournisseurs as $f)
                @php($solde = $agregats[$f->id]['solde'])
                <tr data-fournisseur="{{ $f->nom }}">
                    <td><strong>{{ $f->nom }}</strong></td><td>{{ $f->telephone ?: '—' }}</td><td>{{ $f->adresse ?: '—' }}</td><td>{{ $f->fournit ?: '—' }}</td>
                    <td class="droite">{{ $solde > 0.01 ? $nombre($solde) : '—' }}</td>
                </tr>
            @empty
                <tr><td colspan="5" class="centre">Aucun fournisseur enregistré.</td></tr>
            @endforelse
        </tbody>
        @if ($fournisseurs->isNotEmpty())
            <tfoot><tr><td colspan="4">TOTAL ({{ $fournisseurs->count() }})</td><td class="droite">{{ $nombre($detteTotale) }}</td></tr></tfoot>
        @endif
    </table>

    <h2 style="font-weight:700;margin:16px 0 8px">Dettes en cours</h2>
    <table data-table="dettes">
        <thead><tr><th>Référence</th><th>Fournisseur</th><th>Date</th><th>Échéance</th><th class="droite">Total</th><th class="droite">Réglé</th><th class="droite">Reste dû</th><th class="centre">Ancienneté</th></tr></thead>
        <tbody>
            @forelse ($dettes as $d)
                <tr data-dette="{{ $d->reference }}">
                    <td>{{ $d->reference }}</td><td>{{ $noms[$d->fournisseur_id] }}</td>
                    <td>{{ $d->date_achat->timezone($fuseau)->format('d/m/Y') }}</td>
                    <td>{{ $d->echeance ? $d->echeance->timezone($fuseau)->format('d/m/Y') : '—' }}</td>
                    <td class="droite">{{ $nombre($d->total) }}</td><td class="droite">{{ $nombre($d->paye) }}</td>
                    <td class="droite">{{ $nombre($d->total - $d->paye) }}</td>
                    <td class="centre">{{ max(0, (int) $d->date_achat->diffInDays($maintenant, true)) }} j</td>
                </tr>
            @empty
                <tr><td colspan="8" class="centre">Aucune dette ouverte.</td></tr>
            @endforelse
        </tbody>
    </table>
</x-impressions.mise-en-page>
