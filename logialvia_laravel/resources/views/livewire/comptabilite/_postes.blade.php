{{-- Lignes d'un etat financier (Dart : `LignePosteEtat`) : libelle, detail des comptes sources, montant. --}}
@php($f = \App\Support\FormatComptable::class)
@foreach ($postes as $p)
    @continue(($sansTotal ?? false) && $p['total'])
    <div class="flex items-baseline justify-between gap-sm border-b border-outline-variant px-md py-sm text-xs {{ $p['total'] ? 'bg-brand-gold/10 font-bold' : ($p['sous_total'] ? 'bg-surface-zebra font-bold' : '') }}"
         data-poste="{{ $p['libelle'] }}">
        <div>
            <span>{{ $p['libelle'] }}</span>
            @if ($p['detail'])<span class="block text-caption font-normal text-outline">{{ $p['detail'] }}</span>@endif
        </div>
        <span class="whitespace-nowrap {{ $p['montant'] < 0 ? 'text-error-deep' : '' }}" data-montant>{{ $f::nombre($p['montant']) }}</span>
    </div>
@endforeach
