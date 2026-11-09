@php
    $nombre = fn ($v) => number_format($v, 0, ',', ' ');
    $fuseau = config('logialvia.fuseau');
    $solde = fn ($a) => max(0, $a->total - $a->paye);
    $totalSolde = $achats->sum(fn ($a) => max(0, $a->total - $a->paye));
@endphp
<x-impressions.mise-en-page titre="Relevé fournisseur — {{ $fournisseur->nom }}">
    <table style="margin-bottom:12px" data-bloc="fournisseur">
        <tr>
            <td style="border:0;vertical-align:top">
                <p style="font-weight:700;font-size:14px" data-fournisseur>{{ $fournisseur->nom }}</p>
                @if ($fournisseur->telephone)<p>{{ $fournisseur->telephone }}</p>@endif
                @if ($fournisseur->adresse)<p>{{ $fournisseur->adresse }}</p>@endif
                @if ($fournisseur->fournit)<p>Fournit : {{ $fournisseur->fournit }}</p>@endif
            </td>
            <td style="border:0;vertical-align:top" class="droite">
                <p style="font-size:11px;text-transform:uppercase">Solde dû à ce jour</p>
                <p style="font-size:18px;font-weight:700" data-solde-du>{{ $nombre($totalSolde) }} FCFA</p>
            </td>
        </tr>
    </table>

    <h2 style="font-weight:700;margin:8px 0">Commandes (hors annulées)</h2>
    <table data-table="commandes">
        <thead>
            <tr><th>Référence</th><th>Date</th><th>Statut</th><th class="droite">Total</th><th class="droite">Réglé</th><th class="droite">Reste dû</th><th>Échéance</th><th class="centre">Ancienneté</th></tr>
        </thead>
        <tbody>
            @forelse ($achats as $a)
                @php($jours = max(0, (int) $a->date_achat->diffInDays($maintenant, true)))
                @php($echue = $a->echeance && $solde($a) > 0 && $a->echeance->timezone($fuseau)->endOfDay()->lessThan($maintenant))
                <tr data-achat="{{ $a->reference }}">
                    <td>{{ $a->reference }}</td>
                    <td>{{ $a->date_achat->timezone($fuseau)->format('d/m/Y') }}</td>
                    <td>{{ $a->statut }}</td>
                    <td class="droite">{{ $nombre($a->total) }}</td>
                    <td class="droite">{{ $nombre($a->paye) }}</td>
                    <td class="droite">{{ $solde($a) > 0 ? $nombre($solde($a)) : '—' }}</td>
                    <td>{{ $a->echeance ? $a->echeance->timezone($fuseau)->format('d/m/Y') : '—' }}{{ $echue ? ' (échue)' : '' }}</td>
                    <td class="centre">{{ $solde($a) > 0 ? $jours.' j' : '—' }}</td>
                </tr>
            @empty
                <tr><td colspan="8" class="centre">Aucune commande pour ce fournisseur.</td></tr>
            @endforelse
        </tbody>
        @if ($achats->isNotEmpty())
            <tfoot>
                <tr data-totaux>
                    <td colspan="3">TOTAUX ({{ $achats->count() }})</td>
                    <td class="droite">{{ $nombre($achats->sum('total')) }}</td>
                    <td class="droite">{{ $nombre($achats->sum('paye')) }}</td>
                    <td class="droite">{{ $nombre($totalSolde) }}</td>
                    <td colspan="2"></td>
                </tr>
            </tfoot>
        @endif
    </table>

    @if ($reglements->isNotEmpty())
        <h2 style="font-weight:700;margin:16px 0 8px">Règlements ultérieurs enregistrés au journal</h2>
        <table data-table="reglements">
            <thead><tr><th>Date</th><th>Pièce</th><th>Commande</th><th>Compte de trésorerie</th><th class="droite">Montant</th></tr></thead>
            <tbody>
                @foreach ($reglements as $r)
                    <tr data-reglement="{{ $r['reference'] }}">
                        <td>{{ $r['date']->format('d/m/Y') }}</td><td>{{ $r['numero'] }}</td><td>{{ $r['reference'] }}</td>
                        <td>{{ $r['compte'] }}</td><td class="droite">{{ $nombre($r['montant']) }}</td>
                    </tr>
                @endforeach
            </tbody>
        </table>
        <p style="font-size:10px;margin-top:4px">Le montant réglé à la commande figure dans la colonne « Réglé » ci-dessus, pas dans ce tableau.</p>
    @endif
</x-impressions.mise-en-page>
