{{-- En-tete commun des ecrans de comptabilite : titre, description, selecteur d'exercice (Dart : `SelecteurExercice`). --}}
{{-- Vue IMPRIMABLE (le poste exporte un PDF) : en impression, la navigation et les boutons disparaissent. --}}
<p class="mb-sm hidden text-xs text-outline print:block" data-entete-impression>ALLMANY ET COMPAGNIE — {{ $titre }} — exercice {{ $annee }} — imprimé le {{ now(config('logialvia.fuseau'))->format('d/m/Y') }}</p>
<div class="mb-xs flex flex-wrap items-center justify-between gap-sm">
    <h1 class="flex items-center gap-xs text-page-title font-bold text-brand-navy">@isset($icone)<x-icone :nom="$icone" class="text-[26px]" />@endisset{{ $titre }}</h1>
    <div class="flex items-center gap-sm text-xs print:hidden">
        @if (method_exists($this, 'exporter'))
            <button type="button" wire:click="exporter" data-action="exporter"
                    class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Exporter (XLSX)</button>
        @endif
        <button type="button" onclick="window.print()" data-action="imprimer"
                class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Imprimer / PDF</button>
        <label for="exercice" class="text-caption font-bold uppercase text-outline">Exercice</label>
        <select id="exercice" wire:model.live="exercice" data-selecteur="exercice"
                class="rounded-lg border border-outline-variant bg-surface-card px-sm py-xs text-xs">
            @foreach ($exercices as $e)
                <option value="{{ $e }}" @selected($e === $annee)>{{ $e }}</option>
            @endforeach
        </select>
        @if ($cloture)
            <span class="rounded-full bg-surface-zebra px-sm py-xs text-caption font-bold text-outline" data-badge="cloture">Clôturé</span>
        @endif
    </div>
</div>
<p class="mb-md text-xs text-outline">{{ $description }}</p>
