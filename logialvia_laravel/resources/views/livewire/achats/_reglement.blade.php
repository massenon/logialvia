{{-- Modale « Régler » (Dart : `_FormulaireReglement`). Variables : `$reglement` (voir `ReglementDette::reglementEnCours`). --}}
@if ($reglement['achat'])
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-reglement" data-modale="reglement">
        <form wire:submit="confirmerReglement" class="w-full max-w-sm rounded-lg bg-surface-card p-lg shadow-xl">
            <h2 id="titre-reglement" class="mb-md text-modal-title font-bold">Régler {{ $reglement['achat']->reference }}</h2>
            <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs" data-reste-du>
                {{ $reglement['fournisseur'] ?? '—' }}<br>Solde dû : <strong>{{ number_format($reglement['reste'], 0, ',', ' ') }} FCFA</strong>
            </p>
            <label class="mb-sm block text-xs">Montant Réglé (FCFA) *
                <input type="text" inputmode="decimal" wire:model="montantReglement" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                <span class="text-caption text-outline">Un versement supérieur au solde est borné au reste dû.</span></label>
            <label class="block text-xs">Mode du règlement *
                <select wire:model="modeReglement" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                    <option value="Espèces">Espèces (compte {{ \App\Support\PlanSyscohada::CAISSE }})</option>
                    <option value="Mobile Money">Mobile Money (compte {{ \App\Support\PlanSyscohada::MOBILE_MONEY }})</option>
                </select></label>
            @if ($erreurReglement)
                <p role="alert" class="mt-sm text-xs text-error-deep" data-erreur-reglement>{{ $erreurReglement }}</p>
            @endif
            <div class="mt-md flex justify-end gap-sm">
                <button type="button" wire:click="annulerReglement" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                <button type="submit" data-action="confirmer-reglement" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Enregistrer</button>
            </div>
        </form>
    </div>
@endif
