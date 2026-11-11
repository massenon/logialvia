<div>
    @php($f = \App\Support\FormatComptable::class)
    @include('livewire.comptabilite._entete')

    <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="lecture-seule">
        Lecture seule : somme des écritures de tous les postes. Export : XLSX (bouton « Exporter ») et vue imprimable (« Imprimer / PDF ») ; le PDF généré du poste n'est pas reproduit.
    </p>

    <div class="mb-md flex flex-wrap items-end gap-sm rounded-lg border border-outline-variant bg-surface-card p-md">
        <div>
            <label for="compte" class="block text-caption font-bold uppercase text-outline">Compte :</label>
            <select id="compte" wire:model.live="compte" class="w-72 max-w-full rounded-lg border border-outline-variant px-sm py-xs text-xs">
                <option value="">Sélectionner un compte</option>
                @foreach ($comptesActifs as $c)
                    <option value="{{ $c->numero_compte }}">{{ $c->numero_compte }} — {{ $c->libelle }}</option>
                @endforeach
            </select>
        </div>
        <div>
            <label for="debut" class="block text-caption font-bold uppercase text-outline">Du</label>
            <input id="debut" type="date" wire:model.live="debut" class="rounded-lg border border-outline-variant px-sm py-xs text-xs">
            @if ($debut !== '')<button type="button" wire:click="retirerBorne('debut')" title="Retirer cette borne" class="text-xs text-outline">✕</button>@endif
        </div>
        <div>
            <label for="fin" class="block text-caption font-bold uppercase text-outline">Au</label>
            <input id="fin" type="date" wire:model.live="fin" class="rounded-lg border border-outline-variant px-sm py-xs text-xs">
            @if ($fin !== '')<button type="button" wire:click="retirerBorne('fin')" title="Retirer cette borne" class="text-xs text-outline">✕</button>@endif
        </div>
        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Rechercher un libellé, une référence…" aria-label="Rechercher"
               class="w-full rounded-lg border border-outline-variant px-md py-sm text-xs sm:w-64">
    </div>

    @if ($compte_choisi === null)
        <p class="rounded-lg bg-surface-card p-lg text-center text-xs text-outline" data-vide="aucun-compte">
            Sélectionnez un compte ci-dessus pour afficher ses écritures et son solde progressif.</p>
    @else
        <div class="mb-md grid grid-cols-2 gap-md lg:grid-cols-4">
            <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
                <p class="text-caption uppercase text-outline">Solde d'Ouverture</p>
                <p class="font-bold" data-kpi="ouverture">{{ $f::montant($ouverture) }}</p>
            </div>
            <div class="rounded-lg border border-outline-variant border-l-4 border-l-success-deep bg-white p-md shadow-sm">
                <p class="text-caption uppercase text-outline">Total Débit Période</p>
                <p class="font-bold text-success-deep" data-kpi="debit">{{ $f::montant($debit) }}</p>
            </div>
            <div class="rounded-lg border border-outline-variant border-l-4 border-l-error-deep bg-white p-md shadow-sm">
                <p class="text-caption uppercase text-outline">Total Crédit Période</p>
                <p class="font-bold text-error-deep" data-kpi="credit">{{ $f::montant($credit) }}</p>
            </div>
            <div class="rounded-lg border-l-4 border-brand-gold bg-brand-gold/10 p-md shadow-sm">
                <p class="text-caption uppercase text-outline">Solde Final</p>
                <p class="font-bold text-brand-navy" data-kpi="solde-final">{{ $f::montant($solde_final) }}</p>
            </div>
        </div>

        <div class="mb-sm flex items-center justify-between">
            <h2 class="text-section-title font-bold" data-compte="{{ $compte_choisi->numero_compte }}">{{ $compte_choisi->numero_compte }} — {{ $compte_choisi->libelle }}</h2>
            <span class="rounded-full border border-outline-variant bg-surface-zebra px-sm py-xs text-caption text-outline" data-sens>
                {{ $compte_choisi->estDebiteurParNature() ? 'Débiteur par nature' : 'Créditeur par nature' }}</span>
        </div>

        @if (count($lignes) === 0)
            <p class="rounded-lg bg-surface-card p-lg text-center text-xs text-outline" data-vide="aucune-ecriture">Aucune écriture ne correspond à ces critères.</p>
        @else
            <div class="mb-lg hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
                <table class="w-full text-left text-xs" data-table="grand-livre">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-md py-sm">Date</th>
                            <th class="px-md py-sm">Origine</th>
                            <th class="px-md py-sm">Libellé</th>
                            <th class="px-md py-sm text-right">Débit</th>
                            <th class="px-md py-sm text-right">Crédit</th>
                            <th class="px-md py-sm text-right">Solde Progressif</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr class="bg-surface-zebra" data-report>
                            <td></td><td></td>
                            <td class="px-md py-sm italic text-outline">Report — solde d'ouverture</td>
                            <td></td><td></td>
                            <td class="px-md py-sm text-right text-outline">{{ $f::nombre($ouverture) }}</td>
                        </tr>
                        @foreach ($lignes as $l)
                            @php($e = $l['ecriture'])
                            <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-ligne="{{ $e->id }}">
                                <td class="px-md py-sm">{{ $e->date->format('d/m/Y') }}</td>
                                <td class="px-md py-sm font-mono">{{ $e->venteRef ?? $e->achatRef ?? $e->numeroPiece ?? '—' }}</td>
                                <td class="px-md py-sm">{{ $e->libelle }}</td>
                                <td class="px-md py-sm text-right {{ $e->debit > 0 ? 'text-success-deep' : '' }}">{{ $f::ouTiret($e->debit) }}</td>
                                <td class="px-md py-sm text-right {{ $e->credit > 0 ? 'text-error-deep' : '' }}">{{ $f::ouTiret($e->credit) }}</td>
                                <td class="px-md py-sm text-right font-bold" data-solde>{{ $f::nombre($l['solde']) }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>

            <div class="mb-lg flex flex-col gap-sm sm:hidden" data-vue="cartes">
                @foreach ($lignes as $l)
                    @php($e = $l['ecriture'])
                    <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-ligne="{{ $e->id }}">
                        <p class="font-mono text-xs font-bold text-brand-navy">{{ $e->venteRef ?? $e->achatRef ?? $e->numeroPiece ?? '—' }}
                            <span class="font-normal text-outline">{{ $e->date->format('d/m/Y') }}</span></p>
                        <p class="text-xs">{{ $e->libelle }}</p>
                        <p class="text-xs">Débit {{ $f::ouTiret($e->debit) }} · Crédit {{ $f::ouTiret($e->credit) }}</p>
                        <p class="text-xs font-bold">Solde {{ $f::nombre($l['solde']) }}</p>
                    </article>
                @endforeach
            </div>
        @endif
    @endif
</div>
