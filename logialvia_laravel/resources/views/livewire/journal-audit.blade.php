<div>
    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <div>
            <h1 class="text-page-title font-bold">Journal d'Audit</h1>
            <p class="text-xs text-outline">Gestes sensibles enregistrés par le serveur : connexions, comptes, synchronisation, clôtures. Lecture seule.</p>
        </div>
        <div class="flex gap-sm no-print">
            <button type="button" wire:click="exporter" data-action="exporter" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Exporter (XLSX)</button>
            <x-bouton-imprimer />
            <a href="/parametres/generaux" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Paramètres Généraux</a>
        </div>
    </div>

    <form class="no-print mb-md grid grid-cols-1 gap-sm rounded-lg border border-outline-variant bg-surface-card p-md sm:grid-cols-2 lg:grid-cols-5" wire:submit.prevent>
        <label class="text-caption font-semibold uppercase text-outline">Du
            <input type="date" wire:model.live="dateDebut" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm text-xs normal-case"></label>
        <label class="text-caption font-semibold uppercase text-outline">Au (inclus)
            <input type="date" wire:model.live="dateFin" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm text-xs normal-case"></label>
        <label class="text-caption font-semibold uppercase text-outline">Action
            <select wire:model.live="action" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm text-xs normal-case">
                <option value="">Toutes</option>
                @foreach ($actions as $code => $libelle)<option value="{{ $code }}">{{ $libelle }}</option>@endforeach
            </select></label>
        <label class="text-caption font-semibold uppercase text-outline">Utilisateur
            <select wire:model.live="utilisateur" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm text-xs normal-case">
                <option value="">Tous</option>
                @foreach ($comptes as $c)<option value="{{ $c->id }}">{{ $c->name }} ({{ $c->username }})</option>@endforeach
            </select></label>
        <div class="flex items-end">
            <button type="button" wire:click="reinitialiser" class="w-full rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Réinitialiser les filtres</button>
        </div>
    </form>

    @if ($erreur)
        <p role="alert" class="mb-md rounded-lg bg-error-container p-sm text-xs text-error-deep" data-erreur>{{ $erreur }}</p>
    @endif

    <p class="mb-sm text-xs text-outline" data-total>{{ $total }} entrée(s) — page {{ $page }} / {{ $pages }} · heures de {{ $fuseau }}</p>

    <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs" data-table="audit">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Date</th>
                    <th class="px-md py-sm">Utilisateur</th>
                    <th class="px-md py-sm">Action</th>
                    <th class="px-md py-sm">Détail</th>
                    <th class="px-md py-sm">Adresse IP</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($lignes as $l)
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }} align-top" data-ligne-audit="{{ $l->action }}">
                        <td class="whitespace-nowrap px-md py-sm">{{ $l->created_at->timezone($fuseau)->format('d/m/Y H:i:s') }}</td>
                        <td class="px-md py-sm">{{ $auteurs[$l->utilisateur_id] ?? '' }}<span class="text-outline">{{ $l->identifiant ? ' ('.$l->identifiant.')' : '' }}</span>@if (! $l->utilisateur_id && ! $l->identifiant)—@endif</td>
                        <td class="px-md py-sm font-semibold">{{ \App\Support\LibellesAudit::action($l->action) }}<br><span class="font-mono text-caption font-normal text-outline">{{ $l->action }}</span></td>
                        <td class="px-md py-sm text-outline">@foreach (\App\Support\LibellesAudit::detail($l->detail) as $ligne){{ $ligne }}@unless ($loop->last)<br>@endunless @endforeach</td>
                        <td class="px-md py-sm font-mono">{{ $l->ip ?? '—' }}</td>
                    </tr>
                @empty
                    <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucune entrée ne correspond à ces filtres.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>
    <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
        @forelse ($lignes as $l)
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md text-xs" data-carte-audit="{{ $l->action }}">
                <p class="font-bold">{{ \App\Support\LibellesAudit::action($l->action) }}</p>
                <p class="text-outline">{{ $l->created_at->timezone($fuseau)->format('d/m/Y H:i:s') }} · {{ $auteurs[$l->utilisateur_id] ?? $l->identifiant ?? '—' }} · {{ $l->ip ?? '—' }}</p>
                @foreach (\App\Support\LibellesAudit::detail($l->detail) as $ligne)<p class="text-outline">{{ $ligne }}</p>@endforeach
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucune entrée ne correspond à ces filtres.</p>
        @endforelse
    </div>

    <div class="no-print mt-md flex items-center justify-between">
        <button type="button" wire:click="precedente" @disabled($page <= 1) class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold disabled:opacity-40">Précédente</button>
        <span class="text-xs text-outline">Page {{ $page }} / {{ $pages }}</span>
        <button type="button" wire:click="suivante" @disabled($page >= $pages) class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold disabled:opacity-40">Suivante</button>
    </div>
</div>
