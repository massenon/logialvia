@php
    $quantite = fn ($v) => rtrim(rtrim(number_format($v, 2, ',', ' '), '0'), ',');
    $fuseau = config('logialvia.fuseau');
@endphp
<x-impressions.mise-en-page titre="État des Stocks d'Intrants — journal" orientation="landscape">
    <p style="font-size:11px;margin-bottom:8px" data-ecart="stock-poste">Stock, PMP et valeur sont propres à chaque poste : ils figurent sur l'état imprimé du poste. Ce document liste le référentiel des intrants et le journal partagé de tous les postes.</p>

    <h2 style="font-weight:700;margin:8px 0">Intrants</h2>
    <table data-table="intrants">
        <thead><tr><th>Code</th><th>Désignation</th><th>Catégorie</th><th>Unité</th><th class="droite">Seuil d'alerte</th></tr></thead>
        <tbody>
            @forelse ($intrants as $i)
                <tr data-intrant="{{ $i->code }}"><td>{{ $i->code }}</td><td><strong>{{ $i->name }}</strong></td><td>{{ $i->cat }}</td><td>{{ $i->unit }}</td><td class="droite">{{ $i->threshold }}</td></tr>
            @empty
                <tr><td colspan="5" class="centre">Aucun intrant.</td></tr>
            @endforelse
        </tbody>
    </table>

    <h2 style="font-weight:700;margin:16px 0 8px">Journal des mouvements</h2>
    <table data-table="journal">
        <thead><tr><th>Date / Heure</th><th>Poste</th><th>Référence</th><th>Article</th><th>Type</th><th>Motif</th><th class="droite">Quantité</th></tr></thead>
        <tbody>
            @forelse ($journal as $ligne)
                @php($m = $ligne['mouvement'])
                <tr data-mouvement="{{ $m->reference ?? $m->id }}">
                    <td>{{ $m->horodatage->timezone($fuseau)->format('d/m/Y H:i') }}</td><td>{{ $ligne['poste'] }}</td><td>{{ $m->reference ?? '—' }}</td>
                    <td>{{ $m->article }}</td><td>{{ $m->type }}</td><td>{{ $m->motif }}</td><td class="droite">{{ $quantite($m->quantite) }}</td>
                </tr>
            @empty
                <tr><td colspan="7" class="centre">Aucun mouvement.</td></tr>
            @endforelse
        </tbody>
    </table>
    <p style="font-size:10px;margin-top:4px">La quantité est signée : positive en entrée, négative en sortie.</p>
</x-impressions.mise-en-page>
