<form wire:submit="connecter" class="flex flex-col gap-md" novalidate>
    <div>
        <label for="identifiant" class="mb-xs block text-caption font-semibold uppercase text-outline">Identifiant</label>
        <input id="identifiant" type="text" wire:model="identifiant" autocomplete="username" autofocus
               class="w-full rounded-lg border-outline-variant text-body focus:border-brand-navy focus:ring-brand-navy">
        @error('identifiant') <p class="mt-xs text-invalid text-error-deep">{{ $message }}</p> @enderror
    </div>

    <div>
        <label for="password" class="mb-xs block text-caption font-semibold uppercase text-outline">Mot de passe</label>
        <input id="password" type="password" wire:model="password" autocomplete="current-password"
               class="w-full rounded-lg border-outline-variant text-body focus:border-brand-navy focus:ring-brand-navy">
        @error('password') <p class="mt-xs text-invalid text-error-deep">{{ $message }}</p> @enderror
    </div>

    @if ($erreur)
        <p role="alert" class="rounded-lg bg-error-container p-sm text-xs text-error-deep">{{ $erreur }}</p>
    @endif

    <button type="submit"
            class="rounded-lg bg-brand-navy px-md py-sm text-body font-semibold text-white hover:bg-brand-navy-dark">
        Se connecter
    </button>
</form>
