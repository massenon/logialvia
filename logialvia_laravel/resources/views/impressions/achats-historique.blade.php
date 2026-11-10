@php
    $nombre = fn ($v) => number_format($v, 0, ',', ' ');
    $fuseau = config('logialvia.fuseau');
@endphp
<x-impressions.mise-en-page titre="Achats & Commandes" orientation="landscape">
    <table style="margin-bottom:12px" data-bloc="indicateurs">
        <tr>
            <td style="border:0"><span style="font-size:10px;text-transform:uppercase">Commandes en cours</span><br><strong data-kpi="en-cours">{{ $enCours }}</strong></td>
            <td style="border:0"><span style="font-size:10px;text-transform:uppercase">Montant total engagé</span><br><strong data-kpi="engage">{{ $nombre($engage) }} FCFA</strong></td>
            <td style="border:0"><span style="font-size:10px;text-transform:uppercase">Achats cumulés (mois)</span><br><strong data-kpi="mois">{{ $nombre($achatsDuMois) }} FCFA</strong></td>
        </tr>
    </table>
    @if ($filtres !== '')<p style="font-size:11px;margin-bottom:6px" data-filtres>Filtres : {{ $filtres }}</p>@endif

    <table data-table="achats">
        <thead>
            <tr><th>Référence</th><th>Fournisseur</th><th>Date</th><th>Mode</th><th class="droite">Total</th><th class="droite">Réglé</th><th class="droite">Reste dû</th><th class="centre">Statut</th></tr>
        </thead>
        <tbody>
            @forelse ($achats as $a)
                @php($reste = $a->statut === 'Annulé' ? 0 : max(0, $a->total - $a->paye))
                <tr data-achat="{{ $a->reference }}">
                    <td>{{ $a->reference }}</td>
                    <td>{{ $noms[$a->fournisseur_id] ?? '—' }}</td>
                    <td>{{ $a->date_achat->timezone($fuseau)->format('d/m/Y') }}</td>
                    <td>{{ $a->mode ?: '—' }}</td>
                    <td class="droite">{{ $nombre($a->total) }}</td>
                    <td class="droite">{{ $nombre($a->paye) }}</td>
                    <td class="droite">{{ $reste > 0.01 ? $nombre($reste) : '—' }}</td>
                    <td class="centre">{{ $a->statut }}</td>
                </tr>
            @empty
                <tr><td colspan="8" class="centre">Aucune commande ne correspond aux filtres retenus.</td></tr>
            @endforelse
        </tbody>
        @if ($achats->isNotEmpty())
            <tfoot>
                {{-- Les achats annules sont listes mais ne comptent ni dans les totaux ni dans le reste du. --}}
                @php($actifs = $achats->where('statut', '!=', 'Annulé'))
                <tr data-totaux>
                    <td colspan="4">TOTAUX ({{ $achats->count() }} dont {{ $achats->count() - $actifs->count() }} annulée(s) non comptée(s))</td>
                    <td class="droite">{{ $nombre($actifs->sum('total')) }}</td>
                    <td class="droite">{{ $nombre($actifs->sum('paye')) }}</td>
                    <td class="droite">{{ $nombre($actifs->sum(fn ($a) => max(0, $a->total - $a->paye))) }}</td>
                    <td></td>
                </tr>
            </tfoot>
        @endif
    </table>
</x-impressions.mise-en-page>
