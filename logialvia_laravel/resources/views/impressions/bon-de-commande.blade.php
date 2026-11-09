@php
    $nombre = fn ($v) => number_format($v, 0, ',', ' ');
    $quantite = fn ($v) => rtrim(rtrim(number_format($v, 2, ',', ' '), '0'), ',');
    $fuseau = config('logialvia.fuseau');
    $reste = $achat->statut === 'Annulé' ? 0 : max(0, $achat->total - $achat->paye);
@endphp
<x-impressions.mise-en-page titre="Bon de commande {{ $achat->reference }}">
    <table style="margin-bottom:12px" data-bloc="en-tete">
        <tr>
            <td style="border:0;width:50%;vertical-align:top">
                <p style="font-size:11px;text-transform:uppercase;color:#555">Fournisseur</p>
                <p style="font-weight:700" data-fournisseur>{{ $fournisseur?->nom ?? '—' }}</p>
                @if ($fournisseur?->telephone)<p>{{ $fournisseur->telephone }}</p>@endif
                @if ($fournisseur?->adresse)<p>{{ $fournisseur->adresse }}</p>@endif
            </td>
            <td style="border:0;vertical-align:top" class="droite">
                <p>Commande <strong data-reference>{{ $achat->reference }}</strong></p>
                <p>Date : {{ $achat->date_achat->timezone($fuseau)->format('d/m/Y') }}</p>
                <p>Statut : <strong data-statut>{{ $achat->statut }}</strong></p>
                <p>Règlement : {{ $achat->mode ?: '—' }}</p>
                <p data-echeance>Échéance : {{ $achat->echeance ? $achat->echeance->timezone($fuseau)->format('d/m/Y') : 'aucune convenue' }}</p>
            </td>
        </tr>
    </table>

    <table data-table="lignes">
        <thead>
            <tr><th>Code</th><th>Désignation</th><th class="droite">Quantité</th><th class="droite">Prix unitaire</th><th class="droite">Total</th></tr>
        </thead>
        <tbody>
            @foreach ($achat->lignes as $l)
                <tr data-ligne="{{ $l->intrant_code }}">
                    <td>{{ $l->intrant_code }}</td>
                    <td><strong>{{ $l->nom }}</strong></td>
                    <td class="droite">{{ $quantite($l->qte) }}</td>
                    <td class="droite">{{ $nombre($l->pu_achat) }}</td>
                    <td class="droite">{{ $nombre($l->qte * $l->pu_achat) }}</td>
                </tr>
            @endforeach
        </tbody>
        <tfoot>
            <tr data-total><td colspan="4">TOTAL (FCFA)</td><td class="droite">{{ $nombre($achat->total) }}</td></tr>
            <tr><td colspan="4" style="border-top:0">Déjà réglé</td><td class="droite" style="border-top:0">{{ $nombre($achat->paye) }}</td></tr>
            <tr data-reste><td colspan="4" style="border-top:0">Reste dû</td><td class="droite" style="border-top:0">{{ $nombre($reste) }}</td></tr>
        </tfoot>
    </table>

    <table style="margin-top:32px">
        <tr>
            <td style="border:0;height:70px;vertical-align:top">Pour l'entreprise (nom, date, signature)</td>
            <td style="border:0;vertical-align:top">Pour le fournisseur (nom, date, signature)</td>
        </tr>
    </table>
</x-impressions.mise-en-page>
