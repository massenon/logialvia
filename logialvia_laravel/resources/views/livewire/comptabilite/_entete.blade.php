{{-- En-tete commun des ecrans de comptabilite : titre, description, selecteur d'exercice (Dart : `SelecteurExercice`). --}}
<div class="mb-xs flex flex-wrap items-center justify-between gap-sm">
    <h1 class="text-page-title font-bold">{{ $titre }}</h1>
    <div class="flex items-center gap-sm text-xs">
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
