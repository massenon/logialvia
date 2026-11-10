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
            <div class="mt-md rounded-lg bg-surface-zebra p-md text-xs" data-carte="session">
                <p class="mb-sm text-caption font-semibold uppercase text-outline">Métadonnées de session</p>
                <p class="flex justify-between"><span class="text-outline">Dernière connexion</span>
                    <span class="font-bold" data-profil="derniere-connexion">{{ $derniereConnexion ? $derniereConnexion->timezone($fuseau)->format('d/m/Y H:i') : 'Première connexion' }}</span></p>
                <p class="flex justify-between"><span class="text-outline">Connexions enregistrées</span>
                    <span class="font-bold" data-profil="connexions">{{ $nombreConnexions }}</span></p>
                <p class="flex justify-between"><span class="text-outline">Statut du compte</span>
                    <span class="font-bold {{ $actif ? 'text-success-deep' : 'text-error-deep' }}" data-profil="statut">{{ $actif ? 'Actif' : 'Désactivé' }}</span></p>
            </div>
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
                <p class="text-caption text-outline">{{ \App\Support\RegleMotDePasse::INDICATION }}.</p>

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

        <section class="rounded-lg border border-outline-variant bg-surface-card p-lg lg:col-start-2" data-carte="journal">
            <h2 class="mb-md text-section-title font-bold">Journal d'Audit — Dernières Actions</h2>
            @forelse ($journal as $l)
                <div class="flex flex-wrap justify-between gap-sm border-b border-outline-variant py-sm text-xs" data-ligne-journal="{{ $l->action }}">
                    <span class="whitespace-nowrap text-outline">{{ $l->created_at->timezone($fuseau)->format('d/m/Y H:i') }}</span>
                    <span class="flex-1 font-semibold">{{ \App\Support\LibellesAudit::action($l->action) }}</span>
                    <span class="text-outline">{{ \App\Support\LibellesAudit::module($l->action) }}</span>
                </div>
            @empty
                <p class="text-xs text-outline">Aucune action enregistrée pour ce compte. Le journal se remplit au fil des connexions et des gestes d'administration.</p>
            @endforelse
            <p class="mt-sm text-caption italic text-outline">Le serveur ne journalise ni les déconnexions ni les ventes et achats (saisis sur les postes) : leur historique reste sur le poste.</p>
        </section>
    </div>
</div>
