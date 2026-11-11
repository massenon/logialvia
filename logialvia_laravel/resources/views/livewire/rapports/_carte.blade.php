{{-- Carte KPI à liseré (Dart : `CarteKpiRapport`). --}}
<div class="rounded-lg border border-outline-variant border-l-4 {{ str_replace('border-','border-l-',$accent) }} bg-white p-md shadow-sm" data-carte="{{ $kpi }}">
    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">{{ $libelle }}</span>@isset($icone)<x-icone :nom="$icone" class="text-[18px] text-outline" />@endisset</div>
    <p class="mt-xs text-kpi-value font-extrabold {{ $couleur ?? '' }}" data-kpi="{{ $kpi }}">{{ $valeur }}</p>
    @isset($detail)
        <p class="text-caption text-outline" data-detail="{{ $kpi }}">{{ $detail }}</p>
    @endisset
</div>
