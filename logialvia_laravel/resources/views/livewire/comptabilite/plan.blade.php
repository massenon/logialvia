<div>
    <div class="mb-xs flex flex-wrap items-center justify-between gap-sm">
        <h1 class="text-page-title font-bold">Plan Comptable</h1>
        @if ($peutGerer)
            <button type="button" wire:click="nouveau" data-action="nouveau"
                    class="rounded-lg bg-brand-navy px-md py-sm text-xs font-bold text-white">Nouveau Compte</button>
        @endif
    </div>
    <p class="mb-md text-xs text-outline">Comptes SYSCOHADA Révisée utilisés par le moteur d'écritures automatiques.</p>

    <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="referentiel">
        Référentiel : le serveur fait foi. Chaque modification est une demande, soumise aux mêmes règles que celles d'un poste. Export PDF : au poste.
    </p>

    @if ($message)
        <p class="mb-md rounded-lg bg-success-container p-sm text-xs font-bold text-success-deep" data-message>{{ $message }}</p>
    @endif

    <h2 class="mb-sm text-section-title font-bold" data-compteur>{{ $comptes->count() }} compte(s)</h2>
    <div class="mb-sm flex flex-wrap items-center gap-sm">
        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Rechercher un compte…" aria-label="Rechercher un compte"
               class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-xs">
        <select wire:model.live="classe" aria-label="Filtrer par classe" class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
            <option value="">Classe : Toutes</option>
            @foreach ($classes as $code => $libelleClasse)<option value="{{ $code }}">{{ $libelleClasse }}</option>@endforeach
        </select>
        <label class="flex items-center gap-xs text-xs"><input type="checkbox" wire:model.live="archives" data-filtre="archives"> Archivés</label>
    </div>

    <div class="mb-lg hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs" data-table="plan">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">N° Compte</th>
                    <th class="px-md py-sm">Intitulé</th>
                    <th class="px-md py-sm">Classe</th>
                    <th class="px-md py-sm">Sens</th>
                    <th class="px-md py-sm text-right">Actions</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($comptes as $c)
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-compte="{{ $c->numero_compte }}">
                        <td class="px-md py-sm font-mono font-bold {{ $c->archive ? 'text-outline' : '' }}">{{ $c->numero_compte }}</td>
                        <td class="px-md py-sm {{ $c->archive ? 'text-outline line-through' : '' }}">{{ $c->libelle }}
                            @if ($c->archive)<span class="rounded-full bg-surface-zebra px-sm py-xs text-caption text-outline" data-archive>Archivé</span>@endif
                        </td>
                        <td class="px-md py-sm">{{ $classes[$c->classe] ?? $c->classe }}</td>
                        <td class="px-md py-sm">{{ $c->estDebiteurParNature() ? 'Débiteur' : 'Créditeur' }}</td>
                        <td class="px-md py-sm text-right">
                            @if ($peutGerer)
                                <button type="button" wire:click="modifier('{{ $c->numero_compte }}')" data-action="modifier"
                                        class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Modifier</button>
                                <button type="button" wire:click="basculerArchive('{{ $c->numero_compte }}')" data-action="archiver"
                                        class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">{{ $c->archive ? 'Réactiver' : 'Archiver' }}</button>
                            @endif
                        </td>
                    </tr>
                @empty
                    <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucun compte ne correspond.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>

    <div class="mb-lg flex flex-col gap-sm sm:hidden" data-vue="cartes">
        @forelse ($comptes as $c)
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-compte="{{ $c->numero_compte }}">
                <p class="font-mono font-bold text-brand-navy">{{ $c->numero_compte }} @if ($c->archive)<span class="text-caption font-normal text-outline">Archivé</span>@endif</p>
                <p class="text-xs">{{ $c->libelle }}</p>
                <p class="text-caption text-outline">{{ $classes[$c->classe] ?? $c->classe }} · {{ $c->estDebiteurParNature() ? 'Débiteur' : 'Créditeur' }}</p>
                @if ($peutGerer)
                    <div class="mt-sm flex gap-sm">
                        <button type="button" wire:click="modifier('{{ $c->numero_compte }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Modifier</button>
                        <button type="button" wire:click="basculerArchive('{{ $c->numero_compte }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">{{ $c->archive ? 'Réactiver' : 'Archiver' }}</button>
                    </div>
                @endif
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun compte ne correspond.</p>
        @endforelse
    </div>

    @if ($formulaire)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-compte" data-modale="compte">
            <div class="max-h-full w-full max-w-md overflow-y-auto rounded-lg bg-surface-card p-lg shadow-lg">
                <h2 id="titre-compte" class="mb-md text-modal-title font-bold">{{ $numeroEnEdition ? 'Modifier le compte '.$numeroEnEdition : 'Nouveau Compte' }}</h2>
                @if ($erreur)
                    <p class="mb-md rounded-lg bg-error-container p-sm text-xs text-error-deep" role="alert" data-erreur>{{ $erreur }}</p>
                @endif
                <label class="mb-sm block text-caption font-bold uppercase text-outline" for="numero">N° de compte</label>
                <input id="numero" type="text" wire:model="numero" @disabled($numeroEnEdition) placeholder="Ex. 635"
                       class="mb-md w-full rounded-lg border border-outline-variant px-md py-sm text-xs disabled:bg-surface-zebra">
                <label class="mb-sm block text-caption font-bold uppercase text-outline" for="libelle">Intitulé</label>
                <input id="libelle" type="text" wire:model="libelle" class="mb-md w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                <label class="mb-sm block text-caption font-bold uppercase text-outline" for="classe-compte">Classe</label>
                <select id="classe-compte" wire:model="classeCompte" class="mb-md w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                    <option value="">Sélectionner</option>
                    @foreach ($classes as $code => $libelleClasse)<option value="{{ $code }}">{{ $libelleClasse }}</option>@endforeach
                </select>
                @if ($numeroEnEdition && ($mouvements[$numeroEnEdition] ?? 0) > 0)
                    <p class="mb-md text-caption text-outline">Ce compte porte {{ $mouvements[$numeroEnEdition] }} écriture(s) : son numéro ne change jamais.</p>
                @endif
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-bold">Annuler</button>
                    <button type="button" wire:click="enregistrer" data-action="enregistrer" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-bold text-white">Enregistrer</button>
                </div>
            </div>
        </div>
    @endif

    @if ($aArchiver)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-archivage" data-modale="archivage">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-lg">
                <h2 id="titre-archivage" class="mb-md text-modal-title font-bold">Archiver le compte {{ $aArchiver }} ?</h2>
                <p class="mb-md text-xs">Un compte archivé n'est plus proposé à la saisie, mais ses écritures restent au Journal, au Grand Livre et dans la Balance : les états financiers déjà publiés ne changent pas.<br><br>L'archivage est réversible.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-bold">Annuler</button>
                    <button type="button" wire:click="confirmerArchivage" data-action="confirmer-archivage" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-bold text-white">Archiver</button>
                </div>
            </div>
        </div>
    @endif
</div>
