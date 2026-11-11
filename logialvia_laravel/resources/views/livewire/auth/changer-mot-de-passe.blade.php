{{-- Changement du mot de passe (temporaire apres une reinitialisation) : meme architecture que la connexion (visuel a gauche, formulaire a droite). --}}
<div x-data="{ voir: false }">
    <div class="space-y-8">
        <x-marque-connexion />

        <div>
            <h2 class="text-kpi-value font-bold leading-tight text-brand-navy">Nouveau mot de passe</h2>
            <p class="text-xs text-outline">
                Votre mot de passe est temporaire : choisissez-en un nouveau (8 caractères minimum, 1 majuscule, 1 chiffre) pour continuer.
            </p>
        </div>

        @if ($erreur)
            <div role="alert" class="flex items-center gap-2 rounded-lg border border-error-deep/30 bg-error-container px-4 py-2 text-xs text-error-deep">
                <span class="icone text-[18px]">&#xe899;</span>
                <span>{{ $erreur }}</span>
            </div>
        @endif

        <form wire:submit="enregistrer" class="space-y-4" novalidate>
            @foreach ([['actuel', 'MOT DE PASSE ACTUEL', 'current-password'], ['nouveau', 'NOUVEAU MOT DE PASSE', 'new-password'], ['confirmation', 'CONFIRMER LE NOUVEAU MOT DE PASSE', 'new-password']] as [$champ, $libelle, $auto])
                <div>
                    <label for="{{ $champ }}" class="mb-1.5 block text-xs font-bold tracking-wider text-brand-navy">{{ $libelle }}</label>
                    <div class="relative">
                        <span class="icone absolute left-4 top-1/2 -translate-y-1/2 text-[20px] text-outline">&#xe899;</span>
                        <input id="{{ $champ }}" wire:model="{{ $champ }}" autocomplete="{{ $auto }}" x-bind:type="voir ? 'text' : 'password'" type="password"
                               class="h-[52px] w-full rounded-lg border border-outline-variant py-2.5 pl-12 pr-12 text-section-title outline-none focus:border-brand-navy focus:ring-2 focus:ring-brand-navy">
                        @if ($loop->first)
                            <button type="button" @click="voir = !voir" x-bind:aria-label="voir ? 'Masquer les mots de passe' : 'Afficher les mots de passe'"
                                    class="absolute right-4 top-1/2 -translate-y-1/2 text-outline hover:text-brand-navy">
                                <span class="icone text-[20px]">&#xe8f4;</span>
                            </button>
                        @endif
                    </div>
                </div>
            @endforeach

            <button type="submit" wire:loading.attr="disabled"
                    class="flex h-[52px] w-full items-center justify-center gap-2 rounded-lg bg-brand-navy text-section-title font-bold uppercase tracking-wider text-white shadow-sm transition-all hover:bg-brand-navy-dark active:scale-[0.98] disabled:opacity-50">
                <span class="icone text-[20px]">&#xe898;</span><span>Enregistrer</span>
            </button>
        </form>
    </div>

    <x-pied-connexion />
</div>
