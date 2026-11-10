@php($f = \App\Support\FormatComptable::class)
<x-impressions.mise-en-page titre="Saisie des Dépenses — exercice {{ $annee }}" orientation="landscape">
    <table data-table="depenses">
        <thead>
            <tr><th>N° Pièce</th><th>Date</th><th>Libellé</th><th>Catégorie</th><th class="droite">Montant</th><th class="centre">Statut</th></tr>
        </thead>
        <tbody>
            @forelse ($depenses as $d)
                <tr data-depense="{{ $d['numero_piece'] }}">
                    <td>{{ $d['numero_piece'] }}</td><td>{{ $d['date']->format('d/m/Y') }}</td><td><strong>{{ $d['libelle'] }}</strong></td>
                    <td>{{ $d['compte'] }} - {{ $d['libelle_compte'] }}</td><td class="droite">{{ $f::nombre($d['montant']) }}</td>
                    <td class="centre">{{ $d['payee'] ? 'Payée' : 'En attente' }}</td>
                </tr>
            @empty
                <tr><td colspan="6" class="centre">Aucune dépense ne correspond aux filtres retenus.</td></tr>
            @endforelse
        </tbody>
        @if (count($depenses) > 0)
            <tfoot><tr data-total><td colspan="4">TOTAL ({{ count($depenses) }})</td><td class="droite">{{ $f::nombre(array_sum(array_column($depenses, 'montant'))) }}</td><td></td></tr></tfoot>
        @endif
    </table>
</x-impressions.mise-en-page>
