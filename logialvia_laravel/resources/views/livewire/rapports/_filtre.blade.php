{{-- Filtre d'un tableau (Dart : `FiltreRapport`) : liste d'options + réinitialisation. --}}
<div class="flex items-center gap-sm">
    <select wire:model.live="{{ $modele }}" data-filtre="{{ $modele }}" aria-label="{{ $tous }}"
            class="rounded-lg border border-outline-variant bg-surface-card px-sm py-xs text-xs">
        <option value="">{{ $tous }}</option>
        @foreach ($options as $cle => $libelle)
            <option value="{{ $cle }}" @selected($courant === (string) $cle)>{{ $libelle }}</option>
        @endforeach
    </select>
    @if ($courant !== null)
        <button type="button" wire:click="reinitialiserFiltres" data-action="reinitialiser"
                class="rounded-lg border border-outline-variant px-sm py-xs text-xs text-outline hover:bg-surface-zebra">Réinitialiser</button>
    @endif
</div>
