{{-- Rapports & États (Dart : `rapports_exports_screen.dart`). Lecture seule ; export XLSX protégé par `export-rapports`. --}}
@php
    $f = \App\Support\FormatComptable::class;
    // « — » pour un montant nul (Dart : `MontantRapport`).
    $m = fn (float $v) => abs($v) < 0.01 ? '—' : $f::nombre($v);
    $d = fn (?\Carbon\CarbonImmutable $t) => $t === null ? '—' : $t->format('d/m/Y');
@endphp
<div>
    <div class="mb-xs flex flex-wrap items-center justify-between gap-sm">
        <h1 class="flex items-center gap-xs text-page-title font-bold text-brand-navy"><x-icone nom="picture_as_pdf" class="text-[24px]" />Rapports &amp; États</h1>
        <div class="flex flex-wrap items-center gap-sm">
            <div class="flex flex-wrap items-center gap-sm rounded-lg border border-outline-variant bg-white px-sm py-xs text-xs shadow-sm"><x-icone nom="calendar_month" class="text-[18px] text-brand-navy" />
                <label class="flex items-center gap-sm text-outline">Du
                    <input type="date" wire:model.live="debut" aria-label="Début de la période" data-champ="debut"
                           class="rounded-lg border border-outline-variant px-sm py-xs text-xs font-bold text-brand-navy"></label>
                <label class="flex items-center gap-sm text-outline">au
                    <input type="date" wire:model.live="fin" aria-label="Fin de la période" data-champ="fin"
                           class="rounded-lg border border-outline-variant px-sm py-xs text-xs font-bold text-brand-navy"></label>
            </div>
            @if ($peutExporter && $onglet !== 'stocks')
                <button type="button" wire:click="exporter" data-action="exporter"
                        class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Exporter (XLSX)</button>
            @endif
        </div>
    </div>
    <p class="mb-md text-xs text-outline" data-periode>États de synthèse, période du {{ $d($debutPeriode) }} au {{ $d($finPeriode) }}.</p>

    @unless ($periodeValide)
        <p role="alert" class="mb-md rounded-lg bg-error-container p-sm text-xs text-error-deep" data-alerte="periode">
            Période invalide : le mois en cours est affiché.</p>
    @endunless

    <div class="mb-md flex items-center gap-xs overflow-x-auto border-b border-outline-variant" role="tablist" data-onglets>
        @foreach ($onglets as $cle => $titre)
            <button type="button" role="tab" wire:click="choisirOnglet('{{ $cle }}')" data-onglet="{{ $cle }}"
                    aria-selected="{{ $onglet === $cle ? 'true' : 'false' }}"
                    class="-mb-px whitespace-nowrap border-b-2 px-md py-2.5 text-xs font-bold {{ $onglet === $cle ? 'border-brand-navy text-brand-navy' : 'border-transparent text-outline hover:text-brand-navy' }}">{{ $titre }}</button>
        @endforeach
    </div>

    @include('livewire.rapports._'.$onglet)

    @include('livewire.rapports._ecarts')
</div>
