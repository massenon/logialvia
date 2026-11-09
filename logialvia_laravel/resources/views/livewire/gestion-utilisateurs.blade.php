<div data-onglet="utilisateurs">
    <section class="rounded-lg border border-outline-variant bg-surface-card p-md">
        <div class="mb-sm flex flex-wrap items-center justify-between gap-sm">
            <h2 class="text-section-title font-bold">Gestion des Utilisateurs</h2>
            <button type="button" wire:click="nouveau"
                    class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">
                Ajouter un Utilisateur
            </button>
        </div>

        @if ($message)
            <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep" data-message>{{ $message }}</p>
        @endif
        @if ($erreur && ! $formulaire && ! $cibleReinitialisation)
            <p role="alert" class="mb-md rounded-lg bg-error-container p-sm text-xs text-error-deep" data-erreur>{{ $erreur }}</p>
        @endif

        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Nom, identifiant ou e-mail…" aria-label="Rechercher un compte"
               class="mb-sm w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-sm">

        <div class="hidden overflow-x-auto sm:block">
            <table class="w-full text-left text-xs">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm">Nom Complet</th>
                        <th class="px-md py-sm">Identifiant</th>
                        <th class="px-md py-sm">Rôle</th>
                        <th class="px-md py-sm">Statut</th>
                        <th class="px-md py-sm text-right">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse ($comptes as $c)
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-compte="{{ $c['identifiant'] }}">
                            <td class="px-md py-sm font-bold">{{ $c['nom'] }}@if ($c['moi']) <span class="font-normal text-outline">(vous)</span>@endif</td>
                            <td class="px-md py-sm">{{ $c['identifiant'] }}</td>
                            <td class="px-md py-sm">{{ $c['libelleRole'] }}</td>
                            <td class="px-md py-sm">
                                <span class="rounded-full px-sm py-xs text-caption font-semibold {{ $c['actif'] ? 'bg-success-container text-success-deep' : 'bg-error-container text-error-deep' }}">{{ $c['actif'] ? 'Actif' : 'Désactivé' }}</span>
                                @if ($c['temporaire'])<span class="ml-xs rounded-full bg-brand-gold/10 px-sm py-xs text-caption font-semibold text-brand-navy">Mot de passe temporaire</span>@endif
                            </td>
                            <td class="whitespace-nowrap px-md py-sm text-right">
                                <button type="button" wire:click="modifier('{{ $c['id'] }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Modifier</button>
                                @unless ($c['moi'])
                                    <button type="button" wire:click="demanderReinitialisation('{{ $c['id'] }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Mot de passe</button>
                                    @if ($c['actif'])
                                        <button type="button" wire:click="demanderAction('desactiver', '{{ $c['id'] }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Désactiver</button>
                                    @else
                                        <button type="button" wire:click="reactiver('{{ $c['id'] }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Réactiver</button>
                                    @endif
                                    <button type="button" wire:click="demanderAction('supprimer', '{{ $c['id'] }}')" class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Supprimer</button>
                                @endunless
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucun compte ne correspond.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>

        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
            @foreach ($comptes as $c)
                <article class="rounded-lg border border-outline-variant p-sm text-xs" data-carte-compte="{{ $c['identifiant'] }}">
                    <p class="font-bold">{{ $c['nom'] }}@if ($c['moi']) <span class="font-normal text-outline">(vous)</span>@endif</p>
                    <p class="text-outline">{{ $c['identifiant'] }} · {{ $c['libelleRole'] }} · {{ $c['actif'] ? 'Actif' : 'Désactivé' }}</p>
                    <div class="mt-sm flex flex-wrap gap-sm">
                        <button type="button" wire:click="modifier('{{ $c['id'] }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm font-semibold">Modifier</button>
                        @unless ($c['moi'])
                            <button type="button" wire:click="demanderReinitialisation('{{ $c['id'] }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm font-semibold">Mot de passe</button>
                            @if ($c['actif'])
                                <button type="button" wire:click="demanderAction('desactiver', '{{ $c['id'] }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm font-semibold">Désactiver</button>
                            @else
                                <button type="button" wire:click="reactiver('{{ $c['id'] }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm font-semibold">Réactiver</button>
                            @endif
                            <button type="button" wire:click="demanderAction('supprimer', '{{ $c['id'] }}')" class="flex-1 rounded-lg border border-error-deep px-sm py-sm font-semibold text-error-deep">Supprimer</button>
                        @endunless
                    </div>
                </article>
            @endforeach
        </div>

        <p class="mt-sm rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="utilisateurs">
            Ce sont les comptes du serveur (connexion web et appairage des postes). Les comptes locaux d'un poste lui restent propres
            (création et mots de passe sur le poste). Le dernier administrateur actif et votre propre compte sont protégés : ni
            suppression, ni désactivation, ni changement de rôle. Un compte supprimé se restaure depuis l'onglet Corbeille.
        </p>
    </section>

    @if ($formulaire)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-utilisateur">
            <form wire:submit="enregistrer" class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl" novalidate>
                <h2 id="titre-utilisateur" class="mb-md text-modal-title font-bold">{{ $utilisateurId ? 'Modifier l\'Utilisateur' : 'Ajouter un Utilisateur' }}</h2>
                <label class="mb-sm block text-xs">Nom Complet *
                    <input type="text" wire:model="nom" maxlength="255" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Identifiant de Connexion *
                    <input type="text" wire:model="identifiant" maxlength="60" @readonly($utilisateurId !== null) autocomplete="off"
                           class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm read-only:bg-surface-zebra"></label>
                <label class="mb-sm block text-xs">E-mail
                    <input type="text" inputmode="email" wire:model="email" maxlength="255" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Rôle *
                    <select wire:model="role" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                        <option value="">-- Sélectionner --</option>
                        @foreach ($roles as $cle => $libelle)<option value="{{ $cle }}">{{ $libelle }}</option>@endforeach
                    </select></label>
                @if ($utilisateurId === null)
                    <label class="mb-sm block text-xs">Mot de Passe temporaire *
                        <input type="password" wire:model="motDePasse" autocomplete="new-password" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                        <span class="text-caption text-outline">{{ \App\Support\RegleMotDePasse::INDICATION }}. La personne devra le changer à sa première connexion.</span></label>
                    <label class="mb-sm block text-xs">Confirmer le Mot de Passe *
                        <input type="password" wire:model="confirmation" autocomplete="new-password" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @endif
                @if ($erreur)
                    <p role="alert" class="mb-sm rounded-lg bg-error-container p-sm text-xs text-error-deep" data-erreur>{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">{{ $utilisateurId ? 'Enregistrer' : 'Créer le Compte' }}</button>
                </div>
            </form>
        </div>
    @endif

    @if ($cibleReinitialisation)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-reinit">
            <form wire:submit="reinitialiser" class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl" novalidate>
                <h2 id="titre-reinit" class="mb-sm text-modal-title font-bold">Réinitialiser le mot de passe</h2>
                <p class="mb-md text-xs">Compte <strong>{{ $cibleReinitialisation->username }}</strong>. Le mot de passe saisi est <strong>temporaire</strong> :
                    la personne devra le changer dès sa connexion, et ses postes appairés devront se reconnecter.</p>
                <label class="mb-sm block text-xs">Mot de Passe temporaire *
                    <input type="password" wire:model="motDePasse" autocomplete="new-password" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                    <span class="text-caption text-outline">{{ \App\Support\RegleMotDePasse::INDICATION }}</span></label>
                <label class="mb-sm block text-xs">Confirmer le Mot de Passe *
                    <input type="password" wire:model="confirmation" autocomplete="new-password" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @if ($erreur)
                    <p role="alert" class="mb-sm rounded-lg bg-error-container p-sm text-xs text-error-deep" data-erreur>{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Poser le mot de passe</button>
                </div>
            </form>
        </div>
    @endif

    @if ($cibleAction)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-action-compte">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-action-compte" class="mb-sm text-modal-title font-bold">
                    {{ $actionAConfirmer === 'supprimer' ? 'Supprimer ce compte ?' : 'Désactiver ce compte ?' }}
                </h2>
                <p class="mb-md text-xs">
                    @if ($actionAConfirmer === 'supprimer')
                        Le compte <strong>{{ $cibleAction->username }}</strong> sera archivé (il se restaure depuis la Corbeille) et ses postes perdront leur appairage.
                    @else
                        Le compte <strong>{{ $cibleAction->username }}</strong> ne pourra plus se connecter et ses postes perdront leur appairage. Vous pourrez le réactiver.
                    @endif
                </p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="confirmerAction" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">
                        {{ $actionAConfirmer === 'supprimer' ? 'Supprimer' : 'Désactiver' }}
                    </button>
                </div>
            </div>
        </div>
    @endif
</div>
