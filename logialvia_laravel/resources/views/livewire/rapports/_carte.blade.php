{{-- Carte KPI à liseré (Dart : `CarteKpiRapport`). --}}
<div class="rounded-lg border-l-4 {{ $accent }} bg-surface-card p-md shadow-sm" data-carte="{{ $kpi }}">
    <p class="text-caption uppercase text-outline">{{ $libelle }}</p>
    <p class="text-kpi-value font-bold {{ $couleur ?? '' }}" data-kpi="{{ $kpi }}">{{ $valeur }}</p>
    @isset($detail)
        <p class="text-caption text-outline" data-detail="{{ $kpi }}">{{ $detail }}</p>
    @endisset
</div>
