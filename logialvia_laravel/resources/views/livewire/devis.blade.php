<div>
    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <div>
            <h1 class="text-page-title font-bold">Devis Prestations</h1>
            <p class="text-xs text-outline">Un devis n'est pas une vente : aucun stock, aucune écriture comptable, aucun chiffre d'affaires.
                <a href="/ventes" class="font-semibold text-brand-navy underline">Retour aux Ventes</a></p>
        </div>
        <div class="flex flex-wrap gap-sm">
            @if ($peutExporter)
                <button type="button" wire:click="exporter" data-action="exporter"
                        class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Exporter (XLSX)</button>
            @endif
            @if ($peutGerer)
                <button type="button" wire:click="nouveau"
                        class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Générer un Devis</button>
            @endif
        </div>
    </div>

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-3">
        <div class="rounded-lg border-l-4 border-brand-navy bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Devis Émis</p>
            <p class="text-page-title font-bold" data-kpi="nombre">{{ $nombre }}</p>
        </div>
        <div class="rounded-lg border-l-4 border-brand-gold bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">En Attente de Réponse</p>
            <p class="text-page-title font-bold" data-kpi="en-attente">{{ $enAttente }}</p>
            <p class="text-caption text-outline">Émis et encore valables</p>
        </div>
        <div class="rounded-lg border-l-4 border-success-deep bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Montant Accepté</p>
            <p class="text-page-title font-bold" data-kpi="accepte">{{ number_format($accepte, 0, ',', ' ') }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
    </div>

    <div class="mb-sm flex flex-wrap items-center gap-sm">
        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Référence, client ou objet…" aria-label="Rechercher un devis"
               class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-xs">
        <div class="flex flex-wrap gap-xs" role="group" aria-label="Filtrer par statut">
            @foreach (['' => 'Tous', 'emis' => 'Émis', 'accepte' => 'Acceptés', 'refuse' => 'Refusés', 'expire' => 'Expirés'] as $cle => $libelle)
                <button type="button" wire:click="filtrer('{{ $cle }}')" data-filtre="{{ $cle === '' ? 'tous' : $cle }}" aria-pressed="{{ $filtre === $cle ? 'true' : 'false' }}"
                        class="rounded-full border px-md py-xs text-xs font-semibold {{ $filtre === $cle ? 'border-brand-navy bg-brand-navy text-white' : 'border-outline-variant bg-surface-card text-brand-navy' }}">{{ $libelle }}</button>
            @endforeach
        </div>
    </div>

    @php
        $badge = fn ($d) => $expire($d) ? 'bg-error-container text-error-deep' : match ($d->statut) {
            'accepte' => 'bg-success-container text-success-deep',
            'refuse' => 'bg-error-container text-error-deep',
            default => 'bg-surface-zebra text-brand-gold',
        };
    @endphp

    <section class="rounded-lg border border-outline-variant bg-surface-card" aria-labelledby="titre-liste">
        <h2 id="titre-liste" class="border-b border-outline-variant px-md py-sm text-section-title font-bold">Devis Émis</h2>

        @if ($devis->isEmpty())
            <p class="p-lg text-center text-xs text-outline" data-vide>
                {{ $filtre === '' && trim($recherche) === '' ? 'Aucun devis émis pour le moment.' : 'Aucun devis ne correspond à ces filtres.' }}
            </p>
        @else
            <div class="hidden overflow-x-auto sm:block">
                <table class="w-full text-left text-xs" data-table="devis">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-md py-sm">Référence</th>
                            <th class="px-md py-sm">Client</th>
                            <th class="px-md py-sm">Objet</th>
                            <th class="px-md py-sm text-right">Montant</th>
                            <th class="px-md py-sm text-right">Expire le</th>
                            <th class="px-md py-sm">Statut</th>
                            @if ($peutGerer)<th class="px-md py-sm text-right">Actions</th>@endif
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($devis as $d)
                            <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-devis="{{ $d->reference }}">
                                <td class="px-md py-sm font-bold text-brand-navy">{{ $d->reference }}</td>
                                <td class="px-md py-sm">{{ $d->client }}</td>
                                <td class="px-md py-sm">{{ $d->objet }}</td>
                                <td class="px-md py-sm text-right">{{ number_format($d->montant_estime, 0, ',', ' ') }}</td>
                                <td class="px-md py-sm text-right">{{ $d->dateExpiration()->timezone($fuseau)->format('d/m/Y') }}</td>
                                <td class="px-md py-sm"><span class="rounded-full px-sm py-xs font-bold {{ $badge($d) }}">{{ $libelles($d) }}</span></td>
                                @if ($peutGerer)
                                    <td class="px-md py-sm text-right">
                                        <div class="flex flex-wrap justify-end gap-xs">
                                            @if ($d->statut === 'emis')
                                                <button type="button" wire:click="modifier('{{ $d->id }}')" data-action="modifier" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Modifier</button>
                                            @endif
                                            <button type="button" wire:click="dupliquer('{{ $d->id }}')" data-action="dupliquer" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Dupliquer</button>
                                            @foreach (['emis' => 'Émis', 'accepte' => 'Accepté', 'refuse' => 'Refusé'] as $cle => $lib)
                                                @if ($d->statut !== $cle)
                                                    <button type="button" wire:click="changerStatut('{{ $d->id }}', '{{ $cle }}')" data-action="statut-{{ $cle }}" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">{{ $lib }}</button>
                                                @endif
                                            @endforeach
                                            @if ($d->statut !== 'accepte')
                                                <button type="button" wire:click="demanderSuppression('{{ $d->id }}')" data-action="supprimer" class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Supprimer</button>
                                            @endif
                                        </div>
                                    </td>
                                @endif
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <div class="flex flex-col gap-sm p-sm sm:hidden" data-vue="cartes">
                @foreach ($devis as $d)
                    <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-devis="{{ $d->reference }}">
                        <div class="flex items-center justify-between gap-sm">
                            <p class="font-bold text-brand-navy">{{ $d->reference }}</p>
                            <span class="rounded-full px-sm py-xs text-caption font-bold {{ $badge($d) }}">{{ $libelles($d) }}</span>
                        </div>
                        <p class="text-xs">{{ $d->client }} · {{ $d->objet }}</p>
                        <p class="font-bold">{{ number_format($d->montant_estime, 0, ',', ' ') }} FCFA</p>
                        <p class="text-caption text-outline">Expire le {{ $d->dateExpiration()->timezone($fuseau)->format('d/m/Y') }}</p>
                        @if ($peutGerer)
                            <div class="mt-sm flex flex-wrap gap-sm">
                                @if ($d->statut === 'emis')
                                    <button type="button" wire:click="modifier('{{ $d->id }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Modifier</button>
                                @endif
                                <button type="button" wire:click="dupliquer('{{ $d->id }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Dupliquer</button>
                                @if ($d->statut !== 'accepte')
                                    <button type="button" wire:click="demanderSuppression('{{ $d->id }}')" class="flex-1 rounded-lg border border-error-deep px-sm py-sm text-xs font-semibold text-error-deep">Supprimer</button>
                                @endif
                            </div>
                        @endif
                    </article>
                @endforeach
            </div>
        @endif
    </section>

    @if ($formulaire)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-devis">
            <form wire:submit="enregistrer" class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-devis" class="mb-md text-modal-title font-bold">{{ $devisId ? 'Modifier le Devis' : 'Générer un Devis' }}</h2>
                <label class="mb-sm block text-xs">Client *
                    <input type="text" wire:model="client" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Objet / Prestation *
                    <input type="text" wire:model="objet" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <div class="grid grid-cols-2 gap-sm">
                    <label class="block text-xs">Montant Estimé (FCFA) *
                        <input type="text" inputmode="decimal" wire:model="montant" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="block text-xs">Validité (jours)
                        <input type="text" inputmode="numeric" wire:model="validite" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                </div>
                @if ($erreur)
                    <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">{{ $devisId ? 'Enregistrer les modifications' : 'Générer le Devis' }}</button>
                </div>
            </form>
        </div>
    @endif

    @if ($aConfirmer)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-suppression">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-suppression" class="mb-sm text-modal-title font-bold">Supprimer ce devis ?</h2>
                <p class="mb-md text-xs"><strong>{{ $aConfirmer->reference }}</strong> ({{ $aConfirmer->client }}) disparaît de tous les postes. Son numéro ne sera pas réutilisé.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="confirmerSuppression" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Supprimer</button>
                </div>
            </div>
        </div>
    @endif
</div>
