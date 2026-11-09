<form wire:submit="enregistrer" class="flex flex-col gap-md" novalidate>
    <p class="text-xs text-outline">
        Votre mot de passe est temporaire : choisissez-en un nouveau (10 caractères minimum) pour continuer.
    </p>

    @foreach ([['actuel', 'Mot de passe actuel', 'current-password'], ['nouveau', 'Nouveau mot de passe', 'new-password'], ['confirmation', 'Confirmer le nouveau mot de passe', 'new-password']] as [$champ, $libelle, $auto])
        <div>
            <label for="{{ $champ }}" class="mb-xs block text-caption font-semibold uppercase text-outline">{{ $libelle }}</label>
            <input id="{{ $champ }}" type="password" wire:model="{{ $champ }}" autocomplete="{{ $auto }}"
                   class="w-full rounded-lg border-outline-variant text-body focus:border-brand-navy focus:ring-brand-navy">
        </div>
    @endforeach

    @if ($erreur)
        <p role="alert" class="rounded-lg bg-error-container p-sm text-xs text-error-deep">{{ $erreur }}</p>
    @endif

    <button type="submit"
            class="rounded-lg bg-brand-navy px-md py-sm text-body font-semibold text-white hover:bg-brand-navy-dark">
        Enregistrer
    </button>
</form>
