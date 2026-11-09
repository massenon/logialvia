<div data-onglet="corbeille">
    <section class="rounded-lg border border-outline-variant bg-surface-card p-md">
        <div class="mb-sm flex flex-wrap items-center justify-between gap-sm">
            <h2 class="text-section-title font-bold">Corbeille ({{ $elements->count() }})</h2>
            <div class="no-print flex gap-sm">
                <button type="button" wire:click="exporter" data-action="exporter" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Exporter (XLSX)</button>
                <x-bouton-imprimer />
            </div>
        </div>
        <p class="mb-md text-xs text-outline">
            Les éléments supprimés du serveur restent ici (pierre tombale). Restaurer lève la suppression : l'élément redescend vers tous les postes.
        </p>

        @if ($message)<p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep" data-message>{{ $message }}</p>@endif
        @if ($erreur)<p role="alert" class="mb-md rounded-lg bg-error-container p-sm text-xs text-error-deep" data-erreur>{{ $erreur }}</p>@endif

        <div class="no-print mb-sm flex flex-wrap gap-sm">
            <select wire:model.live="type" aria-label="Type d'élément" class="rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs">
                <option value="">Tous les types</option>
                @foreach ($types as $cle => $libelle)<option value="{{ $cle }}">{{ $libelle }}</option>@endforeach
            </select>
            <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Désignation…" aria-label="Rechercher" class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
        </div>

        <div class="hidden overflow-x-auto sm:block">
            <table class="w-full text-left text-xs">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr><th class="px-md py-sm">Module</th><th class="px-md py-sm">Type</th><th class="px-md py-sm">Désignation</th><th class="px-md py-sm">Archivé le</th><th class="px-md py-sm">Origine</th><th class="no-print px-md py-sm text-right">Actions</th></tr>
                </thead>
                <tbody>
                    @forelse ($elements as $e)
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-element="{{ $e['type'] }}:{{ $e['id'] }}">
                            <td class="px-md py-sm">{{ $e['module'] }}</td>
                            <td class="px-md py-sm">{{ $e['libelle'] }}</td>
                            <td class="px-md py-sm font-bold">{{ $e['designation'] }}</td>
                            <td class="whitespace-nowrap px-md py-sm">{{ $e['archive_le']->timezone($fuseau)->format('d/m/Y H:i') }}</td>
                            <td class="px-md py-sm">{{ $e['origine'] }}</td>
                            <td class="no-print whitespace-nowrap px-md py-sm text-right">
                                @if ($e['restaurable'])
                                    <button type="button" wire:click="restaurer('{{ $e['type'] }}', '{{ $e['id'] }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Restaurer</button>
                                @elseif ($e['reserve_admin'])
                                    <span class="text-caption text-outline">Administrateur seul</span>
                                @endif
                                @if ($e['purgeable'])
                                    <button type="button" wire:click="demanderPurge('{{ $e['type'] }}', '{{ $e['id'] }}')" class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Effacer</button>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">La corbeille est vide.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
            @forelse ($elements as $e)
                <article class="rounded-lg border border-outline-variant p-sm text-xs" data-carte-element="{{ $e['type'] }}:{{ $e['id'] }}">
                    <p class="font-bold">{{ $e['designation'] }}</p>
                    <p class="text-outline">{{ $e['libelle'] }} · {{ $e['archive_le']->timezone($fuseau)->format('d/m/Y H:i') }} · {{ $e['origine'] }}</p>
                    <div class="mt-sm flex gap-sm">
                        @if ($e['restaurable'])<button type="button" wire:click="restaurer('{{ $e['type'] }}', '{{ $e['id'] }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm font-semibold">Restaurer</button>@endif
                        @if ($e['purgeable'])<button type="button" wire:click="demanderPurge('{{ $e['type'] }}', '{{ $e['id'] }}')" class="flex-1 rounded-lg border border-error-deep px-sm py-sm font-semibold text-error-deep">Effacer</button>@endif
                    </div>
                </article>
            @empty
                <p class="text-center text-outline">La corbeille est vide.</p>
            @endforelse
        </div>

        <p class="mt-sm rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="corbeille">
            C'est la corbeille du serveur. Celle d'un poste (éléments archivés localement) se gère sur ce poste. Seuls les comptes supprimés
            s'effacent définitivement (administrateur) : les autres suppressions restent en pierre tombale, pour qu'un poste hors ligne ne
            ressuscite pas l'élément.
        </p>
    </section>

    @if ($purgeAConfirmer)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-purge">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-purge" class="mb-sm text-modal-title font-bold">Effacer définitivement ?</h2>
                <p class="mb-md text-xs">Cet élément sera détruit sans retour possible. Le journal d'audit en gardera la trace.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="confirmerPurge" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Effacer</button>
                </div>
            </div>
        </div>
    @endif
</div>
