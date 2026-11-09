<div>
    <div class="mb-md border-b border-outline-variant pb-md">
        <h1 class="text-page-title font-bold">Mon Profil</h1>
        <p class="text-xs text-outline">Informations de session et sécurité du compte.</p>
    </div>

    <div class="grid grid-cols-1 gap-md lg:grid-cols-[35%_1fr]">
        <section class="rounded-lg border border-outline-variant bg-surface-card p-lg" data-carte="identite">
            <div class="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-brand-navy text-section-title font-extrabold text-white" aria-hidden="true">{{ $initiales }}</div>
            <p class="mt-md text-center text-xs font-bold text-brand-navy" data-profil="nom">{{ $nom }}</p>
            <p class="text-center text-xs text-outline" data-profil="identifiant">{{ $identifiant }}</p>
            <p class="mt-md text-center">
                <span class="rounded-full border border-brand-navy/30 bg-brand-navy/10 px-sm py-xs text-xs font-bold text-brand-navy" data-profil="role">{{ $libelleRole }}</span>
            </p>
            <p class="mt-md rounded-lg bg-surface-zebra p-sm text-xs text-outline">
                Ces informations sont en lecture seule. Seule une Administratrice peut modifier les détails du profil depuis
                Paramètres Généraux &gt; Gestion Utilisateurs.
            </p>
        </section>

        <section class="rounded-lg border border-outline-variant bg-surface-card p-lg" data-carte="mot-de-passe">
            <h2 class="mb-md text-section-title font-bold">Modifier le Mot de Passe</h2>
            <form wire:submit="enregistrer" class="flex flex-col gap-md" novalidate>
                @foreach ([['actuel', 'Ancien mot de passe *', 'current-password'], ['nouveau', 'Nouveau mot de passe *', 'new-password'], ['confirmation', 'Confirmer le nouveau mot de passe *', 'new-password']] as [$champ, $libelle, $auto])
                    <div>
                        <label for="{{ $champ }}" class="mb-xs block text-caption font-semibold uppercase text-outline">{{ $libelle }}</label>
                        <input id="{{ $champ }}" type="password" wire:model="{{ $champ }}" autocomplete="{{ $auto }}"
                               class="w-full rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs">
                    </div>
                @endforeach
                <p class="text-caption text-outline">10 caractères minimum.</p>

                @if ($erreur)
                    <p role="alert" class="rounded-lg bg-error-container p-sm text-xs text-error-deep">{{ $erreur }}</p>
                @endif

                <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">
                    Mettre à jour le mot de passe
                </button>
            </form>
            <p class="mt-md text-caption italic text-outline">
                Le mot de passe n'est jamais affiché ni journalisé. Après un changement, les postes appairés à ce compte devront se reconnecter.
            </p>
        </section>
    </div>
</div>
